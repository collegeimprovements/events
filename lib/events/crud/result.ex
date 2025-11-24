defmodule Events.CRUD.Result do
  @moduledoc """
  Consistent result shape across all operations.
  """

  @type pagination_metadata :: %{
          type: :offset | :cursor | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          cursor: String.t() | nil,
          next_cursor: String.t() | nil,
          prev_cursor: String.t() | nil,
          has_more: boolean(),
          total_count: non_neg_integer() | nil,
          current_page: pos_integer() | nil,
          total_pages: pos_integer() | nil
        }

  @type timing_metadata :: %{
          total_time: non_neg_integer(),
          build_time: non_neg_integer(),
          execution_time: non_neg_integer(),
          optimization_time: non_neg_integer(),
          validation_time: non_neg_integer()
        }

  @type optimization_metadata :: %{
          applied: boolean(),
          operations_reordered: boolean(),
          filters_merged: boolean(),
          joins_optimized: boolean(),
          preloads_optimized: boolean()
        }

  @type query_metadata :: %{
          operation_count: non_neg_integer(),
          has_raw_sql: boolean(),
          complexity_score: non_neg_integer(),
          sql_generated: String.t() | nil,
          schema: module() | nil,
          operations_used: [atom()]
        }

  @type metadata :: %{
          pagination: pagination_metadata(),
          timing: timing_metadata(),
          optimization: optimization_metadata(),
          query_info: query_metadata(),
          operation: atom() | nil
        }

  @type t :: %__MODULE__{
          success: boolean(),
          data: term(),
          metadata: metadata(),
          error: term() | nil
        }

  defstruct success: true, data: nil, metadata: %{operation: nil}, error: nil

  # Consistent result constructors
  @spec success(term(), metadata()) :: t()
  def success(data, metadata \\ %{}) do
    %__MODULE__{success: true, data: data, metadata: normalize_metadata(metadata)}
  end

  @spec error(term(), metadata()) :: t()
  def error(error, metadata \\ %{}) do
    %__MODULE__{success: false, data: nil, error: error, metadata: normalize_metadata(metadata)}
  end

  # CRUD-specific results
  @spec created(Ecto.Schema.t(), metadata()) :: t()
  def created(record, metadata \\ %{}), do: success(record, Map.put(metadata, :operation, :create))

  @spec updated(Ecto.Schema.t(), metadata()) :: t()
  def updated(record, metadata \\ %{}), do: success(record, Map.put(metadata, :operation, :update))

  @spec deleted(Ecto.Schema.t(), metadata()) :: t()
  def deleted(record, metadata \\ %{}), do: success(record, Map.put(metadata, :operation, :delete))

  @spec found(Ecto.Schema.t(), metadata()) :: t()
  def found(record, metadata \\ %{}), do: success(record, Map.put(metadata, :operation, :get))

  @spec not_found(metadata()) :: t()
  def not_found(metadata \\ %{}), do: error(:not_found, Map.put(metadata, :operation, :get))

  @spec list([Ecto.Schema.t()], pagination_metadata(), metadata()) :: t()
  def list(records, pagination_meta, metadata \\ %{}) do
    full_meta = Map.merge(metadata, %{pagination: pagination_meta, operation: :list})
    success(records, full_meta)
  end

  # Metadata normalization
  defp normalize_metadata(metadata) do
    %{
      pagination: normalize_pagination_metadata(metadata[:pagination]),
      timing: normalize_timing_metadata(metadata[:timing]),
      optimization: normalize_optimization_metadata(metadata[:optimization]),
      query_info: normalize_query_metadata(metadata[:query_info]),
      operation: metadata[:operation]
    }
  end

  defp normalize_pagination_metadata(nil),
    do: %{
      type: nil,
      has_more: false,
      limit: nil,
      offset: nil,
      cursor: nil,
      next_cursor: nil,
      prev_cursor: nil,
      total_count: nil,
      current_page: nil,
      total_pages: nil
    }

  defp normalize_pagination_metadata(meta),
    do:
      Map.merge(
        %{
          type: nil,
          has_more: false,
          limit: nil,
          offset: nil,
          cursor: nil,
          next_cursor: nil,
          prev_cursor: nil,
          total_count: nil,
          current_page: nil,
          total_pages: nil
        },
        meta
      )

  defp normalize_timing_metadata(nil),
    do: %{total_time: 0, build_time: 0, execution_time: 0, optimization_time: 0, validation_time: 0}

  defp normalize_timing_metadata(meta),
    do:
      Map.merge(
        %{
          total_time: 0,
          build_time: 0,
          execution_time: 0,
          optimization_time: 0,
          validation_time: 0
        },
        meta
      )

  defp normalize_optimization_metadata(nil),
    do: %{
      applied: false,
      operations_reordered: false,
      filters_merged: false,
      joins_optimized: false,
      preloads_optimized: false
    }

  defp normalize_optimization_metadata(meta),
    do:
      Map.merge(
        %{
          applied: false,
          operations_reordered: false,
          filters_merged: false,
          joins_optimized: false,
          preloads_optimized: false
        },
        meta
      )

  defp normalize_query_metadata(nil),
    do: %{
      operation_count: 0,
      has_raw_sql: false,
      complexity_score: 0,
      sql_generated: nil,
      schema: nil,
      operations_used: []
    }

  defp normalize_query_metadata(meta),
    do:
      Map.merge(
        %{
          operation_count: 0,
          has_raw_sql: false,
          complexity_score: 0,
          sql_generated: nil,
          schema: nil,
          operations_used: []
        },
        meta
      )
end
