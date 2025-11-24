defmodule Events.Query.Multi do
  @moduledoc """
  Integration with Ecto.Multi for transactional query execution.

  Provides helpers to add query tokens to Ecto.Multi chains.

  ## Examples

      alias Events.Query.Multi, as: QM

      # Build a multi-step transaction
      Ecto.Multi.new()
      |> QM.query(:users, user_query_token)
      |> QM.query(:posts, post_query_token)
      |> QM.run(:process, fn _repo, %{users: users, posts: posts} ->
        # Process results
        {:ok, %{user_count: length(users.data), post_count: length(posts.data)}}
      end)
      |> Events.Repo.transaction()

      # With dependencies
      Ecto.Multi.new()
      |> QM.query(:active_users, fn _ ->
        User
        |> Events.Query.new()
        |> Events.Query.filter(:status, :eq, "active")
      end)
      |> QM.query(:user_posts, fn %{active_users: users} ->
        user_ids = Enum.map(users.data, & &1.id)

        Post
        |> Events.Query.new()
        |> Events.Query.filter(:user_id, :in, user_ids)
      end)
      |> Events.Repo.transaction()
  """

  alias Events.Query.{Token, Executor}
  alias Ecto.Multi

  @doc """
  Add a query token to an Ecto.Multi.

  ## Parameters

  - `multi` - The Ecto.Multi to add to
  - `name` - Name for this step
  - `token_or_fun` - Either a Token or a function that returns a Token

  ## Examples

      Multi.new()
      |> Events.Query.Multi.query(:users, user_token)

      Multi.new()
      |> Events.Query.Multi.query(:users, fn _ -> build_user_query() end)
  """
  @spec query(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query(multi, name, token_or_fun) when is_atom(name) do
    Multi.run(multi, name, fn repo, changes ->
      token =
        case token_or_fun do
          %Token{} = t -> t
          fun when is_function(fun, 1) -> fun.(changes)
        end

      result = Executor.execute!(token, repo: repo, telemetry: false)
      {:ok, result}
    end)
  end

  @doc """
  Add multiple queries as separate steps.

  ## Examples

      Multi.new()
      |> Events.Query.Multi.queries(%{
        users: user_token,
        posts: post_token,
        comments: comment_token
      })
  """
  @spec queries(Multi.t(), %{atom() => Token.t()}) :: Multi.t()
  def queries(multi, queries_map) when is_map(queries_map) do
    Enum.reduce(queries_map, multi, fn {name, token}, acc ->
      query(acc, name, token)
    end)
  end

  @doc """
  Execute a query and extract just the data.

  Useful when you want the raw data without the Result wrapper.

  ## Examples

      Multi.new()
      |> Events.Query.Multi.query_data(:users, user_token)
      |> Multi.run(:process, fn _repo, %{users: users} ->
        # users is a list, not a Result struct
        {:ok, Enum.count(users)}
      end)
  """
  @spec query_data(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_data(multi, name, token_or_fun) when is_atom(name) do
    Multi.run(multi, name, fn repo, changes ->
      token =
        case token_or_fun do
          %Token{} = t -> t
          fun when is_function(fun, 1) -> fun.(changes)
        end

      result = Executor.execute!(token, repo: repo, telemetry: false)
      {:ok, result.data}
    end)
  end

  @doc """
  Execute a query and return the first result.

  Returns `{:error, :not_found}` if no results.

  ## Examples

      Multi.new()
      |> Events.Query.Multi.query_one(:user, user_token)
  """
  @spec query_one(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_one(multi, name, token_or_fun) when is_atom(name) do
    Multi.run(multi, name, fn repo, changes ->
      token =
        case token_or_fun do
          %Token{} = t -> t
          fun when is_function(fun, 1) -> fun.(changes)
        end

      result = Executor.execute!(token, repo: repo, telemetry: false)

      case result.data do
        [] -> {:error, :not_found}
        [first | _] -> {:ok, first}
        data -> {:ok, data}
      end
    end)
  end

  @doc """
  Execute a query and assert it returns exactly one result.

  Returns `{:error, reason}` if zero or multiple results.

  ## Examples

      Multi.new()
      |> Events.Query.Multi.query_one!(:user, user_token)
  """
  @spec query_one!(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_one!(multi, name, token_or_fun) when is_atom(name) do
    Multi.run(multi, name, fn repo, changes ->
      token =
        case token_or_fun do
          %Token{} = t -> t
          fun when is_function(fun, 1) -> fun.(changes)
        end

      result = Executor.execute!(token, repo: repo, telemetry: false)

      case result.data do
        [] -> {:error, :not_found}
        [single] -> {:ok, single}
        [_ | _] -> {:error, :multiple_results}
      end
    end)
  end
end
