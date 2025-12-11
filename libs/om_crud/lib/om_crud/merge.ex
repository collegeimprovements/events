defmodule OmCrud.Merge do
  @moduledoc """
  Token-based builder for PostgreSQL 18+ MERGE operations.

  MERGE is more powerful than ON CONFLICT:
  - Can UPDATE, DELETE, or DO NOTHING when matched
  - Can INSERT or DO NOTHING when not matched
  - Supports multiple WHEN clauses with conditions
  - Can reference both source and target values

  ## Usage

      # Simple upsert: update if exists, insert if not
      User
      |> Merge.new(%{email: "test@example.com", name: "Test"})
      |> Merge.match_on(:email)
      |> Merge.when_matched(:update, [:name, :updated_at])
      |> Merge.when_not_matched(:insert)
      |> OmCrud.run()

      # Conditional update - only if source is newer
      User
      |> Merge.new(incoming_data)
      |> Merge.match_on(:id)
      |> Merge.when_matched(&newer_than_target/1, :update)
      |> Merge.when_matched(:nothing)
      |> Merge.when_not_matched(:insert)
      |> OmCrud.run()

      # Bulk sync from external source
      User
      |> Merge.new(external_users)
      |> Merge.match_on(:external_id)
      |> Merge.when_matched(:update, [:name, :email, :synced_at])
      |> Merge.when_not_matched(:insert, %{status: :pending})
      |> OmCrud.run()
  """

  # Protocol implementations are at the end of this module

  defstruct [
    :schema,
    :source,
    :match_on,
    when_matched: [],
    when_not_matched: [],
    returning: true,
    opts: []
  ]

  @type t :: %__MODULE__{
          schema: module(),
          source: source(),
          match_on: [atom()] | nil,
          when_matched: [when_clause()],
          when_not_matched: [when_clause()],
          returning: boolean() | [atom()],
          opts: keyword()
        }

  @type source :: map() | [map()] | Ecto.Query.t()
  @type condition :: :always | (Ecto.Query.t() -> Ecto.Query.t())
  @type match_action ::
          :update
          | :update_all
          | {:update, [atom()]}
          | {:update, keyword()}
          | :delete
          | :nothing
  @type no_match_action :: :insert | {:insert, map()} | :nothing
  @type when_clause :: {condition(), match_action() | no_match_action()}

  # ─────────────────────────────────────────────────────────────
  # Token Creation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Create a new Merge token for a schema.

  ## Examples

      Merge.new(User)
      Merge.new(User, %{email: "test@example.com"})
      Merge.new(User, [%{email: "a@test.com"}, %{email: "b@test.com"}])
  """
  @spec new(module()) :: t()
  def new(schema) when is_atom(schema) do
    %__MODULE__{schema: schema}
  end

  @spec new(module(), source()) :: t()
  def new(schema, source) when is_atom(schema) do
    %__MODULE__{schema: schema, source: source}
  end

  # ─────────────────────────────────────────────────────────────
  # Source Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Set the source data for the MERGE operation.

  The source can be:
  - A single map of attributes
  - A list of maps for bulk operations
  - An Ecto.Query for merging from another table

  ## Examples

      Merge.source(merge, %{email: "test@example.com"})
      Merge.source(merge, [%{email: "a@test.com"}, %{email: "b@test.com"}])
      Merge.source(merge, from(u in ExternalUser, select: %{email: u.email}))
  """
  @spec source(t(), source()) :: t()
  def source(%__MODULE__{} = merge, source) do
    %{merge | source: source}
  end

  # ─────────────────────────────────────────────────────────────
  # Match Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Set the column(s) to match on for detecting existing rows.

  ## Examples

      Merge.match_on(merge, :email)
      Merge.match_on(merge, [:org_id, :email])
  """
  @spec match_on(t(), atom() | [atom()]) :: t()
  def match_on(%__MODULE__{} = merge, column) when is_atom(column) do
    %{merge | match_on: [column]}
  end

  def match_on(%__MODULE__{} = merge, columns) when is_list(columns) do
    %{merge | match_on: columns}
  end

  # ─────────────────────────────────────────────────────────────
  # WHEN MATCHED Clauses
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a WHEN MATCHED clause.

  Called when a matching row exists in the target table.

  ## Actions

  - `:update` - Update all source fields
  - `{:update, fields}` - Update specific fields from source
  - `{:update, set: values}` - Update with explicit values
  - `:delete` - Delete the matched row
  - `:nothing` - Do nothing

  ## Examples

      # Update all fields from source
      Merge.when_matched(merge, :update)

      # Update specific fields
      Merge.when_matched(merge, :update, [:name, :updated_at])

      # Update with explicit values
      Merge.when_matched(merge, :update, set: [login_count: {:increment, 1}])

      # Delete matched rows
      Merge.when_matched(merge, :delete)

      # Conditional: only update if source is newer
      Merge.when_matched(merge, &source_newer/1, :update)
  """
  @spec when_matched(t(), match_action()) :: t()
  def when_matched(%__MODULE__{} = merge, action) when is_atom(action) do
    add_when_matched(merge, :always, action)
  end

  @spec when_matched(t(), :update, [atom()] | keyword()) :: t()
  def when_matched(%__MODULE__{} = merge, :update, fields) when is_list(fields) do
    action =
      if Keyword.keyword?(fields) do
        {:update, fields}
      else
        {:update, fields}
      end

    add_when_matched(merge, :always, action)
  end

  @spec when_matched(t(), condition(), match_action()) :: t()
  def when_matched(%__MODULE__{} = merge, condition, action) when is_function(condition, 1) do
    add_when_matched(merge, condition, action)
  end

  defp add_when_matched(%{when_matched: clauses} = merge, condition, action) do
    %{merge | when_matched: clauses ++ [{condition, action}]}
  end

  # ─────────────────────────────────────────────────────────────
  # WHEN NOT MATCHED Clauses
  # ─────────────────────────────────────────────────────────────

  @doc """
  Add a WHEN NOT MATCHED clause.

  Called when no matching row exists in the target table.

  ## Actions

  - `:insert` - Insert from source values
  - `{:insert, attrs}` - Insert with merged/default attributes
  - `:nothing` - Do nothing

  ## Examples

      # Insert from source
      Merge.when_not_matched(merge, :insert)

      # Insert with defaults
      Merge.when_not_matched(merge, :insert, %{status: :pending, role: :member})

      # Conditional insert
      Merge.when_not_matched(merge, &valid_email?/1, :insert)
  """
  @spec when_not_matched(t(), no_match_action()) :: t()
  def when_not_matched(%__MODULE__{} = merge, action) when action in [:insert, :nothing] do
    add_when_not_matched(merge, :always, action)
  end

  @spec when_not_matched(t(), :insert, map()) :: t()
  def when_not_matched(%__MODULE__{} = merge, :insert, attrs) when is_map(attrs) do
    add_when_not_matched(merge, :always, {:insert, attrs})
  end

  @spec when_not_matched(t(), condition(), no_match_action()) :: t()
  def when_not_matched(%__MODULE__{} = merge, condition, action) when is_function(condition, 1) do
    add_when_not_matched(merge, condition, action)
  end

  defp add_when_not_matched(%{when_not_matched: clauses} = merge, condition, action) do
    %{merge | when_not_matched: clauses ++ [{condition, action}]}
  end

  # ─────────────────────────────────────────────────────────────
  # Output Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Configure which fields to return from the MERGE operation.

  ## Examples

      Merge.returning(merge, true)           # All fields
      Merge.returning(merge, false)          # No fields
      Merge.returning(merge, [:id, :email])  # Specific fields
  """
  @spec returning(t(), boolean() | [atom()]) :: t()
  def returning(%__MODULE__{} = merge, fields) do
    %{merge | returning: fields}
  end

  # ─────────────────────────────────────────────────────────────
  # Options
  # ─────────────────────────────────────────────────────────────

  @doc """
  Set additional options for the MERGE operation.

  ## Options

  - `:prefix` - Database schema prefix
  - `:timeout` - Query timeout

  ## Examples

      Merge.opts(merge, prefix: "tenant_123")
  """
  @spec opts(t(), keyword()) :: t()
  def opts(%__MODULE__{opts: existing} = merge, new_opts) do
    %{merge | opts: Keyword.merge(existing, new_opts)}
  end

  # ─────────────────────────────────────────────────────────────
  # SQL Generation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Convert the Merge token to a raw SQL query and parameters.

  This generates PostgreSQL 18+ MERGE syntax.

  ## Options

  - `:repo` - The repo module to use for query generation (for subqueries)

  ## Returns

  A tuple of `{sql_string, params}`.
  """
  @spec to_sql(t(), keyword()) :: {String.t(), [term()]}
  def to_sql(%__MODULE__{} = merge, opts \\ []) do
    # This is a placeholder - actual SQL generation would be complex
    # and depend on the specific PostgreSQL 18 MERGE syntax
    {build_merge_sql(merge, opts), build_params(merge)}
  end

  defp build_merge_sql(%{schema: schema, match_on: match_on} = merge, opts) do
    table = schema.__schema__(:source)

    """
    MERGE INTO #{table} AS target
    USING #{source_sql(merge, opts)} AS source
    ON #{match_condition(match_on)}
    #{when_matched_sql(merge.when_matched)}
    #{when_not_matched_sql(merge.when_not_matched)}
    #{returning_sql(merge.returning, schema)}
    """
    |> String.trim()
  end

  defp source_sql(%{source: source}, _opts) when is_map(source) do
    "(VALUES (#{placeholder_values(source)})) AS source(#{column_names(source)})"
  end

  defp source_sql(%{source: sources}, _opts) when is_list(sources) do
    values =
      sources
      |> Enum.map(&placeholder_values/1)
      |> Enum.join("), (")

    columns = sources |> List.first() |> column_names()
    "(VALUES (#{values})) AS source(#{columns})"
  end

  defp source_sql(%{source: query}, opts) when is_struct(query) do
    repo = Keyword.get_lazy(opts, :repo, &OmCrud.Config.default_repo/0)
    {sql, _params} = repo.to_sql(:all, query)
    "(#{sql})"
  end

  defp placeholder_values(map) do
    map |> Map.keys() |> Enum.map(fn _ -> "?" end) |> Enum.join(", ")
  end

  defp column_names(map) do
    map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.join(", ")
  end

  defp match_condition(columns) do
    columns
    |> Enum.map(fn col -> "target.#{col} = source.#{col}" end)
    |> Enum.join(" AND ")
  end

  defp when_matched_sql([]), do: ""

  defp when_matched_sql(clauses) do
    clauses
    |> Enum.map(&when_matched_clause_sql/1)
    |> Enum.join("\n")
  end

  defp when_matched_clause_sql({:always, :update}) do
    "WHEN MATCHED THEN UPDATE SET *"
  end

  defp when_matched_clause_sql({:always, {:update, fields}}) when is_list(fields) do
    sets = Enum.map(fields, fn f -> "#{f} = source.#{f}" end) |> Enum.join(", ")
    "WHEN MATCHED THEN UPDATE SET #{sets}"
  end

  defp when_matched_clause_sql({:always, :delete}) do
    "WHEN MATCHED THEN DELETE"
  end

  defp when_matched_clause_sql({:always, :nothing}) do
    "WHEN MATCHED THEN DO NOTHING"
  end

  defp when_matched_clause_sql({condition, action}) when is_function(condition) do
    # Conditional clauses would need query introspection
    "WHEN MATCHED AND <condition> THEN #{action_sql(action)}"
  end

  defp action_sql(:update), do: "UPDATE SET *"
  defp action_sql({:update, fields}), do: "UPDATE SET #{Enum.join(fields, ", ")}"
  defp action_sql(:delete), do: "DELETE"
  defp action_sql(:nothing), do: "DO NOTHING"

  defp when_not_matched_sql([]), do: ""

  defp when_not_matched_sql(clauses) do
    clauses
    |> Enum.map(&when_not_matched_clause_sql/1)
    |> Enum.join("\n")
  end

  defp when_not_matched_clause_sql({:always, :insert}) do
    "WHEN NOT MATCHED THEN INSERT VALUES (source.*)"
  end

  defp when_not_matched_clause_sql({:always, {:insert, _attrs}}) do
    "WHEN NOT MATCHED THEN INSERT VALUES (...)"
  end

  defp when_not_matched_clause_sql({:always, :nothing}) do
    "WHEN NOT MATCHED THEN DO NOTHING"
  end

  defp when_not_matched_clause_sql({_condition, action}) do
    "WHEN NOT MATCHED AND <condition> THEN #{insert_action_sql(action)}"
  end

  defp insert_action_sql(:insert), do: "INSERT VALUES (source.*)"
  defp insert_action_sql({:insert, _}), do: "INSERT VALUES (...)"
  defp insert_action_sql(:nothing), do: "DO NOTHING"

  defp returning_sql(false, _schema), do: ""
  defp returning_sql(true, schema), do: "RETURNING #{all_columns(schema)}"

  defp returning_sql(fields, _schema) when is_list(fields) do
    "RETURNING #{Enum.join(fields, ", ")}"
  end

  defp all_columns(schema) do
    schema.__schema__(:fields) |> Enum.join(", ")
  end

  defp build_params(%{source: source}) when is_map(source) do
    Map.values(source)
  end

  defp build_params(%{source: sources}) when is_list(sources) do
    Enum.flat_map(sources, &Map.values/1)
  end

  defp build_params(_), do: []

  # ─────────────────────────────────────────────────────────────
  # Introspection
  # ─────────────────────────────────────────────────────────────

  @doc """
  Check if the Merge token has any WHEN MATCHED clauses.
  """
  @spec has_matched_clauses?(t()) :: boolean()
  def has_matched_clauses?(%__MODULE__{when_matched: clauses}) do
    length(clauses) > 0
  end

  @doc """
  Check if the Merge token has any WHEN NOT MATCHED clauses.
  """
  @spec has_not_matched_clauses?(t()) :: boolean()
  def has_not_matched_clauses?(%__MODULE__{when_not_matched: clauses}) do
    length(clauses) > 0
  end

  @doc """
  Get the number of source records.
  """
  @spec source_count(t()) :: non_neg_integer() | :unknown
  def source_count(%__MODULE__{source: nil}), do: 0
  def source_count(%__MODULE__{source: source}) when is_map(source), do: 1
  def source_count(%__MODULE__{source: sources}) when is_list(sources), do: length(sources)
  def source_count(%__MODULE__{}), do: :unknown
