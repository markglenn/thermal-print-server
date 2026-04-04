defmodule ThermalPrintServer.Broadway.MessageParserTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Broadway.MessageParser

  @valid_message %{
    "jobId" => "abc-123",
    "chunkIndex" => 0,
    "totalChunks" => 1,
    "printer" => "warehouse-dock3",
    "data" => "^XA^XZ",
    "contentType" => "application/vnd.zebra.zpl",
    "copies" => 2,
    "metadata" => %{
      "labelId" => "lbl-1",
      "labelVersion" => 3,
      "labelName" => "Shipping Label"
    }
  }

  describe "parse/1 — valid messages" do
    test "parses a valid message with all fields" do
      json = Jason.encode!(@valid_message)
      assert {:ok, parsed} = MessageParser.parse(json)

      assert parsed.job_id == "abc-123"
      assert parsed.chunk_index == 0
      assert parsed.total_chunks == 1
      assert parsed.printer == "warehouse-dock3"
      assert parsed.data == "^XA^XZ"
      assert parsed.content_type == "application/vnd.zebra.zpl"
      assert parsed.copies == 2
      assert parsed.metadata.label_id == "lbl-1"
      assert parsed.metadata.label_version == 3
      assert parsed.metadata.label_name == "Shipping Label"
    end

    test "defaults copies to 1 when omitted" do
      json = @valid_message |> Map.delete("copies") |> Jason.encode!()
      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.copies == 1
    end

    test "defaults content type to ZPL when omitted" do
      json = @valid_message |> Map.delete("contentType") |> Jason.encode!()
      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.content_type == "application/vnd.zebra.zpl"
    end

    test "accepts PDF content type" do
      json =
        @valid_message
        |> Map.put("contentType", "application/pdf")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.content_type == "application/pdf"
    end

    test "handles missing metadata gracefully" do
      json = @valid_message |> Map.delete("metadata") |> Jason.encode!()
      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.metadata.label_id == nil
    end

    test "accepts legacy zpl field for backward compatibility" do
      json =
        @valid_message
        |> Map.delete("data")
        |> Map.delete("contentType")
        |> Map.put("zpl", "^XA^FDlegacy^FS^XZ")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.data == "^XA^FDlegacy^FS^XZ"
      assert parsed.content_type == "application/vnd.zebra.zpl"
    end

    test "accepts s3Key instead of inline data" do
      json =
        @valid_message
        |> Map.delete("data")
        |> Map.put("s3Key", "print-jobs/abc-123.zpl.gz")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.s3_key == "print-jobs/abc-123.zpl.gz"
      assert parsed.data == nil
    end

    test "prefers data over legacy zpl when both present" do
      json =
        @valid_message
        |> Map.put("zpl", "old")
        |> Map.put("data", "new")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.data == "new"
    end
  end

  describe "parse/1 — invalid messages" do
    test "rejects invalid JSON" do
      assert {:error, "invalid JSON"} = MessageParser.parse("not json")
    end

    test "rejects non-object JSON" do
      assert {:error, "expected JSON object"} = MessageParser.parse("[1,2,3]")
    end

    test "rejects missing required fields" do
      json = Jason.encode!(%{"jobId" => "x"})
      assert {:error, "missing required fields: " <> _} = MessageParser.parse(json)
    end

    test "rejects missing data, s3Key, and zpl fields" do
      json =
        @valid_message
        |> Map.delete("data")
        |> Jason.encode!()

      assert {:error, "missing required field: data or s3Key"} = MessageParser.parse(json)
    end

    test "rejects invalid content type" do
      json =
        @valid_message
        |> Map.put("contentType", "text/html")
        |> Jason.encode!()

      assert {:error, "contentType must be one of: " <> _} = MessageParser.parse(json)
    end

    test "rejects negative chunkIndex" do
      json = @valid_message |> Map.put("chunkIndex", -1) |> Jason.encode!()
      assert {:error, "chunkIndex must be a non-negative integer"} = MessageParser.parse(json)
    end

    test "rejects zero totalChunks" do
      json = @valid_message |> Map.put("totalChunks", 0) |> Jason.encode!()
      assert {:error, "totalChunks must be a positive integer"} = MessageParser.parse(json)
    end

    test "rejects zero copies" do
      json = @valid_message |> Map.put("copies", 0) |> Jason.encode!()
      assert {:error, "copies must be a positive integer"} = MessageParser.parse(json)
    end
  end
end
