defmodule ThermalPrintServerWeb.HealthControllerTest do
  use ThermalPrintServerWeb.ConnCase, async: false

  setup do
    original_queue = Application.get_env(:thermal_print_server, :sqs_queue_url)
    original_site = Application.get_env(:thermal_print_server, :site_id)

    on_exit(fn ->
      restore(:sqs_queue_url, original_queue)
      restore(:site_id, original_site)
    end)

    :ok
  end

  defp restore(key, nil), do: Application.delete_env(:thermal_print_server, key)
  defp restore(key, value), do: Application.put_env(:thermal_print_server, key, value)

  test "omits optional checks when neither SQS nor site_id is configured", %{conn: conn} do
    Application.delete_env(:thermal_print_server, :sqs_queue_url)
    Application.delete_env(:thermal_print_server, :site_id)

    conn = get(conn, ~p"/health")

    body = json_response(conn, 200)
    assert body["status"] == "ok"
    assert Map.keys(body["checks"]) |> Enum.sort() == ["registry", "store"]
  end

  test "includes broadway and publisher checks when their config is set", %{conn: conn} do
    Application.put_env(:thermal_print_server, :sqs_queue_url, "http://dev-local/queue")
    Application.put_env(:thermal_print_server, :site_id, "test-site")

    conn = get(conn, ~p"/health")

    body = json_response(conn, 200)
    assert body["checks"]["broadway"] == true
    assert body["checks"]["publisher"] == true
  end

  test "returns 503 when Broadway is configured but not running", %{conn: conn} do
    alias ThermalPrintServer.Broadway.PrintPipeline

    Application.put_env(:thermal_print_server, :sqs_queue_url, "http://dev-local/queue")
    running_before? = Process.whereis(PrintPipeline) != nil

    try do
      Supervisor.terminate_child(ThermalPrintServer.Supervisor, PrintPipeline)

      conn = get(conn, ~p"/health")

      body = json_response(conn, 503)
      assert body["status"] == "degraded"
      assert body["checks"]["broadway"] == false
    after
      if running_before? do
        Supervisor.restart_child(ThermalPrintServer.Supervisor, PrintPipeline)
      end
    end
  end
end
