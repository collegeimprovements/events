defmodule Events.Services.S3.FileNameNormalizer do
  @moduledoc """
  Normalizes file names for S3 storage.

  Ensures file names are safe for S3 storage by:
  - Removing or replacing unsafe characters
  - Converting to lowercase
  - Replacing spaces with hyphens or underscores
  - Preserving file extensions
  - Adding timestamps or UUIDs for uniqueness
  - Limiting file name length

  ## Examples

      iex> normalize("My Document (2024).pdf")
      "my-document-2024.pdf"

      iex> normalize("user upload.jpg", prefix: "avatars")
      "avatars/user-upload.jpg"

      iex> normalize("file.txt", add_timestamp: true)
      "file-20240112-143022.txt"

      iex> normalize("file.txt", add_uuid: true)
      "file-a1b2c3d4-e5f6-7890-abcd-ef1234567890.txt"
  """

  @type normalize_opts :: [
          prefix: String.t(),
          add_timestamp: boolean(),
          add_uuid: boolean(),
          separator: String.t(),
          max_length: pos_integer(),
          preserve_case: boolean()
        ]

  @doc """
  Normalizes a file name for safe S3 storage.

  ## Options

  - `:prefix` - Add a prefix path (e.g., "uploads/2024")
  - `:add_timestamp` - Append timestamp before extension (default: false)
  - `:add_uuid` - Append UUID before extension (default: false)
  - `:separator` - Character to replace spaces (default: "-")
  - `:max_length` - Maximum file name length (default: 255)
  - `:preserve_case` - Keep original case (default: false)

  ## Examples

      iex> normalize("User's Photo (1).jpg")
      "users-photo-1.jpg"

      iex> normalize("document.pdf", prefix: "uploads/2024/01")
      "uploads/2024/01/document.pdf"

      iex> normalize("file.txt", add_timestamp: true, separator: "_")
      "file_20240112_143022.txt"
  """
  @spec normalize(String.t(), normalize_opts()) :: String.t()
  def normalize(filename, opts \\ []) do
    separator = Keyword.get(opts, :separator, "-")
    max_length = Keyword.get(opts, :max_length, 255)
    preserve_case = Keyword.get(opts, :preserve_case, false)
    prefix = Keyword.get(opts, :prefix)
    add_timestamp = Keyword.get(opts, :add_timestamp, false)
    add_uuid = Keyword.get(opts, :add_uuid, false)

    # Extract file name and extension
    {name, ext} = split_filename(filename, preserve_case)

    # Normalize the base name
    normalized_name =
      name
      |> remove_unsafe_characters()
      |> replace_spaces(separator)
      |> maybe_lowercase(preserve_case)
      |> trim_separators(separator)

    # Add timestamp or UUID if requested
    normalized_name =
      normalized_name
      |> maybe_add_timestamp(add_timestamp, separator)
      |> maybe_add_uuid(add_uuid, separator)

    # Reconstruct with extension
    full_name = build_filename(normalized_name, ext)

    # Truncate if needed
    full_name = truncate_filename(full_name, max_length)

    # Add prefix if provided
    maybe_add_prefix(full_name, prefix)
  end

  @doc """
  Generates a unique file name using UUID.

  ## Examples

      iex> unique_filename("photo.jpg")
      "a1b2c3d4-e5f6-7890-abcd-ef1234567890.jpg"

      iex> unique_filename("document.pdf", prefix: "uploads")
      "uploads/a1b2c3d4-e5f6-7890-abcd-ef1234567890.pdf"
  """
  @spec unique_filename(String.t(), normalize_opts()) :: String.t()
  def unique_filename(filename, opts \\ []) do
    {_name, ext} = split_filename(filename)
    uuid = generate_uuid()
    full_name = build_filename(uuid, ext)

    prefix = Keyword.get(opts, :prefix)
    maybe_add_prefix(full_name, prefix)
  end

  @doc """
  Generates a timestamped file name.

  ## Examples

      iex> timestamped_filename("photo.jpg")
      "photo-20240112-143022.jpg"

      iex> timestamped_filename("photo.jpg", prefix: "uploads/photos")
      "uploads/photos/photo-20240112-143022.jpg"
  """
  @spec timestamped_filename(String.t(), normalize_opts()) :: String.t()
  def timestamped_filename(filename, opts \\ []) do
    normalize(filename, Keyword.put(opts, :add_timestamp, true))
  end

  @doc """
  Sanitizes a file name by removing all unsafe characters.

  ## Examples

      iex> sanitize("user's file (copy).txt")
      "users-file-copy.txt"

      iex> sanitize("Fichier Français.pdf")
      "fichier-francais.pdf"
  """
  @spec sanitize(String.t()) :: String.t()
  def sanitize(filename) do
    normalize(filename)
  end

  ## Private Functions

  defp split_filename(filename, preserve_case \\ false) do
    case Path.extname(filename) do
      "" ->
        {filename, ""}

      ext ->
        ext = if preserve_case, do: ext, else: String.downcase(ext)
        {Path.rootname(filename), ext}
    end
  end

  defp remove_unsafe_characters(name) do
    # Remove or replace unsafe characters for S3
    # Keep: alphanumeric, hyphens, underscores, periods
    # Replace: everything else
    name
    |> String.replace(~r/[^\w\s\-_.]/u, "")
    |> String.replace(~r/[()[\]{}]/u, "")
  end

  defp replace_spaces(name, separator) do
    name
    |> String.replace(~r/\s+/, separator)
  end

  defp maybe_lowercase(name, true), do: name
  defp maybe_lowercase(name, false), do: String.downcase(name)

  defp trim_separators(name, separator) do
    name
    |> String.trim(separator)
    |> String.replace(~r/#{Regex.escape(separator)}+/, separator)
  end

  defp maybe_add_timestamp(name, false, _separator), do: name

  defp maybe_add_timestamp(name, true, separator) do
    timestamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%d#{separator}%H%M%S")

    "#{name}#{separator}#{timestamp}"
  end

  defp maybe_add_uuid(name, false, _separator), do: name

  defp maybe_add_uuid(name, true, separator) do
    uuid = generate_uuid()
    "#{name}#{separator}#{uuid}"
  end

  defp generate_uuid do
    # Generate a simple UUID v4
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp format_uuid(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>) do
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  defp build_filename(name, ""), do: name
  defp build_filename(name, ext), do: "#{name}#{ext}"

  defp truncate_filename(filename, max_length) when byte_size(filename) <= max_length do
    filename
  end

  defp truncate_filename(filename, max_length) do
    {name, ext} = split_filename(filename)
    ext_length = byte_size(ext)
    max_name_length = max_length - ext_length - 1

    if max_name_length > 0 do
      truncated_name = String.slice(name, 0, max_name_length)
      build_filename(truncated_name, ext)
    else
      # If even the extension is too long, just truncate everything
      String.slice(filename, 0, max_length)
    end
  end

  defp maybe_add_prefix(filename, nil), do: filename
  defp maybe_add_prefix(filename, ""), do: filename

  defp maybe_add_prefix(filename, prefix) do
    prefix = String.trim_trailing(prefix, "/")
    "#{prefix}/#{filename}"
  end
end
