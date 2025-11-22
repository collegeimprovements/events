defmodule Events.KillSwitch.S3 do
  @moduledoc """
  S3 service wrapper with kill switch support.

  Provides graceful degradation when S3 is unavailable. All operations
  check the kill switch before executing and can fall back to alternative
  storage mechanisms.

  ## Usage

      # Simple check
      if KillSwitch.S3.enabled?() do
        S3.upload(bucket, key, content)
      end

      # With automatic fallback
      KillSwitch.S3.upload(bucket, key, content,
        fallback: fn -> DbStorage.save(key, content) end
      )

      # Pattern matching
      case KillSwitch.S3.check() do
        :enabled -> S3.list(bucket)
        {:disabled, reason} -> {:error, {:s3_disabled, reason}}
      end

  ## Configuration

      # Disable S3
      S3_ENABLED=false

      # Or in config
      config :events, Events.KillSwitch, s3: false
  """

  alias Events.KillSwitch
  alias Events.Services.Aws.SimpleS3

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
  - Plus all SimpleS3.list/2 options

  ## Examples

      # With fallback
      KillSwitch.S3.list("my-bucket",
        prefix: "uploads/",
        fallback: fn -> {:ok, %{files: [], next_token: nil}} end
      )

      # Without fallback (returns error if disabled)
      KillSwitch.S3.list("my-bucket", prefix: "uploads/")
  """
  @spec list(String.t(), keyword()) ::
          {:ok, %{files: [map()], next_token: String.t() | nil}} | {:error, term()}
  def list(bucket, opts \\ [])

  def list(bucket, opts) when is_binary(bucket) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)

    execute_with_fallback(
      fn -> SimpleS3.list(bucket, s3_opts) end,
      fallback
    )
  end

  @doc """
  Upload file with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - Plus all SimpleS3.upload/4 options

  ## Examples

      KillSwitch.S3.upload("my-bucket", "photo.jpg", content,
        type: "image/jpeg",
        fallback: fn -> DbStorage.save("photo.jpg", content) end
      )
  """
  @spec upload(String.t(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def upload(bucket, path, content, opts \\ [])

  def upload(bucket, path, content, opts)
      when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)

    execute_with_fallback(
      fn -> SimpleS3.upload(bucket, path, content, s3_opts) end,
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

    execute_with_fallback(
      fn -> SimpleS3.download(bucket, path) end,
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

    execute_with_fallback(
      fn -> SimpleS3.delete(bucket, path) end,
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

    execute_with_fallback(
      fn -> SimpleS3.exists?(bucket, path) end,
      fallback
    )
  end

  @doc """
  Generate presigned upload URL with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - Plus all SimpleS3.url_for_upload/3 options

  ## Examples

      KillSwitch.S3.url_for_upload("my-bucket", "photo.jpg",
        expires: 300,
        fallback: fn -> {:ok, "/api/upload/photo.jpg"} end
      )
  """
  @spec url_for_upload(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def url_for_upload(bucket, path, opts \\ [])

  def url_for_upload(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)

    execute_with_fallback(
      fn -> SimpleS3.url_for_upload(bucket, path, s3_opts) end,
      fallback
    )
  end

  @doc """
  Generate presigned download URL with kill switch protection.

  ## Options

  - `:fallback` - Function to call if S3 is disabled
  - Plus all SimpleS3.url_for_download/3 options

  ## Examples

      KillSwitch.S3.url_for_download("my-bucket", "photo.jpg",
        expires: 3600,
        fallback: fn -> {:ok, "/api/download/photo.jpg"} end
      )
  """
  @spec url_for_download(String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def url_for_download(bucket, path, opts \\ [])

  def url_for_download(bucket, path, opts) when is_binary(bucket) and is_binary(path) do
    {fallback, s3_opts} = Keyword.pop(opts, :fallback)

    execute_with_fallback(
      fn -> SimpleS3.url_for_download(bucket, path, s3_opts) end,
      fallback
    )
  end

  ## Private Helpers

  defp execute_with_fallback(func, nil) do
    KillSwitch.execute(@service, func)
  end

  defp execute_with_fallback(func, fallback) when is_function(fallback, 0) do
    KillSwitch.with_service(@service, func, fallback: fallback)
  end
end
