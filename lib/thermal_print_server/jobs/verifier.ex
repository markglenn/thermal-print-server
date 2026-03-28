defmodule ThermalPrintServer.Jobs.Verifier do
  @moduledoc """
  HMAC-SHA256 signature verification for print jobs.

  Signature = HMAC-SHA256(secret, jobId + chunkIndex + zpl)
  """

  @spec verify(String.t(), integer(), String.t(), String.t()) :: boolean()
  def verify(job_id, chunk_index, zpl, signature) do
    secret = Application.fetch_env!(:thermal_print_server, :signing_secret)
    do_verify(secret, job_id, chunk_index, zpl, signature)
  end

  @doc false
  @spec do_verify(String.t(), String.t(), integer(), String.t(), String.t()) :: boolean()
  def do_verify(secret, job_id, chunk_index, zpl, signature) do
    expected =
      :crypto.mac(:hmac, :sha256, secret, [job_id, Integer.to_string(chunk_index), zpl])
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(expected, signature)
  end
end
