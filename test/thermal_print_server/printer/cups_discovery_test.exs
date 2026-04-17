defmodule ThermalPrintServer.Printer.CupsDiscoveryTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Printer.CupsDiscovery

  test "returns error when CUPS is unreachable" do
    assert {:error, _reason} = CupsDiscovery.discover("ipp://localhost:19999")
  end

  describe "parse_state_reasons/1" do
    test "treats nil / empty / \"none\" as no-active-reason" do
      assert CupsDiscovery.parse_state_reasons(nil) == nil
      assert CupsDiscovery.parse_state_reasons("") == nil
      assert CupsDiscovery.parse_state_reasons("none") == nil
    end

    test "wraps a single reason string in a list" do
      assert CupsDiscovery.parse_state_reasons("media-empty") == ["media-empty"]
    end

    test "filters \"none\" / empty entries from a list" do
      assert CupsDiscovery.parse_state_reasons(["none"]) == nil
      assert CupsDiscovery.parse_state_reasons(["paused", "none"]) == ["paused"]

      assert CupsDiscovery.parse_state_reasons(["offline-report", "media-empty"]) ==
               ["offline-report", "media-empty"]
    end

    test "returns nil for unexpected shapes instead of crashing" do
      assert CupsDiscovery.parse_state_reasons(42) == nil
      assert CupsDiscovery.parse_state_reasons(%{}) == nil
    end
  end

  # Integration test — only runs when included: mix test --include cups_integration
  describe "with CUPS server" do
    @describetag :cups_integration

    setup do
      cups_uri = System.get_env("CUPS_URI") || "ipp://localhost:631"
      {:ok, cups_uri: cups_uri}
    end

    test "discovers printers from CUPS", %{cups_uri: cups_uri} do
      assert {:ok, printers} = CupsDiscovery.discover(cups_uri)
      assert is_map(printers)
      assert map_size(printers) > 0

      Enum.each(printers, fn {name, config} ->
        assert is_binary(name)
        assert is_binary(config.uri)
        assert String.starts_with?(config.uri, "ipp://")
      end)
    end
  end
end
