defmodule Events.Core.Schema.PipelineMode do
  @moduledoc """
  Pipeline mode for schemas with elegant validation pipelines.

  Use this instead of Events.Core.Schema for the new pipeline-based validation system.

  ## Usage

      defmodule MyApp.User do
        use Events.Core.Schema.PipelineMode

        schema "users" do
          field :email, :string
          field :age, :integer
        end

        def changeset(user, attrs) do
          user
          |> cast(attrs)
          |> validate(:email, :required, :email)
          |> validate(:age, min: 18, max: 120)
          |> apply()
        end
      end
  """

  defmacro __using__(_opts \\ []) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset, except: [cast: 2, cast: 3]
      import Events.Core.Schema.Pipeline
      import Events.Core.Schema.Validators

      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      # Pipeline-specific functions
      def cast(schema, attrs), do: Events.Core.Schema.Pipeline.Token.new(schema, attrs)

      def validate(token, field, validators),
        do: Events.Core.Schema.Pipeline.validate(token, field, validators)

      def apply(token), do: Events.Core.Schema.Pipeline.apply(token)
    end
  end
end
