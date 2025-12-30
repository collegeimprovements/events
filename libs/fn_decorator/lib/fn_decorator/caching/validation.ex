defmodule FnDecorator.Caching.Validation do
  @moduledoc """
  Compile-time validation for @cacheable decorator options.

  Validates configuration at compile time to catch errors early and provide
  helpful error messages.
  """

  @type validation_error :: {:error, String.t()}
  @type validation_warning :: {:warning, String.t()}
  @type validation_result :: :ok | validation_error | {:ok, [validation_warning]}

  @doc """
  Validates the complete cacheable options and returns errors or warnings.

  Returns `:ok` if valid, `{:error, message}` if invalid, or
  `{:ok, warnings}` if valid with warnings.
  """
  @spec validate(keyword()) :: validation_result()
  def validate(opts) do
    with :ok <- validate_required_fields(opts),
         :ok <- validate_types(opts),
         :ok <- validate_dependencies(opts),
         :ok <- validate_logical_constraints(opts) do
      case collect_warnings(opts) do
        [] -> :ok
        warnings -> {:ok, warnings}
      end
    end
  end

  @doc """
  Validates and raises on error. Returns opts if valid.
  """
  @spec validate!(keyword()) :: keyword()
  def validate!(opts) do
    case validate(opts) do
      :ok ->
        opts

      {:ok, warnings} ->
        Enum.each(warnings, fn {:warning, msg} ->
          IO.warn("cacheable warning: #{msg}", [])
        end)

        opts

      {:error, message} ->
        raise CompileError, description: "cacheable: #{message}"
    end
  end

  # ============================================
  # Required Fields
  # ============================================

  defp validate_required_fields(opts) do
    store = Keyword.get(opts, :store, [])

    cond do
      !Keyword.has_key?(store, :cache) ->
        {:error, "store.cache is required"}

      !Keyword.has_key?(store, :key) ->
        {:error, "store.key is required"}

      !Keyword.has_key?(store, :ttl) ->
        {:error, "store.ttl is required"}

      true ->
        :ok
    end
  end

  # ============================================
  # Type Validation
  # ============================================

  defp validate_types(opts) do
    with :ok <- validate_store_types(Keyword.get(opts, :store, [])),
         :ok <- validate_refresh_types(Keyword.get(opts, :refresh, [])),
         :ok <- validate_serve_stale_types(Keyword.get(opts, :serve_stale, [])),
         :ok <- validate_thunder_herd_types(Keyword.get(opts, :prevent_thunder_herd, true)),
         :ok <- validate_fallback_types(Keyword.get(opts, :fallback, [])) do
      :ok
    end
  end

  defp validate_store_types(store) do
    ttl = Keyword.get(store, :ttl)
    only_if = Keyword.get(store, :only_if)

    cond do
      ttl != nil and not is_positive_integer(ttl) ->
        {:error, "store.ttl must be a positive integer (timeout in milliseconds)"}

      only_if != nil and not is_function(only_if, 1) ->
        {:error, "store.only_if must be a function with arity 1"}

      true ->
        :ok
    end
  end

  defp validate_refresh_types(refresh) do
    triggers = Keyword.get(refresh, :on)
    retries = Keyword.get(refresh, :retries)

    cond do
      triggers != nil and not valid_triggers?(triggers) ->
        {:error, "refresh.on contains invalid trigger. Valid: :stale_access, :immediately_when_expired, {:every, ms}, {:cron, \"...\"}"}

      retries != nil and not is_positive_integer(retries) ->
        {:error, "refresh.retries must be a positive integer"}

      true ->
        validate_cron_expressions(triggers)
    end
  end

  defp validate_serve_stale_types(serve_stale) do
    ttl = Keyword.get(serve_stale, :ttl)

    cond do
      ttl != nil and not is_positive_integer(ttl) ->
        {:error, "serve_stale.ttl must be a positive integer"}

      true ->
        :ok
    end
  end

  defp validate_thunder_herd_types(thunder_herd) when is_boolean(thunder_herd), do: :ok
  defp validate_thunder_herd_types(thunder_herd) when is_integer(thunder_herd) and thunder_herd > 0, do: :ok

  defp validate_thunder_herd_types(thunder_herd) when is_list(thunder_herd) do
    max_wait = Keyword.get(thunder_herd, :max_wait)
    retries = Keyword.get(thunder_herd, :retries)
    lock_timeout = Keyword.get(thunder_herd, :lock_timeout)
    on_timeout = Keyword.get(thunder_herd, :on_timeout)

    cond do
      max_wait != nil and not is_positive_integer(max_wait) ->
        {:error, "prevent_thunder_herd.max_wait must be a positive integer"}

      retries != nil and (not is_integer(retries) or retries < 0) ->
        {:error, "prevent_thunder_herd.retries must be a non-negative integer"}

      lock_timeout != nil and not is_positive_integer(lock_timeout) ->
        {:error, "prevent_thunder_herd.lock_timeout must be a positive integer"}

      on_timeout != nil and not valid_on_timeout?(on_timeout) ->
        {:error, "prevent_thunder_herd.on_timeout must be :serve_stale, :error, {:call, fn}, or {:value, term}"}

      true ->
        :ok
    end
  end

  defp validate_thunder_herd_types(_), do: {:error, "prevent_thunder_herd must be boolean, timeout, or keyword list"}

  defp validate_fallback_types(fallback) do
    on_refresh_failure = Keyword.get(fallback, :on_refresh_failure)
    on_cache_unavailable = Keyword.get(fallback, :on_cache_unavailable)

    cond do
      on_refresh_failure != nil and not valid_fallback_action?(on_refresh_failure) ->
        {:error, "fallback.on_refresh_failure must be :serve_stale, :error, {:call, fn}, or {:value, term}"}

      on_cache_unavailable != nil and not valid_fallback_action?(on_cache_unavailable) ->
        {:error, "fallback.on_cache_unavailable must be :serve_stale, :error, {:call, fn}, or {:value, term}"}

      true ->
        :ok
    end
  end

  # ============================================
  # Dependency Validation
  # ============================================

  defp validate_dependencies(opts) do
    refresh = Keyword.get(opts, :refresh, [])
    serve_stale = Keyword.get(opts, :serve_stale)
    thunder_herd = Keyword.get(opts, :prevent_thunder_herd)
    fallback = Keyword.get(opts, :fallback, [])

    triggers = Keyword.get(refresh, :on, []) |> List.wrap()
    has_serve_stale = serve_stale != nil

    cond do
      # :stale_access requires serve_stale
      :stale_access in triggers and not has_serve_stale ->
        {:error, ":stale_access trigger requires serve_stale to be configured. Either add serve_stale: [ttl: ...] or use a different trigger like :immediately_when_expired"}

      # on_timeout: :serve_stale requires serve_stale (only check if explicitly set)
      explicitly_set_on_timeout?(thunder_herd) == :serve_stale and not has_serve_stale ->
        {:error, "prevent_thunder_herd.on_timeout: :serve_stale requires serve_stale to be configured"}

      # on_refresh_failure: :serve_stale requires serve_stale
      Keyword.get(fallback, :on_refresh_failure) == :serve_stale and not has_serve_stale ->
        {:error, "fallback.on_refresh_failure: :serve_stale requires serve_stale to be configured"}

      # only_if_stale option requires serve_stale
      has_only_if_stale_trigger?(triggers) and not has_serve_stale ->
        {:error, "only_if_stale: true option requires serve_stale to be configured"}

      true ->
        :ok
    end
  end

  # ============================================
  # Logical Constraints
  # ============================================

  defp validate_logical_constraints(opts) do
    store = Keyword.get(opts, :store, [])
    serve_stale = Keyword.get(opts, :serve_stale, [])
    refresh = Keyword.get(opts, :refresh, [])

    store_ttl = Keyword.get(store, :ttl)
    stale_ttl = Keyword.get(serve_stale, :ttl)
    triggers = Keyword.get(refresh, :on, []) |> List.wrap()

    cond do
      # serve_stale.ttl must be > store.ttl
      stale_ttl != nil and store_ttl != nil and stale_ttl <= store_ttl ->
        {:error, "serve_stale.ttl (#{format_duration(stale_ttl)}) must be greater than store.ttl (#{format_duration(store_ttl)}). serve_stale extends the cache lifetime beyond the fresh ttl."}

      # {:every, interval} < store.ttl without only_if_stale
      has_short_interval_without_stale?(triggers, store_ttl) ->
        {:error, "refresh interval is shorter than store.ttl, causing unnecessary refreshes while cache is still fresh. Use :immediately_when_expired instead, or add only_if_stale: true to the interval trigger."}

      true ->
        :ok
    end
  end

  # ============================================
  # Warnings (non-fatal)
  # ============================================

  defp collect_warnings(opts) do
    []
    |> maybe_add_lock_timeout_warning(opts)
    |> Enum.reverse()
  end

  defp maybe_add_lock_timeout_warning(warnings, opts) do
    thunder_herd = Keyword.get(opts, :prevent_thunder_herd, [])

    case thunder_herd do
      opts when is_list(opts) ->
        max_wait = Keyword.get(opts, :max_wait, 5_000)
        lock_timeout = Keyword.get(opts, :lock_timeout, 30_000)

        if lock_timeout < max_wait do
          warning =
            {:warning,
             "lock_timeout (#{format_duration(lock_timeout)}) is less than max_wait (#{format_duration(max_wait)}). This may cause duplicate fetches if the lock expires while waiters are still waiting."}

          [warning | warnings]
        else
          warnings
        end

      _ ->
        warnings
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp is_positive_integer(val), do: is_integer(val) and val > 0

  defp valid_triggers?(triggers) when is_list(triggers), do: Enum.all?(triggers, &valid_trigger?/1)
  defp valid_triggers?(trigger), do: valid_trigger?(trigger)

  defp valid_trigger?(:stale_access), do: true
  defp valid_trigger?(:immediately_when_expired), do: true
  defp valid_trigger?(:when_expired), do: true
  defp valid_trigger?(:on_expiry), do: true
  defp valid_trigger?({:every, ms}) when is_integer(ms) and ms > 0, do: true
  defp valid_trigger?({:every, ms, opts}) when is_integer(ms) and ms > 0 and is_list(opts), do: true
  defp valid_trigger?({:cron, expr}) when is_binary(expr), do: true
  defp valid_trigger?({:cron, expr, opts}) when is_binary(expr) and is_list(opts), do: true
  defp valid_trigger?(_), do: false

  defp validate_cron_expressions(nil), do: :ok
  defp validate_cron_expressions(triggers) when is_list(triggers) do
    Enum.find_value(triggers, :ok, fn
      {:cron, expr} -> validate_cron_expression(expr)
      {:cron, expr, _opts} -> validate_cron_expression(expr)
      _ -> nil
    end)
  end
  defp validate_cron_expressions({:cron, expr}), do: validate_cron_expression(expr)
  defp validate_cron_expressions({:cron, expr, _opts}), do: validate_cron_expression(expr)
  defp validate_cron_expressions(_), do: :ok

  defp validate_cron_expression(expr) do
    parts = String.split(expr, " ")
    if length(parts) in [5, 6] do
      :ok
    else
      {:error, "invalid cron expression: \"#{expr}\". Expected 5 or 6 space-separated fields."}
    end
  end

  defp valid_on_timeout?(:serve_stale), do: true
  defp valid_on_timeout?(:error), do: true
  defp valid_on_timeout?({:call, f}) when is_function(f), do: true
  defp valid_on_timeout?({:value, _}), do: true
  defp valid_on_timeout?(_), do: false

  defp valid_fallback_action?(:serve_stale), do: true
  defp valid_fallback_action?(:error), do: true
  defp valid_fallback_action?({:call, f}) when is_function(f), do: true
  defp valid_fallback_action?({:value, _}), do: true
  defp valid_fallback_action?(_), do: false

  # Returns on_timeout only if explicitly set by user (not default)
  # Boolean and integer shorthands use defaults, so return nil
  defp explicitly_set_on_timeout?(opts) when is_list(opts), do: Keyword.get(opts, :on_timeout)
  defp explicitly_set_on_timeout?(_), do: nil

  defp has_only_if_stale_trigger?(triggers) do
    Enum.any?(triggers, fn
      {:every, _, opts} -> Keyword.get(opts, :only_if_stale, false)
      {:cron, _, opts} -> Keyword.get(opts, :only_if_stale, false)
      _ -> false
    end)
  end

  defp has_short_interval_without_stale?(triggers, store_ttl) when is_integer(store_ttl) do
    Enum.any?(triggers, fn
      {:every, interval} when interval < store_ttl -> true
      {:every, interval, opts} ->
        interval < store_ttl and not Keyword.get(opts, :only_if_stale, false)
      _ -> false
    end)
  end
  defp has_short_interval_without_stale?(_, _), do: false

  defp format_duration(ms) when is_integer(ms) do
    cond do
      ms >= 86_400_000 -> "#{div(ms, 86_400_000)}d"
      ms >= 3_600_000 -> "#{div(ms, 3_600_000)}h"
      ms >= 60_000 -> "#{div(ms, 60_000)}m"
      ms >= 1_000 -> "#{div(ms, 1_000)}s"
      true -> "#{ms}ms"
    end
  end
end
