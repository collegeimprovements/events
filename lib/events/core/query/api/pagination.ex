defmodule Events.Core.Query.Api.Pagination do
  @moduledoc false
  # Internal module for Query - pagination operations
  #
  # Handles paginate, limit, and offset operations.

  alias Events.Core.Query.Token

  @doc "Add pagination (offset or cursor-based)"
  @spec paginate(Token.t(), :offset | :cursor, keyword()) :: Token.t()
  def paginate(token, type, opts) do
    Token.add_operation(token, {:paginate, {type, opts}})
  end

  @doc "Add a limit"
  @spec limit(Token.t(), pos_integer()) :: Token.t()
  def limit(token, value) do
    Token.add_operation(token, {:limit, value})
  end

  @doc "Add an offset"
  @spec offset(Token.t(), non_neg_integer()) :: Token.t()
  def offset(token, value) do
    Token.add_operation(token, {:offset, value})
  end
end
