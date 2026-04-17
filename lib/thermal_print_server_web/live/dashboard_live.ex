defmodule ThermalPrintServerWeb.DashboardLive do
  use ThermalPrintServerWeb, :live_view

  import ThermalPrintServerWeb.DashboardLive.Components

  alias ThermalPrintServer.Jobs.{Store, TestJob}
  alias ThermalPrintServer.Printer.Registry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "print_jobs")
      Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "printers")
    end

    jobs = Store.recent(100)
    printers = Registry.list_all()
    debug_links = Application.get_env(:thermal_print_server, :debug_links, [])

    {:ok,
     assign(socket,
       jobs: jobs,
       printers: printers,
       debug_links: debug_links,
       page_title: "Print Dashboard",
       total_completed: Enum.count(jobs, &(&1[:status] == :completed)),
       total_failed: Enum.count(jobs, &(&1[:status] == :failed)),
       test_data: TestJob.sample_zpl(),
       test_content_type: "application/vnd.zebra.zpl",
       test_label_size: "4x6",
       test_dpmm: "8dpmm",
       test_printer: List.first(printers)[:name] || "",
       preview_job: nil,
       selected_printer: nil,
       printer_jobs: [],
       show_test_form: false,
       show_printers_panel: false,
       printer_search: "",
       filter_device: "",
       filter_status: "",
       filter_time: ""
     )}
  end

  # -- PubSub handlers --

  @impl true
  def handle_info({:printers_updated, printers}, socket) do
    {:noreply, assign(socket, printers: printers)}
  end

  def handle_info({:job_updated, _job_id, _attrs}, socket) do
    jobs = Store.recent(100)

    {:noreply,
     assign(socket,
       jobs: jobs,
       total_completed: Enum.count(jobs, &(&1[:status] == :completed)),
       total_failed: Enum.count(jobs, &(&1[:status] == :failed))
     )}
  end

  # -- Events --

  @impl true
  def handle_event("refresh_printers", _params, socket) do
    case Registry.refresh_sync() do
      {:ok, count} ->
        {:noreply, put_flash(socket, :info, "Refreshed — #{count} printer(s) found")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "CUPS unreachable")}
    end
  end

  def handle_event("toggle_printers_panel", _params, socket) do
    {:noreply, assign(socket, show_printers_panel: !socket.assigns.show_printers_panel)}
  end

  def handle_event("search_printers", %{"search" => search}, socket) do
    {:noreply, assign(socket, printer_search: search)}
  end

  def handle_event("update_filters", params, socket) do
    {:noreply,
     assign(socket,
       filter_device: params["device"] || "",
       filter_status: params["status"] || "",
       filter_time: params["time"] || ""
     )}
  end

  def handle_event("toggle_test_form", _params, socket) do
    {:noreply, assign(socket, show_test_form: !socket.assigns.show_test_form)}
  end

  def handle_event("update_form", params, socket) do
    assigns =
      Enum.reduce(params, [], fn
        {"data", val}, acc -> [{:test_data, val} | acc]
        {"printer", val}, acc -> [{:test_printer, val} | acc]
        {"content_type", val}, acc -> [{:test_content_type, val} | acc]
        {"label_size", val}, acc -> [{:test_label_size, val} | acc]
        {"dpmm", val}, acc -> [{:test_dpmm, val} | acc]
        _, acc -> acc
      end)

    {:noreply, assign(socket, assigns)}
  end

  def handle_event("submit_test_job", _params, socket) do
    data = socket.assigns.test_data
    printer = socket.assigns.test_printer
    content_type = socket.assigns.test_content_type

    opts = [
      label_size: socket.assigns.test_label_size,
      dpmm: socket.assigns.test_dpmm
    ]

    case TestJob.submit(printer, data, content_type, opts) do
      {:ok, _job_id} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Test job failed: #{inspect(reason)}")}
    end
  end

  def handle_event("clear_queue", _params, socket) do
    sqs_result =
      case Application.get_env(:thermal_print_server, :sqs_queue_url) do
        nil -> :ok
        queue_url -> queue_url |> ExAws.SQS.purge_queue() |> ExAws.request()
      end

    case sqs_result do
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Queue purge failed: #{inspect(reason)}")}

      _ ->
        Store.clear()

        Phoenix.PubSub.broadcast(
          ThermalPrintServer.PubSub,
          "print_jobs",
          {:job_updated, nil, %{}}
        )

        {:noreply,
         assign(socket,
           jobs: [],
           total_completed: 0,
           total_failed: 0,
           preview_job: nil
         )}
    end
  end

  def handle_event("show_printer", %{"name" => name}, socket) do
    printer = Enum.find(socket.assigns.printers, &(&1.name == name))

    printer_jobs =
      Store.recent(100)
      |> Enum.filter(&(&1[:printer] == name))

    {:noreply, assign(socket, selected_printer: printer, printer_jobs: printer_jobs)}
  end

  def handle_event("close_printer", _params, socket) do
    {:noreply, assign(socket, selected_printer: nil)}
  end

  def handle_event("show_job_from_printer", %{"job-id" => job_id}, socket) do
    job = Store.get(job_id)
    {:noreply, assign(socket, selected_printer: nil, preview_job: job)}
  end

  def handle_event("show_preview", %{"job-id" => job_id}, socket) do
    job = Store.get(job_id)
    {:noreply, assign(socket, preview_job: job)}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, preview_job: nil)}
  end

  # -- Render --

  @impl true
  def render(assigns) do
    ~H"""
    <div class="thermal-dashboard">
      <div class="scanlines"></div>
      <Layouts.flash_group flash={@flash} />

      <.dashboard_header
        printers={@printers}
        total_completed={@total_completed}
        total_failed={@total_failed}
        debug_links={@debug_links}
      />

      <.test_job_modal
        :if={@show_test_form}
        printers={@printers}
        test_printer={@test_printer}
        test_content_type={@test_content_type}
        test_label_size={@test_label_size}
        test_dpmm={@test_dpmm}
        test_data={@test_data}
      />

      <.job_feed
        jobs={@jobs}
        filter_device={@filter_device}
        filter_status={@filter_status}
        filter_time={@filter_time}
      />

      <.job_detail_modal :if={@preview_job} job={@preview_job} />

      <.printer_detail_modal
        :if={@selected_printer}
        printer={@selected_printer}
        jobs={@printer_jobs}
      />

      <.printers_panel
        show={@show_printers_panel}
        printers={@printers}
        search={@printer_search}
      />

      <.dashboard_footer printers={@printers} jobs={@jobs} />
    </div>
    """
  end
end