end

# ─────────────────────────────────────────────────────────────
# Protocol Implementations
# ─────────────────────────────────────────────────────────────

defimpl OmCrud.Executable, for: OmCrud.Merge do
  alias OmCrud.Merge

  def execute(%Merge{} = merge, opts) do
    # Delegate to the main OmCrud module for execution
    OmCrud.execute_merge(merge, opts)
  end
end

defimpl OmCrud.Validatable, for: OmCrud.Merge do
  alias OmCrud.Merge

  def validate(%Merge{match_on: nil}) do
    {:error, ["Merge must specify match_on columns"]}
  end

  def validate(%Merge{source: nil}) do
    {:error, ["Merge must have a source"]}
  end

  def validate(%Merge{when_matched: [], when_not_matched: []}) do
    {:error, ["Merge must have at least one WHEN clause"]}
  end

  def validate(%Merge{}), do: :ok
end

defimpl OmCrud.Debuggable, for: OmCrud.Merge do
  alias OmCrud.Merge

  def to_debug(%Merge{} = merge) do
    %{
      type: :merge,
      schema: merge.schema,
      match_on: merge.match_on,
      source_count: Merge.source_count(merge),
      when_matched_count: length(merge.when_matched),
      when_not_matched_count: length(merge.when_not_matched),
      returning: merge.returning
    }
  end
end

defimpl Inspect, for: OmCrud.Merge do
  alias OmCrud.Merge

  def inspect(%Merge{} = merge, _opts) do
    schema_name = merge.schema |> Module.split() |> List.last()
    match_on = merge.match_on || []
    source_info = Merge.source_count(merge)

    "#OmCrud.Merge<#{schema_name}, match: #{inspect(match_on)}, source: #{source_info}>"
  end
end
