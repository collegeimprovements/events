# IEx configuration file

# Core & Database
alias Events.Core.{Repo, Cache, Query, Schema, Migration}

# CRUD (from libs/om_crud)
alias OmCrud
alias OmCrud.{Multi, Merge, ChangesetBuilder, Options}

# Functional Types
alias FnTypes.{Result, Maybe, Pipeline, AsyncResult, Guards, Validation}

# Infrastructure
alias Events.Infra.{Decorator, KillSwitch, SystemHealth, Idempotency}
alias Events.Infra.Scheduler.Workflow

# API & Services
alias Events.Api.Client
alias Events.Services.S3

# Web
alias EventsWeb.{Endpoint, Router}

Events.Support.IExHelpers.on_startup()

import Events.Support.IExHelpers
import FnTypes.Guards
