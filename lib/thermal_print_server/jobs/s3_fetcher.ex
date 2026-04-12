defmodule ThermalPrintServer.Jobs.S3Fetcher do
  @moduledoc """
  Fetches and decompresses print job data from S3.
  Used for large jobs that exceed the SQS inline threshold (200 KB).
  The client gzips the data before uploading.
  """

  require Logger

  # 30-second timeout for S3 fetches
  @fetch_timeout 30_000

  @spec fetch(String.t()) :: {:ok, binary()} | {:error, term()}
  def fetch(s3_key) do
    case Application.get_env(:thermal_print_server, :print_bucket) do
      nil ->
        Logger.error("S3 fetch requested but PRINT_BUCKET is not configured")
        {:error, "PRINT_BUCKET not configured"}

      bucket ->
        do_fetch(bucket, s3_key)
    end
  end

  defp do_fetch(bucket, s3_key) do
    Logger.info("Fetching print data from S3: #{bucket}/#{s3_key}")

    bucket
    |> ExAws.S3.get_object(s3_key)
    |> ExAws.request(timeout: @fetch_timeout, recv_timeout: @fetch_timeout)
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
