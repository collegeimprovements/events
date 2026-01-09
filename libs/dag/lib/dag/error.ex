defmodule Dag.Error do
  @moduledoc """
  Structured error types for DAG operations.

  All errors implement the `Exception` behaviour and can be raised or
  returned as `{:error, %Dag.Error.SomeError{}}`.

  ## Error Types

  - `Dag.Error.CycleDetected` - Graph contains a cycle
  - `Dag.Error.NoPath` - No path exists between nodes
  - `Dag.Error.NodeNotFound` - Node does not exist
  - `Dag.Error.EdgeNotFound` - Edge does not exist
  - `Dag.Error.InvalidDefinition` - Invalid DAG definition
  - `Dag.Error.ValidationFailed` - General validation failure

  ## Examples

      case Dag.topological_sort(dag) do
        {:ok, sorted} -> sorted
        {:error, %Dag.Error.CycleDetected{path: path}} ->
          Logger.error("Cycle detected: \#{inspect(path)}")
      end

      # Or raise
      case Dag.shortest_path(dag, :a, :z) do
        {:ok, path} -> path
        {:error, error} -> raise error
      end
  """

  defmodule CycleDetected do
    @moduledoc """
    Raised when a cycle is detected in the DAG.

    ## Fields

    - `:path` - The cycle path as a list of node IDs (e.g., `[:a, :b, :c, :a]`)
    - `:message` - Human-readable error message
    """
    defexception [:path, :message]

    @type t :: %__MODULE__{
            path: [Dag.node_id()],
            message: String.t()
          }

    @impl true
    def exception(opts) do
      path = Keyword.get(opts, :path, [])

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Cycle detected in DAG: #{format_path(path)}"
        end)

      %__MODULE__{path: path, message: message}
    end

    defp format_path([]), do: "(empty)"
    defp format_path(path), do: Enum.join(path, " -> ")
  end

  defmodule NoPath do
    @moduledoc """
    Raised when no path exists between two nodes.

    ## Fields

    - `:from` - Source node ID
    - `:to` - Target node ID
    - `:message` - Human-readable error message
    """
    defexception [:from, :to, :message]

    @type t :: %__MODULE__{
            from: Dag.node_id(),
            to: Dag.node_id(),
            message: String.t()
          }

    @impl true
    def exception(opts) do
      from = Keyword.fetch!(opts, :from)
      to = Keyword.fetch!(opts, :to)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "No path exists from #{inspect(from)} to #{inspect(to)}"
        end)

      %__MODULE__{from: from, to: to, message: message}
    end
  end

  defmodule NodeNotFound do
    @moduledoc """
    Raised when a node does not exist in the DAG.

    ## Fields

    - `:node` - The missing node ID
    - `:message` - Human-readable error message
    """
    defexception [:node, :message]

    @type t :: %__MODULE__{
            node: Dag.node_id(),
            message: String.t()
          }

    @impl true
    def exception(opts) do
      node = Keyword.fetch!(opts, :node)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Node #{inspect(node)} not found in DAG"
        end)

      %__MODULE__{node: node, message: message}
    end
  end

  defmodule EdgeNotFound do
    @moduledoc """
    Raised when an edge does not exist in the DAG.

    ## Fields

    - `:from` - Source node ID
    - `:to` - Target node ID
    - `:message` - Human-readable error message
    """
    defexception [:from, :to, :message]

    @type t :: %__MODULE__{
            from: Dag.node_id(),
            to: Dag.node_id(),
            message: String.t()
          }

    @impl true
    def exception(opts) do
      from = Keyword.fetch!(opts, :from)
      to = Keyword.fetch!(opts, :to)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Edge from #{inspect(from)} to #{inspect(to)} not found"
        end)

      %__MODULE__{from: from, to: to, message: message}
    end
  end

  defmodule InvalidDefinition do
    @moduledoc """
    Raised when a DAG definition is invalid.

    ## Fields

    - `:reason` - The specific reason for invalidity
    - `:details` - Additional details (optional)
    - `:message` - Human-readable error message
    """
    defexception [:reason, :details, :message]

    @type t :: %__MODULE__{
            reason: atom(),
            details: term(),
            message: String.t()
          }

    @impl true
    def exception(opts) do
      reason = Keyword.fetch!(opts, :reason)
      details = Keyword.get(opts, :details)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          build_invalid_definition_message(reason, details)
        end)

      %__MODULE__{reason: reason, details: details, message: message}
    end

    defp build_invalid_definition_message(reason, nil), do: "Invalid DAG definition: #{reason}"

    defp build_invalid_definition_message(reason, details) do
      "Invalid DAG definition: #{reason} - #{inspect(details)}"
    end
  end

  defmodule MissingNodes do
    @moduledoc """
    Raised when edges reference nodes that don't exist.

    ## Fields

    - `:nodes` - List of missing node IDs
    - `:message` - Human-readable error message
    """
    defexception [:nodes, :message]

    @type t :: %__MODULE__{
            nodes: [Dag.node_id()],
            message: String.t()
          }

    @impl true
    def exception(opts) do
      nodes = Keyword.fetch!(opts, :nodes)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Edges reference missing nodes: #{inspect(nodes)}"
        end)

      %__MODULE__{nodes: nodes, message: message}
    end
  end

  defmodule DeserializationFailed do
    @moduledoc """
    Raised when DAG deserialization fails.

    ## Fields

    - `:reason` - The underlying error reason
    - `:message` - Human-readable error message
    """
    defexception [:reason, :message]

    @type t :: %__MODULE__{
            reason: term(),
            message: String.t()
          }

    @impl true
    def exception(opts) do
      reason = Keyword.fetch!(opts, :reason)

      message =
        Keyword.get_lazy(opts, :message, fn ->
          "Failed to deserialize DAG: #{inspect(reason)}"
        end)

      %__MODULE__{reason: reason, message: message}
    end
  end

  # ============================================
  # Helper Functions
  # ============================================

  @doc """
  Converts a legacy error tuple to a structured error.

  ## Examples

      Dag.Error.from_tuple({:error, :cycle_detected})
      #=> %Dag.Error.CycleDetected{path: []}

      Dag.Error.from_tuple({:error, {:cycle_detected, [:a, :b, :a]}})
      #=> %Dag.Error.CycleDetected{path: [:a, :b, :a]}
  """
  @spec from_tuple({:error, term()}) :: Exception.t()
  def from_tuple({:error, :cycle_detected}) do
    CycleDetected.exception(path: [])
  end

  def from_tuple({:error, {:cycle_detected, path}}) do
    CycleDetected.exception(path: path)
  end

  def from_tuple({:error, :no_path}) do
    NoPath.exception(from: nil, to: nil)
  end

  def from_tuple({:error, :not_found}) do
    NodeNotFound.exception(node: nil)
  end

  def from_tuple({:error, {:missing_nodes, nodes}}) do
    MissingNodes.exception(nodes: nodes)
  end

  def from_tuple({:error, {:deserialization_failed, reason}}) do
    DeserializationFailed.exception(reason: reason)
  end

  def from_tuple({:error, reason}) do
    InvalidDefinition.exception(reason: reason)
  end

  @doc """
  Converts a structured error back to a legacy tuple.

  ## Examples

      Dag.Error.to_tuple(%Dag.Error.CycleDetected{path: [:a, :b, :a]})
      #=> {:error, {:cycle_detected, [:a, :b, :a]}}
  """
  @spec to_tuple(Exception.t()) :: {:error, term()}
  def to_tuple(%CycleDetected{path: path}), do: {:error, {:cycle_detected, path}}
  def to_tuple(%NoPath{from: from, to: to}), do: {:error, {:no_path, {from, to}}}
  def to_tuple(%NodeNotFound{node: node}), do: {:error, {:node_not_found, node}}
  def to_tuple(%EdgeNotFound{from: from, to: to}), do: {:error, {:edge_not_found, {from, to}}}
  def to_tuple(%MissingNodes{nodes: nodes}), do: {:error, {:missing_nodes, nodes}}
  def to_tuple(%DeserializationFailed{reason: reason}), do: {:error, {:deserialization_failed, reason}}
  def to_tuple(%InvalidDefinition{reason: reason}), do: {:error, reason}
end
