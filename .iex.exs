# IEx configuration file

# Core & Database (use libs directly)
alias Events.Core.{Repo, Cache, Migration}

# Libs - use directly with Events defaults from config
alias OmSchema
alias OmQuery
alias OmCrud
alias OmCrud.{Multi, Merge, ChangesetBuilder, Options}
alias OmScheduler
alias OmScheduler.Workflow
alias OmKillSwitch

# Functional Types
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Guards, Validation, Retry}

# Infrastructure
alias Events.Infra.{Decorator, SystemHealth, Idempotency}

# API & Services
alias Events.Api.Client
alias OmApiClient
alias OmS3

# Web
alias EventsWeb.{Endpoint, Router}

Events.Support.IExHelpers.on_startup()

import Events.Support.IExHelpers
import FnTypes.Guards
