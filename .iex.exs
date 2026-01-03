# IEx configuration file

# Data layer
alias Events.Data.{Repo, Cache}

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

# Services
alias Events.Services.{PubSub, Mailer, ApiClient}

# Extensions
alias Events.Extensions.Decorator

# Observability
alias Events.Observability.SystemHealth

# Libs - API & S3
alias OmApiClient
alias OmS3

# Web
alias EventsWeb.{Endpoint, Router}

Events.Dev.IExHelpers.on_startup()

import Events.Dev.IExHelpers
import FnTypes.Guards
