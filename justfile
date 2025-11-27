# Events Application Task Runner
# https://github.com/casey/just

# Docker image name
IMAGE_NAME := "events:latest"

# Default recipe to display help
default:
    @just --list

# ==============================================================================
# HELPERS
# ==============================================================================

# Check if mix is available, otherwise use Docker
[private]
_mix *ARGS:
    #!/usr/bin/env bash
    if command -v mix &> /dev/null; then
        mix {{ARGS}}
    else
        docker run --rm -i \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            {{IMAGE_NAME}} \
            mix {{ARGS}}
    fi

# Run elixir command (locally or in Docker)
[private]
_elixir *ARGS:
    #!/usr/bin/env bash
    if command -v elixir &> /dev/null; then
        elixir {{ARGS}}
    else
        docker run --rm -i \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            {{IMAGE_NAME}} \
            elixir {{ARGS}}
    fi

# Run iex command (locally or in Docker)
[private]
_iex *ARGS:
    #!/usr/bin/env bash
    if command -v iex &> /dev/null; then
        iex {{ARGS}}
    else
        docker run --rm -it \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            -p 4000:4000 \
            {{IMAGE_NAME}} \
            iex {{ARGS}}
    fi

# ==============================================================================
# DEVELOPMENT
# ==============================================================================

# Start the Phoenix server
server:
    @just _iex -S mix phx.server

# Start the Phoenix server with specific port
serve PORT="4000":
    #!/usr/bin/env bash
    if command -v iex &> /dev/null; then
        PORT={{PORT}} iex -S mix phx.server
    else
        docker run --rm -it \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            -p {{PORT}}:{{PORT}} \
            -e PORT={{PORT}} \
            {{IMAGE_NAME}} \
            iex -S mix phx.server
    fi

# Install dependencies
deps:
    @just _mix deps.get
    cd assets && npm install

# Run database migrations
migrate:
    @just _mix ecto.migrate

# Rollback database migration
rollback STEPS="1":
    @just _mix ecto.rollback --step {{STEPS}}

# Reset database (drop, create, migrate, seed)
reset:
    @just _mix ecto.reset

# ==============================================================================
# TESTING
# ==============================================================================

# Run all tests
test:
    @just _mix test

# Run tests with coverage
test-coverage:
    @just _mix test --cover

# Run tests and watch for changes
test-watch:
    @just _mix test.watch

# ==============================================================================
# CODE QUALITY
# ==============================================================================

# Format code
format:
    @just _mix format

# Check code formatting
format-check:
    @just _mix format --check-formatted

# Run static analysis with Credo
lint:
    @just _mix credo --strict

# Run Dialyzer for type checking
dialyzer:
    @just _mix dialyzer

# ==============================================================================
# SYSTEM HEALTH
# ==============================================================================

# Display comprehensive system health status
health:
    @just _mix run -e "Events.SystemHealth.display()"

# Check system health via HTTP endpoint (requires server running)
health-http PORT="4000":
    @curl -s http://localhost:{{PORT}}/health | jq '.' || echo "Error: Server not running or jq not installed"

# Check system health via HTTP (plain text, no jq required)
health-check PORT="4000":
    @curl -s http://localhost:{{PORT}}/health

# Monitor system health continuously (every 5 seconds)
health-watch INTERVAL="5":
    #!/usr/bin/env bash
    if command -v mix &> /dev/null; then
        watch -n {{INTERVAL}} 'mix run -e "Events.SystemHealth.display()"'
    else
        watch -n {{INTERVAL}} 'just _mix run -e "Events.SystemHealth.display()"'
    fi

# Quick health check - show only service status
health-quick:
    @just _mix run -e 'Events.SystemHealth.Services.check_all() |> Enum.each(fn s -> IO.puts("#{s.name}: #{s.status}") end)'

