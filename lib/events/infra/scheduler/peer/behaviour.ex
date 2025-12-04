defmodule Events.Infra.Scheduler.Peer.Behaviour do
  @moduledoc """
  Behaviour for peer election in clustered scheduler deployments.

  Only the leader node should run scheduled jobs to prevent duplicate execution.

  ## Implementations

  - `Events.Infra.Scheduler.Peer.Postgres` - PostgreSQL advisory lock
  - `Events.Infra.Scheduler.Peer.Global` - Erlang :global (single node/dev)

  ## Usage

  Configure in your scheduler config:

      config :events, Events.Infra.Scheduler,
        peer: Events.Infra.Scheduler.Peer.Postgres
  """

  @doc """
  Starts the peer election process.

  ## Options

  - `:name` - Name for the GenServer
  - `:conf` - Scheduler configuration
  """
  @callback start_link(keyword()) :: GenServer.on_start()

  @doc """
  Returns true if this node is the current leader.
  """
  @callback leader?(name :: atom()) :: boolean()

  @doc """
  Returns the current leader node, or nil if none.
  """
  @callback get_leader(name :: atom()) :: node() | nil

  @doc """
  Returns all known peer nodes.
  """
  @callback peers(name :: atom()) :: [%{node: node(), leader: boolean(), started_at: DateTime.t()}]

  @doc """
  Child spec for supervision.
  """
  @callback child_spec(keyword()) :: Supervisor.child_spec()
end
