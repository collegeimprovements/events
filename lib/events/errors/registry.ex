defmodule Events.Errors.Registry do
  @moduledoc """
  Central registry of error codes and their default messages.

  This module provides a single source of truth for error codes and their
  human-readable messages across the application.

  ## Usage

      # Get error message
      Registry.message(:validation, :invalid_email)
      #=> "Email address is invalid"

      # Check if code exists
      Registry.exists?(:validation, :invalid_email)
      #=> true

      # List all codes for a type
      Registry.list(:validation)
      #=> [:changeset_invalid, :invalid_email, ...]

      # List all types
      Registry.types()
      #=> [:validation, :not_found, ...]
  """

  @codes %{
    validation: %{
      changeset_invalid: "Validation failed",
      invalid_email: "Email address is invalid",
      invalid_format: "Format is invalid",
      required_field: "Field is required",
      too_short: "Value is too short",
      too_long: "Value is too long",
      out_of_range: "Value is out of acceptable range",
      invalid_type: "Type is invalid",
      uniqueness_constraint: "Value must be unique"
    },
    not_found: %{
      not_found: "Resource not found",
      user_not_found: "User not found",
      record_not_found: "Record not found",
      file_not_found: "File not found",
      path_not_found: "Path not found"
    },
    unauthorized: %{
      unauthorized: "Authentication required",
      invalid_credentials: "Invalid credentials",
      token_expired: "Authentication token has expired",
      token_invalid: "Authentication token is invalid",
      session_expired: "Session has expired"
    },
    forbidden: %{
      forbidden: "Access forbidden",
      insufficient_permissions: "Insufficient permissions",
      access_denied: "Access denied"
    },
    conflict: %{
      conflict: "Resource conflict",
      already_exists: "Resource already exists",
      duplicate_entry: "Duplicate entry",
      concurrent_modification: "Resource was modified by another request"
    },
    internal: %{
      internal: "Internal server error",
      exception: "An unexpected error occurred",
      database_error: "Database error occurred",
      query_error: "Query execution failed"
    },
    external: %{
      external: "External service error",
      service_unavailable: "External service is unavailable",
      api_error: "External API error",
      integration_error: "Integration error"
    },
    timeout: %{
      timeout: "Operation timed out",
      connection_timeout: "Connection timeout",
      request_timeout: "Request timeout",
      query_timeout: "Query timeout"
    },
    rate_limit: %{
      rate_limit: "Rate limit exceeded",
      too_many_requests: "Too many requests",
      quota_exceeded: "Quota exceeded"
    },
    bad_request: %{
      bad_request: "Bad request",
      invalid_params: "Invalid parameters",
      malformed_request: "Malformed request",
      invalid_json: "Invalid JSON"
    },
    unprocessable: %{
      unprocessable: "Request cannot be processed",
      invalid_state: "Invalid state",
      precondition_failed: "Precondition failed"
    },
    service_unavailable: %{
      service_unavailable: "Service unavailable",
      maintenance: "Service under maintenance",
      overloaded: "Service overloaded"
    },
    network: %{
      network: "Network error",
      connection_failed: "Connection failed",
      connection_refused: "Connection refused",
      host_unreachable: "Host unreachable",
      dns_error: "DNS resolution failed"
    },
    configuration: %{
      configuration: "Configuration error",
      missing_config: "Missing configuration",
      invalid_config: "Invalid configuration"
    },
    unknown: %{
      unknown: "Unknown error",
      error: "An error occurred"
    }
  }

  @doc """
  Gets the default message for an error type and code.

  Returns a generic message if the specific code is not found.

  ## Examples

      iex> Registry.message(:validation, :invalid_email)
      "Email address is invalid"

      iex> Registry.message(:validation, :unknown_code)
      "Validation failed"
  """
  @spec message(atom(), atom() | String.t()) :: String.t()
  def message(type, code) when is_atom(type) and (is_atom(code) or is_binary(code)) do
    code = if is_binary(code), do: String.to_existing_atom(code), else: code

    @codes
    |> Map.get(type, %{})
    |> Map.get(code)
    |> case do
      nil -> fallback_message(type)
      message -> message
    end
  rescue
    ArgumentError -> fallback_message(type)
  end

  @doc """
  Checks if an error code exists for a given type.

  ## Examples

      iex> Registry.exists?(:validation, :invalid_email)
      true

      iex> Registry.exists?(:validation, :nonexistent)
      false
  """
  @spec exists?(atom(), atom()) :: boolean()
  def exists?(type, code) when is_atom(type) and is_atom(code) do
    @codes
    |> Map.get(type, %{})
    |> Map.has_key?(code)
  end

  @doc """
  Lists all codes for a given error type.

  ## Examples

      iex> Registry.list(:validation)
      [:changeset_invalid, :invalid_email, ...]
  """
  @spec list(atom()) :: [atom()]
  def list(type) when is_atom(type) do
    @codes
    |> Map.get(type, %{})
    |> Map.keys()
  end

  @doc """
  Lists all error types.

  ## Examples

      iex> Registry.types()
      [:validation, :not_found, :unauthorized, ...]
  """
  @spec types() :: [atom()]
  def types do
    Map.keys(@codes)
  end

  @doc """
  Gets all codes and messages as a nested map.
  """
  @spec all() :: map()
  def all, do: @codes

  ## Helpers

  defp fallback_message(:validation), do: "Validation failed"
  defp fallback_message(:not_found), do: "Resource not found"
  defp fallback_message(:unauthorized), do: "Authentication required"
  defp fallback_message(:forbidden), do: "Access forbidden"
  defp fallback_message(:conflict), do: "Resource conflict"
  defp fallback_message(:internal), do: "Internal server error"
  defp fallback_message(:external), do: "External service error"
  defp fallback_message(:timeout), do: "Operation timed out"
  defp fallback_message(:rate_limit), do: "Rate limit exceeded"
  defp fallback_message(:bad_request), do: "Bad request"
  defp fallback_message(:unprocessable), do: "Request cannot be processed"
  defp fallback_message(:service_unavailable), do: "Service unavailable"
  defp fallback_message(:network), do: "Network error"
  defp fallback_message(:configuration), do: "Configuration error"
  defp fallback_message(_), do: "An error occurred"
end
