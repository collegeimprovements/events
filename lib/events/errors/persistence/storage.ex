defmodule Events.Errors.Persistence.Storage do
  @moduledoc """
  Error storage schema for persisting errors to the database.

  This module provides a unified interface for storing, retrieving,
  and querying errors across the application.

  ## Schema Fields

  - `id` - UUIDv7 primary key
  - `type` - Error type (validation, not_found, etc.)
  - `code` - Specific error code
  - `message` - Human-readable message
  - `source` - Error source system
  - `details` - Additional error details (JSONB)
  - `metadata` - Context metadata (JSONB)
    - `user` - User context
    - `request` - Request context
    - `application` - Application context
    - `temporal` - Temporal context
  - `stacktrace` - Error stacktrace (text)
  - `fingerprint` - Error fingerprint for grouping (computed)
  - `count` - Occurrence count for this fingerprint
  - `first_seen_at` - First occurrence timestamp
  - `last_seen_at` - Last occurrence timestamp
  - `resolved_at` - Resolution timestamp
  - `resolved_by_urm_id` - Who resolved it
  - Standard audit fields (created_by_urm_id, etc.)

  ## Usage

      # Store an error
      {:ok, stored} = Storage.store(error)

      # Store with context
      error
      |> Context.enrich(user: [user_id: 123], request: [request_id: "req_123"])
      |> Storage.store()

      # Query errors
      Storage.list(filters: [type: :validation], limit: 10)
      Storage.get_by_fingerprint(fingerprint)
      Storage.get_recent(hours: 24)

      # Mark as resolved
      Storage.resolve(error_id, resolved_by: urm_id)
  """

  use Events.Schema
  use Events.Decorator

  require Logger
  import Ecto.Query
  alias Events.Repo
  alias Events.Errors.Error

  @type t :: %__MODULE__{}

  schema "errors" do
    field :error_type, Ecto.Enum,
      values: [
        :validation,
        :not_found,
        :unauthorized,
        :forbidden,
        :conflict,
        :internal,
        :external,
        :timeout,
        :rate_limit,
        :bad_request,
        :unprocessable,
        :service_unavailable,
        :network,
        :configuration,
        :unknown
      ]

    field :code, :string
    field :message, :string
    field :source, :string
    field :error_details, :map
    field :stacktrace, :string

    # Grouping & Analytics
    field :fingerprint, :string
    field :count, :integer, default: 1
    field :first_seen_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec

    # Resolution
    field :resolved_at, :utc_datetime_usec
    field :resolved_by_urm_id, Ecto.UUID
  end

  ## Changeset

  @doc false
  def changeset(error_storage \\ %__MODULE__{}, attrs) do
    error_storage
    |> cast(attrs, [
      :error_type,
      :code,
      :message,
      :source,
      :error_details,
      :metadata,
      :stacktrace,
      :fingerprint,
      :count,
      :first_seen_at,
      :last_seen_at,
      :resolved_at,
      :resolved_by_urm_id
    ])
    |> validate_required([:error_type, :code, :message])
    |> generate_fingerprint()
    |> set_timestamps()
  end

  defp generate_fingerprint(changeset) do
    case get_change(changeset, :fingerprint) do
      nil ->
        # Generate fingerprint from type, code, source, and message pattern
        error_type = get_field(changeset, :error_type)
        code = get_field(changeset, :code)
        source = get_field(changeset, :source)
        message = get_field(changeset, :message)

        fingerprint = compute_fingerprint(error_type, code, source, message)
        put_change(changeset, :fingerprint, fingerprint)

      _ ->
        changeset
    end
  end

  defp compute_fingerprint(type, code, source, message) do
    # Create a stable fingerprint for grouping similar errors
    # Remove dynamic parts from message (IDs, timestamps, etc.)
    normalized_message =
      message
      |> String.replace(
        ~r/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
        "<UUID>"
      )
      |> String.replace(~r/\b\d+\b/, "<NUM>")
      |> String.replace(~r/\b\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, "<TIMESTAMP>")

    data = "#{type}:#{code}:#{source}:#{normalized_message}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  defp set_timestamps(changeset) do
    now = DateTime.utc_now()

    changeset
    |> put_change(:last_seen_at, now)
    |> maybe_put_first_seen_at(now)
  end

  defp maybe_put_first_seen_at(changeset, now) do
    case get_field(changeset, :first_seen_at) do
      nil -> put_change(changeset, :first_seen_at, now)
      _ -> changeset
    end
  end

  ## Storage Operations

  @doc """
  Stores an Error struct in the database.

  If an error with the same fingerprint exists, increments the count
  and updates last_seen_at instead of creating a new record.

  ## Examples

      iex> Storage.store(error)
      {:ok, %Storage{}}

      iex> Storage.store(error, created_by_urm_id: urm_id)
      {:ok, %Storage{}}
  """
  @spec store(Error.t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  @decorate telemetry_span([:events, :error, :storage, :store])
  def store(%Error{} = error, opts \\ []) do
    attrs = error_to_attrs(error, opts)

    # Generate fingerprint before checking for duplicates
    fingerprint =
      compute_fingerprint(
        error.type,
        to_string(error.code),
        to_string(error.source || :unknown),
        error.message
      )

    case get_by_fingerprint(fingerprint) do
      nil ->
        %__MODULE__{}
        |> changeset(Map.put(attrs, :fingerprint, fingerprint))
        |> Repo.insert()

      existing ->
        existing
        |> changeset(%{
          count: existing.count + 1,
          last_seen_at: DateTime.utc_now(),
          metadata: merge_metadata(existing.metadata, attrs.metadata)
        })
        |> Repo.update()
    end
  end

  @doc """
  Stores an error and returns :ok, logging on failure.

  Useful when you want to store errors without handling the result.

  ## Examples

      iex> Storage.store_async(error)
      :ok
  """
  @spec store_async(Error.t(), keyword()) :: :ok
  def store_async(%Error{} = error, opts \\ []) do
    Task.start(fn ->
      case store(error, opts) do
        {:ok, _} -> :ok
        {:error, changeset} -> Logger.error("Failed to store error: #{Kernel.inspect(changeset)}")
      end
    end)

    :ok
  end

  ## Query Operations

  @doc """
  Gets an error by ID.
  """
  @spec get(Ecto.UUID.t()) :: t() | nil
  def get(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets an error by fingerprint.
  """
  @spec get_by_fingerprint(String.t()) :: t() | nil
  def get_by_fingerprint(fingerprint) do
    Repo.get_by(__MODULE__, fingerprint: fingerprint)
  end

  @doc """
  Lists errors with optional filters.

  ## Options

  - `:type` - Filter by error type
  - `:code` - Filter by error code
  - `:source` - Filter by error source
  - `:resolved` - Filter by resolution status (true/false)
  - `:since` - Errors since datetime
  - `:limit` - Result limit (default: 100)
  - `:offset` - Result offset
  - `:order_by` - Order by field (default: :last_seen_at)

  ## Examples

      iex> Storage.list(type: :validation, limit: 10)
      [%Storage{}, ...]

      iex> Storage.list(resolved: false, since: ~U[2024-01-01 00:00:00Z])
      [%Storage{}, ...]
  """
  @spec list(keyword()) :: [t()]
  def list(opts \\ []) do
    __MODULE__
    |> apply_filters(opts)
    |> apply_order(Keyword.get(opts, :order_by, :last_seen_at))
    |> limit_query(Keyword.get(opts, :limit, 100))
    |> offset_query(Keyword.get(opts, :offset, 0))
    |> Repo.all()
  end

  @doc """
  Gets recent errors within the specified time window.

  ## Examples

      iex> Storage.get_recent(hours: 24)
      [%Storage{}, ...]

      iex> Storage.get_recent(minutes: 30, type: :validation)
      [%Storage{}, ...]
  """
  @spec get_recent(keyword()) :: [t()]
  def get_recent(opts) do
    since = calculate_since(opts)
    filters = Keyword.put(opts, :since, since)
    list(filters)
  end

  @doc """
  Groups errors by a field and returns counts.

  ## Examples

      iex> Storage.group_by(:type)
      %{validation: 42, not_found: 18, ...}

      iex> Storage.group_by(:code, filters: [type: :validation])
      %{invalid_email: 15, required_field: 8, ...}
  """
  @spec group_by(atom(), keyword()) :: map()
  def group_by(field, opts \\ []) do
    __MODULE__
    |> apply_filters(opts)
    |> group_by([e], field(e, ^field))
    |> select([e], {field(e, ^field), sum(e.count)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Marks an error as resolved.

  ## Examples

      iex> Storage.resolve(error_id, resolved_by: urm_id)
      {:ok, %Storage{}}
  """
  @spec resolve(Ecto.UUID.t(), keyword()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def resolve(id, opts) do
    get(id)
    |> changeset(%{
      resolved_at: DateTime.utc_now(),
      resolved_by_urm_id: Keyword.fetch!(opts, :resolved_by)
    })
    |> Repo.update()
  end

  ## Helpers

  defp error_to_attrs(%Error{} = error, opts) do
    %{
      error_type: error.type,
      code: to_string(error.code),
      message: error.message,
      source: to_string(error.source || :unknown),
      error_details: error.details,
      metadata: error.metadata,
      stacktrace: format_stacktrace(error.stacktrace),
      created_by_urm_id: Keyword.get(opts, :created_by_urm_id)
    }
  end

  defp format_stacktrace(nil), do: nil

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    Exception.format_stacktrace(stacktrace)
  end

  defp format_stacktrace(stacktrace), do: to_string(stacktrace)

  defp merge_metadata(existing, new) do
    Map.merge(existing || %{}, new || %{}, fn _k, v1, v2 ->
      case {v1, v2} do
        {m1, m2} when is_map(m1) and is_map(m2) -> Map.merge(m1, m2)
        {_, v} -> v
      end
    end)
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:type, type}, q -> where(q, [e], e.error_type == ^type)
      {:code, code}, q -> where(q, [e], e.code == ^code)
      {:source, source}, q -> where(q, [e], e.source == ^source)
      {:resolved, true}, q -> where(q, [e], not is_nil(e.resolved_at))
      {:resolved, false}, q -> where(q, [e], is_nil(e.resolved_at))
      {:since, datetime}, q -> where(q, [e], e.last_seen_at >= ^datetime)
      _, q -> q
    end)
  end

  defp apply_order(query, field) do
    order_by(query, [e], desc: field(e, ^field))
  end

  defp limit_query(query, limit) do
    limit(query, ^limit)
  end

  defp offset_query(query, 0), do: query
  defp offset_query(query, offset), do: offset(query, ^offset)

  defp calculate_since(opts) do
    now = DateTime.utc_now()

    cond do
      hours = Keyword.get(opts, :hours) ->
        DateTime.add(now, -hours * 3600, :second)

      minutes = Keyword.get(opts, :minutes) ->
        DateTime.add(now, -minutes * 60, :second)

      days = Keyword.get(opts, :days) ->
        DateTime.add(now, -days * 86400, :second)

      true ->
        DateTime.add(now, -24 * 3600, :second)
    end
  end
end
