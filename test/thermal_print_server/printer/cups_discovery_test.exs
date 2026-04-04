defmodule ThermalPrintServer.Printer.CupsDiscoveryTest do
  use ExUnit.Case, async: true

  alias ThermalPrintServer.Printer.CupsDiscovery

  test "returns error when CUPS is unreachable" do
    assert {:error, _reason} = CupsDiscovery.discover("ipp://localhost:19999")
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
