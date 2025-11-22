defmodule Events.Schema.Validators.Boolean do
  @moduledoc """
  Boolean-specific validations for enhanced schema fields.

  Provides acceptance validation for boolean fields.
  """

  @doc """
  Apply all boolean validations to a changeset.
  """
  def validate(changeset, field_name, opts) do
    if opts[:acceptance] do
      Ecto.Changeset.validate_acceptance(changeset, field_name)
    else
      changeset
    end
  end
end
