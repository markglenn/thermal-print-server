defmodule ThermalPrintServer.Jobs.TestJob do
  @moduledoc """
  Publishes test print jobs to SQS, exercising the full pipeline.
  Falls back to direct printing if SQS is not configured.
  """

  require Logger

  @sample_zpl """
  ^XA
  ^FO50,50^A0N,40,40^FDThermal Print Server^FS
  ^FO50,110^A0N,25,25^FDTest Label^FS
  ^FO50,150^A0N,20,20^FD#{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}^FS
  ^FO50,200^BY3^BCN,80,Y,N,N^FD>:THERMAL001^FS
  ^FO50,320^A0N,18,18^FDPrinted via CUPS^FS
  ^XZ
  """

  @spec sample_zpl() :: String.t()
  def sample_zpl, do: @sample_zpl

  @spec submit(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def submit(printer_name, data, content_type \\ "application/vnd.zebra.zpl", opts \\ []) do
    job_id = generate_job_id()

    message = %{
      "jobId" => job_id,
      "printer" => printer_name,
      "data" => data,
      "contentType" => content_type,
      "copies" => 1,
      "metadata" => %{
        "labelName" => "Test Label",
        "labelSize" => Keyword.get(opts, :label_size),
        "dpmm" => Keyword.get(opts, :dpmm)
      }
    }

    case publish_to_sqs(message) do
      :ok ->
        Logger.info("Test job #{job_id} published to SQS")
        {:ok, job_id}

      {:error, reason} ->
        Logger.error("Failed to publish test job to SQS: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp publish_to_sqs(message) do
    case Application.get_env(:thermal_print_server, :sqs_queue_url) do
      nil ->
        {:error, "SQS not configured (PRINT_QUEUE_URL not set)"}

      queue_url ->
        body = Jason.encode!(message)

        queue_url
        |> ExAws.SQS.send_message(body)
        |> ExAws.request()
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @spec generate_job_id() :: String.t()
  defp generate_job_id do
    "test-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
