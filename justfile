# Events Application Task Runner
# https://github.com/casey/just

# Default recipe to display help
default:
    @just --list

# ==============================================================================
# DEVELOPMENT
# ==============================================================================

# Start the Phoenix server
server:
    iex -S mix phx.server

# Start the Phoenix server with specific port
serve PORT="4000":
    PORT={{PORT}} iex -S mix phx.server

# Install dependencies
deps:
    mix deps.get
    cd assets && npm install

# Run database migrations
migrate:
    mix ecto.migrate

# Rollback database migration
rollback STEPS="1":
    mix ecto.rollback --step {{STEPS}}

# Reset database (drop, create, migrate, seed)
reset:
    mix ecto.reset

# ==============================================================================
# TESTING
# ==============================================================================

# Run all tests
test:
    mix test

# Run tests with coverage
test-coverage:
    mix test --cover

# Run tests and watch for changes
test-watch:
    mix test.watch

# ==============================================================================
# CODE QUALITY
# ==============================================================================

# Format code
format:
    mix format

# Check code formatting
format-check:
    mix format --check-formatted

# Run static analysis with Credo
lint:
    mix credo --strict

# Run Dialyzer for type checking
dialyzer:
    mix dialyzer

# ==============================================================================
# SYSTEM HEALTH
# ==============================================================================

# Display comprehensive system health status
health:
    @mix run -e "Events.SystemHealth.display()"

# Check system health via HTTP endpoint (requires server running)
health-http PORT="4000":
    @curl -s http://localhost:{{PORT}}/health | jq '.' || echo "Error: Server not running or jq not installed"

# Check system health via HTTP (plain text, no jq required)
health-check PORT="4000":
    @curl -s http://localhost:{{PORT}}/health

# Monitor system health continuously (every 5 seconds)
health-watch INTERVAL="5":
    @watch -n {{INTERVAL}} 'mix run -e "Events.SystemHealth.display()"'

# Quick health check - show only service status
health-quick:
    @mix run -e 'Events.SystemHealth.Services.check_all() |> Enum.each(fn s -> IO.puts("#{s.name}: #{s.status}") end)'

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
    mix run -e "
    context = Events.Services.Aws.Context.from_env()
    case Events.Services.Aws.S3.list_objects(context, max_keys: 1) do
      {:ok, _} -> IO.puts(\"✓ Bucket '#{context.bucket}': ACCESSIBLE\")
      {:error, {:s3_error, status, _}} -> IO.puts(\"✗ Bucket access failed: HTTP #{status}\"); System.halt(1)
      {:error, reason} -> IO.puts(\"✗ Bucket access failed: #{inspect(reason)}\"); System.halt(1)
    end
    " 2>&1 | grep -E "✓|✗"

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
    MIX_ENV=prod mix release

# Deploy production assets
assets-deploy:
    mix assets.deploy

# ==============================================================================
# DATABASE
# ==============================================================================

# Create database
db-create:
    mix ecto.create

# Drop database
db-drop:
    mix ecto.drop

# Generate a new migration
db-gen-migration NAME:
    mix ecto.gen.migration {{NAME}}

# Check database connection
db-check:
    @mix run -e "case Events.Repo.query(\"SELECT 1\") do; {:ok, _} -> IO.puts(\"✓ Database connected\"); {:error, e} -> IO.puts(\"✗ Database error: #{inspect(e)}\"); end"

# ==============================================================================
# UTILITIES
# ==============================================================================

# Open IEx console
console:
    iex -S mix

# Clean build artifacts
clean:
    mix clean
    rm -rf _build deps

# Show project information
info:
    @echo "Project: Events"
    @echo "Elixir: $(elixir --version | grep Elixir)"
    @echo "Erlang: $(elixir --version | grep Erlang)"
    @echo "Mix env: $MIX_ENV"

# Generate Phoenix secret
gen-secret:
    @mix phx.gen.secret
