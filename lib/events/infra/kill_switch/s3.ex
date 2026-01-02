defmodule Events.Infra.KillSwitch.S3 do
  @moduledoc """
  S3 service wrapper with kill switch support for Events.

  Thin wrapper around `OmKillSwitch.Services.S3` with Events-specific
  configuration. Uses `OmS3.from_env()` for S3 config by default.

  See `OmKillSwitch.Services.S3` for full documentation.
  """

  # Delegate all functions to the lib version
  defdelegate enabled?, to: OmKillSwitch.Services.S3
  defdelegate check, to: OmKillSwitch.Services.S3
  defdelegate status, to: OmKillSwitch.Services.S3
  defdelegate disable(opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate enable, to: OmKillSwitch.Services.S3

  defdelegate list(bucket, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate upload(bucket, path, content, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate download(bucket, path, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate delete(bucket, path, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate exists?(bucket, path, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate url_for_upload(bucket, path, opts \\ []), to: OmKillSwitch.Services.S3
  defdelegate url_for_download(bucket, path, opts \\ []), to: OmKillSwitch.Services.S3
end
