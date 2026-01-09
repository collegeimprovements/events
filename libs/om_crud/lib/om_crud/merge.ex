defmodule OmCrud.Merge do
  @moduledoc """
  Token-based builder for PostgreSQL MERGE operations.

  This module delegates to `OmQuery.Merge` for token building and SQL generation,
  while providing OmCrud protocol implementations for execution via `OmCrud.run/2`.

  ## Usage

      # Build and execute via OmCrud
      User
      |> Merge.new(%{email: "test@example.com", name: "Test"})
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name, :updated_at])
      |> Merge.when_not_matched(:insert)
      |> OmCrud.run()

      # Or execute directly
      User
      |> Merge.new(data)
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name])
      |> Merge.when_not_matched(:insert)
      |> Merge.execute(repo: MyApp.Repo)

  See `OmQuery.Merge` for full documentation on all builder functions.
  """

  # Delegate all struct and builder functions to OmQuery.Merge
  # This ensures OmCrud.Merge tokens ARE OmQuery.Merge tokens

  defdelegate new(schema), to: OmQuery.Merge
  defdelegate new(schema, source), to: OmQuery.Merge
  defdelegate source(merge, source), to: OmQuery.Merge
  defdelegate match_on(merge, columns), to: OmQuery.Merge
  defdelegate when_matched(merge, action), to: OmQuery.Merge
  defdelegate when_matched(merge, action_or_condition, fields_or_action), to: OmQuery.Merge
  defdelegate when_not_matched(merge, action), to: OmQuery.Merge
  defdelegate when_not_matched(merge, action_or_condition, attrs_or_action), to: OmQuery.Merge
  defdelegate returning(merge, fields), to: OmQuery.Merge
  defdelegate opts(merge, new_opts), to: OmQuery.Merge
  defdelegate validate(merge), to: OmQuery.Merge
  defdelegate to_sql(merge), to: OmQuery.Merge
  defdelegate to_sql(merge, opts), to: OmQuery.Merge
  defdelegate execute(merge), to: OmQuery.Merge
  defdelegate execute(merge, opts), to: OmQuery.Merge
  defdelegate has_matched_clauses?(merge), to: OmQuery.Merge
  defdelegate has_not_matched_clauses?(merge), to: OmQuery.Merge
  defdelegate source_count(merge), to: OmQuery.Merge

  # Type alias for backwards compatibility
  @type t :: OmQuery.Merge.t()
end

# ─────────────────────────────────────────────────────────────
# Protocol Implementations
# ─────────────────────────────────────────────────────────────

defimpl OmCrud.Executable, for: OmQuery.Merge do
  def execute(%OmQuery.Merge{} = merge, opts) do
    # Merge token opts with call-time opts (call-time takes precedence)
    merged_opts = Keyword.merge(merge.opts, opts)

    # Get repo from options or config
    repo =
      Keyword.get_lazy(merged_opts, :repo, fn ->
        OmCrud.Config.default_repo()
      end)

    OmQuery.Merge.execute(merge, Keyword.put(merged_opts, :repo, repo))
  end
end

defimpl OmCrud.Validatable, for: OmQuery.Merge do
  def validate(%OmQuery.Merge{} = merge) do
    OmQuery.Merge.validate(merge)
  end
end

defimpl OmCrud.Debuggable, for: OmQuery.Merge do
  def to_debug(%OmQuery.Merge{} = merge) do
    %{
      type: :merge,
      schema: merge.schema,
      match_on: merge.match_on,
      source_count: OmQuery.Merge.source_count(merge),
      when_matched_count: length(merge.when_matched),
      when_not_matched_count: length(merge.when_not_matched),
      returning: merge.returning
    }
  end
end
