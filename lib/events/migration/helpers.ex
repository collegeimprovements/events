defmodule Events.Migration.Helpers do
  @moduledoc """
  Helper functions for migrations using pure functions and pattern matching.

  All functions are pure and composable.
  """

  @doc """
  Generates a standard index name.

  ## Examples

      iex> index_name(:users, [:email])
      :users_email_index

      iex> index_name(:products, [:category_id, :status])
      :products_category_id_status_index
  """
  @spec index_name(atom() | String.t(), list(atom())) :: atom()
  def index_name(table, columns) when is_list(columns) do
    [to_string(table), Enum.map(columns, &to_string/1), "index"]
    |> List.flatten()
    |> Enum.join("_")
    |> String.to_atom()
  end

  @doc """
  Generates a unique index name.

  ## Examples

      iex> unique_index_name(:users, [:email])
      :users_email_unique

      iex> unique_index_name(:products, [:sku])
      :products_sku_unique
  """
  @spec unique_index_name(atom() | String.t(), list(atom())) :: atom()
  def unique_index_name(table, columns) when is_list(columns) do
    [to_string(table), Enum.map(columns, &to_string/1), "unique"]
    |> List.flatten()
    |> Enum.join("_")
    |> String.to_atom()
  end

  @doc """
  Generates a constraint name.

  ## Examples

      iex> constraint_name(:users, :age, :check)
      :users_age_check

      iex> constraint_name(:products, :price, :positive)
      :products_price_positive
  """
  @spec constraint_name(atom() | String.t(), atom(), atom()) :: atom()
  def constraint_name(table, field, type) do
    [to_string(table), to_string(field), to_string(type)]
    |> Enum.join("_")
    |> String.to_atom()
  end

  @doc """
  Generates a foreign key constraint name.

  ## Examples

      iex> fk_constraint_name(:orders, :customer_id)
      :orders_customer_id_fkey

      iex> fk_constraint_name(:products, :category_id)
      :products_category_id_fkey
  """
  @spec fk_constraint_name(atom() | String.t(), atom()) :: atom()
  def fk_constraint_name(table, field) do
    [to_string(table), to_string(field), "fkey"]
    |> Enum.join("_")
    |> String.to_atom()
  end

  @doc """
  Validates field options using pattern matching.

  ## Examples

      iex> validate_field_options(:string, min_length: 3, max_length: 100)
      {:ok, [min_length: 3, max_length: 100]}

      iex> validate_field_options(:integer, format: :email)
      {:error, "format is not valid for integer fields"}
  """
  @spec validate_field_options(atom(), keyword()) :: {:ok, keyword()} | {:error, String.t()}
  def validate_field_options(type, opts) do
    opts
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
      case validate_option(type, key, value) do
        :ok -> {:cont, {:ok, [{key, value} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  defp validate_option(:string, :min_length, n) when is_integer(n) and n >= 0, do: :ok
  defp validate_option(:string, :max_length, n) when is_integer(n) and n > 0, do: :ok
  defp validate_option(:string, :format, _), do: :ok
  defp validate_option(:string, :unique, b) when is_boolean(b), do: :ok

  defp validate_option(:integer, :min, _), do: :ok
  defp validate_option(:integer, :max, _), do: :ok
  defp validate_option(:integer, :default, n) when is_integer(n), do: :ok

  defp validate_option(:decimal, :precision, n) when is_integer(n) and n > 0, do: :ok
  defp validate_option(:decimal, :scale, n) when is_integer(n) and n >= 0, do: :ok

  defp validate_option(_type, :null, b) when is_boolean(b), do: :ok
  defp validate_option(_type, :default, _), do: :ok
  defp validate_option(_type, :primary_key, b) when is_boolean(b), do: :ok

  defp validate_option(type, key, _value) do
    {:error, "#{key} is not valid for #{type} fields"}
  end

  @doc """
  Merges field options with defaults.

  ## Examples

      iex> merge_with_defaults(:string, [required: true])
      [null: false, required: true]

      iex> merge_with_defaults(:jsonb, [])
      [null: false, default: %{}]
  """
  @spec merge_with_defaults(atom(), keyword()) :: keyword()
  def merge_with_defaults(type, opts) do
    defaults = default_options(type)
    Keyword.merge(defaults, opts)
  end

  defp default_options(:string), do: [null: true]
  defp default_options(:text), do: [null: true]
  defp default_options(:integer), do: [null: true]
  defp default_options(:decimal), do: [null: true, precision: 10, scale: 2]
  defp default_options(:boolean), do: [null: false, default: false]
  defp default_options(:jsonb), do: [null: false, default: %{}]
  defp default_options({:array, _}), do: [null: false, default: []]
  defp default_options(:utc_datetime), do: [null: true]
  defp default_options(:utc_datetime_usec), do: [null: true]
  defp default_options(:date), do: [null: true]
  defp default_options(:time), do: [null: true]
  defp default_options(:binary_id), do: [null: true]
  defp default_options(:citext), do: [null: true]
  defp default_options(_), do: []

  @doc """
  Builds SQL check constraint expressions.

  ## Examples

      iex> build_check_constraint(:age, min: 0, max: 120)
      "age >= 0 AND age <= 120"

      iex> build_check_constraint(:status, in: ["active", "pending"])
      "status IN ('active', 'pending')"
  """
  @spec build_check_constraint(atom(), keyword()) :: String.t()
  def build_check_constraint(field, opts) do
    opts
    |> Enum.map(&build_check_clause(field, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" AND ")
  end

  defp build_check_clause(field, {:min, value}) do
    "#{field} >= #{value}"
  end

  defp build_check_clause(field, {:max, value}) do
    "#{field} <= #{value}"
  end

  defp build_check_clause(field, {:in, values}) when is_list(values) do
    value_list = values |> Enum.map(&"'#{&1}'") |> Enum.join(", ")
    "#{field} IN (#{value_list})"
  end

  defp build_check_clause(field, {:not_in, values}) when is_list(values) do
    value_list = values |> Enum.map(&"'#{&1}'") |> Enum.join(", ")
    "#{field} NOT IN (#{value_list})"
  end

  defp build_check_clause(field, {:positive, true}) do
    "#{field} > 0"
  end

  defp build_check_clause(field, {:non_negative, true}) do
    "#{field} >= 0"
  end

  defp build_check_clause(_field, _), do: nil

  @doc """
  Groups fields by their type for batch processing.

  ## Examples

      iex> group_by_type([
      ...>   {:name, :string, []},
      ...>   {:age, :integer, []},
      ...>   {:email, :string, []}
      ...> ])
      %{
        string: [{:name, []}, {:email, []}],
        integer: [{:age, []}]
      }
  """
  @spec group_by_type(list({atom(), atom(), keyword()})) ::
          %{atom() => list({atom(), keyword()})}
  def group_by_type(fields) do
    fields
    |> Enum.group_by(
      fn {_name, type, _opts} -> type end,
      fn {name, _type, opts} -> {name, opts} end
    )
  end

  @doc """
  Extracts references from field definitions.

  ## Examples

      iex> extract_references([
      ...>   {:user_id, {:references, :users, []}, []},
      ...>   {:name, :string, []}
      ...> ])
      [{:user_id, :users, []}]
  """
  @spec extract_references(list({atom(), any(), keyword()})) ::
          list({atom(), atom(), keyword()})
  def extract_references(fields) do
    fields
    |> Enum.filter(fn
      {_name, {:references, _, _}, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {name, {:references, table, opts}, _field_opts} ->
      {name, table, opts}
    end)
  end

  @doc """
  Checks if a field is nullable.

  ## Examples

      iex> nullable?([null: false])
      false

      iex> nullable?([null: true])
      true

      iex> nullable?([])
      true  # Default is nullable
  """
  @spec nullable?(keyword()) :: boolean()
  def nullable?(opts) do
    Keyword.get(opts, :null, true)
  end

  @doc """
  Extracts default value from options.

  ## Examples

      iex> extract_default([default: 0])
      {:ok, 0}

      iex> extract_default([])
      :none

      iex> extract_default([default: {:fragment, "now()"}])
      {:ok, {:fragment, "now()"}}
  """
  @spec extract_default(keyword()) :: {:ok, any()} | :none
  def extract_default(opts) do
    case Keyword.get(opts, :default) do
      nil -> :none
      value -> {:ok, value}
    end
  end
end
