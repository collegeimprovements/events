defmodule OmSchema.SchemaDiff do
  @moduledoc """
  Runtime schema diffing - compares Ecto schema definitions to the actual database.

  This module is useful for:
  - Detecting drift between schema and database
  - Validating migrations are complete
  - Generating migration stubs for missing changes
  - CI/CD checks to ensure schema/DB sync

  ## Usage

      # Compare a single schema
      diff = OmSchema.SchemaDiff.diff(MyApp.User, repo: MyApp.Repo)

      # Compare multiple schemas
      diffs = OmSchema.SchemaDiff.diff_all([MyApp.User, MyApp.Account], repo: MyApp.Repo)

      # Format for display
      OmSchema.SchemaDiff.format(diff)

  ## Diff Structure

  The diff returns a map with:

    * `:module` - The schema module
    * `:table` - The database table name
    * `:in_sync` - Boolean indicating if schema matches DB
    * `:missing_in_db` - Columns/constraints in schema but not in DB
    * `:missing_in_schema` - Columns/constraints in DB but not in schema
    * `:type_mismatches` - Columns with incompatible types
    * `:nullable_mismatches` - Columns with different nullability
    * `:constraint_mismatches` - Constraint differences

  ## Example Output

      %{
        module: MyApp.User,
        table: "users",
        in_sync: false,
        missing_in_db: [
          {:column, :new_field}
        ],
        missing_in_schema: [
          {:column, :legacy_field}
        ],
        type_mismatches: [
          {:column, :status, :string, "integer"}
        ],
        nullable_mismatches: [
          {:column, :email, :required, :nullable}
        ]
      }

  """

  alias OmSchema.DatabaseValidator.{PgIntrospection, TypeMapper}

  @type diff_result :: %{
          module: module(),
          table: String.t(),
          in_sync: boolean(),
          missing_in_db: [missing_item()],
          missing_in_schema: [missing_item()],
          type_mismatches: [type_mismatch()],
          nullable_mismatches: [nullable_mismatch()],
          constraint_mismatches: [constraint_mismatch()]
        }

  @type missing_item :: {:column, atom()} | {:constraint, atom()}
  @type type_mismatch :: {:column, atom(), atom() | tuple(), String.t()}
  @type nullable_mismatch :: {:column, atom(), :required | :optional, :nullable | :not_null}
  @type constraint_mismatch :: {:constraint, atom(), :missing | :extra | :different}

  @doc """
  Compares an Ecto schema module to its corresponding database table.

  ## Options

    * `:repo` - The Ecto repo to use (required if not configured globally)
    * `:schema` - The database schema/namespace (default: "public")
    * `:include_constraints` - Whether to check constraints (default: true)
    * `:include_indexes` - Whether to check indexes (default: false)
    * `:ignore_columns` - List of column names to ignore (default: [])
    * `:ignore_constraints` - List of constraint names to ignore (default: [])

  ## Examples

      OmSchema.SchemaDiff.diff(MyApp.User, repo: MyApp.Repo)

      OmSchema.SchemaDiff.diff(MyApp.User,
        repo: MyApp.Repo,
        ignore_columns: [:inserted_at, :updated_at]
      )

  """
  @spec diff(module(), keyword()) :: diff_result() | {:error, term()}
  def diff(schema_module, opts \\ []) do
    repo = get_repo(opts)
    db_schema = Keyword.get(opts, :schema, "public")
    table_name = get_table_name(schema_module)

    with :ok <- validate_repo(repo),
         true <- PgIntrospection.table_exists?(repo, table_name, db_schema) do
      do_diff(schema_module, repo, table_name, db_schema, opts)
    else
      false ->
        %{
          module: schema_module,
          table: table_name,
          in_sync: false,
          missing_in_db: [{:table, table_name}],
          missing_in_schema: [],
          type_mismatches: [],
          nullable_mismatches: [],
          constraint_mismatches: []
        }

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Compares multiple schema modules to their database tables.

  Returns a list of diff results.

  ## Options

  Same as `diff/2`, plus:

    * `:parallel` - Whether to run diffs in parallel (default: false)

  """
  @spec diff_all([module()], keyword()) :: [diff_result()]
  def diff_all(schema_modules, opts \\ []) do
    parallel = Keyword.get(opts, :parallel, false)

    if parallel do
      schema_modules
      |> Task.async_stream(fn mod -> diff(mod, opts) end, timeout: 30_000)
      |> Enum.map(fn {:ok, result} -> result end)
    else
      Enum.map(schema_modules, fn mod -> diff(mod, opts) end)
    end
  end

  @doc """
  Checks if all given schemas are in sync with the database.

  Returns `true` only if all schemas match their database tables.
  """
  @spec in_sync?([module()], keyword()) :: boolean()
  def in_sync?(schema_modules, opts \\ []) do
    schema_modules
    |> diff_all(opts)
    |> Enum.all?(& &1.in_sync)
  end

  @doc """
  Formats a diff result as a human-readable string.

  ## Options

    * `:color` - Whether to use ANSI colors (default: false)
    * `:verbose` - Whether to include all details (default: false)

  """
  @spec format(diff_result(), keyword()) :: String.t()
  def format(diff, opts \\ []) do
    use_color = Keyword.get(opts, :color, false)
    verbose = Keyword.get(opts, :verbose, false)

    lines = [
      format_header(diff, use_color),
      format_missing_in_db(diff.missing_in_db, use_color),
      format_missing_in_schema(diff.missing_in_schema, use_color, verbose),
      format_type_mismatches(diff.type_mismatches, use_color),
      format_nullable_mismatches(diff.nullable_mismatches, use_color),
      format_constraint_mismatches(diff.constraint_mismatches, use_color)
    ]

    lines
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  @doc """
  Generates migration code to bring the database in sync with the schema.

  Note: This is a best-effort generation and may need manual adjustment.

  ## Options

    * `:module_name` - Migration module name (default: auto-generated)
    * `:version` - Migration version (default: current timestamp)

  """
  @spec generate_migration(diff_result(), keyword()) :: String.t()
  def generate_migration(diff, opts \\ []) do
    _timestamp = Keyword.get(opts, :version, generate_timestamp())
    module_name = Keyword.get(opts, :module_name, generate_module_name(diff))

    up_statements = generate_up_statements(diff)
    down_statements = generate_down_statements(diff)

    """
    defmodule #{module_name} do
      use Ecto.Migration

      def up do
    #{indent(up_statements, 4)}
      end

      def down do
    #{indent(down_statements, 4)}
      end
    end
    """
  end

  # ============================================
  # Private Implementation
  # ============================================

  defp do_diff(schema_module, repo, table_name, db_schema, opts) do
    ignore_columns = Keyword.get(opts, :ignore_columns, [])
    ignore_constraints = Keyword.get(opts, :ignore_constraints, [])
    include_constraints = Keyword.get(opts, :include_constraints, true)

    # Get schema info
    schema_fields = get_schema_fields(schema_module)
    schema_fields = Enum.reject(schema_fields, fn {name, _, _} -> name in ignore_columns end)

    # Get DB info
    db_columns = PgIntrospection.columns(repo, table_name, db_schema)
    db_columns = Enum.reject(db_columns, fn col -> col.name in ignore_columns end)

    # Compare columns
    {missing_in_db, missing_in_schema, type_mismatches, nullable_mismatches} =
      compare_columns(schema_fields, db_columns)

    # Compare constraints if enabled
    constraint_mismatches =
      if include_constraints do
        compare_constraints(schema_module, repo, table_name, db_schema, ignore_constraints)
      else
        []
      end

    in_sync =
      missing_in_db == [] &&
        missing_in_schema == [] &&
        type_mismatches == [] &&
        nullable_mismatches == [] &&
        constraint_mismatches == []

    %{
      module: schema_module,
      table: table_name,
      in_sync: in_sync,
      missing_in_db: missing_in_db,
      missing_in_schema: missing_in_schema,
      type_mismatches: type_mismatches,
      nullable_mismatches: nullable_mismatches,
      constraint_mismatches: constraint_mismatches
    }
  end

  defp get_schema_fields(schema_module) do
    # Get fields from Ecto schema
    schema_module.__schema__(:fields)
    |> Enum.map(fn field ->
      type = schema_module.__schema__(:type, field)

      # Get validation opts for required/nullable info
      required =
        if function_exported?(schema_module, :field_validations, 0) do
          schema_module.field_validations()
          |> Enum.find(fn {name, _, _} -> name == field end)
          |> case do
            {_, _, opts} -> Keyword.get(opts, :required, false)
            nil -> false
          end
        else
          false
        end

      {field, type, required}
    end)
  end

  defp compare_columns(schema_fields, db_columns) do
    schema_names = MapSet.new(schema_fields, fn {name, _, _} -> name end)
    db_names = MapSet.new(db_columns, fn col -> col.name end)

    # Find missing columns
    missing_in_db =
      schema_names
      |> MapSet.difference(db_names)
      |> Enum.map(&{:column, &1})

    missing_in_schema =
      db_names
      |> MapSet.difference(schema_names)
      |> Enum.map(&{:column, &1})

    # Find type and nullable mismatches for matching columns
    common_names = MapSet.intersection(schema_names, db_names)

    {type_mismatches, nullable_mismatches} =
      Enum.reduce(common_names, {[], []}, fn name, {type_acc, null_acc} ->
        {_, schema_type, schema_required} = Enum.find(schema_fields, fn {n, _, _} -> n == name end)
        db_col = Enum.find(db_columns, fn col -> col.name == name end)

        # Check type compatibility
        type_acc =
          if TypeMapper.compatible?(schema_type, db_col.data_type) do
            type_acc
          else
            [{:column, name, schema_type, db_col.data_type} | type_acc]
          end

        # Check nullable mismatch
        null_acc =
          if TypeMapper.nullable_mismatch?(schema_required, db_col.is_nullable) do
            schema_null = if schema_required, do: :required, else: :optional
            db_null = if db_col.is_nullable, do: :nullable, else: :not_null
            [{:column, name, schema_null, db_null} | null_acc]
          else
            null_acc
          end

        {type_acc, null_acc}
      end)

    {missing_in_db, missing_in_schema, type_mismatches, nullable_mismatches}
  end

  defp compare_constraints(schema_module, repo, table_name, db_schema, ignore_constraints) do
    # Get expected constraints from schema
    schema_constraints =
      if function_exported?(schema_module, :__constraints__, 0) do
        constraints = schema_module.__constraints__()

        # Collect all constraint names
        unique_names = Enum.map(constraints.unique || [], & &1.name)
        fk_names = Enum.map(constraints.foreign_key || [], & &1.name)
        check_names = Enum.map(constraints.check || [], & &1.name)

        MapSet.new(unique_names ++ fk_names ++ check_names)
      else
        MapSet.new()
      end

    # Filter out ignored constraints
    schema_constraints = MapSet.difference(schema_constraints, MapSet.new(ignore_constraints))

    # Get actual constraints from DB
    db_constraints =
      PgIntrospection.constraints(repo, table_name, db_schema)
      |> Enum.map(& &1.name)
      |> MapSet.new()
      |> MapSet.difference(MapSet.new(ignore_constraints))

    # Find differences
    missing =
      schema_constraints
      |> MapSet.difference(db_constraints)
      |> Enum.map(&{:constraint, &1, :missing})

    extra =
      db_constraints
      |> MapSet.difference(schema_constraints)
      |> Enum.map(&{:constraint, &1, :extra})

    missing ++ extra
  end

  defp get_table_name(schema_module) do
    schema_module.__schema__(:source)
  end

  defp get_repo(opts) do
    Keyword.get(opts, :repo) ||
      Application.get_env(:om_schema, :default_repo)
  end

  defp validate_repo(nil), do: {:error, :repo_not_configured}
  defp validate_repo(_repo), do: :ok

  # ============================================
  # Formatting Helpers
  # ============================================

  defp format_header(diff, use_color) do
    status = if diff.in_sync, do: "✓ IN SYNC", else: "✗ OUT OF SYNC"
    status = if use_color, do: colorize(status, if(diff.in_sync, do: :green, else: :red)), else: status

    "#{inspect(diff.module)} (#{diff.table}): #{status}"
  end

  defp format_missing_in_db([], _), do: nil

  defp format_missing_in_db(items, _use_color) do
    header = "  Missing in database:"
    lines = Enum.map(items, fn {type, name} -> "    - #{type}: #{name}" end)
    [header | lines]
  end

  defp format_missing_in_schema([], _, _), do: nil

  defp format_missing_in_schema(items, _use_color, _verbose) do
    header = "  Extra in database (not in schema):"
    lines = Enum.map(items, fn {type, name} -> "    - #{type}: #{name}" end)
    [header | lines]
  end

  defp format_type_mismatches([], _), do: nil

  defp format_type_mismatches(items, _use_color) do
    header = "  Type mismatches:"

    lines =
      Enum.map(items, fn {:column, name, schema_type, db_type} ->
        "    - #{name}: schema has #{inspect(schema_type)}, DB has #{db_type}"
      end)

    [header | lines]
  end

  defp format_nullable_mismatches([], _), do: nil

  defp format_nullable_mismatches(items, _use_color) do
    header = "  Nullable mismatches:"

    lines =
      Enum.map(items, fn {:column, name, schema_null, db_null} ->
        "    - #{name}: schema is #{schema_null}, DB is #{db_null}"
      end)

    [header | lines]
  end

  defp format_constraint_mismatches([], _), do: nil

  defp format_constraint_mismatches(items, _use_color) do
    header = "  Constraint differences:"

    lines =
      Enum.map(items, fn {:constraint, name, status} ->
        "    - #{name}: #{status}"
      end)

    [header | lines]
  end

  defp colorize(text, :green), do: "\e[32m#{text}\e[0m"
  defp colorize(text, :red), do: "\e[31m#{text}\e[0m"
  defp colorize(text, _), do: text

  # ============================================
  # Migration Generation Helpers
  # ============================================

  defp generate_up_statements(diff) do
    column_adds =
      Enum.map(diff.missing_in_db, fn
        {:column, name} ->
          # We'd need type info to generate proper add_column
          "add :#{name}, :string  # TODO: verify type"

        {:table, table} ->
          "# Table #{table} does not exist - create it first"

        _ ->
          nil
      end)

    type_alters =
      Enum.map(diff.type_mismatches, fn {:column, name, _schema_type, _db_type} ->
        "# modify :#{name}, :new_type  # TODO: update type"
      end)

    nullable_alters =
      Enum.map(diff.nullable_mismatches, fn {:column, name, :required, :nullable} ->
        "modify :#{name}, null: false"
      end)

    constraint_adds =
      Enum.flat_map(diff.constraint_mismatches, fn
        {:constraint, name, :missing} ->
          ["# create constraint :#{name}  # TODO: add constraint"]

        _ ->
          []
      end)

    (column_adds ++ type_alters ++ nullable_alters ++ constraint_adds)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp generate_down_statements(diff) do
    column_removes =
      Enum.map(diff.missing_in_db, fn
        {:column, name} -> "remove :#{name}"
        _ -> nil
      end)

    nullable_reverts =
      Enum.map(diff.nullable_mismatches, fn {:column, name, :required, :nullable} ->
        "modify :#{name}, null: true"
      end)

    (column_removes ++ nullable_reverts)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp generate_timestamp do
    {{y, m, d}, {h, min, s}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(h)}#{pad(min)}#{pad(s)}"
  end

  defp generate_module_name(diff) do
    table = diff.table |> String.replace(~r/[^a-z0-9_]/i, "_") |> Macro.camelize()
    "SyncSchema#{table}"
  end

  defp pad(int), do: int |> Integer.to_string() |> String.pad_leading(2, "0")

  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map(&(prefix <> &1))
    |> Enum.join("\n")
  end
end
