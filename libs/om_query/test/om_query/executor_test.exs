defmodule OmQuery.ExecutorTest do
  @moduledoc """
  Tests for OmQuery.Executor - Query execution, batching, and streaming.

  Since executor requires a real database for most operations, these tests
  use a stub repo to verify the execution flow, result structure, and
  safe limit behavior without a live DB connection.

  ## Covered Functionality

  - execute/2 returns {:ok, Result} with metadata
  - execute!/2 returns Result directly
  - batch/2 parallel execution with ordered results
  - stream/2 returns an Enumerable
  - Safe limit application for unbounded queries
  """

  use ExUnit.Case, async: true

  alias OmQuery.Token

  # Stub repo that returns empty results without a real DB
  defmodule StubRepo do
    @moduledoc false

    def all(_query, _opts \\ []), do: []

    def aggregate(_query, :count, _opts \\ []), do: 0

    def stream(query, _opts \\ []) do
      Stream.map([query], & &1)
    end

    def to_sql(:all, _query), do: {"SELECT 1", []}
  end

  # Test schema for executor operations
  defmodule User do
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :email, :string
      field :status, :string
    end
  end

  # ============================================
  # execute/2
  # ============================================

  describe "execute/2" do
    test "basic token executes and returns {:ok, result} with empty data" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      assert {:ok, result} = OmQuery.execute(token, repo: StubRepo)
      assert result.data == []
      assert %OmQuery.Result{} = result
    end

    test "result has metadata with timing information" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      {:ok, result} = OmQuery.execute(token, repo: StubRepo)

      assert is_integer(result.metadata.query_time_μs)
      assert result.metadata.query_time_μs >= 0

      assert is_integer(result.metadata.total_time_μs)
      assert result.metadata.total_time_μs >= 0

      # total_time should be >= query_time
      assert result.metadata.total_time_μs >= result.metadata.query_time_μs
    end

    test "result has operation_count in metadata" do
      token =
        Token.new(User)
        |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
        |> Token.add_operation!({:limit, 10})

      {:ok, result} = OmQuery.execute(token, repo: StubRepo)

      assert result.metadata.operation_count == 2
    end

    test "result has SQL in metadata" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      {:ok, result} = OmQuery.execute(token, repo: StubRepo)

      assert is_binary(result.metadata.sql)
    end

    test "token without limit gets safe limit applied" do
      import ExUnit.CaptureLog

      token = Token.new(User)

      # Should log a warning about safe limit and still succeed
      {result, log} =
        with_log(fn ->
          OmQuery.execute(token, repo: StubRepo)
        end)

      assert {:ok, _} = result
      assert log =~ "without pagination or limit"
    end

    test "token with explicit limit does not trigger safe limit warning" do
      import ExUnit.CaptureLog

      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 50})

      {result, log} =
        with_log(fn ->
          OmQuery.execute(token, repo: StubRepo)
        end)

      assert {:ok, _} = result
      refute log =~ "without pagination or limit"
    end

    test "token with pagination does not trigger safe limit warning" do
      import ExUnit.CaptureLog

      token =
        Token.new(User)
        |> Token.add_operation!({:paginate, {:offset, [limit: 20, offset: 0]}})

      {result, log} =
        with_log(fn ->
          OmQuery.execute(token, repo: StubRepo)
        end)

      assert {:ok, _} = result
      refute log =~ "without pagination or limit"
    end

    test "returns {:error, _} when execution fails" do
      # Passing an invalid repo that will cause an error
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      assert {:error, _} = OmQuery.execute(token, repo: NonExistentRepo)
    end

    test "result includes pagination type when paginated" do
      token =
        Token.new(User)
        |> Token.add_operation!({:paginate, {:offset, [limit: 20, offset: 0]}})

      {:ok, result} = OmQuery.execute(token, repo: StubRepo)

      assert result.pagination.type == :offset
      assert result.pagination.limit == 20
      assert result.pagination.offset == 0
    end
  end

  # ============================================
  # execute!/2
  # ============================================

  describe "execute!/2" do
    test "returns Result struct directly" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      result = OmQuery.execute!(token, repo: StubRepo)

      assert %OmQuery.Result{} = result
      assert result.data == []
    end

    test "raises on failure" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      assert_raise UndefinedFunctionError, fn ->
        OmQuery.execute!(token, repo: NonExistentRepo)
      end
    end
  end

  # ============================================
  # batch/2
  # ============================================

  describe "batch/2" do
    test "multiple tokens return list of results in order" do
      token1 =
        Token.new(User)
        |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
        |> Token.add_operation!({:limit, 10})

      token2 =
        Token.new(User)
        |> Token.add_operation!({:filter, {:status, :eq, "inactive", []}})
        |> Token.add_operation!({:limit, 5})

      results = OmQuery.batch([token1, token2], repo: StubRepo)

      assert length(results) == 2
      assert {:ok, %OmQuery.Result{}} = Enum.at(results, 0)
      assert {:ok, %OmQuery.Result{}} = Enum.at(results, 1)
    end

    test "empty list returns empty list" do
      results = OmQuery.batch([], repo: StubRepo)

      assert results == []
    end

    test "single token returns list with one result" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      results = OmQuery.batch([token], repo: StubRepo)

      assert length(results) == 1
      assert {:ok, %OmQuery.Result{}} = Enum.at(results, 0)
    end

    test "each result has independent metadata" do
      token1 =
        Token.new(User)
        |> Token.add_operation!({:filter, {:status, :eq, "active", []}})
        |> Token.add_operation!({:limit, 10})

      token2 =
        Token.new(User)
        |> Token.add_operation!({:limit, 5})

      results = OmQuery.batch([token1, token2], repo: StubRepo)

      {:ok, result1} = Enum.at(results, 0)
      {:ok, result2} = Enum.at(results, 1)

      # Both have timing metadata
      assert is_integer(result1.metadata.query_time_μs)
      assert is_integer(result2.metadata.query_time_μs)

      # Operation counts differ
      assert result1.metadata.operation_count == 2
      assert result2.metadata.operation_count == 1
    end
  end

  # ============================================
  # stream/2
  # ============================================

  describe "stream/2" do
    test "returns an Enumerable" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      stream = OmQuery.stream(token, repo: StubRepo)

      # Stream implements Enumerable protocol
      assert Enumerable.impl_for(stream) != nil
    end

    test "stream without limit or pagination logs warning" do
      import ExUnit.CaptureLog

      token = Token.new(User)

      log =
        capture_log(fn ->
          _stream = OmQuery.stream(token, repo: StubRepo)
        end)

      assert log =~ "Stream executed without pagination or limit"
    end

    test "stream with limit does not log warning" do
      import ExUnit.CaptureLog

      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 100})

      log =
        capture_log(fn ->
          _stream = OmQuery.stream(token, repo: StubRepo)
        end)

      refute log =~ "Stream executed without pagination or limit"
    end

    test "stream with pagination does not log warning" do
      import ExUnit.CaptureLog

      token =
        Token.new(User)
        |> Token.add_operation!({:paginate, {:cursor, [limit: 100]}})

      log =
        capture_log(fn ->
          _stream = OmQuery.stream(token, repo: StubRepo)
        end)

      refute log =~ "Stream executed without pagination or limit"
    end
  end

  # ============================================
  # Safe Limits
  # ============================================

  describe "safe limits" do
    test "unsafe: true skips safe limit enforcement" do
      import ExUnit.CaptureLog

      token = Token.new(User)

      {result, log} =
        with_log(fn ->
          OmQuery.execute(token, repo: StubRepo, unsafe: true)
        end)

      assert {:ok, _} = result
      refute log =~ "without pagination or limit"
    end

    test "default_limit option overrides the safe limit" do
      import ExUnit.CaptureLog

      token = Token.new(User)

      {result, log} =
        with_log(fn ->
          OmQuery.execute(token, repo: StubRepo, default_limit: 500)
        end)

      assert {:ok, _} = result
      assert log =~ "500 records"
    end
  end

  # ============================================
  # Error Handling
  # ============================================

  describe "error handling" do
    test "execute/2 without repo raises ArgumentError" do
      token =
        Token.new(User)
        |> Token.add_operation!({:limit, 10})

      # When no default repo is configured and none passed, should error
      # The Config.repo! will raise ArgumentError
      assert {:error, %ArgumentError{}} = OmQuery.execute(token, repo: nil)
    end
  end
end
