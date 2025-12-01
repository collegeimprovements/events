defmodule Events.Test.Mocks do
  @moduledoc """
  Mock configuration and setup for the test suite.

  This module configures Mimic and Hammox for mocking external dependencies.

  ## Usage

  In your test module:

      use Events.Test.Mocks

  This will import Mimic functions and set up automatic verification.

  ## Mocking Patterns

  ### Quick ad-hoc mocking (Mimic)

      test "handles S3 failure" do
        Events.Services.S3
        |> expect(:get, fn _uri, _config -> {:error, :connection_failed} end)

        assert {:error, _} = MyModule.fetch_file("s3://bucket/key")
      end

  ### Contract-enforced mocking (Hammox)

  For modules with behaviours, use Hammox to ensure mocks match typespecs:

      test "user service follows contract" do
        Hammox.expect(UserServiceMock, :get_user, fn id ->
          {:ok, %User{id: id}}
        end)
      end
  """

  @doc """
  List of modules that should be copied for mocking.

  These modules can be stubbed/expected in tests.
  """
  def mockable_modules do
    [
      # External services
      Events.Services.S3,
      Events.Services.S3.Client,
      Events.Core.Cache,

      # External libraries
      Redix,
      Req,
      Hammer
    ]
  end

  @doc """
  Sets up all mockable modules.

  Called from test_helper.exs
  """
  def setup! do
    for module <- mockable_modules() do
      if Code.ensure_loaded?(module) do
        Mimic.copy(module)
      end
    end

    :ok
  end

  defmacro __using__(_opts) do
    quote do
      use Mimic

      import Events.Test.Mocks, only: [stub_external_services: 0]
    end
  end

  @doc """
  Stubs all external services with safe defaults.

  Use this in setup blocks when you don't care about external calls
  but want tests to not fail due to missing stubs.
  """
  def stub_external_services do
    # S3 - return empty/success by default
    if Code.ensure_loaded?(Events.Services.S3) do
      Mimic.stub(Events.Services.S3, :get, fn _uri, _config -> {:error, :not_configured} end)
      Mimic.stub(Events.Services.S3, :put, fn _uri, _data, _config -> {:error, :not_configured} end)
      Mimic.stub(Events.Services.S3, :list, fn _uri, _config, _opts -> {:ok, []} end)
    end

    # Cache - pass through or return nil
    if Code.ensure_loaded?(Events.Core.Cache) do
      Mimic.stub(Events.Core.Cache, :get, fn _key -> nil end)
      Mimic.stub(Events.Core.Cache, :put, fn _key, value, _opts -> value end)
      Mimic.stub(Events.Core.Cache, :delete, fn _key -> :ok end)
    end

    :ok
  end
end
