defmodule FnTypes.SideEffects do
  @moduledoc """
  Lightweight annotations for documenting and tracking side effects.

  Provides compile-time annotations to document what side effects a function may produce.
  This is primarily for documentation and static analysis - it does not enforce
  effect isolation at runtime.

  ## Design Philosophy

  - **Documentation-first**: Side effects are annotations for humans and tools
  - **Non-invasive**: Zero runtime overhead, purely compile-time
  - **Composable**: Effect tags can be combined and composed
  - **Queryable**: Side effects can be introspected via module attributes

  ## Side Effect Types

  | Effect | Meaning |
  |--------|---------|
  | `:db_read` | Reads from database |
  | `:db_write` | Writes to database |
  | `:http` | Makes HTTP requests |
  | `:io` | File system or stdout |
  | `:time` | Uses current time |
  | `:random` | Uses random values |
  | `:process` | Spawns or messages processes |
  | `:ets` | Reads/writes ETS tables |
  | `:cache` | Cache operations |
  | `:email` | Sends emails |
  | `:pubsub` | Publishes events |
  | `:telemetry` | Emits telemetry |
  | `:external_api` | Calls external service |
  | `:pure` | No side effects (referentially transparent) |

  ## Usage

      defmodule MyApp.Users do
        use FnTypes.SideEffects

        @side_effects [:db_read]
        def get_user(id) do
          Repo.get(User, id)
        end

        @side_effects [:db_write, :email]
        def create_user(attrs) do
          with {:ok, user} <- Repo.insert(User.changeset(attrs)),
               :ok <- Mailer.send_welcome(user) do
            {:ok, user}
          end
        end

        @side_effects [:pure]
        def format_name(user) do
          "\#{user.first_name} \#{user.last_name}"
        end
      end

  ## Introspection

      # Get side effects for a function
      FnTypes.SideEffects.get(MyApp.Users, :create_user, 1)
      #=> [:db_write, :email]

      # List all annotated functions in a module
      FnTypes.SideEffects.list(MyApp.Users)
      #=> [{:get_user, 1, [:db_read]}, {:create_user, 1, [:db_write, :email]}, ...]

      # Find functions with specific side effects
      FnTypes.SideEffects.with_effect(MyApp.Users, :db_write)
      #=> [{:create_user, 1}, {:update_user, 2}, ...]

  ## Static Analysis

  Side effect annotations enable static analysis for:
  - Finding all database-touching functions
  - Auditing external API calls
  - Identifying impure functions for testing
  - Generating dependency graphs
  """

  @type effect ::
          :db_read
          | :db_write
          | :http
          | :io
          | :time
          | :random
          | :process
          | :ets
          | :cache
          | :email
          | :pubsub
          | :telemetry
          | :external_api
          | :pure
          | atom()

  @type effect_entry :: {atom(), arity(), [effect()]}

  @known_effects [
    :db_read,
    :db_write,
    :http,
    :io,
    :time,
    :random,
    :process,
    :ets,
    :cache,
    :email,
    :pubsub,
    :telemetry,
    :external_api,
    :pure
  ]

  @doc """
  Imports side effect annotation macros.

  ## Usage

      defmodule MyModule do
        use FnTypes.SideEffects
      end
  """
  defmacro __using__(_opts) do
    quote do
      Module.register_attribute(__MODULE__, :side_effects, accumulate: false)
      Module.register_attribute(__MODULE__, :fn_side_effects, accumulate: true)

      @before_compile FnTypes.SideEffects
      @on_definition FnTypes.SideEffects

      import FnTypes.SideEffects, only: [side_effects: 1]
    end
  end

  @doc """
  Callback invoked on function definition to capture side effects.
  """
  def __on_definition__(env, kind, name, args, _guards, _body)
      when kind in [:def, :defp] do
    effects = Module.get_attribute(env.module, :side_effects)

    if effects do
      arity = length(args)
      entry = {name, arity, List.wrap(effects)}
      Module.put_attribute(env.module, :fn_side_effects, entry)
      Module.delete_attribute(env.module, :side_effects)
    end
  end

  def __on_definition__(_env, _kind, _name, _args, _guards, _body), do: :ok

  @doc """
  Callback invoked before compilation to generate side effects registry.
  """
  defmacro __before_compile__(env) do
    effects = Module.get_attribute(env.module, :fn_side_effects) || []

    quote do
      @doc false
      def __side_effects__(:all), do: unquote(Macro.escape(effects))

      def __side_effects__({name, arity}) do
        Enum.find_value(__side_effects__(:all), fn
          {^name, ^arity, effects} -> effects
          _ -> nil
        end)
      end

      def __side_effects__(effect) when is_atom(effect) do
        __side_effects__(:all)
        |> Enum.filter(fn {_, _, effects} -> effect in effects end)
        |> Enum.map(fn {name, arity, _} -> {name, arity} end)
      end
    end
  end

  @doc """
  Declares side effects for the following function.

  ## Examples

      @side_effects [:db_read]
      def get_user(id), do: Repo.get(User, id)

      @side_effects [:db_write, :email]
      def create_user(attrs), do: ...
  """
  defmacro side_effects(effect_list) when is_list(effect_list) do
    quote do
      @side_effects unquote(effect_list)
    end
  end

  # ============================================
  # Introspection API
  # ============================================

  @doc """
  Gets the side effects declared for a function.

  ## Examples

      FnTypes.SideEffects.get(MyModule, :create_user, 1)
      #=> [:db_write, :email]

      FnTypes.SideEffects.get(MyModule, :unknown, 0)
      #=> nil
  """
  @spec get(module(), atom(), arity()) :: [effect()] | nil
  def get(module, function, arity) do
    if function_exported?(module, :__side_effects__, 1) do
      module.__side_effects__({function, arity})
    else
      nil
    end
  end

  @doc """
  Lists all functions with side effect annotations in a module.

  ## Examples

      FnTypes.SideEffects.list(MyModule)
      #=> [{:get_user, 1, [:db_read]}, {:create_user, 1, [:db_write, :email]}]
  """
  @spec list(module()) :: [effect_entry()]
  def list(module) do
    if function_exported?(module, :__side_effects__, 1) do
      module.__side_effects__(:all)
    else
      []
    end
  end

  @doc """
  Finds all functions with a specific side effect.

  ## Examples

      FnTypes.SideEffects.with_effect(MyModule, :db_write)
      #=> [{:create_user, 1}, {:update_user, 2}]
  """
  @spec with_effect(module(), effect()) :: [{atom(), arity()}]
  def with_effect(module, effect) when is_atom(effect) do
    if function_exported?(module, :__side_effects__, 1) do
      module.__side_effects__(effect)
    else
      []
    end
  end

  @doc """
  Checks if a function has a specific side effect.

  ## Examples

      FnTypes.SideEffects.has_effect?(MyModule, :create_user, 1, :db_write)
      #=> true
  """
  @spec has_effect?(module(), atom(), arity(), effect()) :: boolean()
  def has_effect?(module, function, arity, effect) do
    case get(module, function, arity) do
      nil -> false
      effects -> effect in effects
    end
  end

  @doc """
  Checks if a function is pure (no side effects or only :pure annotation).

  ## Examples

      FnTypes.SideEffects.pure?(MyModule, :format_name, 1)
      #=> true
  """
  @spec pure?(module(), atom(), arity()) :: boolean()
  def pure?(module, function, arity) do
    case get(module, function, arity) do
      nil -> false
      [:pure] -> true
      [] -> true
      _ -> false
    end
  end

  @doc """
  Returns all known side effect types.

  ## Examples

      FnTypes.SideEffects.known_effects()
      #=> [:db_read, :db_write, :http, ...]
  """
  @spec known_effects() :: [effect()]
  def known_effects, do: @known_effects

  @doc """
  Validates side effect annotations against known effects.

  Returns warnings for unknown effects.

  ## Examples

      FnTypes.SideEffects.validate(MyModule)
      #=> {:ok, []} | {:warnings, [{:create_user, 1, [:unknown_effect]}]}
  """
  @spec validate(module()) :: {:ok, []} | {:warnings, [{atom(), arity(), [atom()]}]}
  def validate(module) do
    known = MapSet.new(@known_effects)

    warnings =
      list(module)
      |> Enum.flat_map(fn {name, arity, effects} ->
        unknown = Enum.reject(effects, &MapSet.member?(known, &1))

        case unknown do
          [] -> []
          unknown_effects -> [{name, arity, unknown_effects}]
        end
      end)

    case warnings do
      [] -> {:ok, []}
      warnings -> {:warnings, warnings}
    end
  end

  # ============================================
  # Effect Composition
  # ============================================

  @doc """
  Combines side effects from multiple sources.

  ## Examples

      FnTypes.SideEffects.combine([:db_read], [:cache])
      #=> [:db_read, :cache]

      FnTypes.SideEffects.combine([:pure], [:db_write])
      #=> [:db_write]  # :pure is removed when combined with other effects
  """
  @spec combine([effect()], [effect()]) :: [effect()]
  def combine(effects1, effects2) do
    combined = Enum.uniq(effects1 ++ effects2)

    # Remove :pure if there are other effects
    case combined do
      [:pure] -> [:pure]
      effects -> Enum.reject(effects, &(&1 == :pure))
    end
  end

  @doc """
  Classifies side effects by category.

  ## Examples

      FnTypes.SideEffects.classify([:db_read, :db_write, :email])
      #=> %{
        database: [:db_read, :db_write],
        external: [:email],
        other: []
      }
  """
  @spec classify([effect()]) :: %{database: [effect()], external: [effect()], other: [effect()]}
  def classify(effects) do
    database = [:db_read, :db_write]
    external = [:http, :email, :external_api]

    %{
      database: Enum.filter(effects, &(&1 in database)),
      external: Enum.filter(effects, &(&1 in external)),
      other: Enum.reject(effects, &(&1 in database or &1 in external))
    }
  end
end
