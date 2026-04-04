defmodule ThermalPrintServer.Broadway.MessageParser do
  @moduledoc """
  Parses and validates SQS message JSON into structured print job data.
  """

  @required_keys ~w(jobId chunkIndex totalChunks printer)
  @valid_content_types ~w(application/vnd.zebra.zpl application/pdf)

  @type parsed :: %{
          job_id: String.t(),
          chunk_index: non_neg_integer(),
          total_chunks: pos_integer(),
          printer: String.t(),
          data: String.t(),
          content_type: String.t(),
          copies: pos_integer(),
          metadata: %{
            label_id: String.t(),
            label_version: pos_integer(),
            label_name: String.t()
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

  # Must have either "data" or legacy "zpl" field
  defp validate_data_field(map) do
    cond do
      Map.has_key?(map, "data") and is_binary(map["data"]) -> :ok
      Map.has_key?(map, "zpl") and is_binary(map["zpl"]) -> :ok
      true -> {:error, "missing required field: data"}
    end
  end

  @spec validate_types(map()) :: :ok | {:error, String.t()}
  defp validate_types(map) do
    cond do
      not is_binary(map["jobId"]) ->
        {:error, "jobId must be a string"}

      not is_integer(map["chunkIndex"]) or map["chunkIndex"] < 0 ->
        {:error, "chunkIndex must be a non-negative integer"}

      not is_integer(map["totalChunks"]) or map["totalChunks"] < 1 ->
        {:error, "totalChunks must be a positive integer"}

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
      chunk_index: map["chunkIndex"],
      total_chunks: map["totalChunks"],
      printer: map["printer"],
      data: data,
      content_type: content_type,
      copies: map["copies"] || 1,
      metadata: %{
        label_id: metadata["labelId"],
        label_version: metadata["labelVersion"],
        label_name: metadata["labelName"]
      }
    }
  end
end
