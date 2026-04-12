defmodule ThermalPrintServer.Broadway.MessageParser do
  @moduledoc """
  Parses and validates SQS message JSON into structured print job data.
  """

  @required_keys ~w(jobId printer)
  @valid_content_types ~w(application/vnd.zebra.zpl application/pdf)
  # 1 MB max for inline data — larger payloads should use s3Key
  @max_inline_bytes 1_048_576

  @type parsed :: %{
          job_id: String.t(),
          printer: String.t(),
          data: String.t() | nil,
          s3_key: String.t() | nil,
          content_type: String.t(),
          copies: pos_integer(),
          metadata: %{
            label_id: String.t(),
            label_version: pos_integer(),
            label_name: String.t(),
            label_size: String.t() | nil,
            dpmm: String.t() | nil
          }
        }

  @spec parse(String.t()) :: {:ok, parsed()} | {:error, String.t()}
  def parse(json_string) when is_binary(json_string) do
    with {:ok, decoded} <- decode_json(json_string),
         :ok <- validate_required(decoded),
         :ok <- validate_data_field(decoded),
         :ok <- validate_types(decoded) do
      {:ok, to_parsed(decoded)}
    end
  end

  @spec decode_json(String.t()) :: {:ok, map()} | {:error, String.t()}
  defp decode_json(json) do
    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "expected JSON object"}
      {:error, _} -> {:error, "invalid JSON"}
    end
  end

  @spec validate_required(map()) :: :ok | {:error, String.t()}
  defp validate_required(map) do
    missing = Enum.filter(@required_keys, &(not Map.has_key?(map, &1)))

    case missing do
      [] -> :ok
      keys -> {:error, "missing required fields: #{Enum.join(keys, ", ")}"}
    end
  end

  # Must have "data", "s3Key", or legacy "zpl" field
  defp validate_data_field(map) do
    cond do
      Map.has_key?(map, "data") and is_binary(map["data"]) ->
        validate_inline_size(map["data"])

      Map.has_key?(map, "s3Key") and is_binary(map["s3Key"]) ->
        :ok

      Map.has_key?(map, "zpl") and is_binary(map["zpl"]) ->
        validate_inline_size(map["zpl"])

      true ->
        {:error, "missing required field: data or s3Key"}
    end
  end

  defp validate_inline_size(data) when byte_size(data) > @max_inline_bytes do
    {:error, "inline data exceeds #{@max_inline_bytes} byte limit — use s3Key for large payloads"}
  end

  defp validate_inline_size(_data), do: :ok

  @spec validate_types(map()) :: :ok | {:error, String.t()}
  defp validate_types(map) do
    cond do
      not is_binary(map["jobId"]) ->
        {:error, "jobId must be a string"}

      not is_binary(map["printer"]) ->
        {:error, "printer must be a string"}

      Map.has_key?(map, "copies") and (not is_integer(map["copies"]) or map["copies"] < 1) ->
        {:error, "copies must be a positive integer"}

      Map.has_key?(map, "contentType") and map["contentType"] not in @valid_content_types ->
        {:error, "contentType must be one of: #{Enum.join(@valid_content_types, ", ")}"}

      true ->
        :ok
    end
  end

  @spec to_parsed(map()) :: parsed()
  defp to_parsed(map) do
    metadata = map["metadata"] || %{}
    # Support legacy "zpl" field, prefer "data" if both present
    data = map["data"] || map["zpl"]
    # Default to ZPL for backward compatibility
    content_type = map["contentType"] || "application/vnd.zebra.zpl"

    %{
      job_id: map["jobId"],
      printer: map["printer"],
      data: data,
      s3_key: map["s3Key"],
      content_type: content_type,
      copies: map["copies"] || 1,
      metadata: %{
        label_id: metadata["labelId"],
        label_version: metadata["labelVersion"],
        label_name: metadata["labelName"],
        label_size: metadata["labelSize"],
        dpmm: metadata["dpmm"]
      }
    }
  end
end
