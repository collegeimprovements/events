# Dockerfile for Events Phoenix Application
# Optimized for Docker Swarm deployment with Erlang clustering
#
# Build: docker build -t events:latest .
# Run:   docker stack deploy -c docker-compose.yml events

ARG ELIXIR_VERSION=1.19.3
ARG OTP_VERSION=27.3.4
ARG DEBIAN_VERSION=bookworm-20250520-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

# ==============================================================================
# BUILD STAGE
# ==============================================================================
FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# Set build ENV
ENV MIX_ENV="prod"

# Install mix dependencies first (better layer caching)
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

# Copy compile-time config
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
COPY config/config_helper.ex config/
RUN mix deps.compile

# Setup assets
RUN mix assets.setup

# Copy application code
COPY priv priv
COPY lib lib

# Compile the release
RUN mix compile

# Build assets
COPY assets assets
RUN mix assets.deploy

# Copy runtime config (doesn't require recompile)
COPY config/runtime.exs config/

# Create release
COPY rel rel
RUN mix release

# ==============================================================================
# RUNTIME STAGE
# ==============================================================================
FROM ${RUNNER_IMAGE} AS final

# Install runtime dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libstdc++6 \
    openssl \
    libncurses5 \
    locales \
    ca-certificates \
    # For DNS resolution in Swarm
    dnsutils \
    # For health checks
    curl \
  && rm -rf /var/lib/apt/lists/*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Runtime environment
ENV MIX_ENV="prod"

# Copy release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/events ./

USER nobody

# Expose Phoenix port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Start the application
CMD ["/app/bin/server"]
