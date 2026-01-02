defmodule Events.Core.Repo.Retry do
  @moduledoc """
  Alias for FnTypes.Retry with Events defaults configured via config.

  This module exists for backwards compatibility. New code should use
  `FnTypes.Retry` directly - defaults are configured in config/config.exs:

      config :fn_types, FnTypes.Retry,
        default_repo: Events.Core.Repo

  See `FnTypes.Retry` for full documentation.
  """

  # Delegate to FnTypes.Retry - default_repo is configured in config.exs
  defdelegate execute(fun, opts \\ []), to: FnTypes.Retry
  defdelegate with_retry(fun, opts \\ []), to: FnTypes.Retry, as: :execute
  defdelegate transaction(fun, opts \\ []), to: FnTypes.Retry
end
