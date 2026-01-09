defmodule OmQuery.Multi do
  @moduledoc """
  Integration with Ecto.Multi for transactional query execution.

  Provides helpers to add query tokens to Ecto.Multi chains.

  ## Examples

      alias OmQuery.Multi, as: QM

      # Build and execute a multi-step transaction
      Ecto.Multi.new()
      |> QM.query(:users, user_query_token)
      |> QM.query(:posts, post_query_token)
      |> QM.transaction(repo: MyApp.Repo)

      # With processing step
      Ecto.Multi.new()
      |> QM.query(:users, user_query_token)
      |> QM.query(:posts, post_query_token)
      |> Ecto.Multi.run(:process, fn _repo, %{users: users, posts: posts} ->
        {:ok, %{user_count: length(users.data), post_count: length(posts.data)}}
      end)
      |> QM.transaction()

      # With dependencies between queries
      Ecto.Multi.new()
      |> QM.query(:active_users, fn _ ->
        User
        |> OmQuery.new()
        |> OmQuery.filter(:status, :eq, "active")
      end)
      |> QM.query(:user_posts, fn %{active_users: users} ->
        user_ids = Enum.map(users.data, & &1.id)

        Post
        |> OmQuery.new()
        |> OmQuery.filter(:user_id, :in, user_ids)
      end)
      |> QM.transaction()

  ## Configuration

  Configure the default repo in your application config:

      config :om_query, :default_repo, MyApp.Repo

  Or pass the repo explicitly:

      QM.transaction(multi, repo: MyApp.Repo)
  """

  alias OmQuery.{Token, Executor, Config}
  alias Ecto.Multi

  @doc """
  Add a query token to an Ecto.Multi.

  ## Parameters

  - `multi` - The Ecto.Multi to add to
  - `name` - Name for this step
  - `token_or_fun` - Either a Token or a function that returns a Token

  ## Examples

      Multi.new()
      |> OmQuery.Multi.query(:users, user_token)

      Multi.new()
      |> OmQuery.Multi.query(:users, fn _ -> build_user_query() end)
  """
  @spec query(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query(multi, name, token_or_fun) when is_atom(name) do
    run_query(multi, name, token_or_fun, fn result -> {:ok, result} end)
  end

  @doc """
  Add multiple queries as separate steps.

  ## Examples

      Multi.new()
      |> OmQuery.Multi.queries(%{
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
      |> OmQuery.Multi.query_data(:users, user_token)
      |> Multi.run(:process, fn _repo, %{users: users} ->
        # users is a list, not a Result struct
        {:ok, Enum.count(users)}
      end)
  """
  @spec query_data(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_data(multi, name, token_or_fun) when is_atom(name) do
    run_query(multi, name, token_or_fun, fn result -> {:ok, result.data} end)
  end

  @doc """
  Execute a query and return the first result.

  Returns `{:error, :not_found}` if no results.

  ## Examples

      Multi.new()
      |> OmQuery.Multi.query_one(:user, user_token)
  """
  @spec query_one(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_one(multi, name, token_or_fun) when is_atom(name) do
    run_query(multi, name, token_or_fun, fn result ->
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
      |> OmQuery.Multi.query_one!(:user, user_token)
  """
  @spec query_one!(Multi.t(), atom(), Token.t() | (map() -> Token.t())) :: Multi.t()
  def query_one!(multi, name, token_or_fun) when is_atom(name) do
    run_query(multi, name, token_or_fun, fn result ->
      case result.data do
        [] -> {:error, :not_found}
        [single] -> {:ok, single}
        [_ | _] -> {:error, :multiple_results}
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────
  # Transaction Execution
  # ─────────────────────────────────────────────────────────────

  @doc """
  Execute the Multi as a transaction.

  This is a convenience function that calls `Repo.transaction/2`.

  ## Options

  - `:repo` - Repo module to use (defaults to configured `:default_repo`)
  - `:timeout` - Transaction timeout in milliseconds

  ## Examples

      Ecto.Multi.new()
      |> OmQuery.Multi.query(:users, user_token)
      |> OmQuery.Multi.transaction()

      # With explicit repo
      |> OmQuery.Multi.transaction(repo: MyApp.Repo)

      # With timeout
      |> OmQuery.Multi.transaction(timeout: 60_000)
  """
  @spec transaction(Multi.t(), keyword()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def transaction(multi, opts \\ []) do
    repo = Config.repo!(opts)
    tx_opts = Keyword.take(opts, [:timeout])
    repo.transaction(multi, tx_opts)
  end

  # ─────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────

  # Common query execution pattern used by query/3, query_data/3, query_one/3, query_one!/3
  defp run_query(multi, name, token_or_fun, result_handler) do
    Multi.run(multi, name, fn repo, changes ->
      token = resolve_token(token_or_fun, changes)
      result = Executor.execute!(token, repo: repo, telemetry: false)
      result_handler.(result)
    end)
  end

  defp resolve_token(%Token{} = token, _changes), do: token
  defp resolve_token(fun, changes) when is_function(fun, 1), do: fun.(changes)
end
