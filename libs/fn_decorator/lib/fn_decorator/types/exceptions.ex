defmodule FnDecorator.Types.TypeError do
  @moduledoc """
  Exception raised when a type mismatch is detected in strict mode.
  """
  defexception [:message]
end

defmodule FnDecorator.Types.UnwrapError do
  @moduledoc """
  Exception raised when attempting to unwrap an error result.
  """
  defexception [:message, :reason]
end
