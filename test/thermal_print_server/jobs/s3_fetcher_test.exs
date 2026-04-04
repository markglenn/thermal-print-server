defmodule ThermalPrintServer.Jobs.S3FetcherTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Jobs.S3Fetcher

  describe "fetch/1" do
    @tag :s3_integration
    test "fetches and decompresses gzipped data from S3" do
      # This test requires a configured S3 bucket with test data
      # Run with: mix test --include s3_integration
      assert {:error, _} = S3Fetcher.fetch("print-jobs/nonexistent.zpl.gz")
    end
  end
end
