defmodule Events.Observability.HealthChecks.Config do
  @moduledoc """
  Configuration validation status for SystemHealth display.

  Integrates with ConfigValidator to provide configuration health checks.
  """

  alias Events.Startup.ConfigValidator

  @doc """
  Checks all service configurations and returns status.

  Returns a map with:
  - `:valid` - Count of valid configurations
  - `:warnings` - Count of configurations with warnings
  - `:errors` - Count of configuration errors
  - `:disabled` - Count of disabled services
  - `:services` - Detailed service information for display

  ## Examples

      Config.check_all()
      #=> %{
      #     valid: 4,
      #     warnings: 1,
      #     errors: 0,
      #     disabled: 1,
      #     services: [...]
      #   }
  """
  @spec check_all() :: map()
  def check_all do
    results = ConfigValidator.validate_all()

    %{
      valid: length(results.ok),
      warnings: length(results.warnings),
      errors: length(results.errors),
      disabled: length(results.disabled),
      services: format_services(results)
    }
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp format_services(results) do
    []
    |> append_services(results.ok, :ok)
    |> append_services(results.warnings, :warning)
    |> append_services(results.errors, :error)
    |> append_services(results.disabled, :disabled)
    |> Enum.sort_by(& &1.name)
  end

  defp append_services(list, services, status) do
    formatted =
      Enum.map(services, fn service ->
        %{
          name: format_service_name(service.service),
          status: status,
          critical: service.critical,
          description: service.description,
          details: format_details(service.metadata),
          reason: service.reason,
          adapter: extract_adapter(service.metadata)
        }
      end)

    list ++ formatted
  end

  defp format_service_name(service) do
    service
    |> to_string()
    |> String.capitalize()
  end

  defp format_details(metadata) when metadata == %{}, do: nil

  defp format_details(metadata) do
    metadata
    |> Enum.reject(fn {k, v} -> k in [:adapter, :backend, :configured] or is_nil(v) end)
    |> Enum.map(&format_detail_pair/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      details -> details
    end
  end

  defp format_detail_pair({:pool_size, value}), do: "Pool: #{value}"
  defp format_detail_pair({:host, value}), do: "Host: #{value}"
  defp format_detail_pair({:port, value}), do: "Port: #{value}"
  defp format_detail_pair({:database, value}), do: "DB: #{value}"
  defp format_detail_pair({:bucket, value}), do: "Bucket: #{value}"
  defp format_detail_pair({:region, value}), do: "Region: #{value}"
  defp format_detail_pair({:endpoint, value}), do: "Endpoint: #{value}"
  defp format_detail_pair({:mode, value}), do: "Mode: #{value}"
  defp format_detail_pair({:api_version, value}), do: "API: #{value}"
  defp format_detail_pair({:store, value}), do: "Store: #{value}"
  defp format_detail_pair({:peer, value}), do: "Peer: #{value}"
  defp format_detail_pair({:queues, values}), do: "Queues: #{Enum.join(values, ", ")}"
  defp format_detail_pair({:enabled, true}), do: "Enabled"
  defp format_detail_pair({:enabled, false}), do: "Disabled"
  defp format_detail_pair({:ssl, true}), do: "SSL"
  defp format_detail_pair({key, value}), do: "#{key}: #{inspect(value)}"

  defp extract_adapter(%{adapter: adapter}), do: format_adapter(adapter)
  defp extract_adapter(%{backend: backend}), do: backend
  defp extract_adapter(_), do: "-"

  defp format_adapter(nil), do: "-"
  defp format_adapter(adapter) when is_atom(adapter), do: inspect(adapter)
  defp format_adapter(adapter) when is_binary(adapter), do: adapter
end
