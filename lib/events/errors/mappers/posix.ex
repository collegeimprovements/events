defmodule Events.Errors.Mappers.Posix do
  @moduledoc """
  Error mapper for POSIX (file system) errors.

  Handles normalization of errors from :file module and related operations.
  """

  alias Events.Errors.Error

  @doc """
  Normalizes a POSIX error code into an Error struct.

  ## Examples

      iex> Posix.normalize(:enoent)
      %Error{type: :not_found, code: :file_not_found}

      iex> Posix.normalize(:eacces)
      %Error{type: :forbidden, code: :access_denied}
  """
  @spec normalize(atom()) :: Error.t()
  def normalize(posix_code) when is_atom(posix_code) do
    {type, code, message} = map_posix_error(posix_code)

    Error.new(type, code,
      message: message,
      details: %{posix_code: posix_code},
      source: :file
    )
  end

  ## POSIX Error Mappings

  defp map_posix_error(:enoent),
    do: {:not_found, :file_not_found, "No such file or directory"}

  defp map_posix_error(:eacces),
    do: {:forbidden, :access_denied, "Permission denied"}

  defp map_posix_error(:eisdir),
    do: {:bad_request, :is_directory, "Is a directory"}

  defp map_posix_error(:enotdir),
    do: {:bad_request, :not_directory, "Not a directory"}

  defp map_posix_error(:eexist),
    do: {:conflict, :already_exists, "File already exists"}

  defp map_posix_error(:enospc),
    do: {:service_unavailable, :no_space, "No space left on device"}

  defp map_posix_error(:emfile),
    do: {:service_unavailable, :too_many_open_files, "Too many open files"}

  defp map_posix_error(:enfile),
    do: {:service_unavailable, :file_table_overflow, "File table overflow"}

  defp map_posix_error(:ebadf),
    do: {:bad_request, :bad_file_descriptor, "Bad file descriptor"}

  defp map_posix_error(:einval),
    do: {:bad_request, :invalid_argument, "Invalid argument"}

  defp map_posix_error(:epipe),
    do: {:network, :broken_pipe, "Broken pipe"}

  defp map_posix_error(:erofs),
    do: {:forbidden, :read_only_filesystem, "Read-only file system"}

  defp map_posix_error(:espipe),
    do: {:bad_request, :illegal_seek, "Illegal seek"}

  defp map_posix_error(:enametoolong),
    do: {:bad_request, :name_too_long, "File name too long"}

  defp map_posix_error(:enotempty),
    do: {:conflict, :directory_not_empty, "Directory not empty"}

  defp map_posix_error(:eloop),
    do: {:bad_request, :too_many_symlinks, "Too many levels of symbolic links"}

  defp map_posix_error(:exdev),
    do: {:bad_request, :cross_device_link, "Cross-device link"}

  defp map_posix_error(:etxtbsy),
    do: {:conflict, :text_file_busy, "Text file busy"}

  defp map_posix_error(:efbig),
    do: {:bad_request, :file_too_large, "File too large"}

  defp map_posix_error(:edquot),
    do: {:service_unavailable, :disk_quota_exceeded, "Disk quota exceeded"}

  defp map_posix_error(:estale),
    do: {:not_found, :stale_file_handle, "Stale file handle"}

  defp map_posix_error(code),
    do: {:external, :posix_error, "File system error: #{code}"}
end
