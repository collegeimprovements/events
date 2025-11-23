defmodule Events.Repo.Migration.Indexes do
  @moduledoc """
  Index creation macros with pattern matching and pipelines.

  Provides a clean DSL for creating various types of indexes
  with automatic naming and configuration.
  """

  use Ecto.Migration

  @doc """
  Creates indexes for name fields.

  ## Examples

      # Basic indexes
      name_indexes(:users)

      # With unique constraint
      name_indexes(:users, unique: true)

      # With custom fields
      name_indexes(:users, fields: [:first_name, :last_name])

      # With fulltext search
      name_indexes(:users, fulltext: true)
  """
  defmacro name_indexes(table, opts \\ []) do
    quote bind_quoted: [table: table, opts: opts] do
      opts
      |> Events.Repo.Migration.Indexes.build_name_indexes(table)
      |> Events.Repo.Migration.Indexes.create_indexes()
    end
  end

  @doc false
  def build_name_indexes(opts, table) do
    fields = Keyword.get(opts, :fields, [:first_name, :last_name, :display_name])
    unique = Keyword.get(opts, :unique, false)
    fulltext = Keyword.get(opts, :fulltext, false)

    indexes =
      fields
      |> Enum.map(&build_field_index(&1, table, unique: unique))
      |> add_composite_indexes(table, fields)
      |> add_fulltext_index_if_needed(table, fields, fulltext)

    indexes
  end

  defp build_field_index(field, table, opts) do
    %{
      table: table,
      columns: [field],
      unique: Keyword.get(opts, :unique, false),
      name: index_name(table, [field])
    }
  end

  defp add_composite_indexes(indexes, table, fields) when length(fields) > 1 do
    composite = %{
      table: table,
      columns: fields,
      unique: false,
      name: index_name(table, fields)
    }

    [composite | indexes]
  end

  defp add_composite_indexes(indexes, _, _), do: indexes

  defp add_fulltext_index_if_needed(indexes, table, fields, true) do
    fulltext = %{
      table: table,
      columns: fields,
      using: :gin,
      name: index_name(table, fields, "fulltext")
    }

    [fulltext | indexes]
  end

  defp add_fulltext_index_if_needed(indexes, _, _, false), do: indexes

  @doc """
  Creates indexes for status field.

  ## Examples

      # Basic status index
      status_indexes(:orders)

      # With partial index for active records
      status_indexes(:orders, partial: "status != 'deleted'")

      # Multiple status fields
      status_indexes(:orders, fields: [:status, :payment_status])
  """
  defmacro status_indexes(table, opts \\ []) do
    quote bind_quoted: [table: table, opts: opts] do
      opts
      |> Events.Repo.Migration.Indexes.build_status_indexes(table)
      |> Events.Repo.Migration.Indexes.create_indexes()
    end
  end

  @doc false
  def build_status_indexes(opts, table) do
    fields = Keyword.get(opts, :fields, [:status])
    partial = Keyword.get(opts, :partial)

    fields
    |> Enum.map(&build_status_index(&1, table, partial: partial))
    |> add_active_status_index(table, partial)
  end

  defp build_status_index(field, table, opts) do
    base_index = %{
      table: table,
      columns: [field],
      name: index_name(table, [field])
    }

    case Keyword.get(opts, :partial) do
      nil -> base_index
      where_clause -> Map.put(base_index, :where, where_clause)
    end
  end

  defp add_active_status_index(indexes, table, nil) do
    active_index = %{
      table: table,
      columns: [:status],
      where: "status IN ('active', 'published')",
      name: index_name(table, [:status], "active")
    }

    [active_index | indexes]
  end

  defp add_active_status_index(indexes, _, _), do: indexes

  @doc """
  Creates indexes for timestamp fields.

  ## Examples

      # Basic timestamp indexes
      timestamp_indexes(:events)

      # With custom fields
      timestamp_indexes(:events, fields: [:created_at, :updated_at, :published_at])

      # With descending order
      timestamp_indexes(:events, order: :desc)
  """
  defmacro timestamp_indexes(table, opts \\ []) do
    quote bind_quoted: [table: table, opts: opts] do
      opts
      |> Events.Repo.Migration.Indexes.build_timestamp_indexes(table)
      |> Events.Repo.Migration.Indexes.create_indexes()
    end
  end

  @doc false
  def build_timestamp_indexes(opts, table) do
    fields = Keyword.get(opts, :fields, [:created_at, :updated_at])
    order = Keyword.get(opts, :order, :asc)

    fields
    |> Enum.map(&build_timestamp_index(&1, table, order))
    |> add_composite_timestamp_index(table, fields, order)
  end

  defp build_timestamp_index(field, table, order) do
    %{
      table: table,
      columns: [field],
      order: order,
      name: index_name(table, [field], to_string(order))
    }
  end

  defp add_composite_timestamp_index(indexes, table, fields, order) when length(fields) > 1 do
    composite = %{
      table: table,
      columns: fields,
      order: order,
      name: index_name(table, fields, "composite_#{order}")
    }

    [composite | indexes]
  end

  defp add_composite_timestamp_index(indexes, _, _, _), do: indexes

  @doc """
  Creates indexes for deleted fields (soft delete).

  ## Examples

      # Basic soft delete indexes
      deleted_indexes(:users)

      # With partial index for non-deleted records
      deleted_indexes(:users, active_index: true)
  """
  defmacro deleted_indexes(table, opts \\ []) do
    quote bind_quoted: [table: table, opts: opts] do
      opts
      |> Events.Repo.Migration.Indexes.build_deleted_indexes(table)
      |> Events.Repo.Migration.Indexes.create_indexes()
    end
  end

  @doc false
  def build_deleted_indexes(opts, table) do
    active_index = Keyword.get(opts, :active_index, true)

    base_indexes = [
      %{
        table: table,
        columns: [:deleted_at],
        name: index_name(table, [:deleted_at])
      }
    ]

    if active_index do
      active = %{
        table: table,
        columns: [:id],
        where: "deleted_at IS NULL",
        name: index_name(table, [:id], "active")
      }

      [active | base_indexes]
    else
      base_indexes
    end
  end

  @doc """
  Creates GIN index for JSONB metadata field.

  ## Examples

      # Basic metadata index
      metadata_index(:products)

      # Custom field name
      metadata_index(:products, field: :properties)

      # With specific paths
      metadata_index(:products, paths: ["tags", "categories"])
  """
  defmacro metadata_index(table, opts \\ []) do
    quote bind_quoted: [table: table, opts: opts] do
      opts
      |> Events.Repo.Migration.Indexes.build_metadata_index(table)
      |> Events.Repo.Migration.Indexes.create_index()
    end
  end

  @doc false
  def build_metadata_index(opts, table) do
    field = Keyword.get(opts, :field, :metadata)
    paths = Keyword.get(opts, :paths, [])

    base_index = %{
      table: table,
      columns: [field],
      using: :gin,
      name: index_name(table, [field], "gin")
    }

    if length(paths) > 0 do
      path_indexes =
        paths
        |> Enum.map(&build_path_index(&1, field, table))

      [base_index | path_indexes]
    else
      [base_index]
    end
  end

  defp build_path_index(path, field, table) do
    %{
      table: table,
      columns: ["(#{field}->>'#{path}')"],
      name: index_name(table, [field, path], "path")
    }
  end

  @doc """
  Creates a custom unique index with options.

  ## Examples

      # Basic unique index
      unique_index(:users, :email)

      # Composite unique index
      unique_index(:products, [:category, :sku])

      # Partial unique index
      unique_index(:users, :email, where: "deleted_at IS NULL")
  """
  defmacro unique_index(table, columns, opts \\ []) do
    columns = List.wrap(columns)

    quote bind_quoted: [table: table, columns: columns, opts: opts] do
      index_def = Events.Repo.Migration.Indexes.build_unique_index(opts, table, columns)
      Events.Repo.Migration.Indexes.create_index(index_def)
    end
  end

  @doc false
  def build_unique_index(opts, table, columns) do
    base_index = %{
      table: table,
      columns: columns,
      unique: true,
      name: Keyword.get(opts, :name, unique_index_name(table, columns))
    }

    case Keyword.get(opts, :where) do
      nil -> base_index
      where_clause -> Map.put(base_index, :where, where_clause)
    end
  end

  # ============================================
  # Index Creation Helpers
  # ============================================

  @doc false
  def create_indexes(index_definitions) when is_list(index_definitions) do
    Enum.each(index_definitions, &create_index/1)
  end

  @doc false
  def create_index(%{table: table, columns: columns} = index_def) do
    opts =
      index_def
      |> Map.drop([:table, :columns])
      |> Map.to_list()

    create index(table, columns, opts)
  end

  # ============================================
  # Naming Helpers
  # ============================================

  defp index_name(table, columns, suffix \\ nil) do
    base = "#{table}_" <> Enum.join(columns, "_") <> "_index"
    if suffix, do: "#{base}_#{suffix}", else: base
  end

  defp unique_index_name(table, columns) do
    "#{table}_" <> Enum.join(columns, "_") <> "_unique"
  end
end
