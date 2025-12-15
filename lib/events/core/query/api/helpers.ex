defmodule Events.Core.Query.Api.Helpers do
  @moduledoc false
  # Internal module for Query - pipeline helpers
  #
  # Provides helper functions for conditional and compositional query building:
  # - then_if - Conditional pipeline
  # - include/include_if - Query fragments
  # - Pipeline utilities

  alias Events.Core.Query.Token

  @doc """
  Conditionally apply a function to the token.

  Useful for building queries conditionally in a pipeline.

  ## Examples

      User
      |> Query.new()
      |> Query.then_if(params[:status], fn token, status ->
        Query.filter(token, :status, :eq, status)
      end)
      |> Query.then_if(params[:min_age], fn token, age ->
        Query.filter(token, :age, :gte, age)
      end)
      |> Query.execute()
  """
  @spec then_if(Token.t(), term(), (Token.t(), term() -> Token.t())) :: Token.t()
  def then_if(%Token{} = token, nil, _fun), do: token
  def then_if(%Token{} = token, false, _fun), do: token
  def then_if(%Token{} = token, value, fun), do: fun.(token, value)

  @doc """
  Conditionally apply a function to the token (boolean version).

  ## Examples

      User
      |> Query.new()
      |> Query.if_true(show_active?, fn token ->
        Query.filter(token, :status, :eq, "active")
      end)
      |> Query.execute()
  """
  @spec if_true(Token.t(), boolean(), (Token.t() -> Token.t())) :: Token.t()
  def if_true(%Token{} = token, true, fun), do: fun.(token)
  def if_true(%Token{} = token, false, _fun), do: token
end
