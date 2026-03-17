defmodule OmS3.ContentType do
  @moduledoc """
  Content type detection for S3 object keys.

  Maps file extensions to MIME types. Used by `OmS3.Client` and `OmS3.Stream`
  for automatic content type detection during uploads.
  """

  @doc """
  Detects the MIME content type from a file key/path based on its extension.

  Returns `"application/octet-stream"` for unknown extensions.

  ## Examples

      OmS3.ContentType.detect("photo.jpg")
      #=> "image/jpeg"

      OmS3.ContentType.detect("uploads/report.pdf")
      #=> "application/pdf"

      OmS3.ContentType.detect("unknown.xyz")
      #=> "application/octet-stream"
  """
  @spec detect(String.t()) :: String.t()
  def detect(key) do
    case Path.extname(key) |> String.downcase() do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".txt" -> "text/plain"
      ".html" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".zip" -> "application/zip"
      ".gz" -> "application/gzip"
      ".tar" -> "application/x-tar"
      ".mp4" -> "video/mp4"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".csv" -> "text/csv"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".xls" -> "application/vnd.ms-excel"
      ".xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      _ -> "application/octet-stream"
    end
  end
end
