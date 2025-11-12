defmodule Events.Errors.Examples do
  @moduledoc """
  Real-world usage examples for the Events.Errors.Handler module.

  This module contains copy-paste ready examples for different contexts.
  """

  alias Events.Errors

  ## Phoenix Controller Examples

  @doc """
  Example: Basic Phoenix controller with error handling.
  """
  def example_controller do
    quote do
      defmodule MyAppWeb.UserController do
        use MyAppWeb, :controller

        alias MyApp.Users
        alias Events.Errors

        def create(conn, params) do
          case Users.create_user(params) do
            {:ok, user} ->
              conn
              |> put_status(:created)
              |> json(user)

            {:error, reason} ->
              # Handler automatically:
              # - Normalizes the error
              # - Enriches with user/request context from conn
              # - Logs the error
              # - Stores in database
              # - Returns formatted JSON response with appropriate status
              Errors.handle_plug_error(conn, reason)
          end
        end

        def update(conn, %{"id" => id} = params) do
          case Users.update_user(id, params) do
            {:ok, user} -> json(conn, user)
            {:error, reason} -> Errors.handle_plug_error(conn, reason)
          end
        end

        def delete(conn, %{"id" => id}) do
          case Users.delete_user(id) do
            {:ok, _user} -> send_resp(conn, :no_content, "")
            {:error, reason} -> Errors.handle_plug_error(conn, reason)
          end
        end

        # Custom error handling with options
        def custom_action(conn, params) do
          case Users.complex_operation(params) do
            {:ok, result} ->
              json(conn, result)

            {:error, reason} ->
              # Don't store this error, only log as warning
              Errors.handle_plug_error(conn, reason,
                store: false,
                log_level: :warn
              )
          end
        end
      end
    end
  end

  @doc """
  Example: Phoenix controller with rescue for unexpected errors.
  """
  def example_controller_with_rescue do
    quote do
      defmodule MyAppWeb.SecureController do
        use MyAppWeb, :controller

        alias Events.Errors

        # Override action/2 to catch all errors
        def action(conn, _) do
          apply(__MODULE__, action_name(conn), [conn, conn.params])
        rescue
          error ->
            # Handler will normalize the exception and add stacktrace
            Errors.handle_plug_error(conn, error)
        end

        def risky_action(conn, params) do
          # This might raise
          result = perform_risky_operation(params)
          json(conn, result)
        end

        defp perform_risky_operation(_params) do
          raise "Something went wrong!"
        end
      end
    end
  end

  ## GraphQL Resolver Examples

  @doc """
  Example: Absinthe GraphQL resolver with error handling.
  """
  def example_graphql_resolver do
    quote do
      defmodule MyAppWeb.Resolvers.UserResolver do
        alias MyApp.Users
        alias Events.Errors

        def create_user(_parent, args, %{context: context}) do
          case Users.create_user(args) do
            {:ok, user} ->
              {:ok, user}

            {:error, reason} ->
              # Handler automatically:
              # - Normalizes the error
              # - Enriches with user/request context
              # - Converts to Absinthe error format
              # - Logs and stores
              Errors.handle_graphql_error(reason, context)
          end
        end

        def update_user(_parent, %{id: id} = args, context) do
          case Users.update_user(id, args) do
            {:ok, user} -> {:ok, user}
            {:error, reason} -> Errors.handle_graphql_error(reason, context)
          end
        end

        # Custom handling
        def complex_query(_parent, args, context) do
          case Users.complex_query(args) do
            {:ok, result} ->
              {:ok, result}

            {:error, reason} ->
              # Don't log this error (too noisy)
              Errors.handle_graphql_error(reason, context, log: false)
          end
        end
      end
    end
  end

  ## Background Job Examples

  @doc """
  Example: Oban worker with error handling.
  """
  def example_oban_worker do
    quote do
      defmodule MyApp.Workers.UserProcessor do
        use Oban.Worker, queue: :default, max_attempts: 3

        alias MyApp.Users
        alias Events.Errors

        @impl Oban.Worker
        def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
          case Users.process_user(user_id) do
            {:ok, _result} ->
              :ok

            {:error, reason} ->
              # Handler returns :ok for non-retriable errors
              # Returns {:error, :retry} for retriable errors (timeout, rate_limit, etc.)
              Errors.handle_worker_error(reason, %{
                user_id: user_id,
                worker: :user_processor
              })
          end
        end
      end
    end
  end

  @doc """
  Example: GenServer with error handling.
  """
  def example_genserver do
    quote do
      defmodule MyApp.Services.UserService do
        use GenServer

        alias Events.Errors

        def handle_call({:process_user, user_id}, _from, state) do
          case do_process_user(user_id) do
            {:ok, result} ->
              {:reply, {:ok, result}, state}

            {:error, reason} ->
              # Handle error with worker context
              error =
                Errors.handle_error(reason,
                  metadata: %{
                    user_id: user_id,
                    service: :user_service,
                    node: node()
                  },
                  context: :genserver
                )

              {:reply, {:error, error}, state}
          end
        end

        defp do_process_user(_user_id) do
          {:error, :processing_failed}
        end
      end
    end
  end

  ## Plug Examples

  @doc """
  Example: Custom authentication plug with error handling.
  """
  def example_auth_plug do
    quote do
      defmodule MyAppWeb.Plugs.RequireAuth do
        import Plug.Conn

        alias Events.Errors

        def init(opts), do: opts

        def call(conn, _opts) do
          case get_current_user(conn) do
            {:ok, user} ->
              assign(conn, :current_user, user)

            {:error, reason} ->
              # Handler returns conn with 401 status and error JSON
              Errors.handle_plug_error(conn, reason)
              |> halt()
          end
        end

        defp get_current_user(conn) do
          case get_req_header(conn, "authorization") do
            ["Bearer " <> token] -> verify_token(token)
            _ -> {:error, :unauthorized}
          end
        end

        defp verify_token(_token) do
          {:error, :invalid_token}
        end
      end
    end
  end

  ## LiveView Examples

  @doc """
  Example: Phoenix LiveView with error handling.
  """
  def example_liveview do
    quote do
      defmodule MyAppWeb.UserLive.Index do
        use MyAppWeb, :live_view

        alias MyApp.Users
        alias Events.Errors

        def handle_event("create_user", params, socket) do
          case Users.create_user(params) do
            {:ok, user} ->
              {:noreply,
               socket
               |> put_flash(:info, "User created successfully")
               |> assign(:users, [user | socket.assigns.users])}

            {:error, reason} ->
              # Handle error and extract message for flash
              error =
                Errors.handle_error(reason,
                  metadata: %{
                    user_id: socket.assigns.current_user.id,
                    live_view: :user_index
                  }
                )

              {:noreply,
               socket
               |> put_flash(:error, error.message)
               |> assign(:changeset_errors, error.details[:errors] || [])}
          end
        end
      end
    end
  end

  ## Generic Service Examples

  @doc """
  Example: Service module with error wrapping.
  """
  def example_service do
    quote do
      defmodule MyApp.Services.PaymentService do
        alias Events.Errors

        def charge_customer(customer_id, amount) do
          Errors.wrap(fn ->
            # This might raise or return {:error, reason}
            with {:ok, customer} <- get_customer(customer_id),
                 {:ok, payment_method} <- get_payment_method(customer),
                 {:ok, charge} <- create_charge(payment_method, amount) do
              {:ok, charge}
            end
          end)
        end

        def process_refund(charge_id) do
          case Stripe.Refund.create(%{charge: charge_id}) do
            {:ok, refund} ->
              {:ok, refund}

            {:error, stripe_error} ->
              # Normalize Stripe error
              Errors.handle_error_tuple(stripe_error,
                metadata: %{charge_id: charge_id, service: :stripe}
              )
          end
        end

        defp get_customer(_id), do: {:error, :not_found}
        defp get_payment_method(_customer), do: {:error, :no_payment_method}
        defp create_charge(_method, _amount), do: {:error, :charge_failed}
      end
    end
  end

  ## Testing Examples

  @doc """
  Example: Testing with error handler.
  """
  def example_test do
    quote do
      defmodule MyAppWeb.UserControllerTest do
        use MyAppWeb.ConnCase

        alias Events.Errors

        test "creates user with valid params", %{conn: conn} do
          params = %{email: "test@example.com", name: "Test"}

          conn = post(conn, ~p"/api/users", params)

          assert %{"id" => _id, "email" => "test@example.com"} = json_response(conn, 201)
        end

        test "returns error with invalid params", %{conn: conn} do
          params = %{email: "invalid", name: ""}

          conn = post(conn, ~p"/api/users", params)

          assert %{"error" => error} = json_response(conn, 422)
          assert error["type"] == "validation"
          assert error["code"] == "changeset_invalid"
        end

        test "handles unexpected errors gracefully", %{conn: conn} do
          # Simulate an unexpected error
          conn = get(conn, ~p"/api/users/raise")

          assert %{"error" => error} = json_response(conn, 500)
          assert error["type"] == "internal"
        end
      end
    end
  end

  ## Advanced Examples

  @doc """
  Example: Custom error with enrichment.
  """
  def example_custom_enrichment do
    quote do
      defmodule MyApp.Services.DataProcessor do
        alias Events.Errors

        def process_file(file_path, user_id) do
          case File.read(file_path) do
            {:ok, content} ->
              process_content(content)

            {:error, reason} ->
              # Create custom error with rich context
              error =
                reason
                |> Errors.normalize()
                |> Errors.with_details(%{
                  file_path: file_path,
                  file_size: File.stat(file_path) |> elem(1) |> Map.get(:size),
                  attempted_at: DateTime.utc_now()
                })
                |> Errors.enrich(
                  user: [user_id: user_id],
                  application: [
                    service: :data_processor,
                    operation: :read_file,
                    node: node()
                  ]
                )
                |> tap(&Errors.store/1)

              {:error, error}
          end
        end

        defp process_content(_content), do: {:ok, :processed}
      end
    end
  end

  @doc """
  Example: Conditional error handling based on environment.
  """
  def example_conditional_handling do
    quote do
      defmodule MyApp.Services.ExternalAPI do
        alias Events.Errors

        def call_api(endpoint, params) do
          case HTTPoison.post(endpoint, params) do
            {:ok, %{status_code: 200, body: body}} ->
              {:ok, body}

            {:ok, %{status_code: status, body: body}} ->
              # Different handling for dev vs prod
              opts =
                if Mix.env() == :prod do
                  # In production: store and log as error
                  [store: true, log_level: :error]
                else
                  # In development: don't store, log as debug
                  [store: false, log_level: :debug]
                end

              error =
                Errors.handle_error(
                  {:http_error, status, body},
                  [
                    metadata: %{
                      endpoint: endpoint,
                      params: params,
                      status: status
                    }
                  ],
                  opts
                )

              {:error, error}

            {:error, reason} ->
              Errors.handle_error_tuple(reason,
                metadata: %{endpoint: endpoint},
                store: Mix.env() == :prod
              )
          end
        end
      end
    end
  end
end
