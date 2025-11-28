defmodule Events.Test.Factory do
  @moduledoc """
  Test data factory using Faker for realistic data generation.

  ## Usage

  Import in your test module:

      import Events.Test.Factory

  Build data:

      # Build a map (not persisted)
      user_attrs = build(:user)

      # Build with overrides
      user_attrs = build(:user, email: "[email protected]")

      # Build a list
      users = build_list(3, :user)

  ## Adding New Factories

  Add a new clause to `build/2`:

      def build(:order, overrides) do
        defaults = %{
          number: sequence("ORD"),
          status: :pending,
          total: Faker.Commerce.price()
        }
        Map.merge(defaults, Map.new(overrides))
      end
  """

  @doc """
  Generates a sequential value with the given prefix.

  ## Examples

      iex> sequence("user")
      "user_1"
      iex> sequence("user")
      "user_2"
  """
  def sequence(prefix) do
    counter = :erlang.unique_integer([:positive, :monotonic])
    "#{prefix}_#{counter}"
  end

  @doc """
  Builds a factory by name with optional overrides.
  """
  def build(factory_name, overrides \\ [])

  def build(:user, overrides) do
    defaults = %{
      email: Faker.Internet.email(),
      name: Faker.Person.name(),
      status: :active,
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def build(:user_credentials, overrides) do
    defaults = %{
      email: Faker.Internet.email(),
      password: Faker.Lorem.characters(12) |> to_string(),
      password_confirmation: nil
    }

    result = Map.merge(defaults, Map.new(overrides))
    # Set password_confirmation to match password if not overridden
    if is_nil(result.password_confirmation) do
      Map.put(result, :password_confirmation, result.password)
    else
      result
    end
  end

  def build(:s3_config, overrides) do
    defaults = %{
      access_key_id: Faker.Lorem.characters(20) |> to_string(),
      secret_access_key: Faker.Lorem.characters(40) |> to_string(),
      region: Enum.random(["us-east-1", "us-west-2", "eu-west-1"]),
      bucket: Faker.Lorem.word(),
      endpoint: nil
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def build(:http_response, overrides) do
    defaults = %{
      status: 200,
      body: %{},
      headers: [{"content-type", "application/json"}]
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def build(:error_response, overrides) do
    defaults = %{
      status: Enum.random([400, 401, 403, 404, 500, 502, 503]),
      body: %{"error" => Faker.Lorem.sentence()},
      headers: [{"content-type", "application/json"}]
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def build(:changeset_attrs, overrides) do
    # Generic changeset attributes for schema testing
    defaults = %{
      name: Faker.Person.name(),
      email: Faker.Internet.email(),
      description: Faker.Lorem.paragraph(),
      status: :active
    }

    Map.merge(defaults, Map.new(overrides))
  end

  @doc """
  Builds a list of factories.

  ## Examples

      build_list(3, :user)
      build_list(5, :user, status: :inactive)
  """
  def build_list(count, factory_name, overrides \\ []) do
    Enum.map(1..count, fn _ -> build(factory_name, overrides) end)
  end

  @doc """
  Builds factory attributes as a keyword list (useful for changesets).
  """
  def build_attrs(factory_name, overrides \\ []) do
    factory_name
    |> build(overrides)
    |> Map.to_list()
  end

  @doc """
  Generates params map with string keys (useful for controller tests).
  """
  def build_params(factory_name, overrides \\ []) do
    factory_name
    |> build(overrides)
    |> stringify_keys()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(value), do: value
end
