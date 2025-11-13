defmodule Events.S3.Mock do
  @moduledoc """
  Mock S3 adapter for testing.

  Stores files in memory using an Agent. Useful for tests that don't need
  real S3 interaction.

  ## Usage

      # In test helper or setup
      {:ok, _pid} = Events.S3.Mock.start_link()

      # Configure for tests
      config = AWSConfig.new(
        access_key_id: "test",
        secret_access_key: "test",
        region: "us-east-1",
        bucket: "test-bucket"
      )

      # Use like production adapter
      :ok = S3.upload(config, "test.txt", "content")
      {:ok, "content"} = S3.get_object(config, "test.txt")

      # Clear state between tests
      Events.S3.Mock.clear()
  """

  @behaviour Events.S3
  @behaviour Events.Behaviours.Adapter

  use Agent

  alias Events.AWSConfig

  ## Agent Management

  @doc """
  Starts the mock S3 agent.
  """
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, name: opts[:name] || __MODULE__)
  end

  @doc """
  Clears all stored objects.
  """
  def clear(agent \\ __MODULE__) do
    Agent.update(agent, fn _ -> %{} end)
  end

  @doc """
  Gets the current state (for testing).
  """
  def get_state(agent \\ __MODULE__) do
    Agent.get(agent, & &1)
  end

  ## Adapter Callbacks

  @impl Events.Behaviours.Adapter
  def adapter_name, do: :mock

  @impl Events.Behaviours.Adapter
  def adapter_config(opts) do
    %{
      bucket: Keyword.get(opts, :bucket, "test-bucket"),
      agent: Keyword.get(opts, :agent, __MODULE__)
    }
  end

  ## S3 Callbacks

  @impl Events.S3
  def upload(%AWSConfig{bucket: bucket}, key, content, _opts) do
    bucket_key = {bucket, key}

    Agent.update(__MODULE__, fn state ->
      Map.put(state, bucket_key, %{
        content: content,
        metadata: %{
          size: byte_size(to_binary(content)),
          last_modified: DateTime.utc_now(),
          etag: generate_etag(content)
        }
      })
    end)

    :ok
  end

  @impl Events.S3
  def get_object(%AWSConfig{bucket: bucket}, key) do
    bucket_key = {bucket, key}

    Agent.get(__MODULE__, fn state ->
      case Map.get(state, bucket_key) do
        nil -> {:error, :not_found}
        %{content: content} -> {:ok, content}
      end
    end)
  end

  @impl Events.S3
  def delete_object(%AWSConfig{bucket: bucket}, key) do
    bucket_key = {bucket, key}

    Agent.update(__MODULE__, fn state ->
      Map.delete(state, bucket_key)
    end)

    :ok
  end

  @impl Events.S3
  def object_exists?(%AWSConfig{bucket: bucket}, key) do
    bucket_key = {bucket, key}

    exists =
      Agent.get(__MODULE__, fn state ->
        Map.has_key?(state, bucket_key)
      end)

    {:ok, exists}
  end

  @impl Events.S3
  def list_objects(%AWSConfig{bucket: bucket}, opts) do
    prefix = Keyword.get(opts, :prefix, "")
    max_keys = Keyword.get(opts, :max_keys, 1000)

    objects =
      Agent.get(__MODULE__, fn state ->
        state
        |> Enum.filter(fn {{b, k}, _} ->
          b == bucket && String.starts_with?(k, prefix)
        end)
        |> Enum.take(max_keys)
        |> Enum.map(fn {{_b, k}, %{metadata: meta}} ->
          %{
            key: k,
            size: meta.size,
            last_modified: meta.last_modified,
            etag: meta.etag,
            storage_class: "STANDARD"
          }
        end)
      end)

    {:ok, %{objects: objects, continuation_token: nil}}
  end

  @impl Events.S3
  def presigned_url(%AWSConfig{bucket: bucket}, method, key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    # Generate a fake presigned URL for testing
    url =
      "https://#{bucket}.s3.amazonaws.com/#{key}?" <>
        "X-Amz-Algorithm=AWS4-HMAC-SHA256&" <>
        "X-Amz-Expires=#{expires_in}&" <>
        "X-Amz-Method=#{method}"

    {:ok, url}
  end

  @impl Events.S3
  def copy_object(%AWSConfig{bucket: bucket}, source_key, dest_key) do
    source_bucket_key = {bucket, source_key}
    dest_bucket_key = {bucket, dest_key}

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, source_bucket_key) do
        nil ->
          {{:error, :not_found}, state}

        data ->
          new_state = Map.put(state, dest_bucket_key, data)
          {:ok, new_state}
      end
    end)
  end

  @impl Events.S3
  def head_object(%AWSConfig{bucket: bucket}, key) do
    bucket_key = {bucket, key}

    Agent.get(__MODULE__, fn state ->
      case Map.get(state, bucket_key) do
        nil ->
          {:error, :not_found}

        %{metadata: meta} ->
          {:ok,
           %{
             "content-length" => to_string(meta.size),
             "last-modified" => DateTime.to_iso8601(meta.last_modified),
             "etag" => meta.etag
           }}
      end
    end)
  end

  ## Private Functions

  defp to_binary(content) when is_binary(content), do: content
  defp to_binary(content), do: IO.iodata_to_binary(content)

  defp generate_etag(content) do
    content
    |> to_binary()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
    |> then(&"\"#{&1}\"")
  end
end
