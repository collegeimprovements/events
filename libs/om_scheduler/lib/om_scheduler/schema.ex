defmodule OmScheduler.Schema do
  @moduledoc """
  Schema module for OmScheduler.

  By default uses Ecto.Schema. Can be configured to use a custom schema module:

      config :om_scheduler, :schema_module, MyApp.Schema

  The custom schema module should provide the same macros as Ecto.Schema.
  """

  @schema_module Application.compile_env(:om_scheduler, :schema_module, Ecto.Schema)

  defmacro __using__(opts) do
    schema_module = @schema_module

    quote do
      use unquote(schema_module), unquote(opts)
      import Ecto.Changeset
      alias Ecto.Changeset

      # Default primary key type - can be overridden
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end
end