# Check S3/MinIO connectivity using curl and awscli
health-s3:
    #!/usr/bin/env bash
    set -euo pipefail
    ENDPOINT="${AWS_ENDPOINT_URL_S3:-http://localhost:9000}"
    BUCKET="${S3_BUCKET:-events}"
    echo "Testing S3 connectivity..."
    echo "Endpoint: $ENDPOINT"
    echo "Bucket: $BUCKET"
    echo ""

    # Check if server is online (MinIO health endpoint)
    if curl -sf "$ENDPOINT/minio/health/live" > /dev/null 2>&1; then
        echo "✓ S3 Server: ONLINE"
    else
        echo "⚠ MinIO health endpoint not available (might not be MinIO)"
    fi

    # Check bucket access using Elixir (most reliable)
    echo ""
    echo "Checking bucket access..."
    if command -v mix &> /dev/null; then
        mix run -e "
        bucket = System.get_env(\"S3_BUCKET\") || raise \"S3_BUCKET not set\"
        config = Events.Services.S3.Config.from_env()
        uri = \"s3://#{bucket}/\"
        case Events.Services.S3.list(uri, config, limit: 1) do
          {:ok, _} -> IO.puts(\"✓ Bucket '#{bucket}': ACCESSIBLE\")
          {:error, {:s3_error, status, _}} -> IO.puts(\"✗ Bucket access failed: HTTP #{status}\"); System.halt(1)
          {:error, reason} -> IO.puts(\"✗ Bucket access failed: #{inspect(reason)}\"); System.halt(1)
        end
        " 2>&1 | grep -E "✓|✗"
    else
        docker run --rm -i \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            {{IMAGE_NAME}} \
            mix run -e "
            bucket = System.get_env(\"S3_BUCKET\") || raise \"S3_BUCKET not set\"
            config = Events.Services.S3.Config.from_env()
            uri = \"s3://#{bucket}/\"
            case Events.Services.S3.list(uri, config, limit: 1) do
              {:ok, _} -> IO.puts(\"✓ Bucket '#{bucket}': ACCESSIBLE\")
              {:error, {:s3_error, status, _}} -> IO.puts(\"✗ Bucket access failed: HTTP #{status}\"); System.halt(1)
              {:error, reason} -> IO.puts(\"✗ Bucket access failed: #{inspect(reason)}\"); System.halt(1)
            end
            " 2>&1 | grep -E "✓|✗"
    fi

    if [ $? -eq 0 ]; then
        echo ""
        echo "S3 health check: PASSED"
    else
        echo ""
        echo "S3 health check: FAILED"
        exit 1
    fi

# Check S3 bucket with pure curl (using AWS CLI for signing)
health-s3-curl:
    #!/usr/bin/env bash
    set -euo pipefail
    ENDPOINT="${AWS_ENDPOINT_URL_S3:-http://localhost:9000}"
    BUCKET="${S3_BUCKET:-events}"
    REGION="${AWS_REGION:-us-east-1}"

    echo "Testing S3 with curl..."
    echo "Endpoint: $ENDPOINT"
    echo "Bucket: $BUCKET"
    echo ""

    # Test MinIO/S3 server health
    if curl -sf "$ENDPOINT/minio/health/live" > /dev/null 2>&1; then
        echo "✓ MinIO Server: ONLINE"
    else
        # Try generic S3 endpoint
        if curl -sf -I -X HEAD "$ENDPOINT" > /dev/null 2>&1; then
            echo "✓ S3 Endpoint: REACHABLE"
        else
            echo "✗ S3 Endpoint: NOT REACHABLE"
            exit 1
        fi
    fi

    # Use AWS CLI to sign request (most reliable way)
    if command -v aws &> /dev/null; then
        echo ""
        echo "Testing bucket with AWS CLI..."
        if aws s3 ls "s3://$BUCKET" --endpoint-url "$ENDPOINT" --region "$REGION" > /dev/null 2>&1; then
            echo "✓ Bucket '$BUCKET': ACCESSIBLE (via aws cli)"
        else
            echo "✗ Bucket '$BUCKET': NOT ACCESSIBLE"
            exit 1
        fi
    else
        echo "⚠ AWS CLI not installed - skipping signed request test"
        echo "  Install with: brew install awscli"
    fi

    echo ""
    echo "S3 curl health check: PASSED"

# List S3 buckets using AWS CLI
health-s3-buckets:
    #!/usr/bin/env bash
    set -euo pipefail
    ENDPOINT="${AWS_ENDPOINT_URL_S3:-http://localhost:9000}"
    REGION="${AWS_REGION:-us-east-1}"

    if ! command -v aws &> /dev/null; then
        echo "Error: AWS CLI not installed"
        echo "Install with: brew install awscli"
        exit 1
    fi

    echo "Listing S3 buckets at $ENDPOINT..."
    echo ""
    aws s3 ls --endpoint-url "$ENDPOINT" --region "$REGION"

# ==============================================================================
# DOCKER
# ==============================================================================

# Build Docker image
docker-build:
    docker build -t events:latest .

# Run Docker container
docker-run PORT="4000":
    docker run -p {{PORT}}:4000 --env-file .env events:latest

# ==============================================================================
# PRODUCTION
# ==============================================================================

# Build production release
release:
    #!/usr/bin/env bash
    if command -v mix &> /dev/null; then
        MIX_ENV=prod mix release
    else
        docker run --rm -i \
            --env-file .env \
            -v $(pwd):/app \
            -w /app \
            -e MIX_ENV=prod \
            {{IMAGE_NAME}} \
            mix release
    fi

# Deploy production assets
assets-deploy:
    @just _mix assets.deploy

# ==============================================================================
# DATABASE
# ==============================================================================

# Create database
db-create:
    @just _mix ecto.create

# Drop database
db-drop:
    @just _mix ecto.drop

# Generate a new migration
db-gen-migration NAME:
    @just _mix ecto.gen.migration {{NAME}}

# Check database connection
db-check:
    @just _mix run -e "case Events.Repo.query(\"SELECT 1\") do; {:ok, _} -> IO.puts(\"✓ Database connected\"); {:error, e} -> IO.puts(\"✗ Database error: #{inspect(e)}\"); end"

# ==============================================================================
# UTILITIES
# ==============================================================================

# Open IEx console
console:
    @just _iex -S mix

# Clean build artifacts
clean:
    @just _mix clean
    rm -rf _build deps

# Show project information
info:
    #!/usr/bin/env bash
    echo "Project: Events"
    if command -v elixir &> /dev/null; then
        echo "Elixir: $(elixir --version | grep Elixir)"
        echo "Erlang: $(elixir --version | grep Erlang)"
        echo "Mix env: ${MIX_ENV:-dev}"
    else
        echo "Elixir: (running via Docker)"
        echo "Mix env: ${MIX_ENV:-dev}"
        docker run --rm {{IMAGE_NAME}} elixir --version
    fi

# Generate Phoenix secret
gen-secret:
    @just _mix phx.gen.secret
