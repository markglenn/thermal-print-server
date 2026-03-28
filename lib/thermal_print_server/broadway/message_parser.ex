defmodule ThermalPrintServer.Broadway.MessageParser do
  @moduledoc """
  Parses and validates SQS message JSON into structured print job data.
  """

  @required_keys ~w(jobId chunkIndex totalChunks printer zpl signature)
  @type parsed :: %{
          job_id: String.t(),
          chunk_index: non_neg_integer(),
          total_chunks: pos_integer(),
          printer: String.t(),
          zpl: String.t(),
          copies: pos_integer(),
          signature: String.t(),
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

      not is_binary(map["zpl"]) ->
        {:error, "zpl must be a string"}

      not is_binary(map["signature"]) ->
        {:error, "signature must be a string"}

      Map.has_key?(map, "copies") and (not is_integer(map["copies"]) or map["copies"] < 1) ->
        {:error, "copies must be a positive integer"}

      true ->
        :ok
    end
  end

  @spec to_parsed(map()) :: parsed()
  defp to_parsed(map) do
    metadata = map["metadata"] || %{}

    %{
      job_id: map["jobId"],
      chunk_index: map["chunkIndex"],
      total_chunks: map["totalChunks"],
      printer: map["printer"],
      zpl: map["zpl"],
      copies: map["copies"] || 1,
      signature: map["signature"],
      metadata: %{
        label_id: metadata["labelId"],
        label_version: metadata["labelVersion"],
        label_name: metadata["labelName"]
      }
    }
  end
end
