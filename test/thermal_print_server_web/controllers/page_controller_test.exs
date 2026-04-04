defmodule ThermalPrintServerWeb.PageControllerTest do
  use ThermalPrintServerWeb.ConnCase

  test "GET / renders the dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "THERMAL"
  end
end
