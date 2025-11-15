defmodule Events.SystemHealth.Infra do
  @moduledoc """
  Collects connection metadata for external infrastructure services so the
  health dashboard can display where each dependency is pointing.
  """

  @redis_host_env "REDIS_HOST"
  @redis_port_env "REDIS_PORT"
  @redis_url_env "REDIS_URL"
  @nebulex_url_env "NEBULEX_REDIS_URL"
  @nebulex_host_env "NEBULEX_REDIS_HOST"
  @nebulex_port_env "NEBULEX_REDIS_PORT"
  @aws_env_namespace :events
  @aws_config_key :aws

  @spec connections() :: [map()]
  def connections do
    [
      postgres_connection(),
      redis_connection(),
      hammer_connection(),
      nebulex_connection(),
      s3_connection(),
      dns_cluster_connection()
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp postgres_connection do
    url = repo_url()

    if url do
      %{
        name: "PostgreSQL",
        category: :database,
        url: mask_url(url),
        raw_url: url,
        source: postgres_source(),
        details: postgres_details()
      }
    end
  end

  defp postgres_source do
    cond do
      System.get_env("DATABASE_URL") -> "DATABASE_URL env"
      true -> "runtime.exs default"
    end
  end

  defp postgres_details do
    with {:ok, config} <- fetch_repo_config(),
         database when is_binary(database) <- Keyword.get(config, :database),
         hostname when is_binary(hostname) <- Keyword.get(config, :hostname) do
      port = Keyword.get(config, :port, 5432)
      "database=#{database}, host=#{hostname}, port=#{port}"
    else
      _ -> "Events.Repo"
    end
  end

  defp fetch_repo_config do
    repo_config = Application.get_env(:events, Events.Repo)

    cond do
      is_list(repo_config) -> {:ok, repo_config}
      function_exported?(Events.Repo, :config, 0) -> {:ok, Events.Repo.config()}
      true -> :error
    end
  rescue
    _ -> :error
  end

  defp repo_url do
    with {:ok, config} <- fetch_repo_config(),
         url when is_binary(url) <- Keyword.get(config, :url) do
      url
    else
      _ -> System.get_env("DATABASE_URL")
    end
  end

  defp redis_connection do
    {url, source} = redis_base_url()

    %{
      name: "Redis",
      category: :redis,
      url: mask_url(url),
      raw_url: url,
      source: source,
      details: "General purpose Redis endpoint"
    }
  end

  defp redis_base_url do
    cond do
      url = System.get_env(@redis_url_env) ->
        {url, "#{@redis_url_env} env"}

      host = System.get_env(@redis_host_env) ->
        port = System.get_env(@redis_port_env, "6379")
        {"redis://#{host}:#{port}", "#{@redis_host_env}/#{@redis_port_env} env"}

      true ->
        {"redis://localhost:6379", "default localhost"}
    end
  end

  defp hammer_connection do
    case Application.get_env(:hammer, :backend) do
      {Hammer.Backend.Redis, opts} ->
        redix_opts = Keyword.get(opts, :redix_config, [])
        url = hammer_url(redix_opts)

        %{
          name: "Hammer Redis",
          category: :redis,
          url: mask_url(url),
          raw_url: url,
          source: "config :hammer, backend",
          details: "expiry_ms=#{opts[:expiry_ms]}"
        }

      _ ->
        nil
    end
  end

  defp hammer_url(redix_opts) do
    cond do
      url = Keyword.get(redix_opts, :url) ->
        url

      true ->
        host = Keyword.get(redix_opts, :host, "localhost")
        port = Keyword.get(redix_opts, :port, 6379)
        db = Keyword.get(redix_opts, :database, 0)

        password =
          redix_opts
          |> Keyword.get(:password)
          |> case do
            nil -> nil
            pass -> pass
          end

        userinfo =
          case password do
            nil -> nil
            pass -> ":#{pass}@"
          end

        "redis://#{userinfo || ""}#{host}:#{port}/#{db}"
    end
  end

  defp nebulex_connection do
    adapter = Application.get_env(:events, Events.Cache, [])
    adapter_module = Keyword.get(adapter, :adapter, Nebulex.Adapters.Local)

    url =
      cond do
        custom = System.get_env(@nebulex_url_env) ->
          {custom, "#{@nebulex_url_env} env"}

        host = System.get_env(@nebulex_host_env) ->
          port = System.get_env(@nebulex_port_env, System.get_env(@redis_port_env, "6379"))
          {"redis://#{host}:#{port}", "#{@nebulex_host_env}/#{@nebulex_port_env} env"}

        true ->
          case redis_base_url() do
            {redis_url, _} -> {redis_url, "falls back to Redis host"}
            _ -> {nil, nil}
          end
      end

    case url do
      {nil, _} ->
        %{
          name: "Nebulex Cache",
          category: :cache,
          url: "local://memory",
          raw_url: nil,
          source: "config :events, Events.Cache",
          details: "Adapter=#{inspect(adapter_module)}"
        }

      {redis_url, source} ->
        %{
          name: "Nebulex Redis",
          category: :cache,
          url: mask_url(redis_url),
          raw_url: redis_url,
          source: source,
          details: "Adapter=#{inspect(adapter_module)}"
        }
    end
  end

  defp s3_connection do
    config = Application.get_env(@aws_env_namespace, @aws_config_key, [])

    bucket =
      System.get_env("AWS_S3_BUCKET") ||
        Keyword.get(config, :bucket)

    region =
      System.get_env("AWS_REGION") ||
        System.get_env("AWS_DEFAULT_REGION") ||
        Keyword.get(config, :region, "us-east-1")

    endpoint =
      System.get_env("AWS_ENDPOINT") ||
        Keyword.get(config, :endpoint)

    if bucket || endpoint || System.get_env("AWS_ACCESS_KEY_ID") do
      base =
        cond do
          bucket -> "s3://#{bucket}"
          endpoint -> endpoint
          true -> "s3://(bucket not set)"
        end

      %{
        name: "AWS S3",
        category: :object_storage,
        url: base,
        raw_url: base,
        source:
          if(System.get_env("AWS_S3_BUCKET"), do: "AWS_* env vars", else: "config :events, :aws"),
        details:
          build_details([
            region && "region=#{region}",
            endpoint && "endpoint=#{endpoint}"
          ])
      }
    end
  end

  defp dns_cluster_connection do
    if query = System.get_env("DNS_CLUSTER_QUERY") do
      %{
        name: "DNS Cluster",
        category: :service_discovery,
        url: query,
        raw_url: query,
        source: "DNS_CLUSTER_QUERY env",
        details: "Used for distributed node discovery"
      }
    end
  end

  defp mask_url(nil), do: nil

  defp mask_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.userinfo ->
        [user | rest] = String.split(uri.userinfo, ":", parts: 2)

        masked_userinfo =
          case rest do
            [] -> user
            [_password] -> "#{user}:********"
          end

        uri
        |> Map.put(:userinfo, masked_userinfo)
        |> URI.to_string()

      true ->
        url
    end
  rescue
    _ -> url
  end

  defp build_details(parts) do
    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> case do
      "" -> nil
      string -> string
    end
  end
end
