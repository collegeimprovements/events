defmodule OmSchema.Sensitive do
  @moduledoc """
  Provides automatic protocol implementations for schemas with sensitive fields.

  When a field is marked with `sensitive: true`, it should be:
  - Redacted in `Inspect` output (shows `"[REDACTED]"` instead of actual value)
  - Excluded from `Jason.Encoder` output (if Jason is available)

  ## Usage

  Mark fields as sensitive in your schema:

      defmodule MyApp.User do
        use OmSchema

        schema "users" do
          field :email, :string
          field :password_hash, :string, sensitive: true
          field :api_key, :string, sensitive: true
        end
      end

  When inspected, sensitive fields are redacted:

      iex> inspect(user)
      #MyApp.User<id: "abc-123", email: "user@example.com", password_hash: "[REDACTED]", ...>

  ## Protocol Implementations

  This module provides a `__before_compile__` callback that automatically implements:

  - `Inspect` protocol - redacts sensitive field values
  - `Jason.Encoder` protocol - excludes sensitive fields (if Jason is available)

  ## Manual Redaction

  You can also manually redact a struct:

      OmSchema.Sensitive.redact(user)
      # => %User{..., password_hash: "[REDACTED]", api_key: "[REDACTED]"}

  Or get the redacted fields map:

      OmSchema.Sensitive.redacted_fields(user)
      # => %{password_hash: "[REDACTED]", api_key: "[REDACTED]"}

  """

  @redacted_marker "[REDACTED]"

  @doc """
  Returns the redaction marker string.
  """
  def redacted_marker, do: @redacted_marker

  @doc """
  Redacts sensitive fields in a struct, replacing their values with "[REDACTED]".

  ## Examples

      iex> user = %User{email: "test@example.com", password_hash: "secret123"}
      iex> OmSchema.Sensitive.redact(user)
      %User{email: "test@example.com", password_hash: "[REDACTED]"}

  """
  @spec redact(struct()) :: struct()
  def redact(%module{} = struct) do
    if function_exported?(module, :sensitive_fields, 0) do
      sensitive = module.sensitive_fields()
      redacted = Map.new(sensitive, fn field -> {field, @redacted_marker} end)
      Map.merge(struct, redacted)
    else
      struct
    end
  end

  @doc """
  Returns a map of sensitive field names to "[REDACTED]" markers.

  ## Examples

      iex> OmSchema.Sensitive.redacted_fields(%User{})
      %{password_hash: "[REDACTED]", api_key: "[REDACTED]"}

  """
  @spec redacted_fields(struct()) :: map()
  def redacted_fields(%module{} = _struct) do
    if function_exported?(module, :sensitive_fields, 0) do
      Map.new(module.sensitive_fields(), fn field -> {field, @redacted_marker} end)
    else
      %{}
    end
  end

  @doc """
  Returns the list of sensitive field names for a struct.

  ## Examples

      iex> OmSchema.Sensitive.sensitive_field_names(%User{})
      [:password_hash, :api_key]

  """
  @spec sensitive_field_names(struct()) :: [atom()]
  def sensitive_field_names(%module{} = _struct) do
    if function_exported?(module, :sensitive_fields, 0) do
      module.sensitive_fields()
    else
      []
    end
  end

  @doc """
  Checks if a struct has any sensitive fields.

  ## Examples

      iex> OmSchema.Sensitive.has_sensitive_fields?(%User{})
      true

      iex> OmSchema.Sensitive.has_sensitive_fields?(%PublicData{})
      false

  """
  @spec has_sensitive_fields?(struct()) :: boolean()
  def has_sensitive_fields?(%module{} = _struct) do
    function_exported?(module, :sensitive_fields, 0) && module.sensitive_fields() != []
  end

  @doc """
  Converts a struct to a map, excluding sensitive fields.

  Useful for JSON encoding or logging.

  ## Examples

      iex> user = %User{id: 1, email: "test@example.com", password_hash: "secret"}
      iex> OmSchema.Sensitive.to_safe_map(user)
      %{id: 1, email: "test@example.com"}

  """
  @spec to_safe_map(struct()) :: map()
  def to_safe_map(%module{} = struct) do
    map = Map.from_struct(struct)

    if function_exported?(module, :sensitive_fields, 0) do
      sensitive = module.sensitive_fields()
      Map.drop(map, sensitive)
    else
      map
    end
  end

  @doc """
  Converts a struct to a map with sensitive fields redacted (not removed).

  ## Examples

      iex> user = %User{id: 1, email: "test@example.com", password_hash: "secret"}
      iex> OmSchema.Sensitive.to_redacted_map(user)
      %{id: 1, email: "test@example.com", password_hash: "[REDACTED]"}

  """
  @spec to_redacted_map(struct()) :: map()
  def to_redacted_map(%module{} = struct) do
    map = Map.from_struct(struct)

    if function_exported?(module, :sensitive_fields, 0) do
      sensitive = module.sensitive_fields()

      Enum.reduce(sensitive, map, fn field, acc ->
        if Map.has_key?(acc, field) do
          Map.put(acc, field, @redacted_marker)
        else
          acc
        end
      end)
    else
      map
    end
  end

  # ============================================
  # Before Compile Callback
  # ============================================

  @doc false
  defmacro __before_compile__(env) do
    module = env.module

    # Get sensitive fields - check if attribute exists
    sensitive_fields =
      case Module.get_attribute(module, :sensitive_fields_computed) do
        nil -> []
        fields -> fields
      end

    # Get derive options
    derive_inspect = Module.get_attribute(module, :om_derive_inspect, true)
    derive_jason = Module.get_attribute(module, :om_derive_jason, true)

    # Only generate protocol implementations if there are sensitive fields
    if sensitive_fields != [] do
      inspect_impl = if derive_inspect, do: generate_inspect_impl(module, sensitive_fields)
      jason_impl = if derive_jason && Code.ensure_loaded?(Jason.Encoder), do: generate_jason_impl(module, sensitive_fields)

      quote do
        unquote(inspect_impl)
        unquote(jason_impl)
      end
    else
      quote do
      end
    end
  end

  defp generate_inspect_impl(module, sensitive_fields) do
    quote do
      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(struct, opts) do
          # Get all fields from the struct, excluding special keys
          fields = Map.keys(struct) -- [:__struct__, :__meta__]

          # Build the field list with redaction
          field_docs =
            Enum.map(fields, fn field ->
              value =
                if field in unquote(sensitive_fields) do
                  OmSchema.Sensitive.redacted_marker()
                else
                  Map.get(struct, field)
                end

              concat([
                Atom.to_string(field),
                ": ",
                to_doc(value, opts)
              ])
            end)

          # Format as #ModuleName<fields...>
          container_doc(
            "#" <> Kernel.inspect(unquote(module)) <> "<",
            field_docs,
            ">",
            opts,
            fn doc, _opts -> doc end
          )
        end
      end
    end
  end

  defp generate_jason_impl(module, sensitive_fields) do
    quote do
      defimpl Jason.Encoder, for: unquote(module) do
        def encode(struct, opts) do
          # Convert to map, excluding meta and sensitive fields
          map =
            struct
            |> Map.from_struct()
            |> Map.drop([:__meta__ | unquote(sensitive_fields)])

          Jason.Encode.map(map, opts)
        end
      end
    end
  end
end
