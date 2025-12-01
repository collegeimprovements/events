defmodule Events.Infra.KillSwitch.S3 do
  @moduledoc """
  S3 service wrapper with kill switch support.

  Provides graceful degradation when S3 is unavailable. All operations
  check the kill switch before executing and can fall back to alternative
  storage mechanisms.

  ## Usage

      # Simple check
      if KillSwitch.S3.enabled?() do
        S3.put("s3://bucket/key", content, config)
      end

      # With automatic fallback
      KillSwitch.S3.upload(bucket, key, content,
        fallback: fn -> DbStorage.save(key, content) end
      )

      # Pattern matching
      case KillSwitch.S3.check() do
        :enabled -> S3.list("s3://bucket/", config)
        {:disabled, reason} -> {:error, {:s3_disabled, reason}}
      end

  ## Configuration

      # Disable S3
      S3_ENABLED=false

      # Or in config
      config :events, Events.Infra.KillSwitch, s3: false
  """

  alias Events.Infra.KillSwitch
  alias Events.Services.S3

  @service :s3

  @doc "Check if S3 service is enabled"
  @spec enabled?() :: boolean()
  def enabled?, do: KillSwitch.enabled?(@service)

  @doc "Check S3 service status"
  @spec check() :: :enabled | {:disabled, String.t()}
  def check, do: KillSwitch.check(@service)

  @doc "Get detailed S3 service status"
  @spec status() :: KillSwitch.status()
  def status, do: KillSwitch.status(@service)

  @doc "Disable S3 service"
  @spec disable(keyword()) :: :ok
  def disable(opts \\ []), do: KillSwitch.disable(@service, opts)

  @doc "Enable S3 service"
  @spec enable() :: :ok
  def enable, do: KillSwitch.enable(@service)

  ## Service Operations with Kill Switch

  @doc """
  List files with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - `:prefix` - Key prefix to filter by
  - `:limit` - Maximum objects to return

  ## Examples

      # With fallback
      KillSwitch.S3.list("my-bucket",
        prefix: "uploads/",
        fallback: fn -> {:ok, %{files: [], next: nil}} end
      )

      # Without fallback (returns error if disabled)
      KillSwitch.S3.list("my-bucket", prefix: "uploads/")
  """
  @spec list(String.t(), keyword()) ::
          {:ok, %{files: [map()], next: String.t() | nil}} | {:error, term()}
  def list(bucket, opts \\ [])

  def list(bucket, opts) when is_binary(bucket) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)
    prefix = Keyword.get(s3_opts, :prefix, "")
    uri = S3.uri(bucket, prefix)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.list(uri, config, s3_opts) end,
      fallback
    )
  end

  @doc """
  Upload file with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - `:content_type` - MIME type of content

  ## Examples

      KillSwitch.S3.upload("my-bucket", "photo.jpg", content,
        content_type: "image/jpeg",
        fallback: fn -> DbStorage.save("photo.jpg", content) end
      )
  """
  @spec upload(String.t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def upload(bucket, path, content, opts \\ [])

  def upload(bucket, path, content, opts)
      when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.put(uri, content, config, s3_opts) end,
      fallback
    )
  end

  @doc """
  Download file with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled

  ## Examples

      KillSwitch.S3.download("my-bucket", "photo.jpg",
        fallback: fn -> DbStorage.fetch("photo.jpg") end
      )
  """
  @spec download(String.t(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def download(bucket, path, opts \\ [])

  def download(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    fallback = Keyword.get(opts, :fallback)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.get(uri, config) end,
      fallback
    )
  end

  @doc """
  Delete file with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled

  ## Examples

      KillSwitch.S3.delete("my-bucket", "old-file.txt",
        fallback: fn -> DbStorage.delete("old-file.txt") end
      )
  """
  @spec delete(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete(bucket, path, opts \\ [])

  def delete(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    fallback = Keyword.get(opts, :fallback)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.delete(uri, config) end,
      fallback
    )
  end

  @doc """
  Check if file exists with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled (default: returns false)

  ## Examples

      KillSwitch.S3.exists?("my-bucket", "photo.jpg",
        fallback: fn -> DbStorage.exists?("photo.jpg") end
      )
  """
  @spec exists?(String.t(), String.t(), keyword()) :: boolean()
  def exists?(bucket, path, opts \\ [])

  def exists?(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    fallback = Keyword.get(opts, :fallback, fn -> false end)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.exists?(uri, config) end,
      fallback
    )
  end

  @doc """
  Generate presigned upload URL with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - `:expires_in` - Expiration in seconds or tuple like `{5, :minutes}`

  ## Examples

      KillSwitch.S3.url_for_upload("my-bucket", "photo.jpg",
        expires_in: {5, :minutes},
        fallback: fn -> {:ok, "/api/upload/photo.jpg"} end
      )
  """
  @spec url_for_upload(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def url_for_upload(bucket, path, opts \\ [])

  def url_for_upload(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.presign(uri, config, Keyword.put(s3_opts, :method, :put)) end,
      fallback
    )
  end

  @doc """
  Generate presigned download URL with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - `:expires_in` - Expiration in seconds or tuple like `{1, :hour}`

  ## Examples

      KillSwitch.S3.url_for_download("my-bucket", "photo.jpg",
        expires_in: {1, :hour},
        fallback: fn -> {:ok, "/api/download/photo.jpg"} end
      )
  """
  @spec url_for_download(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def url_for_download(bucket, path, opts \\ [])

  def url_for_download(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)
    uri = S3.uri(bucket, path)
    config = s3_config()

    execute_with_fallback(
      fn -> S3.presign(uri, config, Keyword.put(s3_opts, :method, :get)) end,
      fallback
    )
  end

  ## Private Helpers

  defp s3_config do
    S3.Config.from_env()
  end

  defp execute_with_fallback(func, nil) do
    KillSwitch.execute(@service, func)
  end

  defp execute_with_fallback(func, fallback) when is_function(fallback, 0) do
    KillSwitch.with_service(@service, func, fallback: fallback)
  end
end
