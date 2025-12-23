defmodule OmSchema.Telemetry do
  @moduledoc """
  Telemetry integration for OmSchema validation monitoring.

  Emits the following events (prefix configurable via `:om_schema, :telemetry_prefix`):
  - `[prefix, :validation, :start]` - When validation starts
  - `[prefix, :validation, :stop]` - When validation completes
  - `[prefix, :validation, :exception]` - When validation fails

  Default prefix is `[:om_schema]`. Configure for your app:

      config :om_schema, telemetry_prefix: [:myapp, :schema]

  ## Event Measurements

  - `:duration` - Time taken in native units (use System.convert_time_unit/3)

  ## Event Metadata

  - `:field` - The field being validated
  - `:type` - The field type
  - `:validator` - The validator module used
  - `:valid?` - Whether the changeset is valid after validation
  """

  @app_name Application.compile_env(:om_schema, :app_name, :om_schema)
  @telemetry_prefix Application.compile_env(:om_schema, :telemetry_prefix, [:om_schema])

  @doc """
  Execute a validation function with telemetry tracking.
  """
  @spec span(atom(), map(), (-> any())) :: any()
  def span(event_name, metadata, fun) do
    :telemetry.span(
      @telemetry_prefix ++ [:validation, event_name],
      metadata,
      fn ->
        result = fun.()
        {result, %{}}
      end
    )
  end

  @doc """
  Execute field validation with telemetry.
  """
  @spec with_telemetry(Ecto.Changeset.t(), atom(), atom(), keyword(), (-> Ecto.Changeset.t())) ::
          Ecto.Changeset.t()
  def with_telemetry(changeset, field_name, field_type, _opts, fun) do
    span(
      :field,
      %{
        field: field_name,
        type: field_type,
        validator: get_validator_for_type(field_type),
        initial_valid: changeset.valid?
      },
      fn ->
        result = fun.()

        # Emit additional event if validity changed
        if result.valid? != changeset.valid? do
          :telemetry.execute(
            @telemetry_prefix ++ [:validation, :validity_changed],
            %{},
            %{
              field: field_name,
              was_valid: changeset.valid?,
              is_valid: result.valid?
            }
          )
        end

        result
      end
    )
  end

  defp get_validator_for_type(type) do
    case type do
      :string ->
        OmSchema.Validators.String

      :citext ->
        OmSchema.Validators.String

      :integer ->
        OmSchema.Validators.Number

      :float ->
        OmSchema.Validators.Number

      :decimal ->
        OmSchema.Validators.Number

      :boolean ->
        OmSchema.Validators.Boolean

      {:array, _} ->
        OmSchema.Validators.Array

      :map ->
        OmSchema.Validators.Map

      {:map, _} ->
        OmSchema.Validators.Map

      type when type in [:date, :time, :naive_datetime, :utc_datetime] ->
        OmSchema.Validators.DateTime

      _ ->
        nil
    end
  end

  @doc """
  Attach default telemetry handlers for logging.
  """
  def attach_default_handlers do
    prefix = @telemetry_prefix

    :telemetry.attach_many(
      "om-schema-validation",
      [
        prefix ++ [:validation, :field, :start],
        prefix ++ [:validation, :field, :stop],
        prefix ++ [:validation, :validity_changed]
      ],
      &handle_event/4,
      %{prefix: prefix}
    )
  end

  defp handle_event(event, measurements, metadata, %{prefix: prefix}) do
    cond do
      event == prefix ++ [:validation, :field, :start] ->
        if Application.get_env(@app_name, :log_validation_start, false) do
          require Logger
          Logger.debug("Validating #{metadata.field} as #{metadata.type}")
        end

      event == prefix ++ [:validation, :field, :stop] ->
        if Application.get_env(@app_name, :log_validation_timing, false) do
          require Logger
          duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
          Logger.debug("Validated #{metadata.field} in #{duration_ms}ms")
        end

      event == prefix ++ [:validation, :validity_changed] ->
        if Application.get_env(@app_name, :log_validity_changes, true) do
          require Logger
          Logger.info("Field #{metadata.field} changed validity: #{metadata.was_valid} -> #{metadata.is_valid}")
        end

      true ->
        :ok
    end
  end

  defp handle_event(_event, _measurements, _metadata, _config), do: :ok
end
