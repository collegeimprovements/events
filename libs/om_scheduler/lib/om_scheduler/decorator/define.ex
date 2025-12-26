defmodule OmScheduler.Decorator.Define do
  @moduledoc """
  Defines all decorators for OmScheduler.

  This module combines:
  1. All FnDecorator decorators (caching, telemetry, types, etc.)
  2. Scheduler-specific decorators (scheduled, step, graft, subworkflow)
  """

  use Decorator.Define,
    # Caching (from FnDecorator)
    cacheable: 1,
    cache_put: 1,
    cache_evict: 1,
    # Telemetry (from FnDecorator)
    telemetry_span: 1,
    telemetry_span: 2,
    log_call: 1,
    log_context: 1,
    log_if_slow: 1,
    # Performance (from FnDecorator)
    benchmark: 1,
    measure: 1,
    # Debugging (from FnDecorator)
    debug: 1,
    inspect: 1,
    pry: 1,
    # Pipeline (from FnDecorator)
    pipe_through: 1,
    around: 1,
    compose: 1,
    # Additional (from FnDecorator)
    otel_span: 1,
    otel_span: 2,
    track_memory: 1,
    capture_errors: 1,
    trace_vars: 1,
    trace_calls: 1,
    trace_modules: 1,
    trace_dependencies: 1,
    pure: 1,
    deterministic: 1,
    idempotent: 1,
    memoizable: 1,
    with_fixtures: 1,
    sample_data: 1,
    timeout_test: 1,
    mock: 1,
    # Type decorators (from FnDecorator)
    returns_result: 1,
    returns_maybe: 1,
    returns_bang: 1,
    returns_struct: 1,
    returns_list: 1,
    returns_union: 1,
    returns_pipeline: 1,
    normalize_result: 1,
    # Security (from FnDecorator)
    role_required: 1,
    rate_limit: 1,
    audit_log: 1,
    # Validation (from FnDecorator)
    validate_schema: 1,
    coerce_types: 1,
    serialize: 1,
    # Scheduler-specific
    scheduled: 1,
    # Workflow-specific
    step: 0,
    step: 1,
    graft: 0,
    graft: 1,
    subworkflow: 1,
    subworkflow: 2

  # ============================================
  # FnDecorator delegates
  # ============================================

  # Caching
  defdelegate cacheable(opts, body, context), to: FnDecorator.Caching
  defdelegate cache_put(opts, body, context), to: FnDecorator.Caching
  defdelegate cache_evict(opts, body, context), to: FnDecorator.Caching

  # Telemetry
  defdelegate telemetry_span(opts, body, context), to: FnDecorator.Telemetry
  defdelegate telemetry_span(event, opts, body, context), to: FnDecorator.Telemetry
  defdelegate otel_span(opts, body, context), to: FnDecorator.Telemetry
  defdelegate otel_span(name, opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_call(opts, body, context), to: FnDecorator.Telemetry
  defdelegate log_context(fields, body, context), to: FnDecorator.Telemetry
  defdelegate log_if_slow(opts, body, context), to: FnDecorator.Telemetry
  defdelegate track_memory(opts, body, context), to: FnDecorator.Telemetry
  defdelegate capture_errors(opts, body, context), to: FnDecorator.Telemetry
  defdelegate benchmark(opts, body, context), to: FnDecorator.Telemetry
  defdelegate measure(opts, body, context), to: FnDecorator.Telemetry

  # Debugging
  defdelegate debug(opts, body, context), to: FnDecorator.Debugging
  defdelegate inspect(opts, body, context), to: FnDecorator.Debugging
  defdelegate pry(opts, body, context), to: FnDecorator.Debugging
  defdelegate trace_vars(opts, body, context), to: FnDecorator.Debugging

  # Tracing
  defdelegate trace_calls(opts, body, context), to: FnDecorator.Tracing
  defdelegate trace_modules(opts, body, context), to: FnDecorator.Tracing
  defdelegate trace_dependencies(opts, body, context), to: FnDecorator.Tracing

  # Purity
  defdelegate pure(opts, body, context), to: FnDecorator.Purity
  defdelegate deterministic(opts, body, context), to: FnDecorator.Purity
  defdelegate idempotent(opts, body, context), to: FnDecorator.Purity
  defdelegate memoizable(opts, body, context), to: FnDecorator.Purity

  # Testing
  defdelegate with_fixtures(opts, body, context), to: FnDecorator.Testing
  defdelegate sample_data(opts, body, context), to: FnDecorator.Testing
  defdelegate timeout_test(opts, body, context), to: FnDecorator.Testing
  defdelegate mock(opts, body, context), to: FnDecorator.Testing

  # Pipeline
  defdelegate pipe_through(pipeline, body, context), to: FnDecorator.Pipeline
  defdelegate around(wrapper, body, context), to: FnDecorator.Pipeline
  defdelegate compose(decorators, body, context), to: FnDecorator.Pipeline

  # Types
  defdelegate returns_result(opts, body, context), to: FnDecorator.Types
  defdelegate returns_maybe(opts, body, context), to: FnDecorator.Types
  defdelegate returns_bang(opts, body, context), to: FnDecorator.Types
  defdelegate returns_struct(opts, body, context), to: FnDecorator.Types
  defdelegate returns_list(opts, body, context), to: FnDecorator.Types
  defdelegate returns_union(opts, body, context), to: FnDecorator.Types
  defdelegate returns_pipeline(opts, body, context), to: FnDecorator.Types
  defdelegate normalize_result(opts, body, context), to: FnDecorator.Types

  # Security
  defdelegate role_required(opts, body, context), to: FnDecorator.Security
  defdelegate rate_limit(opts, body, context), to: FnDecorator.Security
  defdelegate audit_log(opts, body, context), to: FnDecorator.Security

  # Validation
  defdelegate validate_schema(opts, body, context), to: FnDecorator.Validation
  defdelegate coerce_types(opts, body, context), to: FnDecorator.Validation
  defdelegate serialize(opts, body, context), to: FnDecorator.Validation

  # ============================================
  # Scheduler-specific decorators
  # ============================================

  @doc """
  Decorator for scheduling jobs.

  See `OmScheduler.Decorator.Scheduled` for options.
  """
  defdelegate scheduled(opts, body, context), to: OmScheduler.Decorator.Scheduled

  # ============================================
  # Workflow decorators
  # ============================================

  @doc """
  Decorator for workflow steps.
  """
  def step(body, context), do: step([], body, context)

  def step(opts, body, context) do
    OmScheduler.Workflow.Decorator.Step.step(opts, body, context)
  end

  @doc """
  Decorator for dynamic workflow grafting.
  """
  def graft(body, context), do: graft([], body, context)

  def graft(opts, body, context) do
    OmScheduler.Workflow.Decorator.Graft.graft(opts, body, context)
  end

  @doc """
  Decorator for nested subworkflows.
  """
  def subworkflow(name, body, context) do
    OmScheduler.Workflow.Decorator.Workflow.workflow(name, [], body, context)
  end

  def subworkflow(name, opts, body, context) do
    OmScheduler.Workflow.Decorator.Workflow.workflow(name, opts, body, context)
  end
end
