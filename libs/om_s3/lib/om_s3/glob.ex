defmodule OmS3.Glob do
  @moduledoc """
  Glob pattern matching for S3 keys.

  Supports `*` (matches within a path segment) and `**` (matches across segments).

  ## Examples

      OmS3.Glob.glob?("uploads/*.jpg")
      #=> true

      {:glob, "uploads/", "*.jpg"} = OmS3.Glob.parse_pattern("uploads/*.jpg")

      regex = OmS3.Glob.compile("*.jpg")
      OmS3.Glob.match?(regex, "photo.jpg")
      #=> true
  """

  @type compiled :: Regex.t()

  @doc """
  Returns true if the key contains glob characters.
  """
  @spec glob?(String.t()) :: boolean()
  def glob?(key), do: String.contains?(key, "*")

  @doc """
  Parses a key pattern into `{:glob, prefix, pattern}` or `:literal`.

  The prefix is the directory portion before the first glob character,
  used to narrow S3 listing requests.

  ## Examples

      OmS3.Glob.parse_pattern("uploads/*.jpg")
      #=> {:glob, "uploads/", "*.jpg"}

      OmS3.Glob.parse_pattern("**/*.txt")
      #=> {:glob, "", "**/*.txt"}

      OmS3.Glob.parse_pattern("exact/path.txt")
      #=> :literal
  """
  @spec parse_pattern(String.t()) :: {:glob, String.t(), String.t()} | :literal
  def parse_pattern(key) do
    case glob?(key) do
      false ->
        :literal

      true ->
        [prefix_part | _] = String.split(key, "*", parts: 2)
        prefix = directory_prefix(prefix_part)
        pattern = String.replace_prefix(key, prefix, "")
        {:glob, prefix, pattern}
    end
  end

  @doc """
  Returns the directory prefix from a path (everything up to the last `/`).

  ## Examples

      OmS3.Glob.directory_prefix("uploads/2024/photo")
      #=> "uploads/2024/"

      OmS3.Glob.directory_prefix("file.txt")
      #=> ""
  """
  @spec directory_prefix(String.t()) :: String.t()
  def directory_prefix(path) do
    case String.split(path, "/") |> Enum.drop(-1) do
      [] -> ""
      parts -> Enum.join(parts, "/") <> "/"
    end
  end

  @doc """
  Compiles a glob pattern to a regex for efficient repeated matching.

  Compile once, then use `match?/2` for each key.

  ## Examples

      regex = OmS3.Glob.compile("*.jpg")
      OmS3.Glob.match?(regex, "photo.jpg")
      #=> true
      OmS3.Glob.match?(regex, "sub/photo.jpg")
      #=> false

      regex = OmS3.Glob.compile("**/*.jpg")
      OmS3.Glob.match?(regex, "sub/photo.jpg")
      #=> true
  """
  @spec compile(String.t()) :: compiled() | nil
  def compile(pattern) do
    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> then(&("^" <> &1 <> "$"))

    case Regex.compile(regex_pattern) do
      {:ok, regex} -> regex
      _ -> nil
    end
  end

  @doc """
  Matches a key against a compiled glob regex.

  ## Examples

      regex = OmS3.Glob.compile("*.jpg")
      OmS3.Glob.matches?(regex, "photo.jpg")
      #=> true
  """
  @spec matches?(compiled() | nil, String.t()) :: boolean()
  def matches?(nil, _key), do: false
  def matches?(regex, key), do: Regex.match?(regex, key)

  @doc """
  Filters a list of full keys by a glob pattern, given a prefix.

  Strips the prefix from each key, then matches the remainder against the pattern.
  The pattern should be relative to the prefix.

  ## Examples

      OmS3.Glob.filter_keys(["uploads/a.jpg", "uploads/b.png"], "uploads/", "*.jpg")
      #=> ["uploads/a.jpg"]
  """
  @spec filter_keys([String.t()], String.t(), String.t()) :: [String.t()]
  def filter_keys(keys, prefix, pattern) do
    regex = compile(pattern)

    Enum.filter(keys, fn key ->
      relative_key = String.replace_prefix(key, prefix, "")
      matches?(regex, relative_key)
    end)
  end
end
