defmodule Events.Core.Crud do
  @moduledoc """
  Unified CRUD execution API.

  This module delegates to `OmCrud` - a standalone library for CRUD operations.
  See `OmCrud` for full documentation.

  ## Quick Reference

  ### Token Execution

      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> Crud.run()

  ### Convenience Functions

      Crud.create(User, attrs)
      Crud.fetch(User, id)
      Crud.update(user, attrs)
      Crud.delete(user)

  ## Configuration

  OmCrud is configured in `config/config.exs`:

      config :om_crud,
        default_repo: Events.Core.Repo,
        telemetry_prefix: [:events, :crud, :execute]
  """

  # Re-export types and modules for convenience
  defdelegate run(token, opts \\ []), to: OmCrud
  defdelegate execute(token, opts \\ []), to: OmCrud
  defdelegate transaction(multi_or_fun, opts \\ []), to: OmCrud
  defdelegate execute_merge(merge, opts \\ []), to: OmCrud

  # Single record operations
  defdelegate create(schema, attrs, opts \\ []), to: OmCrud
  defdelegate update(struct_or_schema, attrs_or_id, opts_or_attrs \\ []), to: OmCrud
  defdelegate delete(struct_or_schema, opts_or_id \\ []), to: OmCrud

  # Read operations
  defdelegate fetch(schema_or_token, id_or_opts \\ [], opts \\ []), to: OmCrud
  defdelegate get(schema_or_token, id_or_opts \\ [], opts \\ []), to: OmCrud
  defdelegate exists?(schema_or_token, id_or_opts \\ []), to: OmCrud
  defdelegate fetch_all(query_token, opts \\ []), to: OmCrud
  defdelegate count(query_token), to: OmCrud

  # Bulk operations
  defdelegate create_all(schema, list_of_attrs, opts \\ []), to: OmCrud
  defdelegate upsert_all(schema, list_of_attrs, opts), to: OmCrud
  defdelegate update_all(query_token, updates, opts \\ []), to: OmCrud
  defdelegate delete_all(query_token, opts \\ []), to: OmCrud
end

defmodule Events.Core.Crud.Multi do
  @moduledoc """
  Transaction builder for composable CRUD operations.

  This module delegates to `OmCrud.Multi` - see that module for full documentation.
  """
  defdelegate new(), to: OmCrud.Multi
  defdelegate new(schema), to: OmCrud.Multi
  defdelegate create(multi, name, schema, attrs, opts \\ []), to: OmCrud.Multi
  defdelegate update(multi, name, target, attrs, opts \\ []), to: OmCrud.Multi
  defdelegate delete(multi, name, target, opts \\ []), to: OmCrud.Multi
  defdelegate upsert(multi, name, schema, attrs, opts), to: OmCrud.Multi
  defdelegate merge(multi, name, merge_token), to: OmCrud.Multi
  defdelegate create_all(multi, name, schema, list_of_attrs, opts \\ []), to: OmCrud.Multi
  defdelegate upsert_all(multi, name, schema, list_of_attrs, opts), to: OmCrud.Multi
  defdelegate update_all(multi, name, query, updates, opts \\ []), to: OmCrud.Multi
  defdelegate delete_all(multi, name, query, opts \\ []), to: OmCrud.Multi
  defdelegate merge_all(multi, name, merge_token), to: OmCrud.Multi
  defdelegate run(multi, name, fun), to: OmCrud.Multi
  defdelegate run(multi, name, mod, fun, args), to: OmCrud.Multi
  defdelegate inspect_results(multi, name, fun), to: OmCrud.Multi
  defdelegate when_ok(multi, name, fun), to: OmCrud.Multi
  defdelegate append(multi1, multi2), to: OmCrud.Multi
  defdelegate prepend(multi1, multi2), to: OmCrud.Multi
  defdelegate embed(multi1, multi2, opts \\ []), to: OmCrud.Multi
  defdelegate names(multi), to: OmCrud.Multi
  defdelegate operation_count(multi), to: OmCrud.Multi
  defdelegate has_operation?(multi, name), to: OmCrud.Multi
  defdelegate empty?(multi), to: OmCrud.Multi
  defdelegate to_ecto_multi(multi), to: OmCrud.Multi
end

defmodule Events.Core.Crud.Merge do
  @moduledoc """
  PostgreSQL MERGE operation builder.

  This module delegates to `OmCrud.Merge` - see that module for full documentation.
  """
  defdelegate new(schema), to: OmCrud.Merge
  defdelegate new(schema, source), to: OmCrud.Merge
  defdelegate source(merge, source), to: OmCrud.Merge
  defdelegate match_on(merge, columns), to: OmCrud.Merge
  defdelegate when_matched(merge, action), to: OmCrud.Merge
  defdelegate when_matched(merge, action_or_condition, fields_or_action), to: OmCrud.Merge
  defdelegate when_not_matched(merge, action), to: OmCrud.Merge
  defdelegate when_not_matched(merge, action_or_condition, attrs_or_action), to: OmCrud.Merge
  defdelegate returning(merge, fields), to: OmCrud.Merge
  defdelegate opts(merge, opts), to: OmCrud.Merge
  defdelegate to_sql(merge, opts \\ []), to: OmCrud.Merge
  defdelegate has_matched_clauses?(merge), to: OmCrud.Merge
  defdelegate has_not_matched_clauses?(merge), to: OmCrud.Merge
  defdelegate source_count(merge), to: OmCrud.Merge
end

