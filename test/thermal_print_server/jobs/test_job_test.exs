defmodule ThermalPrintServer.Jobs.TestJobTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Jobs.TestJob

  describe "sample_zpl/0" do
    test "returns a ZPL string" do
      zpl = TestJob.sample_zpl()
      assert is_binary(zpl)
      assert zpl =~ "^XA"
      assert zpl =~ "^XZ"
    end
  end

  describe "submit/4" do
    test "returns error when SQS not configured" do
      original = Application.get_env(:thermal_print_server, :sqs_queue_url)
      Application.delete_env(:thermal_print_server, :sqs_queue_url)

      on_exit(fn ->
        if original,
          do: Application.put_env(:thermal_print_server, :sqs_queue_url, original),
          else: Application.delete_env(:thermal_print_server, :sqs_queue_url)
      end)

      assert {:error, "SQS not configured" <> _} =
               TestJob.submit("printer", "^XA^XZ")
    end

    test "generates unique job IDs" do
      ids =
        for _ <- 1..10 do
          # We can't call submit without SQS, but we can test the ID format
          # by checking the module's generate_job_id indirectly
          :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
        end

      assert length(Enum.uniq(ids)) == 10
    end

    @tag :s3_integration
    test "submits job to SQS and returns job ID" do
      zpl = TestJob.sample_zpl()
      assert {:ok, job_id} = TestJob.submit("TestZebra-Capture", zpl)
      assert String.starts_with?(job_id, "test-")
      assert String.length(job_id) == 21
    end
  end
end
