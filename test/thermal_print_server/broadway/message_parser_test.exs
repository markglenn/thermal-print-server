defmodule ThermalPrintServer.Broadway.MessageParserTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Broadway.MessageParser

  @valid_message %{
    "jobId" => "abc-123",
    "chunkIndex" => 0,
    "totalChunks" => 1,
    "printer" => "warehouse-dock3",
    "zpl" => "^XA^XZ",
    "copies" => 2,
    "signature" => "deadbeef",
    "metadata" => %{
      "labelId" => "lbl-1",
      "labelVersion" => 3,
      "labelName" => "Shipping Label"
    }
  }

  test "parses a valid message" do
    json = Jason.encode!(@valid_message)
    assert {:ok, parsed} = MessageParser.parse(json)

    assert parsed.job_id == "abc-123"
    assert parsed.chunk_index == 0
    assert parsed.total_chunks == 1
    assert parsed.printer == "warehouse-dock3"
    assert parsed.zpl == "^XA^XZ"
    assert parsed.copies == 2
    assert parsed.signature == "deadbeef"
    assert parsed.metadata.label_id == "lbl-1"
    assert parsed.metadata.label_version == 3
    assert parsed.metadata.label_name == "Shipping Label"
  end

  test "defaults copies to 1 when omitted" do
    json = @valid_message |> Map.delete("copies") |> Jason.encode!()
    assert {:ok, parsed} = MessageParser.parse(json)
    assert parsed.copies == 1
  end

  test "handles missing metadata gracefully" do
    json = @valid_message |> Map.delete("metadata") |> Jason.encode!()
    assert {:ok, parsed} = MessageParser.parse(json)
    assert parsed.metadata.label_id == nil
  end

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
