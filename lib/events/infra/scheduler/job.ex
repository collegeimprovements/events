defmodule Events.Infra.Scheduler.Job do
  @moduledoc """
  Schema for scheduled jobs.

  Represents a job that can be executed on a schedule.

  ## Fields

  - `name` - Unique job identifier
  - `module` - Module containing the job function
  - `function` - Function name to call
  - `args` - Arguments to pass to the function
  - `schedule_type` - Type: :interval, :cron, :fixed_rate, :fixed_delay
  - `schedule` - Schedule configuration (cron expression, interval, etc.)
  - `timezone` - Timezone for cron expressions
  - `enabled` - Whether the job is active
  - `paused` - Whether the job is temporarily paused
  - `state` - Current state: active, paused, disabled
  - `queue` - Queue to run in
  - `priority` - Priority (0-9, lower is higher)
  - `max_retries` - Maximum retry attempts
  - `timeout` - Execution timeout in ms
  - `unique` - Whether to prevent overlapping executions
  - `tags` - Tags for filtering/grouping

  ## Schedule Types

  - `:interval` - Run every N time units: `%{every: {5, :minutes}}`
  - `:cron` - Cron expression: `%{expression: "0 6 * * *"}`
  - `:fixed_rate` - Fixed rate regardless of execution time
  - `:fixed_delay` - Fixed delay after execution completes
  """

  use Events.Core.Schema

  alias Events.Infra.Scheduler.Cron

  @type schedule_type :: :interval | :cron | :fixed_rate | :fixed_delay | :reboot
  @type state :: :active | :paused | :disabled

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          module: String.t(),
          function: String.t(),
          args: map(),
          schedule_type: schedule_type(),
          schedule: map(),
          timezone: String.t(),
          enabled: boolean(),
          paused: boolean(),
          state: state(),
          queue: String.t(),
          priority: non_neg_integer(),
          max_retries: non_neg_integer(),
          retry_delay: non_neg_integer(),
          timeout: non_neg_integer(),
          unique: boolean() | keyword(),
          unique_opts: map(),
          unique_key: String.t() | nil,
          tags: [String.t()],
          last_run_at: DateTime.t() | nil,
          next_run_at: DateTime.t() | nil,
          last_result: String.t() | nil,
          last_error: String.t() | nil,
          run_count: non_neg_integer(),
          error_count: non_neg_integer(),
          meta: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "scheduler_jobs" do
    field :name, :string, required: true
    field :module, :string, required: true
    field :function, :string, required: true
    field :args, :map, default: %{}

    field :schedule_type, Ecto.Enum,
      values: [:interval, :cron, :fixed_rate, :fixed_delay, :reboot],
      default: :cron

    field :schedule, :map, default: %{}
    field :timezone, :string, default: "Etc/UTC"

    field :enabled, :boolean, default: true
    field :paused, :boolean, default: false

    field :state, Ecto.Enum,
      values: [:active, :paused, :disabled],
      default: :active

    field :queue, :string, default: "default"
    field :priority, :integer, default: 0
    field :max_retries, :integer, default: 3
    field :retry_delay, :integer, default: 5000
    field :timeout, :integer, default: 60_000
    field :unique, :any, virtual: true, default: false
    field :unique_opts, :map, default: %{}
    field :unique_key, :string

    field :tags, {:array, :string}, default: []

    field :last_run_at, :utc_datetime_usec
    field :next_run_at, :utc_datetime_usec
    field :last_result, :string
    field :last_error, :string
    field :run_count, :integer, default: 0
    field :error_count, :integer, default: 0

    field :meta, :map, default: %{}

    timestamps()
  end

  @required_fields [:name, :module, :function]
  @optional_fields [
    :args,
    :schedule_type,
    :schedule,
    :timezone,
    :enabled,
    :paused,
    :state,
    :queue,
    :priority,
    :max_retries,
    :retry_delay,
    :timeout,
    :unique_opts,
    :unique_key,
    :tags,
    :last_run_at,
    :next_run_at,
    :last_result,
    :last_error,
    :run_count,
    :error_count,
    :meta
  ]

  # ============================================
  # Changesets
  # ============================================

  @doc """
  Creates a changeset for a new job.
  """
  def changeset(job, attrs) do
    job
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:name, ~r/^[a-z][a-z0-9_]*$/,
      message: "must be lowercase alphanumeric with underscores"
    )
    |> validate_inclusion(:priority, 0..9)
    |> validate_number(:max_retries, greater_than_or_equal_to: 0)
    |> validate_number(:timeout, greater_than: 0)
    |> validate_schedule()
    |> validate_timezone()
    |> unique_constraint(:name)
    |> unique_constraint(:unique_key)
  end

  @doc """
  Creates a changeset for updating job state after execution.
  """
  def execution_changeset(job, attrs) do
    job
    |> cast(attrs, [
      :last_run_at,
      :next_run_at,
      :last_result,
      :last_error,
      :run_count,
      :error_count,
      :state
    ])
  end

  @doc """
  Creates a changeset for pausing/resuming a job.
  """
  def state_changeset(job, attrs) do
    job
    |> cast(attrs, [:paused, :state])
  end

  # ============================================
  # Builders
  # ============================================

  @doc """
  Creates a new job struct from attributes.

  ## Examples

      iex> Job.new(%{
      ...>   name: "daily_report",
      ...>   module: "MyApp.Jobs",
      ...>   function: "generate_report",
      ...>   cron: "0 6 * * *"
      ...> })
      {:ok, %Job{...}}
  """
  @spec new(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{}
    |> changeset(attrs)
    |> apply_action(:insert)
  end

  @doc """
  Creates a new job struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, job} -> job
      {:error, changeset} -> raise Ecto.InvalidChangesetError, changeset: changeset, action: :insert
    end
  end

  @doc """
  Builds job attributes from decorator options.

  Converts decorator-friendly options like `cron: "0 6 * * *"` into
  the canonical job format.
  """
  @spec from_decorator_opts(atom(), atom(), keyword()) :: map()
  def from_decorator_opts(module, function, opts) do
    base = %{
      name:
        Keyword.get(
          opts,
          :name,
          "#{module}.#{function}" |> String.replace(".", "_") |> String.downcase()
        ),
      module: to_string(module),
      function: to_string(function),
      args: Keyword.get(opts, :args, %{})
    }

    schedule_attrs = extract_schedule(opts)
    option_attrs = extract_options(opts)

    Map.merge(base, schedule_attrs)
    |> Map.merge(option_attrs)
  end

  # ============================================
  # Query Helpers
  # ============================================

  @doc """
  Returns true if the job is runnable (enabled, not paused, active).
  """
  @spec runnable?(t()) :: boolean()
  def runnable?(%__MODULE__{enabled: enabled, paused: paused, state: state}) do
    enabled and not paused and state == :active
  end

  @doc """
  Returns true if the job is due for execution.
  """
  @spec due?(t(), DateTime.t()) :: boolean()
  def due?(%__MODULE__{next_run_at: nil}, _now), do: false

  def due?(%__MODULE__{next_run_at: next_run_at}, now) do
    DateTime.compare(next_run_at, now) in [:lt, :eq]
  end

  @doc """
  Returns true if the job is a reboot job.
  """
  @spec reboot?(t()) :: boolean()
  def reboot?(%__MODULE__{schedule_type: :reboot}), do: true
  def reboot?(%__MODULE__{}), do: false

  @doc """
  Calculates the next run time for the job.
  """
  @spec calculate_next_run(t(), DateTime.t()) :: {:ok, DateTime.t()} | {:error, term()}
  def calculate_next_run(%__MODULE__{schedule_type: :reboot}, _from) do
    {:error, :no_next_run}
  end

  def calculate_next_run(%__MODULE__{schedule_type: :interval, schedule: schedule}, from) do
    every_ms = get_interval_ms(schedule)
    next = DateTime.add(from, every_ms, :millisecond)
    {:ok, next}
  end

  def calculate_next_run(%__MODULE__{schedule_type: :cron, schedule: schedule, timezone: tz}, from) do
    expression = Map.get(schedule, "expression") || Map.get(schedule, :expression)

    expressions =
      Map.get(schedule, "expressions") || Map.get(schedule, :expressions) || [expression]

    expressions
    |> List.wrap()
    |> Enum.filter(&is_binary/1)
    |> case do
      [] ->
        {:error, :no_expression}

      exprs ->
        results =
          Enum.map(exprs, fn expr ->
            with {:ok, parsed} <- Cron.parse(expr) do
              Cron.next_run(parsed, from, timezone: tz)
            end
          end)

        valid_results = Enum.filter(results, &match?({:ok, _}, &1))

        case valid_results do
          [] -> {:error, :no_next_run}
          results -> {:ok, results |> Enum.map(fn {:ok, dt} -> dt end) |> Enum.min(DateTime)}
        end
    end
  end

  def calculate_next_run(%__MODULE__{schedule_type: type, schedule: schedule}, from)
      when type in [:fixed_rate, :fixed_delay] do
    interval_ms = get_interval_ms(schedule)
    next = DateTime.add(from, interval_ms, :millisecond)
    {:ok, next}
  end

  # ============================================
  # Private Helpers
  # ============================================

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> normalize_schedule_attrs()
    |> normalize_module_function()
    |> Map.new(fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  end

  # Convert module and function atoms to strings
  defp normalize_module_function(attrs) do
    attrs
    |> maybe_convert_to_string(:module)
    |> maybe_convert_to_string("module")
    |> maybe_convert_to_string(:function)
    |> maybe_convert_to_string("function")
  end

  defp maybe_convert_to_string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_atom(value) and not is_nil(value) ->
        Map.put(attrs, key, to_string(value))

      _ ->
        attrs
    end
  end

  defp normalize_schedule_attrs(attrs) do
    case {Map.get(attrs, :cron) || Map.get(attrs, "cron"),
          Map.get(attrs, :every) || Map.get(attrs, "every")} do
      {cron, _} when not is_nil(cron) ->
        {schedule_type, schedule} = build_cron_schedule(cron)

        attrs
        |> Map.drop([:cron, "cron"])
        |> Map.put(:schedule_type, schedule_type)
        |> Map.put(:schedule, schedule)

      {nil, every} when not is_nil(every) ->
        attrs
        |> Map.drop([:every, "every"])
        |> Map.put(:schedule_type, :interval)
        |> Map.put(:schedule, %{every: normalize_duration(every)})

      {nil, nil} ->
        attrs
    end
  end

  defp build_cron_schedule(cron) do
    case Cron.reboot?(cron) do
      true -> {:reboot, %{}}
      false -> {:cron, %{expressions: List.wrap(cron)}}
    end
  end

  defp normalize_duration({n, unit}) when is_integer(n) and is_atom(unit) do
    Events.Infra.Scheduler.Config.to_ms({n, unit})
  end

  defp normalize_duration(ms) when is_integer(ms), do: ms

  defp extract_schedule(opts) do
    schedule_attrs = extract_schedule_type(opts)
    Map.put(schedule_attrs, :timezone, Keyword.get(opts, :zone, "Etc/UTC"))
  end

  defp extract_schedule_type(opts) do
    case {opts[:cron], opts[:every], opts[:fixed_rate], opts[:fixed_delay]} do
      {cron, _, _, _} when not is_nil(cron) ->
        {schedule_type, schedule} = build_cron_schedule(cron)
        %{schedule_type: schedule_type, schedule: schedule}

      {nil, every, _, _} when not is_nil(every) ->
        %{schedule_type: :interval, schedule: %{every: normalize_duration(every)}}

      {nil, nil, rate, _} when not is_nil(rate) ->
        %{schedule_type: :fixed_rate, schedule: %{every: normalize_duration(rate)}}

      {nil, nil, nil, delay} when not is_nil(delay) ->
        %{schedule_type: :fixed_delay, schedule: %{every: normalize_duration(delay)}}

      {nil, nil, nil, nil} ->
        %{}
    end
  end

  defp extract_options(opts) do
    unique = Keyword.get(opts, :unique, false)
    unique_opts = normalize_unique_opts(unique)

    %{
      queue: Keyword.get(opts, :queue, :default) |> to_string(),
      priority: Keyword.get(opts, :priority, 0),
      max_retries: Keyword.get(opts, :max_retries, 3),
      timeout: Keyword.get(opts, :timeout, {1, :minute}) |> normalize_duration(),
      unique: unique,
      unique_opts: unique_opts,
      tags: Keyword.get(opts, :tags, [])
    }
  end

  defp normalize_unique_opts(true), do: %{enabled: true, by: [:name], states: [:running]}
  defp normalize_unique_opts(false), do: %{enabled: false}
  defp normalize_unique_opts(nil), do: %{enabled: false}

  defp normalize_unique_opts(opts) when is_list(opts) do
    %{
      enabled: true,
      by: Keyword.get(opts, :by, [:name]),
      states: Keyword.get(opts, :states, [:running]),
      period: normalize_unique_period(Keyword.get(opts, :period))
    }
  end

  defp normalize_unique_opts(_), do: %{enabled: false}

  defp normalize_unique_period(nil), do: nil
  defp normalize_unique_period({n, unit}) when is_integer(n) and is_atom(unit), do: {n, unit}
  defp normalize_unique_period(ms) when is_integer(ms), do: ms
  defp normalize_unique_period(_), do: nil

  defp get_interval_ms(%{"every" => ms}), do: ms
  defp get_interval_ms(%{every: ms}), do: ms
  defp get_interval_ms(_), do: 60_000

  defp validate_schedule(changeset) do
    schedule_type = get_field(changeset, :schedule_type)
    schedule = get_field(changeset, :schedule)

    case {schedule_type, schedule} do
      {:reboot, _} ->
        changeset

      {:cron, %{expressions: expressions}} when is_list(expressions) ->
        validate_cron_expressions(changeset, expressions)

      {:cron, %{"expressions" => expressions}} when is_list(expressions) ->
        validate_cron_expressions(changeset, expressions)

      {:interval, %{every: ms}} when is_integer(ms) and ms > 0 ->
        changeset

      {:interval, %{"every" => ms}} when is_integer(ms) and ms > 0 ->
        changeset

      {type, _} when type in [:fixed_rate, :fixed_delay] ->
        changeset

      _ ->
        add_error(changeset, :schedule, "is invalid for schedule_type")
    end
  end

  defp validate_cron_expressions(changeset, expressions) do
    case Enum.find(expressions, &(not Cron.valid?(&1))) do
      nil -> changeset
      invalid -> add_error(changeset, :schedule, "contains invalid cron expression: #{invalid}")
    end
  end

  defp validate_timezone(changeset) do
    changeset
    |> get_field(:timezone)
    |> do_validate_timezone(changeset)
  end

  defp do_validate_timezone(nil, changeset), do: changeset

  defp do_validate_timezone(timezone, changeset) do
    case valid_timezone?(timezone) do
      true -> changeset
      false -> add_error(changeset, :timezone, "is not a valid timezone")
    end
  end

  defp valid_timezone?("Etc/UTC"), do: true
  defp valid_timezone?("UTC"), do: true

  defp valid_timezone?(tz) do
    case Calendar.get_time_zone_database().time_zone_periods_from_wall_datetime(
           ~N[2024-01-01 00:00:00],
           tz
         ) do
      {:ok, _} -> true
      _ -> false
    end
  end
end
