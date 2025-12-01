defmodule Events.Core.Schema.DatabaseValidator.AssociationChecker do
  @moduledoc """
  Validates has_many associations to ensure foreign key constraints exist on related tables.

  When a schema declares `has_many :items, Item`, this checker verifies that:
  - The `items` table has a foreign key constraint pointing to this schema's table
  - The FK has the expected `on_delete` behavior (if specified)

  This ensures data integrity is enforced at the database level, not just in application code.
  """

  alias Events.Core.Schema.DatabaseValidator.PgIntrospection

  @doc """
  Validates has_many FK expectations against the database.

  For each `has_many` association in the schema (that isn't a through association),
  checks that the related table has a corresponding FK constraint.

  ## Options

    * `:repo` - The Ecto repo to use (required)
    * `:table` - The table name of the parent schema (required)
    * `:schema_module` - The schema module (required)

  ## Returns

      {:ok, %{validated: count, warnings: [...]}}
      {:error, %{errors: [...], warnings: [...]}}
  """
  @spec validate(keyword()) :: {:ok, map()} | {:error, map()}
  def validate(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)

    # Get has_many FK expectations
    expectations = get_has_many_expectations(schema_module)

    # Validate each expectation
    {errors, warnings, validated} =
      Enum.reduce(expectations, {[], [], 0}, fn expectation, {errs, warns, count} ->
        case validate_expectation(repo, table, schema_module, expectation) do
          :ok ->
            {errs, warns, count + 1}

          {:warning, msg} ->
            {errs, [{expectation.assoc_name, msg} | warns], count + 1}

          {:error, msg} ->
            {[{expectation.assoc_name, msg} | errs], warns, count}
        end
      end)

    if errors == [] do
      {:ok, %{validated: validated, warnings: Enum.reverse(warnings)}}
    else
      {:error, %{errors: Enum.reverse(errors), warnings: Enum.reverse(warnings)}}
    end
  end

  defp get_has_many_expectations(schema_module) do
    if function_exported?(schema_module, :__has_many_expectations__, 0) do
      schema_module.__has_many_expectations__()
    else
      # Fallback: introspect has_many associations
      schema_module.__schema__(:associations)
      |> Enum.map(&schema_module.__schema__(:association, &1))
      |> Enum.filter(&(&1.cardinality == :many && &1.relationship == :child && !&1.through))
      |> Enum.map(fn assoc ->
        %{
          assoc_name: assoc.field,
          related: assoc.related,
          expect_on_delete: nil
        }
      end)
    end
  end

  defp validate_expectation(repo, parent_table, _parent_schema, expectation) do
    related_module = expectation.related

    # Get the related table name
    related_table =
      if function_exported?(related_module, :__schema__, 1) do
        related_module.__schema__(:source)
      else
        # Can't validate if related module isn't compiled yet
        nil
      end

    if is_nil(related_table) do
      {:error, "related module #{inspect(related_module)} not compiled or not an Ecto schema"}
    else
      # Find the FK on the related table that points to this table
      fks = PgIntrospection.foreign_keys(repo, related_table)

      # Look for FK that references parent table
      matching_fk =
        Enum.find(fks, fn fk ->
          fk.references_table == parent_table
        end)

      case matching_fk do
        nil ->
          {:error, "no FK found on #{related_table} referencing #{parent_table}"}

        fk ->
          # Check on_delete expectation if specified
          if expectation.expect_on_delete do
            expected = normalize_on_delete(expectation.expect_on_delete)
            actual = fk.on_delete

            if expected == actual do
              :ok
            else
              {:warning, "FK #{fk.name} has on_delete: #{actual}, expected: #{expected}"}
            end
          else
            :ok
          end
      end
    end
  end

  defp normalize_on_delete(:nothing), do: :nothing
  defp normalize_on_delete(:cascade), do: :cascade
  defp normalize_on_delete(:restrict), do: :restrict
  defp normalize_on_delete(:delete_all), do: :cascade
  defp normalize_on_delete(:nilify_all), do: :set_null
  defp normalize_on_delete(other), do: other

  @doc """
  Gets a summary of has_many FK validation.
  """
  @spec summary(keyword()) :: map()
  def summary(opts) do
    repo = Keyword.fetch!(opts, :repo)
    table = Keyword.fetch!(opts, :table)
    schema_module = Keyword.fetch!(opts, :schema_module)

    expectations = get_has_many_expectations(schema_module)

    validated =
      Enum.count(expectations, fn exp ->
        case validate_expectation(repo, table, schema_module, exp) do
          :ok -> true
          {:warning, _} -> true
          {:error, _} -> false
        end
      end)

    %{
      total_has_many: length(expectations),
      validated: validated,
      missing_fks: length(expectations) - validated
    }
  end

  @doc """
  Validates that a specific has_many association has a corresponding FK.

  Useful for targeted validation.

  ## Example

      AssociationChecker.validate_association(
        Events.Core.Repo,
        Events.Domains.Accounts.Account,
        :memberships
      )
  """
  @spec validate_association(module(), module(), atom()) :: :ok | {:error, String.t()}
  def validate_association(repo, schema_module, assoc_name) do
    table = schema_module.__schema__(:source)
    assoc = schema_module.__schema__(:association, assoc_name)

    if assoc && assoc.cardinality == :many && assoc.relationship == :child do
      expectation = %{
        assoc_name: assoc_name,
        related: assoc.related,
        expect_on_delete: nil
      }

      case validate_expectation(repo, table, schema_module, expectation) do
        :ok -> :ok
        {:warning, msg} -> {:ok, msg}
        {:error, msg} -> {:error, msg}
      end
    else
      {:error, "#{assoc_name} is not a has_many child association"}
    end
  end
end
