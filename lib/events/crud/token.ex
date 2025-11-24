defmodule Events.CRUD.Token do
  @moduledoc """
  Core token for composable database operations.
  All operations follow consistent {operation_type, spec} pattern.
  """

  @type operation :: {operation_type, spec}
  @type operation_type ::
          :schema
          | :where
          | :join
          | :order
          | :preload
          | :paginate
          | :select
          | :group
          | :having
          | :window
          | :raw
          | :create
          | :update
          | :delete
          | :get
          | :list
  @type spec :: term()

  @type t :: %__MODULE__{
          operations: [operation()],
          metadata: map(),
          validated: boolean(),
          optimized: boolean(),
          build_only: boolean()
        }

  defstruct operations: [], metadata: %{}, validated: false, optimized: false, build_only: false

  # Constructors
  @spec new() :: t()
  def new(), do: %__MODULE__{}

  @spec new(module()) :: t()
  def new(schema) when is_atom(schema), do: add(%__MODULE__{}, {:schema, schema})

  @spec new(module(), keyword()) :: t()
  def new(schema, opts) when is_atom(schema) do
    token = new(schema)
    build_only = Keyword.get(opts, :build_only, false)
    %{token | build_only: build_only}
  end

  @spec build_only(t()) :: t()
  def build_only(%__MODULE__{} = token), do: %{token | build_only: true}

  # Core composition operators
  @spec add(t(), operation()) :: t()
  def add(%__MODULE__{} = token, operation),
    do: %{token | operations: token.operations ++ [operation]}

  @spec remove(t(), operation_type()) :: t()
  def remove(%__MODULE__{} = token, op_type) do
    %{token | operations: Enum.reject(token.operations, &match?({^op_type, _}, &1))}
  end

  @spec replace(t(), operation_type(), operation()) :: t()
  def replace(%__MODULE__{} = token, op_type, new_operation) do
    operations =
      Enum.map(token.operations, fn
        {^op_type, _} -> new_operation
        op -> op
      end)

    %{token | operations: operations}
  end

  # Pipeline execution
  @spec execute(t()) :: Events.CRUD.Result.t() | Ecto.Query.t()
  def execute(%__MODULE__{} = token) do
    if token.build_only do
      # Return the built query without executing
      token
      |> validate()
      |> optimize()
      |> build_query()
    else
      Events.CRUD.Monitor.with_monitoring(
        fn ->
          token
          |> validate()
          |> optimize()
          |> build_query()
          |> run_query()
          |> format_result()
        end,
        operation: extract_operation_type(token),
        token: token
      )
    end
  end

  # Extract primary operation type for monitoring
  defp extract_operation_type(%__MODULE__{operations: operations}) do
    case operations do
      [] -> :unknown
      [{op_type, _} | _] -> op_type
    end
  end

  # Internal pipeline steps
  defp validate(token) do
    case Events.CRUD.Validation.validate(token) do
      {:ok, validated_token} -> validated_token
      {:error, error} -> raise "Validation error: #{inspect(error)}"
    end
  end

  defp optimize(token) do
    Events.CRUD.Optimization.optimize(token)
  end

  defp build_query(token) do
    Events.CRUD.Builder.build(token)
  end

  defp run_query(query) do
    case query do
      {:raw_sql_result, {sql, params}} ->
        # Execute raw SQL directly
        Events.Repo.query(sql, params)

      _query ->
        # Normal Ecto query
        Events.Repo.all(query)
    end
  end

  defp format_result(result) do
    case result do
      {:ok, records} when is_list(records) ->
        Events.CRUD.Result.success(records, %{})

      {:ok, %Postgrex.Result{rows: rows}} ->
        # Raw SQL result
        Events.CRUD.Result.success(rows, %{})

      {:error, error} ->
        Events.CRUD.Result.error(error, %{})
    end
  end
end
