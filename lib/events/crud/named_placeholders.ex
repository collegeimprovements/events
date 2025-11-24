defmodule Events.CRUD.NamedPlaceholders do
  @moduledoc """
  Processes named placeholders in raw SQL queries.
  Converts {:field, value} style params to positional parameters.
  """

  @placeholder_regex ~r/:([a-zA-Z_][a-zA-Z0-9_]*)/

  @spec process(String.t(), map()) :: {String.t(), [term()]}
  def process(sql, params) when is_binary(sql) and is_map(params) do
    param_names = extract_param_names(sql)

    case validate_params(param_names, Map.keys(params)) do
      :ok ->
        {processed_sql, positional_params} = replace_placeholders(sql, param_names, params)
        {processed_sql, positional_params}

      {:error, reason} ->
        raise ArgumentError, reason
    end
  end

  @spec extract_param_names(String.t()) :: [String.t()]
  def extract_param_names(sql) do
    Regex.scan(@placeholder_regex, sql)
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end

  @spec validate_params([String.t()], [term()]) :: :ok | {:error, String.t()}
  def validate_params(required, provided) do
    provided_strings = Enum.map(provided, &to_string/1)
    missing = required -- provided_strings

    if missing != [] do
      {:error, "Missing required parameters: #{Enum.join(missing, ", ")}"}
    else
      :ok
    end
  end

  @spec replace_placeholders(String.t(), [String.t()], map()) :: {String.t(), [term()]}
  def replace_placeholders(sql, param_names, params) do
    Enum.reduce(param_names, {sql, []}, fn param_name, {sql_acc, params_acc} ->
      # Try both string and atom keys
      value = Map.get(params, param_name) || Map.get(params, String.to_atom(param_name))
      new_sql = String.replace(sql_acc, ":#{param_name}", "?")
      {new_sql, params_acc ++ [value]}
    end)
  end
end
