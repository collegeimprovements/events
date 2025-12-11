defmodule OmCrud.Schema do
  @moduledoc """
  Schema-level CRUD integration for adding CRUD capabilities to schemas.

  This module provides macros that can be used within schema definitions
  to enable CRUD configuration and defaults at the schema level.

  ## Usage

      defmodule MyApp.Accounts.User do
        use Ecto.Schema
        use OmCrud.Schema

        schema "users" do
          field :email, :string
          field :name, :string
          timestamps()
        end

        # Specify the default changeset for CRUD operations
        @crud_changeset :registration_changeset

        # Or use the macro
        crud_changeset :registration_changeset

        # Define changesets
        def changeset(user, attrs) do
          user
          |> cast(attrs, [:email, :name])
          |> validate_required([:email])
        end

        def registration_changeset(user, attrs) do
          user
          |> changeset(attrs)
          |> validate_format(:email, ~r/@/)
        end
      end

  ## Configuration Options

  ### @crud_changeset

  Sets the default changeset function for all CRUD operations:

      @crud_changeset :custom_changeset

  ### changeset_for/2 callback

  For dynamic changeset resolution based on action and options:

      def changeset_for(:create, _opts), do: :registration_changeset
      def changeset_for(:update, _opts), do: :update_changeset
      def changeset_for(:delete, _opts), do: :delete_changeset

  ### crud_config/0 callback

  Return a keyword list of default CRUD options:

      def crud_config do
        [
          preload: [:account],
          changeset: :custom_changeset
        ]
      end

  ## Priority Order

  When resolving changeset functions, the following priority is used:

  1. Explicit `:changeset` option passed to the CRUD function
  2. Action-specific option (`:create_changeset`, `:update_changeset`)
  3. Schema's `@crud_changeset` attribute
  4. Schema's `changeset_for/2` callback
  5. Default `:changeset` function
  """

  @doc """
  Use this module in a schema to enable CRUD integration.

  ## Examples

      defmodule MyApp.User do
        use Ecto.Schema
        use OmCrud.Schema

        @crud_changeset :registration_changeset
      end
  """
  defmacro __using__(_opts) do
    quote do
      import OmCrud.Schema, only: [crud_changeset: 1, crud_config: 1]

      Module.register_attribute(__MODULE__, :crud_changeset, accumulate: false)
      Module.register_attribute(__MODULE__, :crud_config, accumulate: false)

      @before_compile OmCrud.Schema
    end
  end

  @doc """
  Set the default changeset function for CRUD operations.

  ## Examples

      crud_changeset :registration_changeset
      crud_changeset :custom_changeset
  """
  defmacro crud_changeset(changeset_fn) when is_atom(changeset_fn) do
    quote do
      @crud_changeset unquote(changeset_fn)
    end
  end

  @doc """
  Set default CRUD configuration options.

  ## Examples

      crud_config preload: [:account], changeset: :custom_changeset
  """
  defmacro crud_config(opts) when is_list(opts) do
    quote do
      @crud_config unquote(opts)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    crud_changeset = Module.get_attribute(env.module, :crud_changeset)
    crud_config = Module.get_attribute(env.module, :crud_config) || []

    quote do
      if unquote(crud_changeset) do
        @doc false
        def __crud_changeset__, do: unquote(crud_changeset)
      end

      if unquote(crud_config) != [] do
        @doc false
        def __crud_config__, do: unquote(crud_config)
      end
    end
  end
end
