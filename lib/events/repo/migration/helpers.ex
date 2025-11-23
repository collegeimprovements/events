defmodule Events.Repo.Migration.Helpers do
  @moduledoc """
  Helper functions for migration macros using pattern matching and pipelines.

  Provides utility functions that support the migration DSL with clean,
  functional implementations.
  """

  @doc """
  Determines if a field should be required based on pattern matching.

  ## Examples

      iex> field_required?(:email, [:email, :username])
      true

      iex> field_required?(:bio, [:email, :username])
      false

      iex> field_required?(:email, true)
      true

      iex> field_required?(:email, %{email: true, bio: false})
      true
  """
  def field_required?(field, required_config) do
    case required_config do
      true -> true
      false -> false
      nil -> false
      [] -> false
      fields when is_list(fields) -> field in fields
      fields when is_map(fields) -> Map.get(fields, field, false)
      _ -> false
    end
  end

  @doc """
  Builds field options using a pipeline approach.

  ## Examples

      iex> build_field_options(:string, %{required: true, default: "test"})
      [null: false, default: "test"]

      iex> build_field_options(:integer, %{min: 0, max: 100})
      []
  """
  def build_field_options(type, config) do
    []
    |> add_null_constraint(config[:required])
    |> add_default_value(config[:default])
    |> add_size_constraints(type, config)
    |> add_precision_scale(type, config)
    |> Enum.reverse()
  end

  defp add_null_constraint(opts, nil), do: opts

  defp add_null_constraint(opts, required) do
    [{:null, !required} | opts]
  end

  defp add_default_value(opts, nil), do: opts

  defp add_default_value(opts, default) do
    [{:default, default} | opts]
  end

  defp add_size_constraints(opts, :string, %{size: size}) when is_integer(size) do
    [{:size, size} | opts]
  end

  defp add_size_constraints(opts, _, _), do: opts

  defp add_precision_scale(opts, :decimal, %{precision: p, scale: s}) do
    opts
    |> add_if_present(:precision, p)
    |> add_if_present(:scale, s)
  end

  defp add_precision_scale(opts, _, _), do: opts

  defp add_if_present(opts, _key, nil), do: opts
  defp add_if_present(opts, key, value), do: [{key, value} | opts]

  @doc """
  Validates migration options using pattern matching.

  ## Examples

      iex> validate_migration_opts(table: :users, fields: [:email])
      {:ok, %{table: :users, fields: [:email]}}

      iex> validate_migration_opts([])
      {:error, "Missing required option: table"}
  """
  def validate_migration_opts(opts) do
    with {:ok, table} <- get_required_opt(opts, :table),
         {:ok, validated} <- validate_table_name(table) do
      {:ok,
       %{
         table: validated,
         fields: Keyword.get(opts, :fields, []),
         indexes: Keyword.get(opts, :indexes, true)
       }}
    end
  end

  defp get_required_opt(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, "Missing required option: #{key}"}
      value -> {:ok, value}
    end
  end

  defp validate_table_name(name) when is_atom(name) or is_binary(name) do
    {:ok, name}
  end

  defp validate_table_name(_) do
    {:error, "Table name must be an atom or string"}
  end

  @doc """
  Transforms field specs into migration commands using pipelines.

  ## Examples

      iex> field_specs_to_commands([{:email, :string, required: true}])
      [{:add, :email, :string, [null: false]}]
  """
  def field_specs_to_commands(field_specs) do
    field_specs
    |> Enum.map(&normalize_field_spec/1)
    |> Enum.map(&field_spec_to_command/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_field_spec({field, type}) do
    {field, type, []}
  end

  defp normalize_field_spec({field, type, opts}) when is_list(opts) do
    {field, type, opts}
  end

  defp normalize_field_spec({field, type, opts}) when is_map(opts) do
    {field, type, Map.to_list(opts)}
  end

  defp field_spec_to_command({field, type, opts}) do
    {:add, field, type, build_field_options(type, Enum.into(opts, %{}))}
  end

  @doc """
  Merges multiple option lists with conflict resolution.

  ## Examples

      iex> merge_options([required: true], [default: "test"])
      [required: true, default: "test"]

      iex> merge_options([required: true], [required: false, default: "test"])
      [required: false, default: "test"]
  """
  def merge_options(base_opts, override_opts) do
    base_opts
    |> Enum.into(%{})
    |> Map.merge(Enum.into(override_opts, %{}))
    |> Map.to_list()
  end

  @doc """
  Groups fields by their type for batch processing.

  ## Examples

      iex> group_fields_by_type([
      ...>   {:email, :string, []},
      ...>   {:age, :integer, []},
      ...>   {:name, :string, []}
      ...> ])
      %{
        string: [{:email, []}, {:name, []}],
        integer: [{:age, []}]
      }
  """
  def group_fields_by_type(field_specs) do
    field_specs
    |> Enum.group_by(
      fn {_field, type, _opts} -> type end,
      fn {field, _type, opts} -> {field, opts} end
    )
  end

  @doc """
  Generates index names using a consistent pattern.

  ## Examples

      iex> generate_index_name(:users, [:email])
      "users_email_index"

      iex> generate_index_name(:users, [:first_name, :last_name], "unique")
      "users_first_name_last_name_unique_index"
  """
  def generate_index_name(table, columns, suffix \\ nil) do
    parts = [
      to_string(table),
      columns |> Enum.map(&to_string/1) |> Enum.join("_"),
      suffix,
      "index"
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("_")
  end

  @doc """
  Extracts and normalizes language codes from options.

  ## Examples

      iex> extract_languages(languages: [:en, :es, :fr])
      [:en, :es, :fr]

      iex> extract_languages(languages: "en,es,fr")
      [:en, :es, :fr]

      iex> extract_languages([])
      []
  """
  def extract_languages(opts) do
    case Keyword.get(opts, :languages) do
      nil ->
        []

      langs when is_list(langs) ->
        langs

      langs when is_binary(langs) ->
        langs
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)

      _ ->
        []
    end
  end

  @doc """
  Creates a pipeline of validators for a field.

  ## Examples

      iex> create_validation_pipeline(:email, [:required, :format, :unique])
      [
        &validate_required/2,
        &validate_format/2,
        &validate_unique/2
      ]
  """
  def create_validation_pipeline(_field, validations) do
    validations
    |> Enum.map(&get_validator/1)
    |> Enum.reject(&is_nil/1)
  end

  defp get_validator(:required), do: &validate_required/2
  defp get_validator(:format), do: &validate_format/2
  defp get_validator(:unique), do: &validate_unique/2
  defp get_validator(:min_length), do: &validate_min_length/2
  defp get_validator(:max_length), do: &validate_max_length/2
  defp get_validator(_), do: nil

  # Stub validator functions for the example
  defp validate_required(field, opts), do: {:ok, field, opts}
  defp validate_format(field, opts), do: {:ok, field, opts}
  defp validate_unique(field, opts), do: {:ok, field, opts}
  defp validate_min_length(field, opts), do: {:ok, field, opts}
  defp validate_max_length(field, opts), do: {:ok, field, opts}
end
