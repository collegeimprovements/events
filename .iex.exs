# IEx configuration file

alias Events.{Repo, Cache, SystemHealth}
alias EventsWeb.{Endpoint, Router}

Events.IExHelpers.on_startup()

import Events.IExHelpers
