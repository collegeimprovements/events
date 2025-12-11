defmodule OmSchema.FieldHelpers do
  @moduledoc """
  Field-level helper macros for enhanced schema definitions.

  These macros provide shortcuts for common field patterns, making schemas more readable.

  ## Usage

      defmodule MyApp.User do
        use OmSchema
        import OmSchema.FieldHelpers

        schema "users" do
          # String helpers
          email_field :email
          name_field :first_name
          name_field :last_name
          text_field :bio, max_length: 500

          # Date/Time helpers
          date_field :birth_date, past: true
          datetime_field :created_at
          timestamp_field :updated_at

          # Specialized
          slug_field :slug, from: :title
          phone_field :phone, required: false
        end
      end
  """

  @doc """
  Email field with automatic validation and normalization.

  ## Examples

      email_field :email
      email_field :email, required: false
      email_field :work_email, max_length: 100
  """
  defmacro email_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: email(unquote(opts))
    end
  end

  @doc """
  Name field (first name, last name, etc) with titlecase normalization.

  ## Examples

      name_field :first_name
      name_field :last_name, required: false
  """
  defmacro name_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: name(unquote(opts))
    end
  end

  @doc """
  Full name field with space normalization.

  ## Examples

      full_name_field :full_name
      full_name_field :display_name, min_length: 3
  """
  defmacro full_name_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: full_name(unquote(opts))
    end
  end

  @doc """
  Title field for articles, posts, etc.

  ## Examples

      title_field :title
      title_field :heading, max_length: 100
  """
  defmacro title_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: title(unquote(opts))
    end
  end

  @doc """
  Text field with configurable length.

  ## Examples

      text_field :bio
      text_field :description, max_length: 500
      text_field :content, max_length: 10000
  """
  defmacro text_field(name, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, 2000)

    quote do
      import OmSchema.Presets.Strings

      preset =
        case unquote(max_length) do
          n when n <= 500 -> short_text(unquote(opts))
          n when n <= 2000 -> medium_text(unquote(opts))
          _ -> long_text(unquote(opts))
        end

      field unquote(name), :string, preset: preset
    end
  end

  @doc """
  Slug field with automatic uniqueness.

  ## Examples

      slug_field :slug
      slug_field :slug, uniquify: 8
      slug_field :permalink, required: true
  """
  defmacro slug_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: slug(unquote(opts))
    end
  end

  @doc """
  Username field with validation.

  ## Examples

      username_field :username
      username_field :handle, min_length: 3
  """
  defmacro username_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: username(unquote(opts))
    end
  end

  @doc """
  Phone number field.

  ## Examples

      phone_field :phone
      phone_field :mobile, required: false
  """
  defmacro phone_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: phone(unquote(opts))
    end
  end

  @doc """
  URL field.

  ## Examples

      url_field :website
      url_field :homepage, required: false
  """
  defmacro url_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: url(unquote(opts))
    end
  end

  @doc """
  Date field with optional past/future validation.

  ## Examples

      date_field :birth_date, past: true
      date_field :event_date, future: true
      date_field :start_date
  """
  defmacro date_field(name, opts \\ []) do
    quote do
      field unquote(name), :date, unquote(opts)
    end
  end

  @doc """
  Birth date field with age validation (13+ by default).

  ## Examples

      birth_date_field :birth_date
      birth_date_field :date_of_birth, min_age: 18
  """
  defmacro birth_date_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Dates
      field unquote(name), :date, preset: birth_date(unquote(opts))
    end
  end

  @doc """
  DateTime field with optional past/future validation.

  ## Examples

      datetime_field :created_at
      datetime_field :scheduled_at, future: true
      datetime_field :completed_at, past: true
  """
  defmacro datetime_field(name, opts \\ []) do
    quote do
      field unquote(name), :utc_datetime_usec, unquote(opts)
    end
  end

  @doc """
  Timestamp field for created_at/updated_at.

  ## Examples

      timestamp_field :created_at
      timestamp_field :updated_at
  """
  defmacro timestamp_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Dates
      field unquote(name), :utc_datetime_usec, preset: timestamp(unquote(opts))
    end
  end

  @doc """
  Password field with trimming disabled.

  ## Examples

      password_field :password
      password_field :password, min_length: 12
  """
  defmacro password_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets
      field unquote(name), :string, preset: password(unquote(opts))
    end
  end

  @doc """
  Code field (verification codes, promo codes, etc).

  ## Examples

      code_field :verification_code
      code_field :promo_code, min_length: 6
  """
  defmacro code_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: code(unquote(opts))
    end
  end

  @doc """
  Address line field.

  ## Examples

      address_field :street_address
      address_field :address_line_2, required: false
  """
  defmacro address_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: address_line(unquote(opts))
    end
  end

  @doc """
  City field.

  ## Examples

      city_field :city
      city_field :hometown, required: false
  """
  defmacro city_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: city(unquote(opts))
    end
  end

  @doc """
  Color hex code field.

  ## Examples

      color_field :primary_color
      color_field :background, required: false
  """
  defmacro color_field(name, opts \\ []) do
    quote do
      import OmSchema.Presets.Strings
      field unquote(name), :string, preset: color_hex(unquote(opts))
    end
  end
end
