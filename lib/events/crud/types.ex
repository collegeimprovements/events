defmodule Events.CRUD.Types do
  @moduledoc """
  Comprehensive type specifications for the CRUD system.

  This module defines all types used throughout the CRUD system for better
  type safety, documentation, and IDE support.
  """

  # Basic types
  @type operation_type :: atom()
  # Simple field or join field
  @type field :: atom() | {atom(), atom()}
  @type value :: term()
  @type options :: keyword()

  # Operation specifications
  @type where_spec :: {field(), atom(), value(), options()}
  @type join_spec :: {atom(), atom(), options()} | {module(), atom(), options()}
  @type order_spec :: {field(), :asc | :desc, options()}
  @type preload_spec :: {atom(), preload_nested()} | {atom(), (Ecto.Query.t() -> Ecto.Query.t())}
  @type preload_nested :: [operation()]
  @type paginate_spec :: {:offset | :cursor, options()}
  @type select_spec :: {term(), options()}
  @type group_spec :: {[field()], options()}
  @type having_spec :: {keyword(), options()}
  @type raw_spec :: {:sql | :fragment, String.t(), %{String.t() => term()}}
  @type debug_spec :: String.t() | nil
  @type create_spec :: {module(), map(), options()}
  @type update_spec :: {Ecto.Schema.t(), map(), options()}
  @type delete_spec :: {Ecto.Schema.t(), options()}
  @type get_spec :: {module(), term(), options()}
  @type list_spec :: {module(), options()}

  # Union type for all operation specs
  @type operation_spec ::
          where_spec()
          | join_spec()
          | order_spec()
          | preload_spec()
          | paginate_spec()
          | select_spec()
          | group_spec()
          | having_spec()
          | raw_spec()
          | debug_spec()
          | create_spec()
          | update_spec()
          | delete_spec()
          | get_spec()
          | list_spec()

  # Operations
  @type operation :: {operation_type(), operation_spec()}

  # Tokens
  @type token :: %{
          operations: [operation()],
          validated: boolean(),
          executed: boolean(),
          metadata: map()
        }

  # Validation
  @type validation_result :: :ok | {:error, String.t()}

  # Results
  @type result_metadata :: %{
          pagination: pagination_metadata(),
          timing: timing_metadata(),
          optimization: optimization_metadata(),
          query_info: query_info_metadata(),
          operation: atom() | nil
        }

  @type pagination_metadata :: %{
          type: :offset | :cursor | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil,
          cursor: String.t() | nil,
          has_more: boolean(),
          current_page: pos_integer() | nil,
          next_cursor: String.t() | nil,
          prev_cursor: String.t() | nil,
          total_count: non_neg_integer() | nil,
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

  @type query_info_metadata :: %{
          schema: module() | nil,
          operation_count: non_neg_integer(),
          has_raw_sql: boolean(),
          complexity_score: non_neg_integer(),
          operations_used: [operation_type()],
          sql_generated: String.t() | nil
        }

  @type crud_result :: %{
          success: boolean(),
          data: term(),
          error: String.t() | nil,
          metadata: result_metadata()
        }

  # Configuration
  @type config :: %{
          default_limit: pos_integer(),
          max_limit: pos_integer(),
          timeout: pos_integer(),
          optimization: boolean(),
          caching: boolean(),
          observability: boolean(),
          timing: boolean(),
          opentelemetry: boolean()
        }

  # Context for optimization
  @type optimization_context :: %{
          schema: module() | nil,
          available_indexes: [map()],
          table_stats: map(),
          query_complexity: non_neg_integer()
        }

  # DSL query block
  @type query_block :: (-> term())

  # Supported operators
  @type where_operator ::
          :eq
          | :neq
          | :gt
          | :gte
          | :lt
          | :lte
          | :in
          | :not_in
          | :like
          | :ilike
          | :between
          | :is_nil
          | :not_nil
          | :contains
          | :contained_by
          | :jsonb_contains
          | :jsonb_has_key

  @type join_type :: :inner | :left | :right | :full | :cross

  # Error types
  @type error_type ::
          :validation_error
          | :database_error
          | :not_found
          | :permission_denied
          | :timeout
          | :invalid_operation

  # Plugin system
  @type plugin :: %{
          name: atom(),
          operations: [operation_type()],
          hooks: keyword((term() -> term()))
        }
end
