defmodule Events.Errors.Mappers.Aws do
  @moduledoc """
  Error mapper for AWS/ExAws errors.

  Handles normalization of errors from ExAws operations.
  """

  alias Events.Errors.Error

  @doc """
  Normalizes ExAws errors.

  ## Examples

      iex> Aws.normalize({:error, {:http_error, 404, %{body: "NoSuchKey"}}})
      %Error{type: :not_found, code: :no_such_key}
  """
  @spec normalize(term()) :: Error.t()
  def normalize({:error, {:http_error, status_code, response}}) do
    error_code = extract_error_code(response)
    {type, code, message} = map_aws_error(error_code, status_code)

    Error.new(type, code,
      message: message,
      details: %{
        status_code: status_code,
        aws_error_code: error_code,
        response: response
      },
      source: :aws
    )
  end

  def normalize({:error, {:aws_error, error_code}}) do
    {type, code, message} = map_aws_error(error_code)

    Error.new(type, code,
      message: message,
      details: %{aws_error_code: error_code},
      source: :aws
    )
  end

  def normalize({:error, reason}) do
    Error.new(:external, :aws_error,
      message: "AWS service error",
      details: %{reason: reason},
      source: :aws
    )
  end

  ## AWS Error Mappings

  # S3 Errors
  defp map_aws_error("NoSuchKey", _status),
    do: {:not_found, :no_such_key, "The specified key does not exist"}

  defp map_aws_error("NoSuchBucket", _status),
    do: {:not_found, :no_such_bucket, "The specified bucket does not exist"}

  defp map_aws_error("AccessDenied", _status),
    do: {:forbidden, :access_denied, "Access Denied"}

  defp map_aws_error("InvalidBucketName", _status),
    do: {:bad_request, :invalid_bucket_name, "Invalid bucket name"}

  defp map_aws_error("KeyTooLong", _status),
    do: {:bad_request, :key_too_long, "Key too long"}

  defp map_aws_error("BucketAlreadyExists", _status),
    do: {:conflict, :bucket_already_exists, "Bucket already exists"}

  defp map_aws_error("BucketAlreadyOwnedByYou", _status),
    do: {:conflict, :bucket_already_owned, "Bucket already owned by you"}

  defp map_aws_error("BucketNotEmpty", _status),
    do: {:conflict, :bucket_not_empty, "Bucket is not empty"}

  defp map_aws_error("TooManyBuckets", _status),
    do: {:rate_limit, :too_many_buckets, "Too many buckets"}

  defp map_aws_error("SlowDown", _status),
    do: {:rate_limit, :slow_down, "Please reduce your request rate"}

  defp map_aws_error("RequestTimeout", _status),
    do: {:timeout, :request_timeout, "Request timeout"}

  defp map_aws_error("ServiceUnavailable", _status),
    do: {:service_unavailable, :service_unavailable, "Service temporarily unavailable"}

  defp map_aws_error("InternalError", _status),
    do: {:external, :internal_error, "AWS internal error"}

  # DynamoDB Errors
  defp map_aws_error("ResourceNotFoundException", _status),
    do: {:not_found, :resource_not_found, "Resource not found"}

  defp map_aws_error("ConditionalCheckFailedException", _status),
    do: {:conflict, :conditional_check_failed, "Conditional check failed"}

  defp map_aws_error("ProvisionedThroughputExceededException", _status),
    do: {:rate_limit, :throughput_exceeded, "Provisioned throughput exceeded"}

  defp map_aws_error("ResourceInUseException", _status),
    do: {:conflict, :resource_in_use, "Resource is in use"}

  defp map_aws_error("ValidationException", _status),
    do: {:validation, :validation_error, "Validation error"}

  # SQS Errors
  defp map_aws_error("QueueDoesNotExist", _status),
    do: {:not_found, :queue_not_found, "Queue does not exist"}

  defp map_aws_error("QueueDeletedRecently", _status),
    do: {:conflict, :queue_deleted_recently, "Queue was deleted recently"}

  defp map_aws_error("MessageNotInflight", _status),
    do: {:bad_request, :message_not_inflight, "Message is not in flight"}

  defp map_aws_error("ReceiptHandleIsInvalid", _status),
    do: {:bad_request, :invalid_receipt_handle, "Receipt handle is invalid"}

  # SNS Errors
  defp map_aws_error("TopicDoesNotExist", _status),
    do: {:not_found, :topic_not_found, "Topic does not exist"}

  defp map_aws_error("SubscriptionDoesNotExist", _status),
    do: {:not_found, :subscription_not_found, "Subscription does not exist"}

  defp map_aws_error("InvalidParameter", _status),
    do: {:bad_request, :invalid_parameter, "Invalid parameter"}

  # General AWS Errors
  defp map_aws_error("Throttling", _status),
    do: {:rate_limit, :throttling, "Request throttled"}

  defp map_aws_error("InvalidAccessKeyId", _status),
    do: {:unauthorized, :invalid_access_key, "Invalid access key"}

  defp map_aws_error("SignatureDoesNotMatch", _status),
    do: {:unauthorized, :signature_mismatch, "Signature does not match"}

  defp map_aws_error("ExpiredToken", _status),
    do: {:unauthorized, :token_expired, "Security token expired"}

  defp map_aws_error("MissingAuthenticationToken", _status),
    do: {:unauthorized, :missing_token, "Missing authentication token"}

  # Fallback based on status code
  defp map_aws_error(_error_code, 404),
    do: {:not_found, :not_found, "Resource not found"}

  defp map_aws_error(_error_code, 403),
    do: {:forbidden, :forbidden, "Access forbidden"}

  defp map_aws_error(_error_code, 401),
    do: {:unauthorized, :unauthorized, "Unauthorized"}

  defp map_aws_error(_error_code, 409),
    do: {:conflict, :conflict, "Resource conflict"}

  defp map_aws_error(_error_code, 429),
    do: {:rate_limit, :rate_limit, "Rate limit exceeded"}

  defp map_aws_error(_error_code, status) when status >= 500,
    do: {:external, :server_error, "AWS server error"}

  defp map_aws_error(error_code, _status),
    do: {:external, :aws_error, "AWS error: #{error_code}"}

  # Overload for when status is not provided
  defp map_aws_error(error_code) do
    {type, code, message} = map_aws_error(error_code, nil)
    {type, code, message}
  end

  ## Helpers

  defp extract_error_code(%{body: body}) when is_binary(body) do
    # Try to extract error code from XML response
    case Regex.run(~r/<Code>([^<]+)<\/Code>/, body) do
      [_, code] -> code
      _ -> "UnknownError"
    end
  end

  defp extract_error_code(%{body: %{"__type" => type}}) do
    # Handle JSON errors (DynamoDB, etc.)
    type
    |> String.split("#")
    |> List.last()
  end

  defp extract_error_code(%{body: %{"Code" => code}}), do: code

  defp extract_error_code(_), do: "UnknownError"
end
