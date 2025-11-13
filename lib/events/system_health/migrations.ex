defmodule Events.SystemHealth.Migrations do
  @moduledoc """
  Database migration status checks.

  Production-safe: handles missing migration files and database errors gracefully.
  """

  @doc """
  Checks migration status.
  """
  @spec check_status() :: map()
  def check_status do
    try do
      all_migrations = get_all_migrations()
      applied_migrations = get_applied_migrations()

      # Use the count of applied migrations as the total if it's higher
      # (handles cases where migration files might be missing)
      total = max(length(all_migrations), length(applied_migrations))
      pending = max(0, length(all_migrations) - length(applied_migrations))

      %{
        total: length(all_migrations),
        applied: length(applied_migrations),
        pending: pending,
        last_migration: List.last(applied_migrations),
        status: if(pending == 0, do: :up_to_date, else: :pending)
      }
    rescue
      _ ->
        %{
          total: 0,
          applied: 0,
          pending: 0,
          last_migration: nil,
          status: :error,
          error: "Unable to check migration status"
        }
    end
  end

  defp get_all_migrations do
    try do
      migrations_path = Application.app_dir(:events, "priv/repo/migrations")

      case File.ls(migrations_path) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".exs"))
          |> Enum.map(fn file ->
            case String.split(file, "_", parts: 2) do
              [version | _] ->
                case Integer.parse(version) do
                  {int_version, ""} -> int_version
                  _ -> nil
                end

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        {:error, _} ->
          []
      end
    rescue
      _ -> []
    end
  end

  defp get_applied_migrations do
    try do
      case Events.Repo.query(
             "SELECT version FROM schema_migrations ORDER BY version",
             [],
             timeout: 5_000
           ) do
        {:ok, result} ->
          Enum.map(result.rows, fn
            [version] when is_binary(version) ->
              case Integer.parse(version) do
                {int_version, ""} -> int_version
                _ -> nil
              end

            [version] when is_integer(version) ->
              version

            _ ->
              nil
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    rescue
      _ -> []
    end
  end
end
