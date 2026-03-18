defmodule OmBehaviours.AdapterTest do
  use ExUnit.Case, async: true

  alias OmBehaviours.Adapter

  # --- Test support modules ---

  defmodule TestStorage do
    @callback upload(key :: String.t(), data :: binary()) :: {:ok, String.t()} | {:error, term()}
  end

  defmodule TestStorage.S3 do
    @behaviour TestStorage
    @behaviour OmBehaviours.Adapter

    @impl OmBehaviours.Adapter
    def adapter_name, do: :s3

    @impl OmBehaviours.Adapter
    def adapter_config(opts) do
      %{
        bucket: Keyword.fetch!(opts, :bucket),
        region: Keyword.get(opts, :region, "us-east-1")
      }
    end

    @impl TestStorage
    def upload(_key, _data), do: {:ok, "s3://test"}
  end

  defmodule TestStorage.Local do
    @behaviour TestStorage
    @behaviour OmBehaviours.Adapter

    @impl OmBehaviours.Adapter
    def adapter_name, do: :local

    @impl OmBehaviours.Adapter
    def adapter_config(opts) do
      %{root_path: Keyword.get(opts, :root_path, "/tmp/uploads")}
    end

    @impl TestStorage
    def upload(_key, _data), do: {:ok, "file:///tmp/test"}
  end

  defmodule TestStorage.GoogleCloud do
    @behaviour OmBehaviours.Adapter

    @impl true
    def adapter_name, do: :google_cloud

    @impl true
    def adapter_config(_opts), do: %{}
  end

  defmodule NotAnAdapter do
    def hello, do: :world
  end

  # --- resolve/2 tests ---

  describe "resolve/2" do
    test "resolves simple adapter names" do
      assert Adapter.resolve(:s3, TestStorage) == TestStorage.S3
    end

    test "resolves multi-word adapter names by camelizing" do
      assert Adapter.resolve(:google_cloud, TestStorage) == TestStorage.GoogleCloud
    end

    test "resolves :local adapter" do
      assert Adapter.resolve(:local, TestStorage) == TestStorage.Local
    end

    test "returns a module atom even if it doesn't exist (no validation)" do
      result = Adapter.resolve(:nonexistent, TestStorage)
      assert is_atom(result)
      assert result == TestStorage.Nonexistent
    end

    test "handles single-character names" do
      assert Adapter.resolve(:x, TestStorage) == TestStorage.X
    end
  end

  # --- resolve!/2 tests ---

  describe "resolve!/2" do
    test "resolves and validates existing adapter" do
      assert Adapter.resolve!(:s3, TestStorage) == TestStorage.S3
    end

    test "resolves multi-word adapter names" do
      assert Adapter.resolve!(:google_cloud, TestStorage) == TestStorage.GoogleCloud
    end

    test "raises ArgumentError for non-existent module" do
      assert_raise ArgumentError, ~r/is not available/, fn ->
        Adapter.resolve!(:nonexistent, TestStorage)
      end
    end

    test "raises ArgumentError for module that exists but doesn't implement Adapter" do
      assert_raise ArgumentError, ~r/does not implement OmBehaviours.Adapter/, fn ->
        Adapter.resolve!(:not_an_adapter, OmBehaviours.AdapterTest)
      end
    end

    test "error message includes the full module name" do
      error =
        assert_raise ArgumentError, fn ->
          Adapter.resolve!(:nonexistent, TestStorage)
        end

      assert error.message =~ "TestStorage.Nonexistent"
    end
  end

  # --- implements?/1 tests ---

  describe "implements?/1" do
    test "returns true for modules implementing Adapter behaviour" do
      assert Adapter.implements?(TestStorage.S3)
      assert Adapter.implements?(TestStorage.Local)
      assert Adapter.implements?(TestStorage.GoogleCloud)
    end

    test "returns false for modules not implementing Adapter" do
      refute Adapter.implements?(NotAnAdapter)
    end

    test "returns false for non-existent modules" do
      refute Adapter.implements?(DoesNotExist.Module)
    end
  end

  # --- adapter_name/0 tests ---

  describe "adapter_name/0 callback" do
    test "returns the configured atom name" do
      assert TestStorage.S3.adapter_name() == :s3
      assert TestStorage.Local.adapter_name() == :local
      assert TestStorage.GoogleCloud.adapter_name() == :google_cloud
    end
  end

  # --- adapter_config/1 tests ---

  describe "adapter_config/1 callback" do
    test "returns validated config map" do
      config = TestStorage.S3.adapter_config(bucket: "my-bucket")
      assert config == %{bucket: "my-bucket", region: "us-east-1"}
    end

    test "applies default values" do
      config = TestStorage.S3.adapter_config(bucket: "test")
      assert config.region == "us-east-1"
    end

    test "overrides defaults with provided values" do
      config = TestStorage.S3.adapter_config(bucket: "test", region: "eu-west-1")
      assert config == %{bucket: "test", region: "eu-west-1"}
    end

    test "raises on missing required config" do
      assert_raise KeyError, ~r/:bucket/, fn ->
        TestStorage.S3.adapter_config([])
      end
    end

    test "local adapter has sensible defaults" do
      config = TestStorage.Local.adapter_config([])
      assert config == %{root_path: "/tmp/uploads"}
    end
  end

  # --- Integration: resolve + use ---

  describe "resolve and use integration" do
    test "resolved adapter can be called" do
      adapter = Adapter.resolve!(:s3, TestStorage)
      assert {:ok, _url} = adapter.upload("key", "data")
    end

    test "resolved adapter config works" do
      adapter = Adapter.resolve!(:s3, TestStorage)
      config = adapter.adapter_config(bucket: "test-bucket")
      assert config.bucket == "test-bucket"
    end
  end
end
