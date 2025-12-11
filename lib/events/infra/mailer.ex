defmodule Events.Infra.Mailer do
  @app_name Application.compile_env(:events, [__MODULE__, :app_name], :events)
  use Swoosh.Mailer, otp_app: @app_name
end
