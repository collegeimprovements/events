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
    {get_all_migrations(), get_applied_migrations()}
    |> build_migration_status()
  rescue
    _ -> error_status()
  end

  defp build_migration_status({all_migrations, applied_migrations}) do
    available_count = length(all_migrations)
    applied_count = length(applied_migrations)
    total = max(available_count, applied_count)
    pending = max(0, available_count - applied_count)

    %{
      total: total,
      applied: applied_count,
      pending: pending,
      last_migration: List.last(applied_migrations),
      status: if(pending == 0, do: :up_to_date, else: :pending)
    }
  end

  defp error_status do
    %{
      total: 0,
      applied: 0,
      pending: 0,
      last_migration: nil,
      status: :error,
      error: "Unable to check migration status"
    }
  end

  defp get_all_migrations do
    Application.app_dir(:events, "priv/repo/migrations")
    |> File.ls()
    |> parse_migration_files()
  rescue
    _ -> []
  end

  defp parse_migration_files({:ok, files}) do
    files
    |> Enum.filter(&String.ends_with?(&1, ".exs"))
    |> Enum.map(&extract_migration_version/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp parse_migration_files({:error, _}), do: []

  defp extract_migration_version(file) do
    file
    |> String.split("_", parts: 2)
    |> parse_version_number()
  end

  defp parse_version_number([version | _]) do
    case Integer.parse(version) do
      {int_version, ""} -> int_version
      _ -> nil
    end
  end

  defp parse_version_number(_), do: nil

  defp get_applied_migrations do
    Events.Repo.query("SELECT version FROM schema_migrations ORDER BY version", [], timeout: 5_000)
    |> parse_applied_migrations()
  rescue
    _ -> []
  end

  defp parse_applied_migrations({:ok, result}) do
    result.rows
    |> Enum.map(&extract_version_from_row/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_applied_migrations(_), do: []

  defp extract_version_from_row([version]) when is_binary(version) do
    case Integer.parse(version) do
      {int_version, ""} -> int_version
      _ -> nil
    end
  end

  defp extract_version_from_row([version]) when is_integer(version), do: version
  defp extract_version_from_row(_), do: nil
end