defmodule Events.Core.Crud.Options do
  @moduledoc """
  Option handling for CRUD operations.

  This module delegates to `OmCrud.Options` - see that module for full documentation.
  """
  defdelegate valid_opts(operation), to: OmCrud.Options
  defdelegate extract(opts, operation), to: OmCrud.Options
  defdelegate repo_opts(opts), to: OmCrud.Options
  defdelegate sql_opts(opts), to: OmCrud.Options
  defdelegate normalize(opts), to: OmCrud.Options
  defdelegate validate(opts, operation), to: OmCrud.Options
  defdelegate repo(opts), to: OmCrud.Options
  defdelegate preloads(opts), to: OmCrud.Options
  defdelegate timeout(opts), to: OmCrud.Options
  defdelegate prefix(opts), to: OmCrud.Options
  defdelegate insert_opts(opts \\ []), to: OmCrud.Options
  defdelegate upsert_opts(opts), to: OmCrud.Options
  defdelegate update_opts(opts \\ []), to: OmCrud.Options
  defdelegate delete_opts(opts \\ []), to: OmCrud.Options
  defdelegate query_opts(opts \\ []), to: OmCrud.Options
  defdelegate insert_all_opts(opts \\ []), to: OmCrud.Options
  defdelegate update_all_opts(opts \\ []), to: OmCrud.Options
  defdelegate delete_all_opts(opts \\ []), to: OmCrud.Options
  defdelegate merge_opts(opts \\ []), to: OmCrud.Options
end

defmodule Events.Core.Crud.ChangesetBuilder do
  @moduledoc """
  Changeset building utilities.

  This module delegates to `OmCrud.ChangesetBuilder` - see that module for full documentation.
  """
  defdelegate build(schema_or_struct, attrs, opts \\ []), to: OmCrud.ChangesetBuilder
  defdelegate resolve(schema, action, opts), to: OmCrud.ChangesetBuilder
end

defmodule Events.Core.Crud.Context do
  @moduledoc """
  Context-level CRUD generation.

  This module delegates to `OmCrud.Context` - see that module for full documentation.

  ## Usage

      defmodule MyApp.Accounts do
        use Events.Core.Crud.Context

        crud User
        crud Role, only: [:create, :fetch]
      end
  """
  defmacro __using__(opts) do
    quote do
      use OmCrud.Context, unquote(opts)
    end
  end
end

defmodule Events.Core.Crud.Schema do
  @moduledoc """
  Schema-level CRUD configuration.

  This module delegates to `OmCrud.Schema` - see that module for full documentation.

  ## Usage

      defmodule MyApp.User do
        use Events.Core.Schema
        use Events.Core.Crud.Schema

        @crud_changeset :registration_changeset
      end
  """
  defmacro __using__(opts) do
    quote do
      use OmCrud.Schema, unquote(opts)
    end
  end
end

# Protocol wrappers - these re-export the OmCrud protocols for backwards compatibility.
# Code that implements these protocols should use OmCrud.* directly.
# These wrapper modules allow calling the protocol functions via Events.Core.Crud.* namespace.

defmodule Events.Core.Crud.Executable do
  @moduledoc """
  Protocol for executable tokens.

  **Note:** This module wraps `OmCrud.Executable`. For protocol implementations,
  use `defimpl OmCrud.Executable, for: YourModule`.
  """

  @doc "Execute a token. See `OmCrud.Executable.execute/2`."
  @spec execute(any(), keyword()) :: {:ok, any()} | {:error, any()}
  def execute(token, opts \\ []), do: OmCrud.Executable.execute(token, opts)
end

defmodule Events.Core.Crud.Validatable do
  @moduledoc """
  Protocol for validating tokens.

  **Note:** This module wraps `OmCrud.Validatable`. For protocol implementations,
  use `defimpl OmCrud.Validatable, for: YourModule`.
  """

  @doc "Validate a token. See `OmCrud.Validatable.validate/1`."
  @spec validate(any()) :: :ok | {:error, [String.t()]}
  def validate(token), do: OmCrud.Validatable.validate(token)
end

defmodule Events.Core.Crud.Debuggable do
  @moduledoc """
  Protocol for debugging tokens.

  **Note:** This module wraps `OmCrud.Debuggable`. For protocol implementations,
  use `defimpl OmCrud.Debuggable, for: YourModule`.
  """

  @doc "Get debug info for a token. See `OmCrud.Debuggable.to_debug/1`."
  @spec to_debug(any()) :: map()
  def to_debug(token), do: OmCrud.Debuggable.to_debug(token)
end

defmodule Events.Core.Crud.Op do
  @moduledoc """
  Backwards-compatibility module.

  **Deprecated**: Use `OmCrud.ChangesetBuilder` and `OmCrud.Options` instead.
  """
  defdelegate changeset(schema_or_struct, attrs, opts \\ []), to: OmCrud.Op
  defdelegate resolve_changeset(schema, action, opts), to: OmCrud.Op
  defdelegate insert_opts(opts \\ []), to: OmCrud.Op
  defdelegate upsert_opts(opts), to: OmCrud.Op
  defdelegate update_opts(opts \\ []), to: OmCrud.Op
  defdelegate delete_opts(opts \\ []), to: OmCrud.Op
  defdelegate query_opts(opts \\ []), to: OmCrud.Op
  defdelegate insert_all_opts(opts \\ []), to: OmCrud.Op
  defdelegate update_all_opts(opts \\ []), to: OmCrud.Op
  defdelegate delete_all_opts(opts \\ []), to: OmCrud.Op
  defdelegate preloads(opts), to: OmCrud.Op
  defdelegate repo(opts), to: OmCrud.Op
  defdelegate sql_opts(opts), to: OmCrud.Op
end
