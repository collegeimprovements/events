defmodule Events.Infra.Decorator.Types.TypeError do
  @moduledoc """
  Exception raised when a type mismatch is detected in strict mode.
  """
  defexception [:message]
end

defmodule Events.Infra.Decorator.Types.UnwrapError do
  @moduledoc """
  Exception raised when attempting to unwrap an error result.
  """
  defexception [:message, :reason]
end
