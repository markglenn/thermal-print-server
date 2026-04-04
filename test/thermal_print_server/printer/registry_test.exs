defmodule ThermalPrintServer.Printer.RegistryTest do
  use ExUnit.Case, async: false

  alias ThermalPrintServer.Printer.Registry

  @test_printers %{
    "warehouse-dock3" => %{uri: "ipp://10.0.1.50:631/ipp/print"},
    "shipping-station" => %{uri: "ipp://10.0.1.51:631/ipp/print"}
  }

  setup do
    # Save original config
    original_printers = Application.get_env(:thermal_print_server, :printers)
    original_cups = Application.get_env(:thermal_print_server, :cups_uri)

    # Set test config — disable CUPS discovery
    Application.put_env(:thermal_print_server, :printers, @test_printers)
    Application.delete_env(:thermal_print_server, :cups_uri)

    # Refresh the registry with new config
    Registry.refresh()
    Process.sleep(20)

    on_exit(fn ->
      Application.put_env(:thermal_print_server, :printers, original_printers)

      if original_cups,
        do: Application.put_env(:thermal_print_server, :cups_uri, original_cups),
        else: Application.delete_env(:thermal_print_server, :cups_uri)

      Registry.refresh()
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

  test "refresh reloads printers from config" do
    Application.put_env(:thermal_print_server, :printers, %{
      "new-printer" => %{uri: "ipp://10.0.1.99:631/ipp/print"}
    })

    Registry.refresh()
    Process.sleep(50)

    assert {:ok, _} = Registry.lookup("new-printer")
    assert {:error, :not_found} = Registry.lookup("warehouse-dock3")
  end
end
