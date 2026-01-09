defmodule OmQuery.Merge do
  @moduledoc """
  Token-based builder for PostgreSQL MERGE operations.

  MERGE is more powerful than ON CONFLICT (upsert):
  - Can UPDATE, DELETE, or DO NOTHING when matched
  - Can INSERT or DO NOTHING when not matched
  - Supports multiple WHEN clauses with conditions
  - Can reference both source and target values

  ## Usage

      # Simple upsert: update if exists, insert if not
      User
      |> OmQuery.Merge.new(%{email: "test@example.com", name: "Test"})
      |> OmQuery.Merge.match_on(:email)
      |> OmQuery.Merge.when_matched(:update, [:name, :updated_at])
      |> OmQuery.Merge.when_not_matched(:insert)
      |> OmQuery.Merge.execute(repo: MyApp.Repo)

      # Conditional update - only if source is newer
      User
      |> OmQuery.Merge.new(incoming_data)
      |> OmQuery.Merge.match_on(:id)
      |> OmQuery.Merge.when_matched(&newer_than_target/1, :update)
      |> OmQuery.Merge.when_matched(:nothing)
      |> OmQuery.Merge.when_not_matched(:insert)

      # Bulk sync from external source
      User
      |> OmQuery.Merge.new(external_users)
      |> OmQuery.Merge.match_on(:external_id)
      |> OmQuery.Merge.when_matched(:update, [:name, :email, :synced_at])
      |> OmQuery.Merge.when_not_matched(:insert, %{status: :pending})

  ## PostgreSQL Version

  Requires PostgreSQL 15+ for MERGE support.

  ## Configuration

  Configure the default repo in your application config:

      config :om_query, :default_repo, MyApp.Repo

  Or pass the repo explicitly:

      OmQuery.Merge.execute(merge, repo: MyApp.Repo)
  """

  alias __MODULE__
  alias OmQuery.Config

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

      OmQuery.Merge.new(User)
      OmQuery.Merge.new(User, %{email: "test@example.com"})
      OmQuery.Merge.new(User, [%{email: "a@test.com"}, %{email: "b@test.com"}])
  """
  @spec new(module()) :: t()
  def new(schema) when is_atom(schema) do
    %Merge{schema: schema}
  end

  @spec new(module(), source()) :: t()
  def new(schema, source) when is_atom(schema) do
    %Merge{schema: schema, source: source}
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

      OmQuery.Merge.source(merge, %{email: "test@example.com"})
      OmQuery.Merge.source(merge, [%{email: "a@test.com"}, %{email: "b@test.com"}])
      OmQuery.Merge.source(merge, from(u in ExternalUser, select: %{email: u.email}))
  """
  @spec source(t(), source()) :: t()
  def source(%Merge{} = merge, source) do
    %{merge | source: source}
  end

  # ─────────────────────────────────────────────────────────────
  # Match Configuration
  # ─────────────────────────────────────────────────────────────

  @doc """
  Set the column(s) to match on for detecting existing rows.

  ## Examples

      OmQuery.Merge.match_on(merge, :email)
      OmQuery.Merge.match_on(merge, [:org_id, :email])
  """
  @spec match_on(t(), atom() | [atom()]) :: t()
  def match_on(%Merge{} = merge, column) when is_atom(column) do
    %{merge | match_on: [column]}
  end

  def match_on(%Merge{} = merge, columns) when is_list(columns) do
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
      OmQuery.Merge.when_matched(merge, :update)

      # Update specific fields
      OmQuery.Merge.when_matched(merge, :update, [:name, :updated_at])

      # Update with explicit values
      OmQuery.Merge.when_matched(merge, :update, set: [login_count: {:increment, 1}])

      # Delete matched rows
      OmQuery.Merge.when_matched(merge, :delete)

      # Conditional: only update if source is newer
      OmQuery.Merge.when_matched(merge, &source_newer/1, :update)
  """
  @spec when_matched(t(), match_action()) :: t()
  def when_matched(%Merge{} = merge, action) when is_atom(action) do
    add_when_matched(merge, :always, action)
  end

  @spec when_matched(t(), :update, [atom()] | keyword()) :: t()
  def when_matched(%Merge{} = merge, :update, fields) when is_list(fields) do
    add_when_matched(merge, :always, {:update, fields})
  end

  @spec when_matched(t(), condition(), match_action()) :: t()
  def when_matched(%Merge{} = merge, condition, action) when is_function(condition, 1) do
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
      OmQuery.Merge.when_not_matched(merge, :insert)

      # Insert with defaults
      OmQuery.Merge.when_not_matched(merge, :insert, %{status: :pending, role: :member})

      # Conditional insert
      OmQuery.Merge.when_not_matched(merge, &valid_email?/1, :insert)
  """
  @spec when_not_matched(t(), no_match_action()) :: t()
  def when_not_matched(%Merge{} = merge, action) when action in [:insert, :nothing] do
    add_when_not_matched(merge, :always, action)
  end

  @spec when_not_matched(t(), :insert, map()) :: t()
  def when_not_matched(%Merge{} = merge, :insert, attrs) when is_map(attrs) do
    add_when_not_matched(merge, :always, {:insert, attrs})
  end

  @spec when_not_matched(t(), condition(), no_match_action()) :: t()
  def when_not_matched(%Merge{} = merge, condition, action) when is_function(condition, 1) do
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

      OmQuery.Merge.returning(merge, true)           # All fields
      OmQuery.Merge.returning(merge, false)          # No fields
      OmQuery.Merge.returning(merge, [:id, :email])  # Specific fields
  """
  @spec returning(t(), boolean() | [atom()]) :: t()
  def returning(%Merge{} = merge, fields) do
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
  - `:repo` - Ecto repo to use

  ## Examples

      OmQuery.Merge.opts(merge, prefix: "tenant_123")
  """
  @spec opts(t(), keyword()) :: t()
  def opts(%Merge{opts: existing} = merge, new_opts) do
    %{merge | opts: Keyword.merge(existing, new_opts)}
  end

  # ─────────────────────────────────────────────────────────────
  # Validation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Validate the Merge token.

  Returns `:ok` if valid, `{:error, reasons}` if invalid.
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
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

  # ─────────────────────────────────────────────────────────────
  # SQL Generation
  # ─────────────────────────────────────────────────────────────

  @doc """
  Convert the Merge token to a raw SQL query and parameters.

  This generates PostgreSQL 15+ MERGE syntax.

  ## Options

  - `:repo` - The repo module to use for query generation (for subqueries)

  ## Returns

  A tuple of `{sql_string, params}`.
  """
  @spec to_sql(t(), keyword()) :: {String.t(), [term()]}
  def to_sql(%Merge{} = merge, opts \\ []) do
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

  defp source_sql(%{source: query, opts: merge_opts}, call_opts) when is_struct(query) do
    repo = Keyword.get(call_opts, :repo) || Keyword.get(merge_opts, :repo)

    if repo do
      {sql, _params} = repo.to_sql(:all, query)
      "(#{sql})"
    else
      raise ArgumentError, "Merge with query source requires :repo option"
    end
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
  # Execution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Execute the MERGE operation directly.

  ## Options

  - `:repo` - Ecto repo to use (required)
  - `:timeout` - Query timeout
  - `:prefix` - Database schema prefix

  ## Examples

      User
      |> OmQuery.Merge.new(data)
      |> OmQuery.Merge.match_on(:email)
      |> OmQuery.Merge.when_matched(:update, [:name])
      |> OmQuery.Merge.when_not_matched(:insert)
      |> OmQuery.Merge.execute(repo: MyApp.Repo)
  """
  @spec execute(t(), keyword()) :: {:ok, [struct()]} | {:error, term()}
  def execute(%Merge{} = merge, opts \\ []) do
    merged_opts = Keyword.merge(merge.opts, opts)

    with :ok <- validate(merge) do
      repo = Config.repo!(merged_opts)
      sql_opts = Config.sql_opts(merged_opts)
      {sql, params} = to_sql(merge, merged_opts)

      case repo.query(sql, params, sql_opts) do
        {:ok, %{rows: rows, columns: columns}} ->
          {:ok, rows_to_structs(merge.schema, columns, rows)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp rows_to_structs(schema, columns, rows) do
    fields = Enum.map(columns, &String.to_existing_atom/1)

    Enum.map(rows, fn row ->
      attrs = Enum.zip(fields, row) |> Map.new()
      struct(schema, attrs)
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Introspection
  # ─────────────────────────────────────────────────────────────

  @doc """
  Check if the Merge token has any WHEN MATCHED clauses.
  """
  @spec has_matched_clauses?(t()) :: boolean()
  def has_matched_clauses?(%Merge{when_matched: []}), do: false
  def has_matched_clauses?(%Merge{when_matched: [_ | _]}), do: true

  @doc """
  Check if the Merge token has any WHEN NOT MATCHED clauses.
  """
  @spec has_not_matched_clauses?(t()) :: boolean()
  def has_not_matched_clauses?(%Merge{when_not_matched: []}), do: false
  def has_not_matched_clauses?(%Merge{when_not_matched: [_ | _]}), do: true

  @doc """
  Get the number of source records.
  """
  @spec source_count(t()) :: non_neg_integer() | :unknown
  def source_count(%Merge{source: nil}), do: 0
  def source_count(%Merge{source: source}) when is_map(source), do: 1
  def source_count(%Merge{source: sources}) when is_list(sources), do: length(sources)
  def source_count(%Merge{}), do: :unknown
end

defimpl Inspect, for: OmQuery.Merge do
  alias OmQuery.Merge

  def inspect(%Merge{} = merge, _opts) do
    schema_name = merge.schema |> Module.split() |> List.last()
    match_on = merge.match_on || []
    source_info = Merge.source_count(merge)

    "#OmQuery.Merge<#{schema_name}, match: #{inspect(match_on)}, source: #{source_info}>"
  end
end
