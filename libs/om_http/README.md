# OmHttp

Shared HTTP utilities for all Om libraries. Provides unified proxy configuration that works consistently across OmApiClient, OmS3, OmStripe, and OmGoogle.

## Features

- **Multi-format parsing** - URL strings, keyword options, tuples, Mint-native format
- **Environment variable fallback** - Reads `HTTPS_PROXY`/`HTTP_PROXY` with `NO_PROXY` exclusions
- **Req/Finch/Mint output** - Converts to `connect_options` format for Req
- **Credential safety** - Custom `Inspect` protocol and `display_url/1` mask secrets
- **NO_PROXY support** - Exact, suffix, wildcard (`.domain`, `*`), case-insensitive matching
- **HTTP and HTTPS proxies** - Full support for both schemes
- **Zero dependencies** - Pure utility module

## 1 min Setup Guide

**1. Add dependency** (`mix.exs`):

```elixir
{:om_http, "~> 0.1.0"}
```

**2. Set environment variables** (optional — only if using a proxy):

```bash
# Proxy (auto-detected by OmHttp.Proxy.from_env())
export HTTPS_PROXY="http://proxy.example.com:8080"   # or https_proxy
export HTTP_PROXY="http://proxy.example.com:8080"     # fallback
export NO_PROXY="localhost,127.0.0.1,.internal.com"   # bypass list
```

No application config, no supervision. Zero dependencies — pure utility module.

## Quick Start

```elixir
alias OmHttp.Proxy

# Parse from URL
{:ok, config} = Proxy.parse("http://user:pass@proxy.example.com:8080")

# Convert to Req options
connect_opts = Proxy.to_req_options(config)
Req.get!(url, connect_options: connect_opts)
```

### From Environment Variables

```elixir
# Reads HTTPS_PROXY > https_proxy > HTTP_PROXY > http_proxy
# Also reads NO_PROXY / no_proxy for exclusions
case Proxy.from_env() do
  {:ok, config} -> Proxy.to_req_options(config)
  :no_proxy -> []
end
```

### Auto-resolve (explicit config > env vars)

```elixir
# Returns %Proxy{} or nil — handles the fallback chain for you
config = Proxy.get_config(proxy: "http://proxy:8080")
config = Proxy.get_config(nil)  # falls back to env vars
```

---

## Input Formats

`OmHttp.Proxy.parse/1` accepts all common proxy configuration formats:

### URL with embedded credentials

```elixir
{:ok, config} = Proxy.parse("http://user:pass@proxy.example.com:8080")
{:ok, config} = Proxy.parse("https://proxy.example.com:3128")
```

### Keyword options with URL

```elixir
{:ok, config} = Proxy.parse(proxy: "http://proxy.example.com:8080")
{:ok, config} = Proxy.parse(
  proxy: "http://proxy.example.com:8080",
  proxy_auth: {"user", "pass"}
)
```

### Keyword options with tuple

```elixir
{:ok, config} = Proxy.parse(
  proxy: {"proxy.example.com", 8080},
  proxy_auth: {"user", "pass"}
)
```

### Full Mint format

```elixir
{:ok, config} = Proxy.parse(proxy: {:http, "proxy.example.com", 8080, []})
{:ok, config} = Proxy.parse(proxy: {:https, "proxy.example.com", 3128, []})
```

### Map input

```elixir
{:ok, config} = Proxy.parse(%{proxy: "http://proxy:8080", proxy_auth: {"u", "p"}})
```

When `proxy_auth` is provided alongside a URL with embedded credentials, the explicit `proxy_auth` takes precedence.

---

## Environment Variables

`from_env/0` reads proxy configuration from standard environment variables:

| Variable | Priority | Description |
|----------|----------|-------------|
| `HTTPS_PROXY` | 1 (highest) | HTTPS proxy URL |
| `https_proxy` | 2 | Lowercase variant |
| `HTTP_PROXY` | 3 | HTTP proxy URL |
| `http_proxy` | 4 (lowest) | Lowercase variant |
| `NO_PROXY` / `no_proxy` | - | Comma-separated bypass list |

```bash
export HTTPS_PROXY="http://user:pass@proxy.corp.com:8080"
export NO_PROXY="localhost,127.0.0.1,.internal.com"
```

---

## NO_PROXY Matching

`should_bypass?/2` checks whether a host should skip the proxy. All matching is **case-insensitive**.

| Pattern | Matches | Example |
|---------|---------|---------|
| Exact | Exact hostname | `"localhost"` matches `"localhost"` |
| Dot-prefix | Any subdomain | `".internal.com"` matches `"api.internal.com"` |
| Bare domain | Domain and subdomains | `"example.com"` matches `"example.com"` and `"api.example.com"` |
| Global wildcard | Everything | `"*"` bypasses all hosts |

```elixir
config = %Proxy{
  host: {:http, "proxy", 8080, []},
  no_proxy: ["localhost", ".internal.com", "10.0.0.1"]
}

Proxy.should_bypass?(config, "localhost")        #=> true
Proxy.should_bypass?(config, "api.internal.com") #=> true
Proxy.should_bypass?(config, "INTERNAL.COM")     #=> false (dot-prefix requires subdomain)
Proxy.should_bypass?(config, "10.0.0.1")         #=> true
Proxy.should_bypass?(config, "api.stripe.com")   #=> false
```

### Target-aware Req options

```elixir
# Returns proxy options only if the host should not be bypassed
Proxy.to_req_options_for(config, "api.stripe.com")  #=> [proxy: {:http, "proxy", 8080, []}]
Proxy.to_req_options_for(config, "localhost")        #=> []
```

---

## Output Formats

### Req connect_options

