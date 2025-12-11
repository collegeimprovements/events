defmodule Events.Core.Crud.Op do
  @moduledoc """
  Backwards-compatibility module for CRUD operations.

  > **Deprecated**: This module exists for backwards compatibility.
  > Use the following modules instead:
  >
  > - `Events.Core.Crud.ChangesetBuilder` - For changeset building and resolution
  > - `Events.Core.Crud.Options` - For option extraction and validation

  ## Migration Guide

  | Old (Op)                | New (Changeset/Options)           |
  |-------------------------|-----------------------------------|
  | `Op.changeset/3`        | `ChangesetBuilder.build/3`        |
  | `Op.resolve_changeset/3`| `ChangesetBuilder.resolve/3`      |
  | `Op.insert_opts/1`      | `Options.insert_opts/1`           |
  | `Op.update_opts/1`      | `Options.update_opts/1`           |
  | `Op.delete_opts/1`      | `Options.delete_opts/1`           |
  | `Op.query_opts/1`       | `Options.query_opts/1`            |
  | `Op.upsert_opts/1`      | `Options.upsert_opts/1`           |
  | `Op.insert_all_opts/1`  | `Options.insert_all_opts/1`       |
  | `Op.update_all_opts/1`  | `Options.update_all_opts/1`       |
  | `Op.delete_all_opts/1`  | `Options.delete_all_opts/1`       |
  | `Op.repo/1`             | `Options.repo/1`                  |
  | `Op.preloads/1`         | `Options.preloads/1`              |
  | `Op.sql_opts/1`         | `Options.sql_opts/1`              |
  """

  alias Events.Core.Crud.{ChangesetBuilder, Options}

  # ─────────────────────────────────────────────────────────────
  # Changeset Functions (delegate to ChangesetBuilder module)
  # ─────────────────────────────────────────────────────────────

  @doc """
  Build a changeset for a schema or struct.

  **Deprecated**: Use `Events.Core.Crud.ChangesetBuilder.build/3` instead.
  """
  @spec changeset(module() | struct(), map(), keyword()) :: Ecto.Changeset.t()
  defdelegate changeset(schema_or_struct, attrs, opts \\ []), to: ChangesetBuilder, as: :build

  @doc """
  Resolve the changeset function to use for an operation.

  **Deprecated**: Use `Events.Core.Crud.ChangesetBuilder.resolve/3` instead.
  """
  @spec resolve_changeset(module(), ChangesetBuilder.action(), keyword()) :: atom()
  defdelegate resolve_changeset(schema, action, opts), to: ChangesetBuilder, as: :resolve

  # ─────────────────────────────────────────────────────────────
  # Option Functions (delegate to Options module)
  # ─────────────────────────────────────────────────────────────

  @doc "Build options for insert operations. Use `Options.insert_opts/1` instead."
  @spec insert_opts(keyword()) :: keyword()
  defdelegate insert_opts(opts \\ []), to: Options

  @doc "Build options for upsert operations. Use `Options.upsert_opts/1` instead."
  @spec upsert_opts(keyword()) :: keyword()
  defdelegate upsert_opts(opts), to: Options

  @doc "Build options for update operations. Use `Options.update_opts/1` instead."
  @spec update_opts(keyword()) :: keyword()
  defdelegate update_opts(opts \\ []), to: Options

  @doc "Build options for delete operations. Use `Options.delete_opts/1` instead."
  @spec delete_opts(keyword()) :: keyword()
  defdelegate delete_opts(opts \\ []), to: Options

  @doc "Build options for query operations. Use `Options.query_opts/1` instead."
  @spec query_opts(keyword()) :: keyword()
  defdelegate query_opts(opts \\ []), to: Options

  @doc "Build options for insert_all operations. Use `Options.insert_all_opts/1` instead."
  @spec insert_all_opts(keyword()) :: keyword()
  defdelegate insert_all_opts(opts \\ []), to: Options

  @doc "Build options for update_all operations. Use `Options.update_all_opts/1` instead."
  @spec update_all_opts(keyword()) :: keyword()
  defdelegate update_all_opts(opts \\ []), to: Options

  @doc "Build options for delete_all operations. Use `Options.delete_all_opts/1` instead."
  @spec delete_all_opts(keyword()) :: keyword()
  defdelegate delete_all_opts(opts \\ []), to: Options

  @doc "Extract preload configuration. Use `Options.preloads/1` instead."
  @spec preloads(keyword()) :: [atom()] | keyword()
  defdelegate preloads(opts), to: Options

  @doc "Resolve the repo to use. Use `Options.repo/1` instead."
  @spec repo(keyword()) :: module()
  defdelegate repo(opts), to: Options

  @doc "Extract SQL/Repo options. Use `Options.sql_opts/1` instead."
  @spec sql_opts(keyword()) :: keyword()
  defdelegate sql_opts(opts), to: Options
end
