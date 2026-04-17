defmodule ThermalPrintServer.Printer.CupsDiscovery do
  @moduledoc """
  Discovers printers from a CUPS server via IPP using Hippy.
  Fetches printer list, then enriches each with media/resolution capabilities.
  """

  require Logger

  @list_attributes [
    "printer-name",
    "printer-uri-supported",
    "printer-state",
    "printer-location",
    "printer-info"
  ]

  # 10-second timeout for CUPS IPP operations
  @ipp_timeout 10_000

  @spec discover(String.t()) :: {:ok, map()} | {:error, term()}
  def discover(cups_uri) do
    Logger.info("Discovering printers from CUPS at #{cups_uri}")

    with {:ok, printers} <- list_printers(cups_uri) do
      enriched = enrich_all(printers)

      Logger.info("Discovered #{map_size(enriched)} printer(s) from CUPS")
      {:ok, enriched}
    end
  end

  defp list_printers(cups_uri) do
    ipp_request(fn ->
      Hippy.Operation.GetPrinters.new(cups_uri, requested_attributes: @list_attributes)
      |> Hippy.send_operation()
    end)
    |> case do
      {:ok, %Hippy.Response{printer_attributes: attrs}} ->
        attr_map = attrs_to_map(attrs)
        names = List.wrap(attr_map["printer-name"])
        uris = List.wrap(attr_map["printer-uri-supported"])

        printers =
          names
          |> Enum.zip(uris)
          |> Enum.map(fn {name, uri} ->
            uri_str = if is_struct(uri, URI), do: URI.to_string(uri), else: to_string(uri)
            {name, %{uri: uri_str}}
          end)
          |> Map.new()

        {:ok, printers}

      {:error, reason} ->
        Logger.error("CUPS printer discovery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp enrich_all(printers) do
    Map.new(printers, fn {name, config} ->
      {name, enrich(config)}
    end)
  end

  defp enrich(%{uri: uri} = config) do
    case get_capabilities(uri) do
      {:ok, caps} -> Map.merge(config, caps)
      {:error, _} -> config
    end
  end

  defp get_capabilities(uri) do
    ipp_request(fn ->
      Hippy.Operation.GetPrinterAttributes.new(uri)
      |> Hippy.send_operation()
    end)
    |> case do
      {:ok, %Hippy.Response{printer_attributes: attrs}} ->
        attr_map = attrs_to_map(attrs)
        {:ok, extract_capabilities(attr_map)}

      {:error, reason} ->
        Logger.warning("Failed to get attributes for #{uri}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_capabilities(attrs) do
    %{}
    |> maybe_put(:state, parse_state(attrs["printer-state"]))
    |> maybe_put(:state_reasons, parse_state_reasons(attrs["printer-state-reasons"]))
    |> maybe_put(:state_message, parse_state_message(attrs["printer-state-message"]))
    |> maybe_put(:info, attrs["printer-info"])
    |> maybe_put(:location, attrs["printer-location"])
    |> maybe_put(:resolution, parse_resolution(attrs["printer-resolution-supported"]))
    |> maybe_put(:resolution_default, parse_resolution(attrs["printer-resolution-default"]))
    |> maybe_put(:media_default, attrs["media-default"])
    |> maybe_put(:media_ready, attrs["media-ready"])
  end

  # Hippy returns PrinterState enum atom; dashboard uses IPP integer codes.
  defp parse_state(:idle), do: 3
  defp parse_state(:processing), do: 4
  defp parse_state(:stopped), do: 5
  defp parse_state(_), do: nil

  # "none" is CUPS's way of saying no active reason; drop it so callers can
  # treat a populated list as "there's a problem."
  defp parse_state_reasons(nil), do: nil
  defp parse_state_reasons("none"), do: nil
  defp parse_state_reasons(""), do: nil
  defp parse_state_reasons(reason) when is_binary(reason), do: [reason]

  defp parse_state_reasons(reasons) when is_list(reasons) do
    case Enum.reject(reasons, &(&1 in [nil, "", "none"])) do
      [] -> nil
      filtered -> filtered
    end
  end

  defp parse_state_reasons(_), do: nil

  defp parse_state_message(nil), do: nil
  defp parse_state_message(""), do: nil
  defp parse_state_message(msg) when is_binary(msg), do: msg
  defp parse_state_message(_), do: nil

  defp parse_resolution(%Hippy.PrintResolution{xfeed: x, feed: y, unit: unit}) do
    %{x: x, y: y, unit: unit}
  end

  defp parse_resolution(resolutions) when is_list(resolutions) do
    Enum.map(resolutions, &parse_resolution/1)
  end

  defp parse_resolution(_), do: nil

  defp attrs_to_map(attrs) do
    Enum.reduce(attrs, %{}, fn {_type, name, value}, acc ->
      Map.put(acc, name, value)
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp ipp_request(fun) do
    task = Task.async(fun)

    case Task.yield(task, @ipp_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
end
