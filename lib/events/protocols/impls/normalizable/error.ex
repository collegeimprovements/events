defimpl Events.Protocols.Normalizable, for: Events.Types.Error do
  @moduledoc """
  Normalizable implementation for Events.Types.Error.

  An already-normalized error is passed through, optionally enriched with
  additional context from the options.
  """

  def normalize(%Events.Types.Error{} = error, opts) do
    error
    |> maybe_add_context(Keyword.get(opts, :context))
    |> maybe_add_step(Keyword.get(opts, :step))
  end

  defp maybe_add_context(error, nil), do: error

  defp maybe_add_context(%{context: existing} = error, new_context) when is_map(new_context) do
    %{error | context: Map.merge(existing || %{}, new_context)}
  end

  defp maybe_add_context(error, _), do: error

  defp maybe_add_step(error, nil), do: error
  defp maybe_add_step(%{step: nil} = error, step), do: %{error | step: step}
  defp maybe_add_step(error, _), do: error
end
