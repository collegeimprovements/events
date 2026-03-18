# OmHttp API Reference

> **Always use `OmHttp.Proxy`** from `libs/om_http` for proxy configuration. Used by OmApiClient, OmS3, OmStripe, and OmGoogle.

## Quick Start

```elixir
alias OmHttp.Proxy

# Parse proxy URL
{:ok, config} = Proxy.parse("http://user:pass@proxy:8080")

# Use with Req
Req.get!(url, connect_options: Proxy.to_req_options(config))

# Or auto-resolve from env vars
config = Proxy.get_config(nil)  # reads HTTPS_PROXY / HTTP_PROXY
```

---

## API at a Glance

### Parsing

| Function | Returns | Description |
|----------|---------|-------------|
| `parse/1` | `{:ok, t()} \| {:error, term()}` | Parse URL, keyword, map, or nil |
| `from_env/0` | `{:ok, t()} \| :no_proxy` | Parse from env vars |
| `get_config/1` | `t() \| nil` | Resolve: explicit > env > nil |

### Output

| Function | Returns | Description |
|----------|---------|-------------|
| `to_req_options/1` | `keyword()` | Req `connect_options` format |
| `to_req_options_for/2` | `keyword()` | Req options with NO_PROXY check |

### Bypass

| Function | Returns | Description |
|----------|---------|-------------|
| `should_bypass?/2` | `boolean()` | Case-insensitive NO_PROXY match |

### Introspection

| Function | Returns | Description |
|----------|---------|-------------|
| `configured?/1` | `boolean()` | Is proxy host set? |
| `display_url/1` | `String.t() \| nil` | Masked URL for logging |

---

## Input Formats

`parse/1` accepts all common proxy formats:

```elixir
# URL strings (http and https)
Proxy.parse("http://proxy:8080")
Proxy.parse("https://proxy:3128")
Proxy.parse("http://user:pass@proxy:8080")

# Keyword with URL
Proxy.parse(proxy: "http://proxy:8080")
Proxy.parse(proxy: "http://proxy:8080", proxy_auth: {"user", "pass"})

# Keyword with tuple
Proxy.parse(proxy: {"proxy.example.com", 8080})

# Keyword with Mint format
Proxy.parse(proxy: {:http, "proxy", 8080, []})
Proxy.parse(proxy: {:https, "proxy", 3128, []})

# With NO_PROXY
Proxy.parse(proxy: "http://proxy:8080", no_proxy: "localhost,.internal.com")
Proxy.parse(proxy: "http://proxy:8080", no_proxy: ["localhost", ".internal.com"])

# Map input
Proxy.parse(%{proxy: "http://proxy:8080"})

# Nil (empty config)
Proxy.parse(nil)  #=> {:ok, %Proxy{host: nil}}
```

**Auth precedence**: explicit `proxy_auth` > URL-embedded credentials.

---

## Environment Variables

| Variable | Priority |
|----------|----------|
| `HTTPS_PROXY` | 1 (highest) |
| `https_proxy` | 2 |
| `HTTP_PROXY` | 3 |
| `http_proxy` | 4 (lowest) |
| `NO_PROXY` / `no_proxy` | Comma-separated bypass list |

```elixir
# Returns {:ok, config} or :no_proxy
case Proxy.from_env() do
  {:ok, config} -> Proxy.to_req_options(config)
  :no_proxy -> []
end
```

Invalid env var URLs return `:no_proxy` (not an error).

---

## Config Resolution

`get_config/1` is the convenience function for the common pattern: use explicit config if given, fall back to env vars, return nil if nothing found.

```elixir
Proxy.get_config(proxy: "http://proxy:8080")  #=> %Proxy{} from explicit
Proxy.get_config(nil)                          #=> %Proxy{} from env, or nil
Proxy.get_config([])                           #=> %Proxy{} from env, or nil
Proxy.get_config("http://proxy:8080")          #=> %Proxy{} from URL string
```

---

## NO_PROXY Matching

All matching is **case-insensitive**.

