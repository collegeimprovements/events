# Docker Swarm Deployment Guide

This guide covers deploying the Events application to a Docker Swarm cluster across 2 Linux servers.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Swarm Cluster                      │
├─────────────────────────────┬───────────────────────────────┤
│        Server 1 (Manager)   │        Server 2 (Worker)      │
│  ┌────────────────────────┐ │ ┌────────────────────────────┐│
│  │   events_app (replica) │◄─┼─►  events_app (replica)     ││
│  │   events@10.0.0.2      │ │ │   events@10.0.0.3          ││
│  └──────────┬─────────────┘ │ └──────────┬─────────────────┘│
│             │               │            │                   │
│  ┌──────────▼─────────────┐ │            │                   │
│  │   PostgreSQL           │◄─────────────┘                   │
│  │   (manager only)       │ │                                │
│  └────────────────────────┘ │                                │
│  ┌────────────────────────┐ │                                │
│  │   Redis                │◄─────────────────────────────────│
│  │   (manager only)       │ │                                │
│  └────────────────────────┘ │                                │
└─────────────────────────────┴───────────────────────────────┘
                    │
                    ▼
            Swarm Ingress (Port 4000)
                    │
                    ▼
            Load Balancer / Traefik
```

## Prerequisites

- 2 Linux servers with Docker installed
- Docker version 20.10+ (for Swarm mode)
- Servers can communicate on:
  - TCP 2377 (Swarm management)
  - TCP/UDP 7946 (Node communication)
  - UDP 4789 (Overlay network)
  - TCP 9100-9155 (Erlang distribution)

## Quick Start

### 1. Initialize Swarm on Server 1 (Manager)

```bash
# On Server 1
docker swarm init --advertise-addr <SERVER1_IP>

# Save the join token displayed
```

### 2. Join Server 2 as Worker

```bash
# On Server 2
docker swarm join --token <TOKEN> <SERVER1_IP>:2377
```

### 3. Create Secrets

```bash
# On Manager (Server 1)
# Generate secret key
mix phx.gen.secret | docker secret create events_secret_key_base -

# Database URL
echo "ecto://events:your_password@db:5432/events_prod" | docker secret create events_database_url -

# Database password
echo "your_password" | docker secret create events_db_password -

# Erlang cookie (must be same on all nodes)
echo "your_random_cookie_here" | docker secret create events_erlang_cookie -
```

### 4. Build and Push Image

```bash
# Build
docker build -t your-registry.com/events:latest .

# Push to registry accessible by both servers
docker push your-registry.com/events:latest
```

### 5. Deploy Stack

```bash
# On Manager
docker stack deploy -c docker-compose.yml events
```

## Clustering with DNS Cluster

The application uses `dns_cluster` to automatically discover and connect Erlang nodes.

### How It Works

1. Docker Swarm provides internal DNS at `tasks.<service_name>`
2. `DNS_CLUSTER_QUERY=tasks.events_app` is set in the compose file
3. When a node starts, it queries `tasks.events_app`
4. DNS returns IPs of all running replicas
5. Nodes connect via Erlang distribution

### Verify Clustering

```bash
# Check cluster status via health endpoint
curl http://<SERVER_IP>:4000/health/cluster

# Response:
{
  "status": "ok",
  "node": "events@10.0.0.2",
  "connected_nodes": ["events@10.0.0.3"],
  "connected_count": 1,
  "cluster_size": 2
}
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PHX_HOST` | Yes | - | Public hostname |
| `PHX_SERVER` | Yes | - | Must be "true" |
| `SECRET_KEY_BASE` | Yes | - | Phoenix secret key |
| `DATABASE_URL` | Yes | - | PostgreSQL connection URL |
| `REDIS_HOST` | No | localhost | Redis hostname |
| `REDIS_PORT` | No | 6379 | Redis port |
| `DNS_CLUSTER_QUERY` | No | - | DNS name for node discovery |
| `RELEASE_COOKIE` | No | - | Erlang cookie for clustering |

## Health Checks

| Endpoint | Purpose | Used By |
|----------|---------|---------|
| `GET /health` | Liveness check | Docker HEALTHCHECK |
| `GET /health/ready` | Readiness check | Load balancer |
| `GET /health/cluster` | Cluster status | Debugging |

## Scaling

```bash
# Scale to 3 replicas
docker service scale events_app=3

# View service status
docker service ps events_app
```

## Logs

```bash
# All app logs
docker service logs events_app -f

# Specific container
docker logs <container_id> -f
```

## Troubleshooting

### Nodes Not Clustering

1. Check DNS resolution:
   ```bash
   docker exec <container_id> nslookup tasks.events_app
   ```

2. Verify Erlang cookie is same on all nodes:
   ```bash
   docker exec <container_id> cat /run/secrets/events_erlang_cookie
   ```

3. Check network connectivity:
   ```bash
   docker exec <container_id> ping <other_node_ip>
   ```

4. Check Erlang distribution ports:
   ```bash
   docker exec <container_id> netstat -tlnp | grep 9100
   ```

### Database Connection Issues

```bash
# Check database is accessible
docker exec <container_id> pg_isready -h db -U events

# Check secret is mounted
docker exec <container_id> cat /run/secrets/events_database_url
```

### Redis Connection Issues

```bash
# Check Redis is accessible
docker exec <container_id> redis-cli -h redis ping
```

## Rolling Updates

```bash
# Update image
docker service update --image your-registry.com/events:v2 events_app

# The compose file configures:
# - parallelism: 1 (one container at a time)
# - delay: 30s (wait between updates)
# - order: start-first (start new before stopping old)
# - failure_action: rollback (auto-rollback on failure)
```

## Backup & Restore

### Database Backup

```bash
# Create backup
docker exec $(docker ps -q -f name=events_db) \
  pg_dump -U events events_prod > backup.sql

# Restore
docker exec -i $(docker ps -q -f name=events_db) \
  psql -U events events_prod < backup.sql
```

### Redis Backup

Redis is configured with `appendonly yes` for persistence.
Data is stored in the `redis_data` volume.

## Security Checklist

- [ ] Use Docker secrets for sensitive data (never env vars)
- [ ] Enable TLS for PostgreSQL (`DB_SSL=true`)
- [ ] Use private registry for images
- [ ] Restrict Swarm ports with firewall
- [ ] Use Traefik or nginx for TLS termination
- [ ] Set strong Erlang cookie
- [ ] Rotate secrets periodically