```elixir
config = Proxy.get_config(proxy: "http://user:pass@proxy:8080")

# Without auth
Proxy.to_req_options(%Proxy{host: {:http, "proxy", 8080, []}})
#=> [proxy: {:http, "proxy", 8080, []}]

# With auth (generates Basic auth header)
Proxy.to_req_options(config)
#=> [proxy: {:http, "proxy", 8080, []},
#    proxy_headers: [{"proxy-authorization", "Basic dXNlcjpwYXNz"}]]

# Use with Req
Req.get!(url, connect_options: Proxy.to_req_options(config))
```

---

## Credential Safety

Credentials are never exposed in logs or inspect output.

### Custom Inspect protocol

```elixir
config = Proxy.get_config(proxy: "http://admin:secret@proxy:8080")

inspect(config)
#=> "#OmHttp.Proxy<http://***:***@proxy:8080>"

# Without auth
inspect(%Proxy{host: {:http, "proxy", 8080, []}})
#=> "#OmHttp.Proxy<http://proxy:8080>"

# Not configured
inspect(%Proxy{})
#=> "#OmHttp.Proxy<not configured>"
```

### display_url/1

```elixir
Proxy.display_url(config)  #=> "http://***:***@proxy:8080"
Proxy.display_url(nil)     #=> nil
```

---

## Introspection

```elixir
Proxy.configured?(%Proxy{host: {:http, "proxy", 8080, []}})  #=> true
Proxy.configured?(%Proxy{host: nil})                          #=> false
Proxy.configured?(nil)                                        #=> false
```

---

## API Reference

### Parsing

| Function | Returns | Description |
|----------|---------|-------------|
| `parse/1` | `{:ok, t()} \| {:error, term()}` | Parse from URL, keyword, map, or nil |
| `from_env/0` | `{:ok, t()} \| :no_proxy` | Parse from environment variables |
| `get_config/1` | `t() \| nil` | Resolve config (explicit > env > nil) |

### Output

| Function | Returns | Description |
|----------|---------|-------------|
| `to_req_options/1` | `keyword()` | Req-compatible connect_options |
| `to_req_options_for/2` | `keyword()` | Req options with NO_PROXY check |

### Bypass

| Function | Returns | Description |
|----------|---------|-------------|
| `should_bypass?/2` | `boolean()` | Check if host matches NO_PROXY |

### Introspection

| Function | Returns | Description |
|----------|---------|-------------|
| `configured?/1` | `boolean()` | Check if proxy host is set |
| `display_url/1` | `String.t() \| nil` | Masked URL for logging |

---

## Integration with Om Libraries

OmHttp is used by all HTTP-consuming Om libraries for consistent proxy handling:

| Library | How it uses OmHttp |
|---------|-------------------|
| `OmApiClient` | Stores `%Proxy{}` on request struct, applies via `to_req_options/1` |
| `OmS3` | Resolves proxy in config, checks `should_bypass?/2` per S3 endpoint |
| `OmStripe` | Extracts `{host, auth}` from `parse/1` and `from_env/0` |
| `OmGoogle` | Resolves proxy via `get_config/1`, applies via `to_req_options/1` |

### Typical consumer pattern

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

defp apply_proxy(req_opts, %OmHttp.Proxy{} = proxy) do
  Keyword.merge(req_opts, OmHttp.Proxy.to_req_options(proxy))
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

## Real-World Examples

### API client with proxy fallback

```elixir
defmodule MyApp.ApiClient do
  def request(method, url, opts \\ []) do
    proxy_config = OmHttp.Proxy.get_config(opts)
    host = URI.parse(url).host

    connect_opts = OmHttp.Proxy.to_req_options_for(proxy_config, host)

    Req.request!(
      method: method,
      url: url,
      connect_options: connect_opts
    )
  end
end

# Uses explicit proxy
MyApp.ApiClient.request(:get, "https://api.stripe.com/v1/charges",
  proxy: "http://proxy:8080"
)

# Falls back to HTTPS_PROXY env var
MyApp.ApiClient.request(:get, "https://api.stripe.com/v1/charges")
```

### Logging proxy config safely

```elixir
config = OmHttp.Proxy.get_config(app_config)

if OmHttp.Proxy.configured?(config) do
  Logger.info("Using proxy: #{OmHttp.Proxy.display_url(config)}")
  # => "Using proxy: http://***:***@proxy.corp.com:8080"
end
```

### Corporate proxy with NO_PROXY for internal services

```elixir
{:ok, config} = OmHttp.Proxy.parse(
  proxy: "http://squid.corp.com:3128",
  proxy_auth: {"svc-account", "token"},
  no_proxy: ["localhost", ".corp.internal", "10.0.0.0/8"]
)

# External APIs go through proxy
OmHttp.Proxy.to_req_options_for(config, "api.stripe.com")
#=> [proxy: {:http, "squid.corp.com", 3128, []},
#    proxy_headers: [{"proxy-authorization", "Basic ..."}]]

# Internal services bypass proxy
OmHttp.Proxy.to_req_options_for(config, "payments.corp.internal")
#=> []
```

---

## Architecture

```
OmHttp
└── OmHttp.Proxy
    ├── parse/1           # Multi-format input parsing
    ├── from_env/0        # Environment variable resolution
    ├── get_config/1      # Unified config resolution
    ├── to_req_options/1  # Req connect_options output
    ├── to_req_options_for/2  # NO_PROXY-aware output
    ├── should_bypass?/2  # NO_PROXY pattern matching
    ├── configured?/1     # Presence check
    ├── display_url/1     # Safe logging
    └── Inspect protocol  # Credential masking
```

## License

MIT
