defmodule ThermalPrintServer.Jobs.VerifierTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Jobs.Verifier

  @secret "test-signing-secret"

  defp sign(job_id, chunk_index, zpl) do
    :crypto.mac(:hmac, :sha256, @secret, [job_id, Integer.to_string(chunk_index), zpl])
    |> Base.encode16(case: :lower)
  end

  test "verifies a valid signature" do
    job_id = "job-123"
    chunk_index = 0
    zpl = "^XA^FO50,50^ADN,36,20^FDHello^FS^XZ"
    signature = sign(job_id, chunk_index, zpl)

    assert Verifier.do_verify(@secret, job_id, chunk_index, zpl, signature)
  end

  test "rejects an invalid signature" do
    refute Verifier.do_verify(@secret, "job-123", 0, "^XA^XZ", "bad-signature")
  end

  test "rejects when zpl has been tampered with" do
    zpl = "^XA^XZ"
    signature = sign("job-123", 0, zpl)

    refute Verifier.do_verify(@secret, "job-123", 0, "^XA^TAMPERED^XZ", signature)
  end

  test "rejects when chunk_index differs" do
    signature = sign("job-123", 0, "^XA^XZ")

    refute Verifier.do_verify(@secret, "job-123", 1, "^XA^XZ", signature)
  end

  test "rejects when job_id differs" do
    signature = sign("job-123", 0, "^XA^XZ")

    refute Verifier.do_verify(@secret, "job-456", 0, "^XA^XZ", signature)
  end
end
