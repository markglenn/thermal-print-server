defmodule ThermalPrintServer.Jobs.TestJob do
  @moduledoc """
  Submits test print jobs directly, bypassing SQS and HMAC verification.
  Used for development/testing with virtual printers.
  """

  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.{Registry, Worker}

  @sample_zpl """
  ^XA
  ^FO50,50^A0N,40,40^FDThermal Print Server^FS
  ^FO50,110^A0N,25,25^FDTest Label^FS
  ^FO50,150^A0N,20,20^FD#{DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}^FS
  ^FO50,200^BY3^BCN,80,Y,N,N^FD>:THERMAL001^FS
  ^FO50,320^A0N,18,18^FDThis label was rendered via Labelary^FS
  ^XZ
  """

  @spec sample_zpl() :: String.t()
  def sample_zpl, do: @sample_zpl

  @spec submit(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def submit(printer_name, zpl) do
    job_id = generate_job_id()

    Store.record(job_id, %{
      printer: printer_name,
      label_name: "Test Label",
      status: :printing,
      chunk_index: 0,
      total_chunks: 1,
      zpl: zpl
    })

    broadcast(job_id, %{status: :printing, printer: printer_name})

    Task.start(fn ->
      case Registry.lookup(printer_name) do
        {:ok, printer} ->
          case Worker.print(printer, zpl, 1) do
            {:ok, png_bytes} ->
              attrs = %{
                status: :completed,
                preview_png: Base.encode64(png_bytes)
              }

              Store.record(job_id, attrs)
              broadcast(job_id, attrs)

            :ok ->
              Store.record(job_id, %{status: :completed})
              broadcast(job_id, %{status: :completed})

            {:error, reason} ->
              attrs = %{status: :failed, error: inspect(reason)}
              Store.record(job_id, attrs)
              broadcast(job_id, attrs)
          end

        {:error, :not_found} ->
          attrs = %{status: :failed, error: "unknown printer: #{printer_name}"}
          Store.record(job_id, attrs)
          broadcast(job_id, attrs)
      end
    end)

    {:ok, job_id}
  end

  @spec generate_job_id() :: String.t()
  defp generate_job_id do
    "test-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @spec broadcast(String.t(), map()) :: :ok | {:error, term()}
  defp broadcast(job_id, attrs) do
    Phoenix.PubSub.broadcast(
      ThermalPrintServer.PubSub,
      "print_jobs",
      {:job_updated, job_id, attrs}
    )
  end
end
