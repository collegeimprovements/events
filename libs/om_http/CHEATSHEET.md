# OmHttp Cheatsheet

## Parse

```elixir
alias OmHttp.Proxy

# URL string
{:ok, config} = Proxy.parse("http://user:pass@proxy:8080")
{:ok, config} = Proxy.parse("https://proxy:3128")

# Keyword options
{:ok, config} = Proxy.parse(proxy: "http://proxy:8080")
{:ok, config} = Proxy.parse(proxy: {"proxy", 8080})
{:ok, config} = Proxy.parse(proxy: {:http, "proxy", 8080, []})
{:ok, config} = Proxy.parse(proxy: "http://proxy:8080", proxy_auth: {"u", "p"})
{:ok, config} = Proxy.parse(proxy: "http://proxy:8080", no_proxy: "localhost,.internal.com")

# Map
{:ok, config} = Proxy.parse(%{proxy: "http://proxy:8080"})

# Nil
{:ok, %Proxy{host: nil}} = Proxy.parse(nil)

# Errors
{:error, {:invalid_proxy_url, _}} = Proxy.parse("bad")
{:error, {:invalid_proxy_format, _}} = Proxy.parse(proxy: :bad)
```

## Environment Variables

```elixir
# Reads: HTTPS_PROXY > https_proxy > HTTP_PROXY > http_proxy
# Also reads: NO_PROXY / no_proxy
case Proxy.from_env() do
  {:ok, config} -> Proxy.to_req_options(config)    # proxy configured
  :no_proxy -> []                                    # no proxy in env
end
```

## Get Config (explicit > env > nil)

```elixir
Proxy.get_config(proxy: "http://proxy:8080")       # => %Proxy{} from explicit
Proxy.get_config(nil)                               # => %Proxy{} from env, or nil
Proxy.get_config([])                                # => %Proxy{} from env, or nil
Proxy.get_config("http://proxy:8080")               # => %Proxy{} from URL
Proxy.get_config("bad-url")                         # => nil
```

## Req Options

```elixir
# Without auth
Proxy.to_req_options(config)                        # => [proxy: {:http, "proxy", 8080, []}]

# With auth
Proxy.to_req_options(config)                        # => [proxy: ..., proxy_headers: [{"proxy-authorization", "Basic ..."}]]

# Nil-safe
Proxy.to_req_options(nil)                           # => []
Proxy.to_req_options(%Proxy{host: nil})             # => []

# With Req
Req.get!(url, connect_options: Proxy.to_req_options(config))
```

## NO_PROXY Bypass (case-insensitive)

```elixir
config = %Proxy{host: {:http, "proxy", 8080, []}, no_proxy: ["localhost", ".internal.com"]}

Proxy.should_bypass?(config, "localhost")           # => true  (exact)
Proxy.should_bypass?(config, "LOCALHOST")           # => true  (case-insensitive)
Proxy.should_bypass?(config, "api.internal.com")    # => true  (dot-prefix suffix)
Proxy.should_bypass?(config, "external.com")        # => false

# Global wildcard
Proxy.should_bypass?(%Proxy{no_proxy: ["*"]}, host) # => true (always)

# Nil-safe
Proxy.should_bypass?(nil, "any")                    # => false

# Target-aware Req options (bypass check + to_req_options in one call)
Proxy.to_req_options_for(config, "api.stripe.com")  # => [proxy: ...]
Proxy.to_req_options_for(config, "localhost")        # => []
```

## Introspection

```elixir
Proxy.configured?(config)                           # => true/false
Proxy.configured?(nil)                              # => false

Proxy.display_url(config)                           # => "http://***:***@proxy:8080"
Proxy.display_url(nil)                              # => nil
```

## Inspect (credentials auto-masked)

```elixir
inspect(config)                                     # => #OmHttp.Proxy<http://***:***@proxy:8080>
inspect(%Proxy{host: {:https, "p", 3128, []}})      # => #OmHttp.Proxy<https://p:3128>
inspect(%Proxy{})                                   # => #OmHttp.Proxy<not configured>
```

## Types

```elixir
@type scheme     :: :http | :https
@type proxy_host :: {scheme(), String.t(), pos_integer(), keyword()}
@type proxy_auth :: {String.t(), String.t()}
@type t          :: %OmHttp.Proxy{host: proxy_host() | nil, auth: proxy_auth() | nil, no_proxy: [String.t()]}
```

## Typical Consumer Pattern

```elixir
defp resolve_proxy(config) do
  case {Map.get(config, :proxy), Map.get(config, :proxy_auth)} do
    {nil, _} ->
      case OmHttp.Proxy.from_env() do
        {:ok, proxy} -> proxy
        :no_proxy -> nil
      end

    {proxy, auth} ->
      OmHttp.Proxy.get_config(proxy: proxy, proxy_auth: auth)
  end
end

defp apply_proxy(req_opts, proxy, target_host) do
  Keyword.merge(req_opts, OmHttp.Proxy.to_req_options_for(proxy, target_host))
end
```
