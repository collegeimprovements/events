defprotocol OmCrud.Executable do
  @moduledoc """
  Protocol for executable CRUD tokens.

  All token types (Multi, Merge, Query) implement this protocol
  for consistent behavior and unified execution via `OmCrud.run/1`.

  ## Implementations

  - `OmCrud.Multi` - Transaction composition
  - `OmCrud.Merge` - PostgreSQL MERGE operations

  ## Usage

      # All tokens follow the same pattern: build → execute
      Multi.new()
      |> Multi.create(:user, User, attrs)
      |> OmCrud.run()

      User
      |> Merge.new(data)
      |> Merge.match_on(:email)
      |> OmCrud.run()
  """

  @doc """
  Execute the token and return a result tuple.

  ## Options

  Common options supported by all implementations:
  - `:timeout` - Operation timeout in milliseconds
  - `:prefix` - Database schema prefix

  Implementation-specific options are documented in each module.

  ## Returns

  - `{:ok, result}` - Success with the operation result
  - `{:error, reason}` - Failure with error reason

  For transactions (Multi), errors include additional context:
  - `{:error, failed_operation, failed_value, changes_so_far}`
  """
  @spec execute(t(), keyword()) :: {:ok, any()} | {:error, any()}
  def execute(token, opts \\ [])
end

defprotocol OmCrud.Validatable do
  @moduledoc """
  Protocol for validating token configuration before execution.

  Tokens can implement this to catch configuration errors early,
  before hitting the database.

  ## Usage

      case Validatable.validate(merge_token) do
        :ok -> OmCrud.run(merge_token)
        {:error, errors} -> {:error, {:invalid_token, errors}}
      end
  """

  @doc """
  Validate the token configuration.

  Returns `:ok` if valid, or `{:error, errors}` with a list of
  error messages describing the validation failures.
  """
  @spec validate(t()) :: :ok | {:error, [String.t()]}
  def validate(token)
end

defprotocol OmCrud.Debuggable do
  @moduledoc """
  Protocol for debugging and inspecting tokens.

  Provides a structured representation of the token for debugging,
  logging, and error reporting.
  """

  @doc """
  Convert the token to a debug-friendly map representation.

  The returned map should include:
  - `:type` - The token type (e.g., `:multi`, `:merge`, `:query`)
  - Key configuration details relevant to the token type
  """
  @spec to_debug(t()) :: map()
  def to_debug(token)
end
