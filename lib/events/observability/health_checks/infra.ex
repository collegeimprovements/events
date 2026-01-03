defmodule Events.Observability.HealthChecks.Infra do
  @moduledoc """
  Collects connection metadata for external infrastructure services so the
  health dashboard can display where each dependency is pointing.

  ## Configuration

  The repo and cache modules are configurable via:

      config :events, Events.Observability.HealthChecks.Infra,
        app_name: :my_app,
        repo_module: MyApp.Repo,
        cache_module: MyApp.Cache

  Default repo: `Events.Data.Repo`
  Default cache: `Events.Data.Cache`
  """

  alias FnTypes.Config, as: Cfg

  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)
  @repo_module Application.compile_env(:events, [__MODULE__, :repo_module], Events.Data.Repo)
  @cache_module Application.compile_env(:events, [__MODULE__, :cache_module], Events.Data.Cache)
  @redis_host_env "REDIS_HOST"
  @redis_port_env "REDIS_PORT"
  @redis_url_env "REDIS_URL"
  @nebulex_url_env "NEBULEX_REDIS_URL"
  @nebulex_host_env "NEBULEX_REDIS_HOST"
  @nebulex_port_env "NEBULEX_REDIS_PORT"
  @aws_env_namespace @app_name
  @aws_config_key :aws

  @spec connections() :: [map()]
  def connections do
    [
      &postgres_connection/0,
      &redis_connection/0,
      &hammer_connection/0,
      &nebulex_connection/0,
      &s3_connection/0,
      &dns_cluster_connection/0
    ]
    |> Enum.map(& &1.())
    |> Enum.reject(&is_nil/1)
  end

  defp postgres_connection do
    repo_url()
    |> build_postgres_connection()
  end

  defp build_postgres_connection(nil), do: nil

  defp build_postgres_connection(url) do
    %{
      name: "PostgreSQL",
      category: :database,
      url: mask_url(url),
      raw_url: url,
      source: postgres_source(),
      details: postgres_details()
    }
  end

  defp postgres_source do
    if Cfg.present?("DATABASE_URL"), do: "DATABASE_URL env", else: "runtime.exs default"
  end

  defp postgres_details do
    fetch_repo_config()
    |> extract_postgres_details()
  end

  defp extract_postgres_details({:ok, config}) do
    with database when is_binary(database) <- Keyword.get(config, :database),
         hostname when is_binary(hostname) <- Keyword.get(config, :hostname) do
      port = Keyword.get(config, :port, 5432)
      "database=#{database}, host=#{hostname}, port=#{port}"
    else
      _ -> inspect(@repo_module)
    end
  end

  defp extract_postgres_details(:error), do: inspect(@repo_module)

  defp fetch_repo_config do
    Application.get_env(@app_name, @repo_module)
    |> parse_repo_config()
  rescue
    _ -> :error
  end

  defp parse_repo_config(config) when is_list(config), do: {:ok, config}

  defp parse_repo_config(_) do
    case function_exported?(@repo_module, :config, 0) do
      true -> {:ok, @repo_module.config()}
      false -> :error
    end
  end

  defp repo_url do
    fetch_repo_config()
    |> extract_repo_url()
    |> Kernel.||(Cfg.string("DATABASE_URL"))
  end

  defp extract_repo_url({:ok, config}) do
    config
    |> Keyword.get(:url)
    |> case do
      url when is_binary(url) -> url
      _ -> nil
    end
  end

  defp extract_repo_url(:error), do: nil

  defp redis_connection do
    redis_base_url()
    |> build_redis_connection()
  end

  defp build_redis_connection({url, source}) do
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
      url = Cfg.string(@redis_url_env) ->
        {url, "#{@redis_url_env} env"}

      host = Cfg.string(@redis_host_env) ->
        build_redis_host_url(host)

      true ->
        {"redis://localhost:6379", "default localhost"}
    end
  end

  defp build_redis_host_url(host) do
    port = Cfg.integer(@redis_port_env, 6379)
    {"redis://#{host}:#{port}", "#{@redis_host_env}/#{@redis_port_env} env"}
  end

  defp hammer_connection do
    Application.get_env(:hammer, :backend)
    |> build_hammer_connection()
  end

  defp build_hammer_connection({Hammer.Backend.Redis, opts}) do
    opts
    |> Keyword.get(:redix_config, [])
    |> hammer_url()
    |> build_hammer_result(opts)
  end

  defp build_hammer_connection(_), do: nil

  defp build_hammer_result(url, opts) do
    %{
      name: "Hammer Redis",
      category: :redis,
      url: mask_url(url),
      raw_url: url,
      source: "config :hammer, backend",
      details: "expiry_ms=#{opts[:expiry_ms]}"
    }
  end

  defp hammer_url(redix_opts) do
    Keyword.get(redix_opts, :url) || build_redis_url_from_opts(redix_opts)
  end

  defp build_redis_url_from_opts(redix_opts) do
    host = Keyword.get(redix_opts, :host, "localhost")
    port = Keyword.get(redix_opts, :port, 6379)
    db = Keyword.get(redix_opts, :database, 0)

    redix_opts
    |> Keyword.get(:password)
    |> build_userinfo()
    |> then(&"redis://#{&1}#{host}:#{port}/#{db}")
  end

  defp build_userinfo(nil), do: ""
  defp build_userinfo(password), do: ":#{password}@"

  defp nebulex_connection do
    Application.get_env(@app_name, @cache_module, [])
    |> get_nebulex_adapter()
    |> then(fn adapter_module ->
      nebulex_url()
      |> build_nebulex_connection(adapter_module)
    end)
  end

  defp get_nebulex_adapter(config) do
    Keyword.get(config, :adapter, Nebulex.Adapters.Local)
  end

  defp nebulex_url do
    cond do
      custom = Cfg.string(@nebulex_url_env) ->
        {custom, "#{@nebulex_url_env} env"}

      host = Cfg.string(@nebulex_host_env) ->
        build_nebulex_host_url(host)

      true ->
        fallback_to_redis_url()
    end
  end

  defp build_nebulex_host_url(host) do
    port = Cfg.integer([@nebulex_port_env, @redis_port_env], 6379)
    {"redis://#{host}:#{port}", "#{@nebulex_host_env}/#{@nebulex_port_env} env"}
  end

  defp fallback_to_redis_url do
    case redis_base_url() do
      {redis_url, _} -> {redis_url, "falls back to Redis host"}
      _ -> {nil, nil}
    end
  end

  defp build_nebulex_connection({nil, _}, adapter_module) do
    %{
      name: "Nebulex Cache",
      category: :cache,
      url: "local://memory",
      raw_url: nil,
      source: "config :#{@app_name}, #{inspect(@cache_module)}",
      details: "Adapter=#{inspect(adapter_module)}"
    }
  end

  defp build_nebulex_connection({redis_url, source}, adapter_module) do
    %{
      name: "Nebulex Redis",
      category: :cache,
      url: mask_url(redis_url),
      raw_url: redis_url,
      source: source,
      details: "Adapter=#{inspect(adapter_module)}"
    }
  end

  defp s3_connection do
    config = Application.get_env(@aws_env_namespace, @aws_config_key, [])
    s3_config = extract_s3_config(config)

    case has_s3_config?(s3_config) do
      true -> build_s3_connection(s3_config)
      false -> nil
    end
  end

  defp has_s3_config?(%{bucket: bucket, endpoint: endpoint})
       when not is_nil(bucket) or not is_nil(endpoint) do
    true
  end

  defp has_s3_config?(_) do
    Cfg.present?("AWS_ACCESS_KEY_ID")
  end

  defp extract_s3_config(config) do
    %{
      bucket:
        Cfg.string(["S3_BUCKET", "AWS_S3_BUCKET"]) ||
          Keyword.get(config, :bucket),
      region:
        Cfg.string(["AWS_REGION", "AWS_DEFAULT_REGION"]) ||
          Keyword.get(config, :region, "us-east-1"),
      endpoint:
        Cfg.string(["AWS_ENDPOINT_URL_S3", "AWS_ENDPOINT"]) ||
          Keyword.get(config, :endpoint)
    }
  end

  defp build_s3_connection(%{bucket: bucket, region: region, endpoint: endpoint} = s3_config) do
    %{
      name: "S3 / MinIO",
      category: :object_storage,
      url: build_s3_url(s3_config),
      raw_url: build_s3_url(s3_config),
      source: determine_s3_source(bucket),
      details: build_s3_details(bucket, region, endpoint)
    }
  end

  defp build_s3_url(%{bucket: bucket, endpoint: endpoint}) do
    cond do
      bucket && endpoint -> "#{endpoint}/#{bucket}"
      bucket -> "s3://#{bucket}"
      endpoint -> endpoint
      true -> "s3://(bucket not set)"
    end
  end

  defp determine_s3_source(_bucket) do
    if Cfg.present?(["S3_BUCKET", "AWS_S3_BUCKET"]),
      do: "AWS_* env vars",
      else: "config :events, :aws"
  end

  defp build_s3_details(bucket, region, endpoint) do
    [
      bucket && "bucket=#{bucket}",
      region && "region=#{region}",
      endpoint && "endpoint=#{endpoint}"
    ]
    |> build_details()
  end

  defp dns_cluster_connection do
    Cfg.string("DNS_CLUSTER_QUERY")
    |> build_dns_cluster_connection()
  end

  defp build_dns_cluster_connection(nil), do: nil

  defp build_dns_cluster_connection(query) do
    %{
      name: "DNS Cluster",
      category: :service_discovery,
      url: query,
      raw_url: query,
      source: "DNS_CLUSTER_QUERY env",
      details: "Used for distributed node discovery"
    }
  end

  defp mask_url(nil), do: nil

  defp mask_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> mask_userinfo()
    |> URI.to_string()
  rescue
    _ -> url
  end

  defp mask_userinfo(%URI{userinfo: nil} = uri), do: uri

  defp mask_userinfo(%URI{userinfo: userinfo} = uri) do
    userinfo
    |> String.split(":", parts: 2)
    |> build_masked_userinfo()
    |> then(&Map.put(uri, :userinfo, &1))
  end

  defp build_masked_userinfo([user]), do: user
  defp build_masked_userinfo([user, _password]), do: "#{user}:********"

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
