defmodule Events.CRUD.Operations.Raw do
  use Events.CRUD.Operation, type: :raw

  @impl true
  def validate_spec({type, content, params}) do
    cond do
      type not in [:sql, :fragment] ->
        {:error, "Raw type must be :sql or :fragment"}

      not is_binary(content) ->
        {:error, "Content must be a string"}

      not is_map(params) ->
        {:error, "Params must be a map"}

      true ->
        param_names = Events.CRUD.NamedPlaceholders.extract_param_names(content)
        Events.CRUD.NamedPlaceholders.validate_params(param_names, Map.keys(params))
    end
  end

  @impl true
  def execute(_query, {:sql, sql, params}) do
    # For raw SQL queries, return a special marker
    # The executor will handle this specially
    {:raw_sql_result, Events.CRUD.NamedPlaceholders.process(sql, params)}
  end

  @impl true
  def execute(query, {:fragment, _fragment, _params}) do
    # Simplified: just return the query unchanged for now
    # Real implementation would need safe fragment handling
    query
  end
end
