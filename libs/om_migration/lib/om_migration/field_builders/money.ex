defmodule OmMigration.FieldBuilders.Money do
  @moduledoc """
  Builds money/currency fields for migrations.

  Money fields are decimal fields with appropriate precision for currency.
  Default precision is 10 with scale 2 (supports up to 99,999,999.99).

  ## Options

  - `:fields` - List of money field names (default: [:amount])
  - `:precision` - Decimal precision (default: 10)
  - `:scale` - Decimal scale (default: 2)
  - `:currency_field` - Include a currency code field (default: false)

  ## Examples

      create_table(:invoices)
      |> Money.add()                                        # :amount field
      |> Money.add(fields: [:subtotal, :tax, :total])       # Multiple fields
      |> Money.add(fields: [:price], currency_field: true)  # With currency
  """

  @behaviour OmMigration.Behaviours.FieldBuilder

  alias OmMigration.Token
  alias OmMigration.Behaviours.FieldBuilder

  @impl true
  def default_config do
    %{
      fields: [:amount],
      precision: 10,
      scale: 2,
      currency_field: false
    }
  end

  @impl true
  def build(token, config) do
    token
    |> add_money_fields(config)
    |> maybe_add_currency_field(config.currency_field)
  end

  @impl true
  def indexes(_config) do
    []
  end

  # ============================================
  # Money Field Builders
  # ============================================

  defp add_money_fields(token, config) do
    config.fields
    |> Enum.reduce(token, fn field_name, acc ->
      Token.add_field(acc, field_name, :decimal,
        precision: config.precision,
        scale: config.scale,
        null: true,
        comment: "Money field: #{field_name}"
      )
    end)
  end

  defp maybe_add_currency_field(token, false), do: token

  defp maybe_add_currency_field(token, true) do
    Token.add_field(token, :currency, :string,
      null: true,
      default: "USD",
      comment: "ISO 4217 currency code"
    )
  end

  # ============================================
  # Convenience Function
  # ============================================

  @doc """
  Adds money fields to a migration token.

  ## Options

  - `:fields` - List of money field names (default: [:amount])
  - `:precision` - Decimal precision (default: 10)
  - `:scale` - Decimal scale (default: 2)
  - `:currency_field` - Include a currency code field (default: false)

  ## Examples

      Money.add(token)
      Money.add(token, fields: [:subtotal, :tax, :total])
      Money.add(token, fields: [:price], currency_field: true)
      Money.add(token, fields: [:price], precision: 12, scale: 4)
  """
  @spec add(Token.t(), keyword()) :: Token.t()
  def add(token, opts \\ []) do
    FieldBuilder.apply(token, __MODULE__, opts)
  end
end