| Pattern | Example | Matches |
|---------|---------|---------|
| Exact | `"localhost"` | `"localhost"`, `"LOCALHOST"` |
| Dot-prefix | `".internal.com"` | `"api.internal.com"`, `"deep.api.internal.com"` |
| Bare domain | `"example.com"` | `"example.com"`, `"api.example.com"` |
| Global wildcard | `"*"` | Everything |

```elixir
config = %Proxy{
  host: {:http, "proxy", 8080, []},
  no_proxy: ["localhost", ".internal.com"]
}

Proxy.should_bypass?(config, "localhost")         #=> true
Proxy.should_bypass?(config, "api.internal.com")  #=> true
Proxy.should_bypass?(config, "api.stripe.com")    #=> false

# Combined check + Req options in one call
Proxy.to_req_options_for(config, "api.stripe.com")  #=> [proxy: ...]
Proxy.to_req_options_for(config, "localhost")        #=> []
```

---

## Credential Safety

Credentials are **never** exposed in `inspect/1` or `display_url/1`.

```elixir
config = Proxy.get_config(proxy: "http://admin:secret@proxy:8080")

# Inspect protocol masks auth
inspect(config)
#=> "#OmHttp.Proxy<http://***:***@proxy:8080>"

# display_url/1 for logging
Proxy.display_url(config)
#=> "http://***:***@proxy:8080"

# Safe to log
Logger.info("Proxy: #{Proxy.display_url(config)}")
```

---

## Req Integration

```elixir
# Simple — proxy all requests
config = Proxy.get_config(proxy: "http://proxy:8080")
Req.get!(url, connect_options: Proxy.to_req_options(config))

# With auth
config = Proxy.get_config(proxy: "http://user:pass@proxy:8080")
Proxy.to_req_options(config)
#=> [proxy: {:http, "proxy", 8080, []},
#    proxy_headers: [{"proxy-authorization", "Basic dXNlcjpwYXNz"}]]

# NO_PROXY-aware (recommended)
host = URI.parse(url).host
Req.get!(url, connect_options: Proxy.to_req_options_for(config, host))
```

---

## Real-World Patterns

### Consumer library proxy resolution

```elixir
defp get_proxy_config(config) do
  case {Map.get(config, :proxy), Map.get(config, :proxy_auth)} do
    {nil, _} ->
      case OmHttp.Proxy.from_env() do
        {:ok, proxy_config} -> proxy_config
        :no_proxy -> nil
      end

    {proxy, proxy_auth} ->
      OmHttp.Proxy.get_config(proxy: proxy, proxy_auth: proxy_auth)
  end
end
```

### Corporate proxy with internal bypass

```elixir
{:ok, config} = Proxy.parse(
  proxy: "http://squid.corp.com:3128",
  proxy_auth: {"svc-account", "token"},
  no_proxy: "localhost,.corp.internal,10.0.0.1"
)

# External traffic goes through proxy
Proxy.to_req_options_for(config, "api.stripe.com")
#=> [proxy: ..., proxy_headers: [...]]

# Internal traffic bypasses
Proxy.to_req_options_for(config, "payments.corp.internal")
#=> []
```

### Conditional proxy logging

```elixir
config = OmHttp.Proxy.get_config(app_config)

if OmHttp.Proxy.configured?(config) do
  Logger.info("HTTP proxy active: #{OmHttp.Proxy.display_url(config)}")
end
```

---

## Types

```elixir
@type scheme     :: :http | :https
@type proxy_host :: {scheme(), String.t(), pos_integer(), keyword()}
@type proxy_auth :: {String.t(), String.t()}

@type t :: %OmHttp.Proxy{
  host: proxy_host() | nil,
  auth: proxy_auth() | nil,
  no_proxy: [String.t()]
}
```

---

## Module Map

```
OmHttp
└── OmHttp.Proxy         # All proxy functionality
    ├── Parsing           # parse/1, from_env/0, get_config/1
    ├── Output            # to_req_options/1, to_req_options_for/2
    ├── Bypass            # should_bypass?/2
    ├── Introspection     # configured?/1, display_url/1
    └── Inspect protocol  # Credential masking
```
