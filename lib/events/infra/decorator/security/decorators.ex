defmodule Events.Infra.Decorator.Security do
  @moduledoc """
  Security-focused decorators for authorization, rate limiting, and audit logging.

  Inspired by Spring Security, Python Flask-Security, and enterprise patterns.
  """

  use Events.Infra.Decorator.Define
  require Logger

  ## Schemas

  @role_required_schema NimbleOptions.new!(
                          roles: [
                            type: {:list, :atom},
                            required: true,
                            doc: "List of roles that are allowed to execute this function"
                          ],
                          check_fn: [
                            type: {:or, [{:fun, 2}, nil]},
                            default: nil,
                            doc:
                              "Function to check if user has required role (user, roles) -> boolean"
                          ],
                          on_error: [
                            type: {:in, [:raise, :return_error, :return_nil]},
                            default: :raise,
                            doc: "What to do when unauthorized"
                          ],
                          on_unauthorized: [
                            type: {:in, [:raise, :return_error, :return_nil]},
                            required: false,
                            doc: "Deprecated: use on_error instead"
                          ]
                        )

  @rate_limit_schema NimbleOptions.new!(
                       max: [
                         type: :pos_integer,
                         required: true,
                         doc: "Maximum number of calls allowed"
                       ],
                       window: [
                         type: {:in, [:second, :minute, :hour, :day]},
                         default: :minute,
                         doc: "Time window for rate limiting"
                       ],
                       by: [
                         type: {:in, [:global, :ip, :user_id, :custom]},
                         default: :global,
                         doc: "How to group rate limits"
                       ],
                       key_fn: [
                         type: {:fun, 1},
                         required: false,
                         doc: "Custom function to generate rate limit key"
                       ],
                       on_error: [
                         type: {:in, [:raise, :return_error, :sleep]},
                         default: :raise,
                         doc: "What to do when rate limited"
                       ],
                       on_limit: [
                         type: {:in, [:raise, :return_error, :sleep]},
                         required: false,
                         doc: "Deprecated: use on_error instead"
                       ],
                       backend: [
                         type: :atom,
                         default: Events.RateLimiter,
                         doc: "Rate limiter backend module"
                       ]
                     )

  @audit_log_schema NimbleOptions.new!(
                      level: [
                        type: {:in, [:info, :warning, :critical]},
                        default: :info,
                        doc: "Audit log level"
                      ],
                      fields: [
                        type: {:list, :atom},
                        default: [],
                        doc: "Fields from arguments to include in audit log"
                      ],
                      store: [
                        type: :atom,
                        default: Events.AuditLog,
                        doc: "Module to store audit logs"
                      ],
                      async: [
                        type: :boolean,
                        default: true,
                        doc: "Whether to log asynchronously"
                      ],
                      include_result: [
                        type: :boolean,
                        default: false,
                        doc: "Whether to include function result in audit"
                      ],
                      metadata: [
                        type: :map,
                        default: %{},
                        doc: "Additional metadata to include"
                      ]
                    )

  ## Decorators

  @doc """
  Role-based access control decorator.

  Checks if the current user has one of the required roles before
  executing the function. The first argument must be the current user
  or a context containing the user.

  ## Options

  #{NimbleOptions.docs(@role_required_schema)}

  ## Examples

      @decorate role_required(roles: [:admin])
      def delete_user(current_user, user_id) do
        Repo.delete(User, user_id)
      end

      @decorate role_required(
        roles: [:admin, :moderator],
        on_error: :return_error
      )
      def ban_user(context, user_id) do
        # context.current_user is checked for roles
        User.ban(user_id)
      end

      # Custom role check function
      @decorate role_required(
        roles: [:owner],
        check_fn: fn user, roles ->
          user.role in roles or user.is_superadmin
        end
      )
      def sensitive_operation(user, data) do
        process(data)
      end
  """
  def role_required(opts, body, _context) do
    validated_opts = NimbleOptions.validate!(opts, @role_required_schema)

    # Handle deprecated on_unauthorized option
    on_error =
      if validated_opts[:on_unauthorized] do
        IO.warn("on_unauthorized is deprecated, use on_error instead")
        validated_opts[:on_unauthorized]
      else
        validated_opts[:on_error]
      end

    roles = validated_opts[:roles]
    check_fn = validated_opts[:check_fn]

    quote do
      user_or_context =
        case var!(args) do
          [first | _rest] -> first
          _ -> nil
        end

      user =
        case user_or_context do
          %{current_user: user} -> user
          %{user: user} -> user
          user -> user
        end

      check_fn = unquote(check_fn) || (&Events.Infra.Decorator.Security.default_role_check/2)

      if check_fn.(user, unquote(roles)) do
        unquote(body)
      else
        case unquote(on_error) do
          :raise ->
            raise Events.UnauthorizedError,
              message: "User lacks required roles: #{Kernel.inspect(unquote(roles))}"

          :return_error ->
            {:error, :unauthorized}

          :return_nil ->
            nil
        end
      end
    end
  end

  @doc """
  Rate limiting decorator.

  Limits the number of times a function can be called within a time window.
  Can limit globally, by IP, by user, or using custom keys.

  ## Options

  #{NimbleOptions.docs(@rate_limit_schema)}

  ## Examples

      @decorate rate_limit(max: 100, window: :minute)
      def public_api_endpoint(params) do
        # Limited to 100 calls per minute globally
      end

      @decorate rate_limit(
        max: 10,
        window: :hour,
        by: :user_id,
        on_error: :return_error
      )
      def expensive_operation(user_id, data) do
        # Limited to 10 calls per hour per user
      end

      # Custom key function
      @decorate rate_limit(
        max: 50,
        window: :minute,
        by: :custom,
        key_fn: fn [conn | _] -> conn.remote_ip end
      )
      def api_endpoint(conn, params) do
        # Rate limited by IP address
      end
  """
  def rate_limit(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @rate_limit_schema)

    # Handle deprecated on_limit option
    on_error =
      if validated_opts[:on_limit] do
        IO.warn("on_limit is deprecated, use on_error instead")
        validated_opts[:on_limit]
      else
        validated_opts[:on_error]
      end

    max = validated_opts[:max]
    window = validated_opts[:window]
    by = validated_opts[:by]
    key_fn = validated_opts[:key_fn]
    backend = validated_opts[:backend]

    quote do
      key =
        unquote(__MODULE__).generate_rate_limit_key(
          unquote(by),
          unquote(key_fn),
          unquote(context),
          var!(args)
        )

      window_ms = unquote(__MODULE__).window_to_ms(unquote(window))

      case unquote(backend).check_rate(key, unquote(max), window_ms) do
        :ok ->
          unquote(body)

        {:error, :rate_limited} ->
          case unquote(on_error) do
            :raise ->
              raise Events.RateLimitError,
                message: "Rate limit exceeded: #{unquote(max)} per #{unquote(window)}"

            :return_error ->
              {:error, :rate_limited}

            :sleep ->
              Process.sleep(1000)
              unquote(body)
          end
      end
    end
  end

  @doc """
  Audit logging decorator.

  Creates an immutable audit trail of function executions.
  Captures who, what, when, and optionally the result.

  ## Options

  #{NimbleOptions.docs(@audit_log_schema)}

  ## Examples

      @decorate audit_log(level: :critical)
      def delete_account(admin_user, account_id) do
        # Logged with critical level
        Account.delete(account_id)
      end

      @decorate audit_log(
        level: :info,
        fields: [:user_id, :amount],
        include_result: true
      )
      def transfer_funds(user_id, from_account, to_account, amount) do
        # Logs user_id, amount, and the result
        perform_transfer(from_account, to_account, amount)
      end

      @decorate audit_log(
        store: ComplianceAuditLog,
        metadata: %{regulation: "SOX", system: "financial"}
      )
      def modify_financial_records(user, changes) do
        apply_changes(changes)
      end
  """
  def audit_log(opts, body, context) do
    validated_opts = NimbleOptions.validate!(opts, @audit_log_schema)

    level = validated_opts[:level]
    fields = validated_opts[:fields]
    store = validated_opts[:store]
    async = validated_opts[:async]
    include_result = validated_opts[:include_result]
    metadata = validated_opts[:metadata]

    quote do
      start_time = System.monotonic_time(:microsecond)

      # Extract specified fields from arguments
      arg_names = unquote(Events.Support.AST.get_args(context))
      args_map = Enum.zip(arg_names, var!(args)) |> Map.new()

      captured_fields =
        unquote(fields)
        |> Enum.map(fn field ->
          {field, Map.get(args_map, field)}
        end)
        |> Map.new()

      # Execute function
      result = unquote(body)

      duration = System.monotonic_time(:microsecond) - start_time

      # Build audit entry
      audit_entry = %{
        function: "#{unquote(context.module)}.#{unquote(context.name)}/#{unquote(context.arity)}",
        level: unquote(level),
        fields: captured_fields,
        metadata: unquote(metadata),
        duration_us: duration,
        timestamp: DateTime.utc_now(),
        node: node()
      }

      audit_entry =
        if unquote(include_result) do
          Map.put(audit_entry, :result, result)
        else
          audit_entry
        end

      # Store audit log
      if unquote(async) do
        Task.start(fn ->
          unquote(store).log(audit_entry)
        end)
      else
        unquote(store).log(audit_entry)
      end

      result
    end
  end

  ## Helper Functions

  @doc false
  def generate_rate_limit_key(:global, _key_fn, context, _args) do
    "rate_limit:#{context.module}.#{context.name}"
  end

  def generate_rate_limit_key(:ip, _key_fn, _context, [%{remote_ip: ip} | _]) do
    "rate_limit:ip:#{Kernel.inspect(ip)}"
  end

  def generate_rate_limit_key(:user_id, _key_fn, _context, args) do
    user_id =
      case args do
        [%{id: id} | _] -> id
        [%{user_id: id} | _] -> id
        [id | _] when is_integer(id) or is_binary(id) -> id
        _ -> "unknown"
      end

    "rate_limit:user:#{user_id}"
  end

  def generate_rate_limit_key(:custom, key_fn, _context, args) do
    "rate_limit:custom:#{key_fn.(args)}"
  end

  @doc false
  def window_to_ms(:second), do: 1_000
  def window_to_ms(:minute), do: 60_000
  def window_to_ms(:hour), do: 3_600_000
  def window_to_ms(:day), do: 86_400_000

  @doc false
  def default_role_check(nil, _roles), do: false

  def default_role_check(user, roles) do
    user_role =
      case user do
        %{role: role} ->
          role

        %{roles: user_roles} when is_list(user_roles) ->
          # User has multiple roles - check if any match
          Enum.any?(user_roles, &(&1 in roles))

        _ ->
          nil
      end

    case user_role do
      # From Enum.any? above
      true -> true
      # From Enum.any? above
      false -> false
      # No role found
      nil -> false
      # Single role comparison
      role -> role in roles
    end
  end
end

defmodule Events.UnauthorizedError do
  defexception [:message]
end

defmodule Events.RateLimitError do
  defexception [:message]
end
