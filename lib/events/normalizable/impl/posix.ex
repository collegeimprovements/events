defmodule Events.PosixError do
  @moduledoc """
  Wrapper struct for POSIX file system errors.

  Since POSIX error codes are atoms and cannot have protocol implementations
  (protocols for atoms would apply to ALL atoms), this struct wraps POSIX
  error information for normalization.

  ## Usage

      # Wrap a POSIX error
      error = Events.PosixError.new(:enoent, path: "/path/to/file")
      error = Events.PosixError.new(:eacces, path: "/etc/passwd", operation: :write)

      # Normalize it
      Events.Normalizable.normalize(error)

  ## Common POSIX Codes

  - `:enoent` - No such file or directory
  - `:eacces` - Permission denied
  - `:eexist` - File exists
  - `:eisdir` - Is a directory
  - `:enotdir` - Not a directory
  - `:enospc` - No space left on device
  - `:emfile` - Too many open files
  - `:erofs` - Read-only file system
  - `:ebusy` - Resource busy
  """

  @type posix_code ::
          :enoent
          | :eacces
          | :eexist
          | :eisdir
          | :enotdir
          | :enospc
          | :emfile
          | :enfile
          | :enomem
          | :erofs
          | :ebusy
          | :eloop
          | :enametoolong
          | :enotempty
          | :eperm
          | :einval
          | :eio
          | :exdev
          | atom()

  @type t :: %__MODULE__{
          code: posix_code(),
          path: String.t() | nil,
          operation: atom() | nil
        }

  defstruct [:code, :path, :operation]

  @doc """
  Creates a new POSIX error wrapper.

  ## Options

  - `:path` - File/directory path involved in the error
  - `:operation` - Operation that failed (:read, :write, :delete, etc.)

  ## Examples

      PosixError.new(:enoent)
      PosixError.new(:eacces, path: "/etc/passwd", operation: :read)
  """
  @spec new(posix_code(), keyword()) :: t()
  def new(code, opts \\ []) when is_atom(code) do
    %__MODULE__{
      code: code,
      path: Keyword.get(opts, :path),
      operation: Keyword.get(opts, :operation)
    }
  end

  @doc """
  Creates a POSIX error from a File operation result.

  ## Examples

      case File.read("/path/to/file") do
        {:ok, content} -> {:ok, content}
        {:error, posix} -> {:error, PosixError.from_file_error(posix, "/path/to/file", :read)}
      end
  """
  @spec from_file_error(posix_code(), String.t() | nil, atom() | nil) :: t()
  def from_file_error(code, path \\ nil, operation \\ nil) do
    %__MODULE__{
      code: code,
      path: path,
      operation: operation
    }
  end
end

defimpl Events.Normalizable, for: Events.PosixError do
  @moduledoc """
  Normalizable implementation for POSIX file system errors.

  Maps POSIX error codes to appropriate error types with meaningful messages.
  """

  alias Events.Error

  def normalize(%Events.PosixError{code: code, path: path, operation: operation}, opts) do
    {type, error_code, base_message, recoverable} = map_posix(code)
    message = build_message(base_message, path, operation)

    Error.new(type, error_code,
      message: Keyword.get(opts, :message, message),
      source: :posix,
      recoverable: recoverable,
      details: %{
        posix_code: code,
        path: path,
        operation: operation
      },
      context: Keyword.get(opts, :context, %{}),
      step: Keyword.get(opts, :step)
    )
  end

  defp build_message(base_message, nil, nil), do: base_message
  defp build_message(base_message, path, nil), do: "#{base_message}: #{path}"
  defp build_message(base_message, nil, op), do: "#{base_message} (#{op})"
  defp build_message(base_message, path, op), do: "#{base_message}: #{path} (#{op})"

  # File/directory not found
  defp map_posix(:enoent),
    do: {:not_found, :file_not_found, "No such file or directory", false}

  # Permission errors
  defp map_posix(:eacces),
    do: {:forbidden, :permission_denied, "Permission denied", false}

  defp map_posix(:eperm),
    do: {:forbidden, :operation_not_permitted, "Operation not permitted", false}

  # File exists errors
  defp map_posix(:eexist),
    do: {:conflict, :file_exists, "File already exists", false}

  # Directory errors
  defp map_posix(:eisdir),
    do: {:validation, :is_directory, "Is a directory", false}

  defp map_posix(:enotdir),
    do: {:validation, :not_directory, "Not a directory", false}

  defp map_posix(:enotempty),
    do: {:conflict, :directory_not_empty, "Directory not empty", false}

  # Resource errors
  defp map_posix(:enospc),
    do: {:external, :disk_full, "No space left on device", true}

  defp map_posix(:emfile),
    do: {:external, :too_many_open_files, "Too many open files", true}

  defp map_posix(:enfile),
    do: {:external, :file_table_overflow, "File table overflow", true}

  defp map_posix(:enomem),
    do: {:external, :out_of_memory, "Out of memory", true}

  # Read-only file system
  defp map_posix(:erofs),
    do: {:forbidden, :read_only_filesystem, "Read-only file system", false}

  # Resource busy
  defp map_posix(:ebusy),
    do: {:conflict, :resource_busy, "Resource busy", true}

  # Symbolic link errors
  defp map_posix(:eloop),
    do: {:validation, :symlink_loop, "Too many levels of symbolic links", false}

  # Name errors
  defp map_posix(:enametoolong),
    do: {:validation, :name_too_long, "File name too long", false}

  # Cross-device link
  defp map_posix(:exdev),
    do: {:validation, :cross_device_link, "Cross-device link not permitted", false}

  # Invalid argument
  defp map_posix(:einval),
    do: {:validation, :invalid_argument, "Invalid argument", false}

  # I/O error
  defp map_posix(:eio),
    do: {:external, :io_error, "I/O error", true}

  # Network file system errors
  defp map_posix(:estale),
    do: {:external, :stale_file_handle, "Stale file handle", true}

  defp map_posix(:etimedout),
    do: {:timeout, :file_timeout, "File operation timed out", true}

  # Quota exceeded
  defp map_posix(:edquot),
    do: {:forbidden, :quota_exceeded, "Disk quota exceeded", false}

  # Generic fallback
  defp map_posix(code),
    do: {:internal, code, "File system error: #{code}", false}
end
