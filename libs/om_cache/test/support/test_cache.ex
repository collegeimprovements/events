defmodule OmCache.TestCache do
  @moduledoc false
  use OmCache, otp_app: :om_cache, default_adapter: :local
end

defmodule OmCache.TestL1Cache do
  @moduledoc false
  use OmCache, otp_app: :om_cache, default_adapter: :local
end

defmodule OmCache.TestL2Cache do
  @moduledoc false
  use OmCache, otp_app: :om_cache, default_adapter: :local
end
