defmodule ThermalPrintServer.Jobs.S3Fetcher do
  @moduledoc """
  Fetches and decompresses print job data from S3.
  Used for large jobs that exceed the SQS inline threshold (200 KB).
  The client gzips the data before uploading.
  """

  require Logger

  @spec fetch(String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch(s3_key) do
    bucket = Application.fetch_env!(:thermal_print_server, :print_bucket)

    Logger.info("Fetching print data from S3: #{bucket}/#{s3_key}")

    bucket
    |> ExAws.S3.get_object(s3_key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body}} ->
        decompress(body, s3_key)

      {:error, reason} ->
        Logger.error("S3 fetch failed for #{s3_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp decompress(body, s3_key) do
    if String.ends_with?(s3_key, ".gz") do
      case safe_gunzip(body) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, "decompression failed: #{inspect(reason)}"}
      end
    else
      {:ok, body}
    end
  end

  defp safe_gunzip(data) do
    {:ok, :zlib.gunzip(data)}
  rescue
    e -> {:error, e}
  end
end
