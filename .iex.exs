# IEx configuration file

alias Events.Core.{Repo, Cache}
alias Events.Infra.SystemHealth
alias EventsWeb.{Endpoint, Router}

Events.Support.IExHelpers.on_startup()

import Events.Support.IExHelpers
