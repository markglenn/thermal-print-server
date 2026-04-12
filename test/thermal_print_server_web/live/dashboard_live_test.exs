defmodule ThermalPrintServerWeb.DashboardLiveTest do
  use ThermalPrintServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias ThermalPrintServer.Jobs.Store
  alias ThermalPrintServer.Printer.Registry

  @test_printers %{
    "TestZebra-4x6" => %{uri: "ipp://localhost:631/printers/TestZebra-4x6"},
    "TestZebra-4x2" => %{uri: "ipp://localhost:631/printers/TestZebra-4x2"}
  }

  setup do
    :ets.delete_all_objects(Store)

    original_printers = Application.get_env(:thermal_print_server, :printers)
    original_cups = Application.get_env(:thermal_print_server, :cups_uri)

    Application.put_env(:thermal_print_server, :printers, @test_printers)
    Application.delete_env(:thermal_print_server, :cups_uri)
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

  describe "mount" do
    test "renders dashboard with page title", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      assert page_title(view) =~ "Print Dashboard"
      assert html =~ "THERMAL"
      assert html =~ "PRINT CONTROL"
    end

    test "shows discovered printers count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "2"
    end

    test "shows empty state when no jobs", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")
      assert html =~ "AWAITING PRINT JOBS"
    end

    test "shows existing jobs on mount", %{conn: conn} do
      Store.record("existing-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        label_name: "Existing Label"
      })

      {:ok, _view, html} = live(conn, "/")
      assert html =~ "Existing Label"
    end
  end

  describe "job feed" do
    test "updates when a job is broadcast", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Store.record("live-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        label_name: "Live Label"
      })

      Phoenix.PubSub.broadcast(
        ThermalPrintServer.PubSub,
        "print_jobs",
        {:job_updated, "live-job", %{status: :completed}}
      )

      html = render(view)
      assert html =~ "Live Label"
    end

    test "shows completed and failed counts", %{conn: conn} do
      Store.record("job-ok", %{status: :completed, printer: "TestZebra-4x6"})
      Store.record("job-fail", %{status: :failed})

      {:ok, _view, html} = live(conn, "/")
      # The stats show in the header
      assert html =~ "PROCESSED"
      assert html =~ "FAILED"
    end
  end

  describe "filters" do
    setup %{conn: conn} do
      Store.record("job-a", %{
        status: :completed,
        printer: "TestZebra-4x6",
        label_name: "Alpha"
      })

      Store.record("job-b", %{
        status: :failed,
        printer: "TestZebra-4x2",
        label_name: "Beta"
      })

      {:ok, view, _html} = live(conn, "/")
      %{view: view}
    end

    test "filters by status", %{view: view} do
      html =
        view
        |> element(".feed-filters")
        |> render_change(%{"status" => "failed", "device" => "", "time" => ""})

      assert html =~ "Beta"
      refute html =~ "Alpha"
    end

    test "filters by device", %{view: view} do
      html =
        view
        |> element(".feed-filters")
        |> render_change(%{"device" => "TestZebra-4x6", "status" => "", "time" => ""})

      assert html =~ "Alpha"
      refute html =~ "Beta"
    end

    test "clears filters with empty values", %{view: view} do
      html =
        view
        |> element(".feed-filters")
        |> render_change(%{"device" => "", "status" => "", "time" => ""})

      assert html =~ "Alpha"
      assert html =~ "Beta"
    end
  end

  describe "test job modal" do
    test "opens and closes", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      refute html =~ "SEND TO PRINTER"

      html = view |> element(".feed-action-btn") |> render_click()
      assert html =~ "SEND TO PRINTER"
      assert html =~ "SEND TEST JOB"

      html = view |> element(".test-modal .preview-modal-close") |> render_click()
      refute html =~ "test-textarea"
    end
  end

  describe "preview modal" do
    test "opens when VIEW is clicked", %{conn: conn} do
      Store.record("preview-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        label_name: "Preview Test",
        preview_data: "^XA^FDTest^FS^XZ",
        preview_content_type: "application/vnd.zebra.zpl"
      })

      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("[phx-click='show_preview'][phx-value-job-id='preview-job']")
        |> render_click()

      assert html =~ "JOB DETAILS"
      assert html =~ "Preview Test"
    end

    test "closes when close button is clicked", %{conn: conn} do
      Store.record("close-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        preview_data: "^XA^XZ",
        preview_content_type: "application/vnd.zebra.zpl"
      })

      {:ok, view, _html} = live(conn, "/")

      view
      |> element("[phx-click='show_preview'][phx-value-job-id='close-job']")
      |> render_click()

      html = view |> element(".job-detail-modal .preview-modal-close") |> render_click()
      refute html =~ "JOB DETAILS"
    end

    test "does not auto-open on job update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Store.record("new-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        preview_data: "^XA^XZ",
        preview_content_type: "application/vnd.zebra.zpl"
      })

      Phoenix.PubSub.broadcast(
        ThermalPrintServer.PubSub,
        "print_jobs",
        {:job_updated, "new-job", %{status: :completed}}
      )

      html = render(view)
      refute html =~ "JOB DETAILS"
    end

    test "shows page count", %{conn: conn} do
      Store.record("pages-job", %{
        status: :completed,
        printer: "TestZebra-4x6",
        page_count: 6,
        preview_data: "^XA^XZ",
        preview_content_type: "application/vnd.zebra.zpl"
      })

      {:ok, view, _html} = live(conn, "/")

      html =
        view
        |> element("[phx-click='show_preview'][phx-value-job-id='pages-job']")
        |> render_click()

      assert html =~ "PAGES"
      assert html =~ "6"
    end
  end

  describe "printers panel" do
    test "toggles printers panel", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")
      refute html =~ "printers-panel-open"

      html = view |> element(".header-devices-btn") |> render_click()
      assert html =~ "printers-panel-open"
    end

    test "filters printers by search", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element(".header-devices-btn") |> render_click()

      html =
        view
        |> element(".printers-panel-search")
        |> render_change(%{"search" => "4x6"})

      assert html =~ "TestZebra-4x6"
      refute html =~ "TestZebra-4x2"
    end

    test "opens printer detail modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> element(".header-devices-btn") |> render_click()

      html =
        view
        |> element("[phx-click='show_printer'][phx-value-name='TestZebra-4x6']")
        |> render_click()

      assert html =~ "TESTZEBRA-4X6"
      assert html =~ "ipp://localhost:631/printers/TestZebra-4x6"
    end
  end

  describe "clear queue" do
    test "clears jobs from store and resets counts", %{conn: conn} do
      Store.record("clear-1", %{status: :completed, printer: "TestZebra-4x6"})
      Store.record("clear-2", %{status: :failed})

      {:ok, view, html} = live(conn, "/")
      assert html =~ "clear-1"

      html = view |> element(".clear-queue-btn") |> render_click()
      assert html =~ "AWAITING PRINT JOBS"
      assert Store.recent(10) == []
    end
  end

  describe "printers update" do
    test "updates printer list on PubSub broadcast", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      Phoenix.PubSub.broadcast(
        ThermalPrintServer.PubSub,
        "printers",
        {:printers_updated, [
          %{name: "NewPrinter", uri: "ipp://localhost/new", state: 3}
        ]}
      )

      html = render(view)
      assert html =~ "1"
    end
  end
end
