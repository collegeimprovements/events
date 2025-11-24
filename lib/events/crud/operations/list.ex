defmodule Events.CRUD.Operations.List do
  use Events.CRUD.Operation, type: :list

  @impl true
  def validate_spec({schema, opts}) do
    cond do
      not is_atom(schema) -> {:error, "Schema must be an atom"}
      not is_list(opts) -> {:error, "Options must be a keyword list"}
      true -> :ok
    end
  end

  @impl true
  def execute(query, {_schema, opts}) do
    records = Events.Repo.all(query)
    pagination_meta = build_pagination_metadata(query, records, opts)
    Events.CRUD.Result.list(records, pagination_meta)
  end

  # Build pagination metadata
  defp build_pagination_metadata(_query, records, opts) do
    limit = opts[:limit]
    has_more = limit && length(records) == limit

    %{
      type: (opts[:cursor] && :cursor) || (opts[:limit] && :offset) || nil,
      limit: limit,
      offset: opts[:offset] || 0,
      cursor: opts[:cursor],
      has_more: has_more,
      # Would need separate count query
      total_count: nil
    }
  end
end
