defmodule Events.Infra.Decorator.Testing do
  @moduledoc """
  Testing-focused decorators for common test patterns.

  Provides decorators that help with:
  - Fixture management
  - Test data generation
  - Assertion helpers
  - Mock/stub integration

  These decorators are designed to be used in test modules only.

  > #### Note on Property-Based Testing {: .info}
  >
  > For property-based testing, use the StreamData or PropCheck libraries
  > which provide comprehensive features including data generators, shrinking,
  > and advanced property testing capabilities.

  ## Examples

      defmodule MyApp.CalculatorTest do
        use ExUnit.Case
        use Events.Infra.Decorator

        @decorate with_fixtures([:user, :organization])
        def test_user_permissions(user, organization) do
          # user and organization fixtures automatically provided
          assert can_access?(user, organization)
        end

        @decorate sample_data(generator: &Faker.Internet.email/0, count: 5)
        def test_bulk_email_processing(emails) do
          # emails is a list of 5 generated email addresses
          assert Enum.all?(emails, &valid_email?/1)
        end
      end
  """

  ## Schemas

  @with_fixtures_schema NimbleOptions.new!(
                          fixtures: [
                            type: {:list, :atom},
                            required: true,
                            doc: "List of fixture names to load"
                          ],
                          cleanup: [
                            type: :boolean,
                            default: true,
                            doc: "Whether to cleanup fixtures after test"
                          ]
                        )

  @sample_data_schema NimbleOptions.new!(
                        generator: [
                          type: {:or, [:atom, {:fun, 0}, {:fun, 1}]},
                          required: true,
                          doc: "Data generator function or module"
                        ],
                        count: [
                          type: :pos_integer,
                          default: 1,
                          doc: "Number of samples to generate"
                        ]
                      )

  @timeout_test_schema NimbleOptions.new!(
                         timeout: [
                           type: :pos_integer,
                           required: true,
                           doc: "Timeout in milliseconds"
                         ],
                         on_timeout: [
                           type: {:in, [:raise, :return_error, :return_nil]},
                           default: :raise,
                           doc: "What to do on timeout"
                         ]
                       )

  @mock_schema NimbleOptions.new!(
                 module: [
                   type: :atom,
                   required: true,
                   doc: "Module to mock"
                 ],
                 functions: [
                   type: :keyword_list,
                   required: true,
                   doc: "Functions to mock as keyword list"
                 ]
               )

  ## Decorator Implementations

  @doc """
  Fixture loading decorator.

  Automatically loads and provides fixtures to test functions.

  ## Options

  #{NimbleOptions.docs(@with_fixtures_schema)}

  ## Examples

      @decorate with_fixtures(fixtures: [:user, :organization])
      def test_permissions(user, organization) do
        # user and organization automatically provided from fixtures
        assert authorized?(user, organization)
      end

      @decorate with_fixtures(fixtures: [:db_connection], cleanup: false)
      def test_query(db_connection) do
        # db_connection provided, won't be cleaned up
        result = query(db_connection, "SELECT * FROM users")
        assert length(result) > 0
      end

  ## Fixture Resolution

  Fixtures are resolved by calling:
  - `Fixtures.fixture_name()` if Fixtures module exists
  - `:fixture_name` from process dictionary
  - ExUnit context if available
  """
  def with_fixtures(opts, body, _context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @with_fixtures_schema)

    fixtures = validated_opts[:fixtures]
    cleanup? = validated_opts[:cleanup]

    quote do
      # Load fixtures
      loaded_fixtures = unquote(load_fixtures(fixtures))

      try do
        unquote(body)
      after
        if unquote(cleanup?) do
          unquote(cleanup_fixtures(fixtures))
        end
      end
    end
  end

  @doc """
  Sample data generation decorator.

  Generates sample/fake data for testing purposes.

  ## Options

  #{NimbleOptions.docs(@sample_data_schema)}

  ## Examples

      @decorate sample_data(generator: &Faker.Internet.email/0)
      def test_email_validation(email) do
        # email is a generated fake email
        assert valid_email?(email)
      end

      @decorate sample_data(generator: UserFactory, count: 5)
      def test_bulk_operation(users) do
        # users is a list of 5 generated users
        assert length(users) == 5
        Enum.each(users, fn user ->
          assert %User{} = user
        end)
      end

  ## Custom Generators

  Generators can be:
  - Function: `&Faker.Name.name/0`
  - Module (must implement build/0): `UserFactory`
  - Function with args: `fn -> build(:user) end`
  """
  def sample_data(opts, body, _context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @sample_data_schema)

    generator = validated_opts[:generator]
    count = validated_opts[:count]

    quote do
      # Generate sample data
      data =
        case unquote(count) do
          1 ->
            unquote(generate_data(generator))

          n ->
            for _ <- 1..n, do: unquote(generate_data(generator))
        end

      # Make data available to function
      # This is simplified - actual implementation would inject into args
      var!(sample_data) = data

      unquote(body)
    end
  end

  @doc """
  Test timeout decorator.

  Ensures a test completes within a specified timeout.

  ## Options

  #{NimbleOptions.docs(@timeout_test_schema)}

  ## Examples

      @decorate timeout_test(timeout: 1000)
      def test_fast_operation do
        # Must complete within 1 second
        perform_operation()
      end

      @decorate timeout_test(timeout: 5000, on_timeout: :return_error)
      def test_slow_operation do
        # Returns {:error, :timeout} if exceeds 5 seconds
        slow_operation()
      end

  ## Use Cases

  - Ensuring tests don't hang
  - Performance regression testing
  - Testing async operations
  """
  def timeout_test(opts, body, context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @timeout_test_schema)

    timeout = validated_opts[:timeout]
    on_timeout = validated_opts[:on_timeout]

    quote do
      task = Task.async(fn -> unquote(body) end)

      task
      |> Task.yield(unquote(timeout))
      |> handle_task_result(task, unquote(timeout), unquote(on_timeout), unquote(context))
    end
  end

  # Helper functions for task timeout handling with pattern matching
  # These are public because they're called from within quote blocks
  @doc false
  def handle_task_result({:ok, result}, _task, _timeout, _on_timeout, _context), do: result

  @doc false
  def handle_task_result(nil, task, timeout, on_timeout, context) do
    Task.shutdown(task)
    handle_timeout_action(on_timeout, timeout, context)
  end

  # Pattern match on timeout actions
  @doc false
  def handle_timeout_action(:raise, timeout, context) do
    raise "Test timed out after #{timeout}ms: #{context.module}.#{context.name}/#{context.arity}"
  end

  @doc false
  def handle_timeout_action(:return_error, _timeout, _context), do: {:error, :timeout}

  @doc false
  def handle_timeout_action(:return_nil, _timeout, _context), do: nil

  @doc """
  Mock decorator for testing.

  Temporarily mocks module functions for the duration of the test.

  ## Options

  #{NimbleOptions.docs(@mock_schema)}

  ## Examples

      @decorate mock(
        module: ExternalAPI,
        functions: [
          get_user: fn id -> {:ok, %{id: id, name: "Test"}} end,
          create_user: fn attrs -> {:ok, %{id: 123, name: attrs.name}} end
        ]
      )
      def test_api_integration do
        # ExternalAPI.get_user/1 and create_user/1 are mocked
        {:ok, user} = ExternalAPI.get_user(1)
        assert user.name == "Test"
      end

  ## Note

  This is a simplified mock decorator. For comprehensive mocking,
  use libraries like Mox or Mimic.

  This decorator is primarily for documentation and simple cases.
  """
  def mock(opts, body, _context) when is_list(opts) do
    validated_opts = NimbleOptions.validate!(opts, @mock_schema)

    module = validated_opts[:module]
    _functions = validated_opts[:functions]

    quote do
      # This is a placeholder for actual mocking
      # Real implementation would use :meck or Mox
      IO.warn("""
      @mock decorator is for documentation only.
      Use Mox or Mimic for actual mocking:

        import Mox
        expect(#{inspect(unquote(module))}, :function_name, fn args -> result end)
      """)

      unquote(body)
    end
  end

  # Helper functions that were in the deleted helpers module

  defp load_fixtures(fixtures) do
    quote do
      Enum.map(unquote(fixtures), fn fixture_name ->
        # Try different methods to load fixture
        cond do
          # Check if Fixtures module exists with function
          function_exported?(Fixtures, fixture_name, 0) ->
            {fixture_name, apply(Fixtures, fixture_name, [])}

          # Check process dictionary
          Process.get(fixture_name) != nil ->
            {fixture_name, Process.get(fixture_name)}

          # Default to creating a simple fixture
          true ->
            {fixture_name, %{name: fixture_name, id: System.unique_integer()}}
        end
      end)
      |> Enum.into(%{})
    end
  end

  defp cleanup_fixtures(fixtures) do
    quote do
      Enum.each(unquote(fixtures), fn fixture_name ->
        # Cleanup logic - simplified
        Process.delete(fixture_name)

        # If there's a cleanup function, call it
        if function_exported?(Fixtures, :"cleanup_#{fixture_name}", 0) do
          apply(Fixtures, :"cleanup_#{fixture_name}", [])
        end
      end)
    end
  end

  defp generate_data(generator) do
    quote do
      case unquote(generator) do
        # Function reference
        f when is_function(f, 0) ->
          f.()

        # Function reference with arity 1
        f when is_function(f, 1) ->
          f.(:default)

        # Module that should have build/0
        module when is_atom(module) ->
          if function_exported?(module, :build, 0) do
            apply(module, :build, [])
          else
            raise "Generator module #{inspect(module)} must implement build/0"
          end

        other ->
          raise "Invalid generator: #{inspect(other)}"
      end
    end
  end
end
