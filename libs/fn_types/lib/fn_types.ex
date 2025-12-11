defmodule FnTypes do
  @moduledoc """
  Functional types library for Elixir.

  FnTypes provides a comprehensive set of functional programming types and utilities:

  ## Core Types

  - `FnTypes.Result` - Monadic operations on `{:ok, value}` | `{:error, reason}` tuples
  - `FnTypes.Maybe` - Option type for nil-safe operations (`{:some, value}` | `:none`)
  - `FnTypes.Pipeline` - Multi-step workflow orchestration with context
  - `FnTypes.AsyncResult` - Concurrent operations with automatic error handling
  - `FnTypes.Validation` - Accumulating validation with multiple error support

  ## Utility Types

  - `FnTypes.Error` - Unified error struct with normalization
  - `FnTypes.Guards` - Guard macros for pattern matching
  - `FnTypes.Retry` - Retry logic with backoff strategies
  - `FnTypes.Lens` - Functional lenses for nested data access
  - `FnTypes.Diff` - Value diffing utilities
  - `FnTypes.NonEmptyList` - List type that guarantees at least one element
  - `FnTypes.Resource` - Resource acquisition with automatic cleanup
  - `FnTypes.Ior` - Inclusive-Or type (both/left/right)

  ## Rate Limiting

  - `FnTypes.RateLimiter` - Token bucket rate limiting
  - `FnTypes.Throttler` - Throttling with configurable intervals
  - `FnTypes.Debouncer` - Debouncing for high-frequency events

  ## Protocols

  - `FnTypes.Normalizable` - Error normalization protocol
  - `FnTypes.Recoverable` - Error recovery strategy protocol
  - `FnTypes.Identifiable` - Entity identification protocol

  ## Error Types

  - `FnTypes.Errors.HttpError` - HTTP status code wrapper
  - `FnTypes.Errors.PosixError` - File system errors
  - `FnTypes.Errors.StripeError` - Stripe API errors
  - `FnTypes.Errors.FcmError` - Firebase Cloud Messaging errors

  ## Usage

      # Import commonly used types
      alias FnTypes.{Result, Maybe, Pipeline, AsyncResult}

      # Use Result for error handling
      {:ok, user}
      |> Result.and_then(&send_email/1)
      |> Result.map(&format_response/1)

      # Use Maybe for optional values
      Maybe.from_nilable(value)
      |> Maybe.map(&String.upcase/1)
      |> Maybe.unwrap_or("default")

      # Use Pipeline for multi-step workflows
      Pipeline.new(%{user_id: id})
      |> Pipeline.step(:user, &fetch_user/1)
      |> Pipeline.step(:account, &fetch_account/1)
      |> Pipeline.run()

      # Use AsyncResult for concurrent operations
      AsyncResult.parallel([
        fn -> fetch_user(id) end,
        fn -> fetch_orders(id) end
      ])
  """

  @doc """
  Returns the version of the FnTypes library.
  """
  def version, do: "0.1.0"
end
