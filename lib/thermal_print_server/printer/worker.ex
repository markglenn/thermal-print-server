defmodule ThermalPrintServer.Printer.Worker do
  @moduledoc """
  Sends print data to printers via IPP (Hippy).
  Supports both ZPL and PDF content types.
  """

  require Logger

  # 30-second timeout for IPP operations
  @print_timeout 30_000

  @spec print(map(), String.t(), String.t(), pos_integer()) ::
          {:ok, %{cups_job_id: pos_integer() | nil}} | {:error, term()}
  def print(%{uri: uri}, data, content_type, copies) do
    Logger.info("Sending #{content_type} print job to #{uri} (#{copies} copies)")

    job_opts = [job_name: "Thermal", copies: copies]

    job_opts =
      case content_type do
        "application/vnd.zebra.zpl" -> job_opts
        mime -> Keyword.put(job_opts, :document_format, mime)
      end

    task =
      Task.async(fn ->
        Hippy.Operation.PrintJob.new(uri, data, job_opts)
        |> Hippy.send_operation()
      end)

    case Task.yield(task, @print_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Hippy.Response{status_code: status_code} = resp}} ->
        handle_ipp_response(uri, status_code, resp)

      {:ok, {:error, reason}} ->
        Logger.error("Print failed to #{uri}: #{inspect(reason)}")
        {:error, reason}

      nil ->
        Logger.error("Print timed out after #{@print_timeout}ms to #{uri}")
        {:error, :timeout}
    end
  end

  # IPP returns HTTP 200 even when the printer rejects the job — the real
  # outcome is in the response's `status-code`. Anything outside the
  # `successful_*` family means CUPS didn't accept the submission.
  defp handle_ipp_response(uri, status_code, %Hippy.Response{
         request_id: request_id,
         job_attributes: attrs
       }) do
    cond do
      ipp_successful?(status_code) ->
        cups_job_id = extract_job_id(attrs)

        Logger.info(
          "Print job sent to #{uri} (request_id=#{request_id}, cups_job_id=#{inspect(cups_job_id)}, status=#{status_code})"
        )

        {:ok, %{cups_job_id: cups_job_id}}

      true ->
        Logger.error("Print rejected by #{uri}: status=#{inspect(status_code)}")
        {:error, {:ipp_error, status_code}}
    end
  end

  defp ipp_successful?(status_code) when is_atom(status_code) do
    status_code |> Atom.to_string() |> String.starts_with?("successful")
  end

  defp ipp_successful?(_), do: false

  # Hippy returns job_attributes as a list of attribute *groups*, each group
  # itself a list of {type, name, value} tuples. Walk the nested structure.
  defp extract_job_id(attrs) do
    attrs
    |> List.flatten()
    |> Enum.find_value(fn
      {_type, "job-id", value} when is_integer(value) -> value
      _ -> nil
    end)
  end
end
