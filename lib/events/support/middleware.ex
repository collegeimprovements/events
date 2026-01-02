defmodule Events.Support.Middleware do
  @moduledoc """
  Unified middleware abstraction for composable processing pipelines.

  Thin wrapper around `OmMiddleware` with Events-specific defaults.

  See `OmMiddleware` for full documentation.
  """

  defdelegate wrap(middleware, context, fun), to: OmMiddleware
  defdelegate run_before(middleware, context), to: OmMiddleware
  defdelegate run_after(middleware, result, context), to: OmMiddleware
  defdelegate run_error(middleware, error, context), to: OmMiddleware
  defdelegate run_complete(middleware, result, context), to: OmMiddleware
  defdelegate pipe(middleware), to: OmMiddleware
  defdelegate compose(middleware), to: OmMiddleware
  defdelegate normalize(middleware), to: OmMiddleware

  defmacro __using__(opts) do
    quote do
      use OmMiddleware, unquote(opts)
    end
  end
end
