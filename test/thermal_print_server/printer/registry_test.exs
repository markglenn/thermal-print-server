defmodule ThermalPrintServer.Printer.RegistryTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Printer.Registry

  @test_printers %{
    "warehouse-dock3" => %{uri: "ipp://10.0.1.50:631/ipp/print"},
    "shipping-station" => %{uri: "ipp://10.0.1.51:631/ipp/print"}
  }

  setup do
    # Save original config and set test printers
    original = Application.get_env(:thermal_print_server, :printers)
    Application.put_env(:thermal_print_server, :printers, @test_printers)

    # Restart the registry so it picks up the new config
    pid = GenServer.whereis(Registry)
    if pid, do: GenServer.stop(pid)

    # Wait for supervisor to restart it
    Process.sleep(50)

    on_exit(fn ->
      Application.put_env(:thermal_print_server, :printers, original)
    end)

    :ok
  end

  test "looks up an existing printer" do
    assert {:ok, config} = Registry.lookup("warehouse-dock3")
    assert config.uri == "ipp://10.0.1.50:631/ipp/print"
    assert config.name == "warehouse-dock3"
  end

  test "returns error for unknown printer" do
    assert {:error, :not_found} = Registry.lookup("nonexistent")
  end

  test "lists all printers" do
    printers = Registry.list_all()
    assert length(printers) == 2
    names = Enum.map(printers, & &1.name) |> Enum.sort()
    assert names == ["shipping-station", "warehouse-dock3"]
  end
end
