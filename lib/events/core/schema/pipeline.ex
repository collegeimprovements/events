defmodule Events.Core.Schema.Pipeline do
  @moduledoc """
  Beautiful validation pipelines for schemas.

  Each validation flows through the pipeline, accumulating
  validations that will be applied to create the final changeset.
  """

  alias Events.Core.Schema.Pipeline.Token
  alias Events.Core.Schema.Validators
  import Ecto.Changeset

  # ============================================
  # Token Module
  # ============================================

  defmodule Token do
    @moduledoc """
    Token that flows through the validation pipeline.
    """

    defstruct [
      :schema,
      :attrs,
      :validations,
      :casted_fields,
      :required_fields,
      :meta
    ]

    @type validation :: {atom(), atom(), keyword()}

    @type t :: %__MODULE__{
            schema: struct(),
            attrs: map(),
            validations: list(validation()),
            casted_fields: list(atom()),
            required_fields: list(atom()),
            meta: map()
          }

    @doc """
    Creates a new validation token.
    """
    def new(schema, attrs) do
      %__MODULE__{
        schema: schema,
        attrs: attrs,
        validations: [],
        casted_fields: extract_fields(schema),
        required_fields: [],
        meta: %{}
      }
    end

    defp extract_fields(%{__struct__: module}) do
      module.__schema__(:fields)
    end

    defp extract_fields(_), do: []

    @doc """
    Adds a validation to the token.
    """
    def add_validation(%__MODULE__{} = token, field, type, opts \\ []) do
      validation = {field, type, opts}
      %{token | validations: token.validations ++ [validation]}
    end

    @doc """
    Marks a field as required.
    """
    def add_required(%__MODULE__{} = token, field) do
      %{token | required_fields: Enum.uniq(token.required_fields ++ [field])}
    end

    @doc """
    Updates casted fields.
    """
    def set_casted_fields(%__MODULE__{} = token, fields) do
      %{token | casted_fields: fields}
    end
  end

  # ============================================
  # Main Pipeline Functions
  # ============================================

  @doc """
  Validates a field with given validators.

  ## Examples

      token
      |> validate(:email, :required)
      |> validate(:email, :email)
      |> validate(:email, unique: true)

      token
      |> validate(:age, :required, min: 18, max: 120)
  """
  def validate(%Token{} = token, field, validators) when is_list(validators) do
    Enum.reduce(validators, token, &add_validator(&2, field, &1))
  end

  def validate(%Token{} = token, field, validator) do
    add_validator(token, field, validator)
  end

  defp add_validator(token, field, :required) do
    token
    |> Token.add_required(field)
    |> Token.add_validation(field, :required, [])
  end

  defp add_validator(token, field, validator) when is_atom(validator) do
    Token.add_validation(token, field, validator, [])
  end

  defp add_validator(token, field, {validator, opts}) when is_atom(validator) do
    Token.add_validation(token, field, validator, opts)
  end

  defp add_validator(token, field, opts) when is_list(opts) do
    Enum.reduce(opts, token, fn {key, value}, acc ->
      Token.add_validation(acc, field, key, value: value)
    end)
  end

  # ============================================
  # Validation Application
  # ============================================

  @doc """
  Applies all validations and returns a changeset.
  """
  def apply(%Token{} = token) do
    token.schema
    |> cast(token.attrs, token.casted_fields)
    |> validate_required(token.required_fields)
    |> apply_validations(token.validations)
  end

  defp apply_validations(changeset, validations) do
    Enum.reduce(validations, changeset, &apply_validation(&2, &1))
  end

  defp apply_validation(changeset, {field, type, opts}) do
    Validators.apply(changeset, field, type, opts)
  end

  # ============================================
  # Composition Helpers
  # ============================================

  @doc """
  Validates a string field.

  ## Examples

      token
      |> validate_string(:email, :required, :email)
      |> validate_string(:username, min: 3, max: 30, format: ~r/^[a-z0-9_]+$/)
  """
  def validate_string(token, field, opts) do
    token
    |> validate(field, :string)
    |> validate(field, opts)
  end

  @doc """
  Validates a number field.

  ## Examples

      token
      |> validate_number(:age, :required, min: 18, max: 120)
      |> validate_number(:quantity, positive: true)
  """
  def validate_number(token, field, opts) do
    token
    |> validate(field, :number)
    |> validate(field, opts)
  end

  @doc """
  Validates a date/time field.

  ## Examples

      token
      |> validate_datetime(:published_at, :required)
      |> validate_datetime(:scheduled_for, future: true)
  """
  def validate_datetime(token, field, opts) do
    token
    |> validate(field, :datetime)
    |> validate(field, opts)
  end

  @doc """
  Validates an email field.

  ## Examples

      token
      |> validate_email(:email)
      |> validate_email(:backup_email, required: false)
  """
  def validate_email(token, field, opts \\ []) do
    token
    |> validate(field, :email)
    |> maybe_validate_required(field, opts)
  end

  @doc """
  Validates a URL field.

  ## Examples

      token
      |> validate_url(:website)
      |> validate_url(:callback_url, required: true)
  """
  def validate_url(token, field, opts \\ []) do
    token
    |> validate(field, :url)
    |> maybe_validate_required(field, opts)
  end

  @doc """
  Validates a UUID field.

  ## Examples

      token
      |> validate_uuid(:user_id, :required)
  """
  def validate_uuid(token, field, opts \\ []) do
    token
    |> validate(field, :uuid)
    |> maybe_validate_required(field, opts)
  end

  @doc """
  Validates a slug field.

  ## Examples

      token
      |> validate_slug(:slug, unique: true)
  """
  def validate_slug(token, field, opts \\ []) do
    token
    |> validate(field, :slug)
    |> maybe_validate_unique(field, opts)
  end

  @doc """
  Validates money fields.

  ## Examples

      token
      |> validate_money(:price, :required, min: 0)
      |> validate_money(:tax, min: 0)
  """
  def validate_money(token, field, opts \\ []) do
    token
    |> validate(field, :decimal)
    |> validate(field, opts)
  end

  @doc """
  Validates percentage fields.

  ## Examples

      token
      |> validate_percentage(:discount, max: 100)
  """
  def validate_percentage(token, field, opts \\ []) do
    default_opts = [min: 0, max: 100]
    merged_opts = Keyword.merge(default_opts, opts)

    token
    |> validate(field, :number)
    |> validate(field, merged_opts)
  end

  @doc """
  Validates phone number.

  ## Examples

      token
      |> validate_phone(:phone)
      |> validate_phone(:mobile, :required)
  """
  def validate_phone(token, field, opts \\ []) do
    token
    |> validate(field, :phone)
    |> maybe_validate_required(field, opts)
  end

  @doc """
  Validates a boolean field.

  ## Examples

      token
      |> validate_boolean(:active, acceptance: true)
  """
  def validate_boolean(token, field, opts \\ []) do
    token
    |> validate(field, :boolean)
    |> validate(field, opts)
  end

  @doc """
  Validates an enum field.

  ## Examples

      token
      |> validate_enum(:status, in: ["active", "pending", "archived"])
      |> validate_enum(:role, in: [:admin, :user, :guest])
  """
  def validate_enum(token, field, opts) do
    token
    |> validate(field, :inclusion)
    |> validate(field, opts)
  end

  @doc """
  Validates JSON/map fields.

  ## Examples

      token
      |> validate_json(:metadata)
      |> validate_json(:settings, required_keys: ["theme", "language"])
  """
  def validate_json(token, field, opts \\ []) do
    token
    |> validate(field, :map)
    |> validate(field, opts)
  end

  @doc """
  Validates array fields.

  ## Examples

      token
      |> validate_array(:tags, min_length: 1, max_length: 10)
  """
  def validate_array(token, field, opts \\ []) do
    token
    |> validate(field, :array)
    |> validate(field, opts)
  end

  # ============================================
  # Conditional Validators
  # ============================================

  @doc """
  Applies validation only if condition is met.

  ## Examples

      token
      |> validate_if(:promo_code, :required, fn attrs ->
        attrs["has_discount"] == true
      end)
  """
  def validate_if(token, field, validators, condition) do
    if evaluate_condition(condition, token) do
      validate(token, field, validators)
    else
      token
    end
  end

  @doc """
  Applies validation unless condition is met.

  ## Examples

      token
      |> validate_unless(:email, :required, fn attrs ->
        attrs["login_type"] == "oauth"
      end)
  """
  def validate_unless(token, field, validators, condition) do
    unless evaluate_condition(condition, token) do
      validate(token, field, validators)
    else
      token
    end
  end

  defp evaluate_condition(condition, %Token{attrs: attrs}) when is_function(condition, 1) do
    condition.(attrs)
  end

  defp evaluate_condition(condition, _token), do: condition

  # ============================================
  # Cross-field Validators
  # ============================================

  @doc """
  Validates that two fields match.

  ## Examples

      token
      |> validate_confirmation(:password, :password_confirmation)
  """
  def validate_confirmation(token, field, confirmation_field) do
    Token.add_validation(token, field, :confirmation, confirmation_field: confirmation_field)
  end

  @doc """
  Validates field comparison.

  ## Examples

      token
      |> validate_comparison(:start_date, :<=, :end_date)
      |> validate_comparison(:min_price, :<, :max_price)
  """
  def validate_comparison(token, field1, operator, field2) do
    Token.add_validation(token, field1, :comparison,
      operator: operator,
      other_field: field2
    )
  end

  @doc """
  Validates mutual exclusion.

  ## Examples

      token
      |> validate_exclusive([:email, :phone], at_least_one: true)
  """
  def validate_exclusive(token, fields, opts \\ []) do
    Token.add_validation(token, :_global, :exclusive,
      fields: fields,
      at_least_one: Keyword.get(opts, :at_least_one, false)
    )
  end

  # ============================================
  # Helper Functions
  # ============================================

  defp maybe_validate_required(token, field, opts) do
    if Keyword.get(opts, :required, false) do
      validate(token, field, :required)
    else
      token
    end
  end

  defp maybe_validate_unique(token, field, opts) do
    if Keyword.get(opts, :unique, false) do
      validate(token, field, unique: true)
    else
      token
    end
  end

  @doc """
  Taps into the pipeline for debugging.

  ## Examples

      token
      |> tap_inspect("After email validation")
      |> validate(:age, min: 18)
  """
  def tap_inspect(token, label \\ "") do
    IO.inspect(token, label: label)
    token
  end

  @doc """
  Groups validations by field for inspection.

  ## Examples

      iex> grouped_validations(token)
      %{
        email: [:required, :email, unique: true],
        age: [:required, min: 18, max: 120]
      }
  """
  def grouped_validations(%Token{validations: validations}) do
    validations
    |> Enum.group_by(
      fn {field, _, _} -> field end,
      fn {_, type, opts} ->
        if opts == [], do: type, else: {type, opts}
      end
    )
  end
end
