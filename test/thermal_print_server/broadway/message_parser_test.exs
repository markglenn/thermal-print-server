defmodule ThermalPrintServer.Broadway.MessageParserTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Broadway.MessageParser

  @valid_message %{
    "jobId" => "abc-123",
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

    test "parses replyToQueueUrl when present" do
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/thermal-replies"
      json = @valid_message |> Map.put("replyToQueueUrl", url) |> Jason.encode!()
      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.reply_to_queue_url == url
    end

    test "reply_to_queue_url defaults to nil when omitted" do
      json = Jason.encode!(@valid_message)
      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.reply_to_queue_url == nil
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

    test "rejects zero copies" do
      json = @valid_message |> Map.put("copies", 0) |> Jason.encode!()
      assert {:error, "copies must be a positive integer"} = MessageParser.parse(json)
    end

    test "rejects negative copies" do
      json = @valid_message |> Map.put("copies", -1) |> Jason.encode!()
      assert {:error, "copies must be a positive integer"} = MessageParser.parse(json)
    end

    test "rejects non-integer copies" do
      json = @valid_message |> Map.put("copies", "five") |> Jason.encode!()
      assert {:error, "copies must be a positive integer"} = MessageParser.parse(json)
    end

    test "rejects non-string jobId" do
      json = @valid_message |> Map.put("jobId", 123) |> Jason.encode!()
      assert {:error, "jobId must be a string"} = MessageParser.parse(json)
    end

    test "rejects non-string printer" do
      json = @valid_message |> Map.put("printer", 456) |> Jason.encode!()
      assert {:error, "printer must be a string"} = MessageParser.parse(json)
    end

    test "rejects empty object" do
      assert {:error, "missing required fields: jobId, printer"} = MessageParser.parse("{}")
    end

    test "rejects non-binary data field" do
      json = @valid_message |> Map.put("data", 123) |> Jason.encode!()
      assert {:error, "missing required field: data or s3Key"} = MessageParser.parse(json)
    end

    test "rejects non-binary s3Key field" do
      json =
        @valid_message
        |> Map.delete("data")
        |> Map.put("s3Key", 123)
        |> Jason.encode!()

      assert {:error, "missing required field: data or s3Key"} = MessageParser.parse(json)
    end

    test "rejects non-string replyToQueueUrl" do
      json = @valid_message |> Map.put("replyToQueueUrl", 42) |> Jason.encode!()
      assert {:error, "replyToQueueUrl must be a string"} = MessageParser.parse(json)
    end
  end

  describe "parse/1 — metadata fields" do
    test "parses labelSize and dpmm from metadata" do
      json =
        @valid_message
        |> put_in(["metadata", "labelSize"], "4x6")
        |> put_in(["metadata", "dpmm"], "8dpmm")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.metadata.label_size == "4x6"
      assert parsed.metadata.dpmm == "8dpmm"
    end

    test "metadata fields default to nil" do
      json =
        @valid_message
        |> Map.put("metadata", %{})
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.metadata.label_id == nil
      assert parsed.metadata.label_version == nil
      assert parsed.metadata.label_name == nil
      assert parsed.metadata.label_size == nil
      assert parsed.metadata.dpmm == nil
    end
  end

  describe "parse/1 — ignores unknown fields" do
    test "extra fields are silently ignored" do
      json =
        @valid_message
        |> Map.put("chunkIndex", 0)
        |> Map.put("totalChunks", 1)
        |> Map.put("extraField", "whatever")
        |> Jason.encode!()

      assert {:ok, parsed} = MessageParser.parse(json)
      assert parsed.job_id == "abc-123"
    end
  end
end
