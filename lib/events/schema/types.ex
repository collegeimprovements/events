defmodule Events.Schema.Types do
  @moduledoc """
  Common type definitions for the Events.Schema system.
  """

  @type changeset :: Ecto.Changeset.t()
  @type field_name :: atom()
  @type field_type :: atom() | tuple()
  @type opts :: keyword()
  @type validation_result :: changeset
  @type error_tuple :: {field_name, String.t()}
  @type errors :: [error_tuple]
  @type field_value :: any()

  @type validation_fun :: (field_value -> :ok | {:error, String.t()} | errors)
  @type condition_fun :: (changeset -> boolean())
  @type normalizer_fun :: (String.t() -> String.t())

  @type cross_field_validation ::
          {:confirmation, field_name, keyword()}
          | {:require_if, field_name, keyword()}
          | {:one_of, [field_name]}
          | {:compare, field_name, keyword()}
end
