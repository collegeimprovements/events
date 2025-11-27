defmodule Events.Schema.Validators.Boolean do
  @moduledoc """
  Boolean-specific validations for enhanced schema fields.

  Provides acceptance validation for boolean fields.

  Implements `Events.Schema.Behaviours.Validator` behavior.
  """

  @behaviour Events.Schema.Behaviours.Validator

  @impl true
  def field_types, do: [:boolean]

  @impl true
  def supported_options, do: [:acceptance]

  @doc """
  Apply all boolean validations to a changeset.
  """
  @impl true
  def validate(changeset, field_name, opts) do
    if opts[:acceptance] do
      Ecto.Changeset.validate_acceptance(changeset, field_name)
    else
      changeset
    end
  end
end
