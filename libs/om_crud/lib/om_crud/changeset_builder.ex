defmodule OmCrud.ChangesetBuilder do
  @moduledoc """
  Changeset builder and resolver for CRUD operations.

  This module provides pure functions that build and resolve changesets
  without any side effects or database calls.

  ## Changeset Resolution

  Changesets are resolved with the following priority:
  1. Explicit `:changeset` option
  2. Action-specific option (`:create_changeset`, `:update_changeset`)
  3. Schema's `@crud_changeset` attribute
  4. Schema's `changeset_for/2` callback
  5. Default `:changeset` function

  ## Usage

      # Build a changeset for a schema
      changeset = ChangesetBuilder.build(User, %{email: "test@example.com"})

      # Build with explicit changeset function
      changeset = ChangesetBuilder.build(User, attrs, changeset: :registration_changeset)

      # Resolve which changeset function to use
      changeset_fn = ChangesetBuilder.resolve(User, :create, opts)
  """

  @type changeset_opt ::
          {:changeset, atom()} | {:create_changeset, atom()} | {:update_changeset, atom()}
  @type action :: :create | :update | :delete

  # ─────────────────────────────────────────────────────────────
  # Changeset Building
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build a changeset for a schema or struct with attributes.

  When given a schema module, builds a changeset for a new struct.
  When given an existing struct, builds a changeset for updating it.

  ## Options

  - `:changeset` - Explicit changeset function name
  - `:action` - The action type (`:create`, `:update`), affects function resolution

  ## Examples

      # From schema module (create)
      ChangesetBuilder.build(User, %{email: "test@example.com"})
      ChangesetBuilder.build(User, %{name: "Test"}, changeset: :profile_changeset)

      # From existing struct (update)
      ChangesetBuilder.build(user, %{name: "Updated"})
      ChangesetBuilder.build(user, %{role: :admin}, changeset: :admin_changeset)
  """
  @spec build(module() | struct(), map(), keyword()) :: Ecto.Changeset.t()
  def build(schema_or_struct, attrs, opts \\ [])

  def build(schema, attrs, opts) when is_atom(schema) do
    action = Keyword.get(opts, :action, :create)
    changeset_fn = resolve(schema, action, opts)
    struct = struct(schema)

    apply(schema, changeset_fn, [struct, attrs])
  end

  def build(%{__struct__: schema} = struct, attrs, opts) when is_map(attrs) do
    action = Keyword.get(opts, :action, :update)
    changeset_fn = resolve(schema, action, opts)

    apply(schema, changeset_fn, [struct, attrs])
  end

  @doc """
  Resolve the changeset function to use for an operation.

  Resolution priority:
  1. Explicit `:changeset` option
  2. Action-specific option (`:create_changeset`, `:update_changeset`)
  3. Schema's `@crud_changeset` attribute
  4. Schema's `changeset_for/2` callback
  5. Default `:changeset` function

  ## Examples

      ChangesetBuilder.resolve(User, :create, [])
      #=> :changeset

      ChangesetBuilder.resolve(User, :create, changeset: :registration_changeset)
      #=> :registration_changeset
  """
  @spec resolve(module(), action(), keyword()) :: atom()
  def resolve(schema, action, opts) do
    cond do
      # Explicit :changeset option
      changeset_fn = Keyword.get(opts, :changeset) ->
        changeset_fn

      # Action-specific option
      changeset_fn = Keyword.get(opts, action_changeset_key(action)) ->
        changeset_fn

      # Schema attribute @crud_changeset
      changeset_fn = get_schema_crud_changeset(schema) ->
        changeset_fn

      # Schema callback changeset_for/2
      function_exported?(schema, :changeset_for, 2) ->
        apply(schema, :changeset_for, [action, opts])

      # Default
      true ->
        :changeset
    end
  end

  defp action_changeset_key(:create), do: :create_changeset
  defp action_changeset_key(:update), do: :update_changeset
  defp action_changeset_key(:delete), do: :delete_changeset
  defp action_changeset_key(_), do: :changeset

  defp get_schema_crud_changeset(schema) do
    if function_exported?(schema, :__info__, 1) do
      schema.__info__(:attributes)
      |> Keyword.get(:crud_changeset)
      |> List.wrap()
      |> List.first()
    end
  end
end
