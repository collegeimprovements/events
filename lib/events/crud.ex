defmodule Events.CRUD do
  @moduledoc """
  Ultra-clean, unified CRUD service with consistent operation pattern.

  ## Overview

  This module provides a composable, pipeline-based approach to database operations.
  All operations follow the consistent `{operation_type, spec}` pattern and can be
  chained together using tokens.

  ## Basic Usage

  ```elixir
  # Create a token and add operations
  token = Events.CRUD.new_token()
           |> Events.CRUD.where(:status, :eq, "active")
           |> Events.CRUD.order(:created_at, :desc)
           |> Events.CRUD.limit(10)

  # Execute the query
  result = Events.CRUD.execute(token)
  ```

  ## Using the DSL

  For more readable query construction, use the DSL:

  ```elixir
  import Events.CRUD.DSL

  result = query User do
    where :status, :eq, "active"
    order :created_at, :desc
    limit 10
  end
  ```

  ## Operation Types

  - `:where` - Filter records with various operators
  - `:join` - Join with associated tables (supports custom `on:` conditions)
  - `:order` - Sort results
  - `:preload` - Load associated data
  - `:paginate` - Pagination (offset or cursor-based)
  - `:select` - Select specific fields
  - `:group` - Group records
  - `:having` - Filter grouped results
  - `:raw` - Execute raw SQL
  - `:debug` - Print current query and SQL (for debugging)
  - `:create`, `:update`, `:delete` - CRUD operations
  - `:get`, `:list` - Retrieve operations

  ## Pure Ecto Functions

  For programmatic query building without macros, use `Events.CRUD.Query`:

  ```elixir
  User
  |> Events.CRUD.Query.where(:status, :eq, "active")
  |> Events.CRUD.Query.order(:created_at, :desc)
  |> Events.CRUD.Query.limit(10)
  |> Events.CRUD.Query.debug("Check query")
  |> Events.CRUD.Query.execute()
  ```

  ## Pure Ecto Functions

  For programmatic query building without macros, use `Events.CRUD.Query`:

  ```elixir
  User
  |> Events.CRUD.Query.where(:status, :eq, "active")
  |> Events.CRUD.Query.order(:created_at, :desc)
  |> Events.CRUD.Query.limit(10)
  |> Events.CRUD.Query.debug("Check query")
   |> Events.CRUD.Query.execute()
   ```

   ## Advanced Join Examples

   ### Association Joins
   ```elixir
   query User do
     join :posts, :left
     join :comments, :inner
   end
   ```

   ### Custom Joins with `on:` Conditions
   ```elixir
   query User do
     # Join posts with custom conditions
     join Post, :posts, on: posts.user_id == user.id and posts.published == true, type: :left

     # Join comments with additional filters
     join Comment, :comments, on: comments.post_id == posts.id and comments.approved == true
   end
   ```

   ### Pure Function Approach
   ```elixir
   User
   |> Events.CRUD.Query.join(Post, :posts, on: posts.user_id == user.id and posts.status == "published", type: :left)
   |> Events.CRUD.Query.join(Comment, :comments, on: comments.post_id == posts.id)
   ```

  ## Configuration

  Configure via application environment:

  ```elixir
  config :events,
    crud_default_limit: 20,        # Default pagination limit
    crud_max_limit: 1000,          # Maximum allowed limit
    crud_timeout: 30_000,          # Query timeout (30 seconds)
    crud_optimization: true,       # Enable query optimization
    crud_caching: false,           # Result caching (disabled)
    crud_observability: false,     # Monitoring (disabled)
    crud_timing: false             # Execution timing (disabled)
  ```

  ## Error Handling

  All operations return `Events.CRUD.Result` structs with consistent error handling:

  ```elixir
  case result do
    %Events.CRUD.Result{success: true, data: records} -> {:ok, records}
    %Events.CRUD.Result{success: false, error: error} -> {:error, error}
  end
  ```
  """

  # Token management
  @doc "Creates a new empty token"
  defdelegate new_token(), to: Events.CRUD.Token, as: :new

  @doc "Creates a new token with a schema"
  defdelegate new_token(schema), to: Events.CRUD.Token, as: :new

  @doc "Creates a new build-only token with a schema"
  def build_token(schema) do
    Events.CRUD.Token.new(schema, build_only: true)
  end

  @doc "Executes a token and returns a result or query"
  defdelegate execute(token), to: Events.CRUD.Token

  # Token operations
  @doc "Adds an operation to a token"
  defdelegate add_operation(token, operation), to: Events.CRUD.Token, as: :add

  @doc "Removes operations of a specific type from a token"
  defdelegate remove_operation(token, op_type), to: Events.CRUD.Token, as: :remove

  @doc "Replaces operations of a specific type in a token"
  defdelegate replace_operation(token, op_type, new_op), to: Events.CRUD.Token, as: :replace

  # Configuration
  @doc "Gets a configuration value"
  defdelegate config(key), to: Events.CRUD.Config

  # Result constructors
  @doc "Creates a success result"
  defdelegate success(data, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates an error result"
  defdelegate error(error, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a result for a created record"
  defdelegate created(record, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a result for an updated record"
  defdelegate updated(record, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a result for a deleted record"
  defdelegate deleted(record, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a result for a found record"
  defdelegate found(record, metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a not found result"
  defdelegate not_found(metadata \\ %{}), to: Events.CRUD.Result

  @doc "Creates a result for a list of records with pagination"
  defdelegate list(records, pagination_meta, metadata \\ %{}), to: Events.CRUD.Result
end
