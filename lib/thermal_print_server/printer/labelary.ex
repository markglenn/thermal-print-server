defmodule ThermalPrintServer.Printer.Labelary do
  @moduledoc """
  Renders ZPL to PNG using the Labelary API.
  Used by virtual printers for testing/preview.
  """

  require Logger

  @base_url "http://api.labelary.com/v1/printers"
  @default_dpmm "8dpmm"
  @default_size "4x6"

  @spec render(String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def render(zpl, opts \\ []) do
    dpmm = Keyword.get(opts, :dpmm, @default_dpmm)
    size = Keyword.get(opts, :size, @default_size)
    index = Keyword.get(opts, :index, 0)

    url = "#{@base_url}/#{dpmm}/labels/#{size}/#{index}/"

    Logger.info("Rendering ZPL via Labelary (#{dpmm}, #{size})")

    case Req.post(url, body: zpl, headers: [{"accept", "image/png"}], retry: :transient, max_retries: 3) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("Labelary returned #{status}: #{inspect(body)}")
        {:error, "labelary returned #{status}"}

      {:error, reason} ->
        Logger.error("Labelary request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @max_preview_pages 10

  @spec render_all(String.t(), keyword()) :: {:ok, [binary()]} | {:error, term()}
  def render_all(zpl, opts \\ []) do
    count = zpl |> String.upcase() |> String.split("^XA") |> length() |> Kernel.-(1) |> max(1)
    count = min(count, @max_preview_pages)

    0..(count - 1)
    |> Enum.reduce_while({:ok, []}, fn index, {:ok, acc} ->
      case render(zpl, Keyword.put(opts, :index, index)) do
        {:ok, png} -> {:cont, {:ok, acc ++ [png]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc """
  Returns a data URI for embedding the rendered PNG in HTML.
  """
  @spec render_data_uri(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render_data_uri(zpl, opts \\ []) do
    case render(zpl, opts) do
      {:ok, png_bytes} ->
        {:ok, "data:image/png;base64," <> Base.encode64(png_bytes)}

      error ->
        error
    end
  end
end
