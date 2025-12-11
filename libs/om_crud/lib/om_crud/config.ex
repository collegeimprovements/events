defmodule OmCrud.Config do
  @moduledoc """
  Configuration for OmCrud.

  ## Configuration Options

  * `:default_repo` - The default Ecto.Repo module to use for database operations.
    This is required if not explicitly passing `:repo` in options.

  * `:telemetry_prefix` - The prefix for telemetry events.
    Defaults to `[:om_crud, :execute]`.

  ## Example Configuration

      config :om_crud,
        default_repo: MyApp.Repo,
        telemetry_prefix: [:my_app, :crud, :execute]
  """

  @doc """
  Get the default repo module.

  Raises if not configured and no repo is provided in options.
  """
  @spec default_repo() :: module()
  def default_repo do
    case Application.get_env(:om_crud, :default_repo) do
      nil ->
        raise ArgumentError, """
        OmCrud requires a default repo to be configured.

        Add to your config:

            config :om_crud, default_repo: MyApp.Repo

        Or pass `:repo` option to each operation:

            OmCrud.create(User, attrs, repo: MyApp.Repo)
        """

      repo when is_atom(repo) ->
        repo
    end
  end

  @doc """
  Get the default repo module, or nil if not configured.

  Useful for checking if configuration exists without raising.
  """
  @spec default_repo_or_nil() :: module() | nil
  def default_repo_or_nil do
    Application.get_env(:om_crud, :default_repo)
  end

  @doc """
  Get the telemetry event prefix.

  Defaults to `[:om_crud, :execute]`.
  """
  @spec telemetry_prefix() :: [atom()]
  def telemetry_prefix do
    Application.get_env(:om_crud, :telemetry_prefix, [:om_crud, :execute])
  end
end
