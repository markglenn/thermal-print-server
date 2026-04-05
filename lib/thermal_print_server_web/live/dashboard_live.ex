defmodule ThermalPrintServerWeb.DashboardLive do
  use ThermalPrintServerWeb, :live_view

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

    {:ok,
     assign(socket,
       jobs: jobs,
       printers: printers,
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

  @impl true
  def handle_info({:printers_updated, printers}, socket) do
    {:noreply, assign(socket, printers: printers)}
  end

  def handle_info({:job_updated, _job_id, _attrs}, socket) do
    jobs = Store.recent(100)

    # Auto-show preview for the latest completed job with a preview
    preview_job =
      Enum.find(jobs, socket.assigns.preview_job, fn job ->
        job[:status] == :completed and job[:preview_data] != nil
      end)

    {:noreply,
     assign(socket,
       jobs: jobs,
       total_completed: Enum.count(jobs, &(&1[:status] == :completed)),
       total_failed: Enum.count(jobs, &(&1[:status] == :failed)),
       preview_job: preview_job
     )}
  end

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

    {:ok, _job_id} = TestJob.submit(printer, data, content_type, opts)
    {:noreply, socket}
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="thermal-dashboard">
      <div class="scanlines"></div>
      <Layouts.flash_group flash={@flash} />

      <%!-- Header --%>
      <header class="thermal-header">
        <div class="header-left">
          <div class="logo-mark">
            <svg width="28" height="28" viewBox="0 0 28 28" fill="none">
              <rect
                x="2"
                y="4"
                width="24"
                height="20"
                rx="2"
                stroke="currentColor"
                stroke-width="1.5"
                fill="none"
              />
              <line
                x1="6"
                y1="10"
                x2="22"
                y2="10"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.5"
              />
              <line
                x1="6"
                y1="13"
                x2="18"
                y2="13"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.5"
              />
              <line
                x1="6"
                y1="16"
                x2="20"
                y2="16"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.5"
              />
              <rect x="8" y="20" width="12" height="6" fill="currentColor" opacity="0.15" />
              <line
                x1="14"
                y1="20"
                x2="14"
                y2="26"
                stroke="currentColor"
                stroke-width="0.5"
                stroke-dasharray="1 1"
              />
            </svg>
          </div>
          <div>
            <h1 class="header-title">THERMAL</h1>
            <span class="header-subtitle">PRINT CONTROL</span>
          </div>
        </div>
        <div class="header-right">
          <button class="header-devices-btn" phx-click="toggle_printers_panel">
            <svg width="16" height="16" viewBox="0 0 32 32" fill="none">
              <rect
                x="4"
                y="12"
                width="24"
                height="12"
                rx="2"
                stroke="currentColor"
                stroke-width="2"
              />
              <path d="M8 12V6h16v6" stroke="currentColor" stroke-width="2" />
              <rect x="8" y="20" width="16" height="8" rx="1" stroke="currentColor" stroke-width="2" />
            </svg>
            <span class="header-devices-label">DEVICES</span>
            <span class="header-devices-count">{length(@printers)}</span>
          </button>
          <div class="header-divider"></div>
          <div class="header-stat">
            <span class="stat-label">PROCESSED</span>
            <span class="stat-value stat-good">{@total_completed}</span>
          </div>
          <div class="header-divider"></div>
          <div class="header-stat">
            <span class="stat-label">FAILED</span>
            <span class={"stat-value #{if @total_failed > 0, do: "stat-bad", else: "stat-neutral"}"}>
              {@total_failed}
            </span>
          </div>
          <div class="header-divider"></div>
          <div class="header-stat">
            <span class="stat-label">UTC</span>
            <span class="stat-value stat-time" id="utc-clock" phx-hook=".UtcClock" phx-update="ignore">{Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")}</span>
            <script :type={Phoenix.LiveView.ColocatedHook} name=".UtcClock">
              export default {
                mounted() {
                  this.tick()
                  this.timer = setInterval(() => this.tick(), 1000)
                },
                tick() {
                  this.el.textContent = new Date().toISOString().slice(11, 19)
                },
                destroyed() {
                  clearInterval(this.timer)
                }
              }
            </script>
          </div>
        </div>
      </header>

      <%!-- Test Job Panel --%>
      <section class="test-section">
        <div class="section-label">
          <span class="label-line"></span>
          <button class="label-text label-toggle" phx-click="toggle_test_form">
            {if @show_test_form, do: "HIDE TEST PANEL", else: "SEND TEST JOB"}
          </button>
          <span class="label-line"></span>
        </div>

        <div :if={@show_test_form} class="test-panel">
          <div class="test-panel-inner">
            <form class="test-form-col" phx-change="update_form" phx-submit="submit_test_job">
              <label class="test-label">DEVICE</label>
              <select class="test-select" name="printer">
                <option
                  :for={p <- @printers}
                  value={p.name}
                  selected={p.name == @test_printer}
                >
                  {p.name}
                </option>
              </select>

              <label class="test-label">CONTENT TYPE</label>
              <select class="test-select" name="content_type">
                <option
                  value="application/vnd.zebra.zpl"
                  selected={@test_content_type == "application/vnd.zebra.zpl"}
                >
                  ZPL
                </option>
                <option value="application/pdf" selected={@test_content_type == "application/pdf"}>
                  PDF
                </option>
              </select>

              <div class="test-row">
                <div class="test-field">
                  <label class="test-label">LABEL SIZE</label>
                  <select class="test-select" name="label_size">
                    <option value="4x6" selected={@test_label_size == "4x6"}>4x6</option>
                    <option value="4x4" selected={@test_label_size == "4x4"}>4x4</option>
                    <option value="4x2" selected={@test_label_size == "4x2"}>4x2</option>
                    <option value="4x1" selected={@test_label_size == "4x1"}>4x1</option>
                    <option value="2x1" selected={@test_label_size == "2x1"}>2x1</option>
                  </select>
                </div>
                <div class="test-field">
                  <label class="test-label">DPI</label>
                  <select class="test-select" name="dpmm">
                    <option value="8dpmm" selected={@test_dpmm == "8dpmm"}>203 dpi</option>
                    <option value="12dpmm" selected={@test_dpmm == "12dpmm"}>300 dpi</option>
                    <option value="24dpmm" selected={@test_dpmm == "24dpmm"}>600 dpi</option>
                  </select>
                </div>
              </div>

              <label class="test-label">DATA</label>
              <textarea
                class="test-textarea"
                name="data"
                spellcheck="false"
                rows="12"
                phx-debounce="300"
              >{@test_data}</textarea>

              <button type="submit" class="test-submit">
                SEND TO PRINTER
              </button>
            </form>

            <div :if={@preview_job && @preview_job[:preview_data]} class="test-preview-col">
              <label class="test-label">LABEL PREVIEW</label>
              <div class="preview-frame">
                <img
                  :if={@preview_job[:preview_content_type] == "image/png"}
                  src={"data:image/png;base64,#{@preview_job[:preview_data]}"}
                  alt="Label preview"
                />
                <iframe
                  :if={@preview_job[:preview_content_type] == "application/pdf"}
                  src={"data:application/pdf;base64,#{@preview_job[:preview_data]}"}
                  class="preview-pdf"
                />
              </div>
              <span class="preview-meta">
                {@preview_job[:printer] || "—"} — {format_time(@preview_job[:timestamp])}
              </span>
            </div>
          </div>
        </div>
      </section>

      <%!-- Job Feed --%>
      <section class="jobs-section">
        <div class="section-label">
          <span class="label-line"></span>
          <span class="label-text">JOB FEED</span>
          <span class="label-line"></span>
        </div>

        <form :if={@jobs != []} class="feed-filters" phx-change="update_filters">
          <select name="device" class="feed-filter-select">
            <option value="">ALL DEVICES</option>
            <option :for={name <- job_device_names(@jobs)} value={name} selected={@filter_device == name}>
              {String.upcase(name)}
            </option>
          </select>
          <select name="status" class="feed-filter-select">
            <option value="">ALL STATUS</option>
            <option value="completed" selected={@filter_status == "completed"}>DONE</option>
            <option value="failed" selected={@filter_status == "failed"}>FAIL</option>
            <option value="printing" selected={@filter_status == "printing"}>SEND</option>
            <option value="queued" selected={@filter_status == "queued"}>WAIT</option>
          </select>
          <select name="time" class="feed-filter-select">
            <option value="">ALL TIME</option>
            <option value="1" selected={@filter_time == "1"}>LAST 1 MIN</option>
            <option value="5" selected={@filter_time == "5"}>LAST 5 MIN</option>
            <option value="15" selected={@filter_time == "15"}>LAST 15 MIN</option>
            <option value="60" selected={@filter_time == "60"}>LAST 1 HOUR</option>
          </select>
        </form>

        <div :if={@jobs == []} class="jobs-empty">
          <div class="empty-icon">
            <svg width="48" height="48" viewBox="0 0 48 48" fill="none">
              <rect
                x="8"
                y="8"
                width="32"
                height="32"
                rx="4"
                stroke="currentColor"
                stroke-width="1.5"
                stroke-dasharray="4 3"
              />
              <line
                x1="16"
                y1="20"
                x2="32"
                y2="20"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.3"
              />
              <line
                x1="16"
                y1="24"
                x2="28"
                y2="24"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.3"
              />
              <line
                x1="16"
                y1="28"
                x2="30"
                y2="28"
                stroke="currentColor"
                stroke-width="1"
                opacity="0.3"
              />
            </svg>
          </div>
          <span class="empty-text">AWAITING PRINT JOBS</span>
          <span class="empty-subtext">Send a test job above, or jobs will stream from SQS</span>
        </div>

        <div :if={@jobs != []} class="jobs-table-wrap">
          <table class="jobs-table">
            <thead>
              <tr>
                <th class="th-status">STS</th>
                <th class="th-id">JOB ID</th>
                <th class="th-printer">DEVICE</th>
                <th class="th-label">LABEL</th>
                <th class="th-chunks">CHUNK</th>
                <th class="th-time">TIME</th>
                <th class="th-preview"></th>
              </tr>
            </thead>
            <tbody id="job-rows" phx-update="replace">
              <tr
                :for={job <- filtered_jobs(@jobs, @filter_device, @filter_status, @filter_time)}
                id={"job-#{job.job_id}"}
                class={"job-row #{status_row_class(job[:status])}"}
              >
                <td class="td-status">
                  <div class={"status-indicator #{status_class(job[:status])}"}>
                    <div class="status-dot"></div>
                    <span class="status-text">{status_label(job[:status])}</span>
                  </div>
                </td>
                <td class="td-id">
                  <span class="job-id-text">{truncate_id(job.job_id)}</span>
                </td>
                <td class="td-printer">{job[:printer] || "—"}</td>
                <td class="td-label">{job[:label_name] || "—"}</td>
                <td class="td-chunks">
                  <div :if={has_chunks?(job)} class="chunk-bar">
                    <div class="chunk-fill" style={"width: #{chunk_pct(job)}%"}></div>
                    <span class="chunk-text">{chunk_display(job)}</span>
                  </div>
                  <span :if={!has_chunks?(job)} class="no-chunks">—</span>
                </td>
                <td class="td-time">{format_time(job.timestamp)}</td>
                <td class="td-preview">
                  <button
                    :if={job[:preview_data]}
                    class="preview-btn"
                    phx-click="show_preview"
                    phx-value-job-id={job.job_id}
                  >
                    VIEW
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <%!-- Job Detail Modal --%>
      <div
        :if={@preview_job && !@show_test_form}
        class="preview-modal-backdrop"
        phx-click="close_preview"
      >
        <div class="preview-modal job-detail-modal" phx-click-away="close_preview">
          <div class="preview-modal-header">
            <span class="preview-modal-title">JOB DETAILS</span>
            <button class="preview-modal-close" phx-click="close_preview">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <line x1="3" y1="3" x2="13" y2="13" stroke="currentColor" stroke-width="1.5" />
                <line x1="13" y1="3" x2="3" y2="13" stroke="currentColor" stroke-width="1.5" />
              </svg>
            </button>
          </div>
          <div class="job-detail-body">
            <dl class="printer-detail-list">
              <dt>STATUS</dt>
              <dd>
                <div class={"status-indicator #{status_class(@preview_job[:status])}"}>
                  <div class="status-dot"></div>
                  <span class="status-text">{status_label(@preview_job[:status])}</span>
                </div>
              </dd>

              <dt>JOB ID</dt>
              <dd class="printer-detail-mono">{@preview_job.job_id}</dd>

              <dt>DEVICE</dt>
              <dd>{@preview_job[:printer] || "—"}</dd>

              <dt :if={@preview_job[:label_name]}>LABEL</dt>
              <dd :if={@preview_job[:label_name]}>{@preview_job[:label_name]}</dd>

              <dt :if={@preview_job[:content_type]}>FORMAT</dt>
              <dd :if={@preview_job[:content_type]}>{@preview_job[:content_type]}</dd>

              <dt>TIME</dt>
              <dd>{format_time(@preview_job[:timestamp])}</dd>

              <dt :if={@preview_job[:error]}>ERROR</dt>
              <dd :if={@preview_job[:error]} class="job-detail-error">{@preview_job[:error]}</dd>
            </dl>

            <div :if={@preview_job[:preview_data]} class="job-detail-preview">
              <div class="printer-jobs-header">
                <span class="printer-jobs-title">PREVIEW</span>
              </div>
              <div class="preview-frame">
                <img
                  :if={@preview_job[:preview_content_type] == "image/png"}
                  src={"data:image/png;base64,#{@preview_job[:preview_data]}"}
                  alt="Label preview"
                />
                <iframe
                  :if={@preview_job[:preview_content_type] == "application/pdf"}
                  src={"data:application/pdf;base64,#{@preview_job[:preview_data]}"}
                  class="preview-pdf-modal"
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Printer Info Modal --%>
      <div
        :if={@selected_printer}
        class="preview-modal-backdrop"
        phx-click="close_printer"
      >
        <div class="preview-modal printer-modal" phx-click-away="close_printer">
          <div class="preview-modal-header">
            <span class="preview-modal-title">{String.upcase(@selected_printer.name)}</span>
            <button class="preview-modal-close" phx-click="close_printer">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <line x1="3" y1="3" x2="13" y2="13" stroke="currentColor" stroke-width="1.5" />
                <line x1="13" y1="3" x2="3" y2="13" stroke="currentColor" stroke-width="1.5" />
              </svg>
            </button>
          </div>
          <div class="printer-modal-body">
            <dl class="printer-detail-list">
              <dt>URI</dt>
              <dd class="printer-detail-mono">{@selected_printer.uri}</dd>

              <dt>STATE</dt>
              <dd>{printer_state_label(@selected_printer[:state])}</dd>

              <dt :if={@selected_printer[:info]}>DESCRIPTION</dt>
              <dd :if={@selected_printer[:info]}>{@selected_printer[:info]}</dd>

              <dt :if={@selected_printer[:location]}>LOCATION</dt>
              <dd :if={@selected_printer[:location]}>{@selected_printer[:location]}</dd>

              <dt :if={@selected_printer[:resolution_default]}>RESOLUTION</dt>
              <dd :if={@selected_printer[:resolution_default]}>
                {format_resolution(@selected_printer[:resolution_default])}
              </dd>

              <dt :if={@selected_printer[:resolution]}>SUPPORTED RESOLUTIONS</dt>
              <dd :if={@selected_printer[:resolution]}>
                {format_resolutions(@selected_printer[:resolution])}
              </dd>

              <dt :if={@selected_printer[:media_default]}>DEFAULT MEDIA</dt>
              <dd :if={@selected_printer[:media_default]}>{@selected_printer[:media_default]}</dd>

              <dt :if={@selected_printer[:media_ready]}>LOADED MEDIA</dt>
              <dd :if={@selected_printer[:media_ready]}>
                {format_media_list(@selected_printer[:media_ready])}
              </dd>

              <dt :if={@selected_printer[:media_supported]}>SUPPORTED MEDIA</dt>
              <dd :if={@selected_printer[:media_supported]}>
                {format_media_list(@selected_printer[:media_supported])}
              </dd>
            </dl>

            <div class="printer-jobs-section">
              <div class="printer-jobs-header">
                <span class="printer-jobs-title">PRINT HISTORY</span>
                <span class="printer-jobs-count">{length(@printer_jobs)}</span>
              </div>
              <div :if={@printer_jobs == []} class="printer-jobs-empty">
                No jobs sent to this printer yet
              </div>
              <table :if={@printer_jobs != []} class="printer-jobs-table">
                <thead>
                  <tr>
                    <th>STS</th>
                    <th>JOB ID</th>
                    <th>LABEL</th>
                    <th>TIME</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={job <- @printer_jobs}
                    class="printer-jobs-row-clickable"
                    phx-click="show_job_from_printer"
                    phx-value-job-id={job.job_id}
                  >
                    <td>
                      <div class={"status-indicator #{status_class(job[:status])}"}>
                        <div class="status-dot"></div>
                        <span class="status-text">{status_label(job[:status])}</span>
                      </div>
                    </td>
                    <td class="printer-jobs-id">{truncate_id(job.job_id)}</td>
                    <td>{job[:label_name] || "—"}</td>
                    <td>{format_time(job.timestamp)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>

      <%!-- Printers Slide-Out Panel --%>
      <div
        class={"printers-panel-backdrop #{if @show_printers_panel, do: "printers-panel-backdrop-visible"}"}
        phx-click="toggle_printers_panel"
      >
      </div>
      <div class={"printers-panel #{if @show_printers_panel, do: "printers-panel-open"}"}>
        <div class="printers-panel-header">
          <span class="printers-panel-title">DEVICES</span>
          <div class="printers-panel-actions">
            <button class="refresh-btn" phx-click="refresh_printers" title="Refresh printers">
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path
                  d="M11.5 2.5A5.5 5.5 0 1 0 13 7"
                  stroke="currentColor"
                  stroke-width="1.3"
                  stroke-linecap="round"
                />
                <path
                  d="M11.5 0.5v2h2"
                  stroke="currentColor"
                  stroke-width="1.3"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                />
              </svg>
            </button>
            <button class="preview-modal-close" phx-click="toggle_printers_panel">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <line x1="3" y1="3" x2="13" y2="13" stroke="currentColor" stroke-width="1.5" />
                <line x1="13" y1="3" x2="3" y2="13" stroke="currentColor" stroke-width="1.5" />
              </svg>
            </button>
          </div>
        </div>
        <form class="printers-panel-search" phx-change="search_printers">
          <input
            type="text"
            placeholder="Search printers..."
            value={@printer_search}
            name="search"
            class="printers-search-input"
            autocomplete="off"
            phx-debounce="150"
          />
        </form>
        <div class="printers-panel-list">
          <div
            :for={printer <- filtered_printers(@printers, @printer_search)}
            class="printers-panel-row"
            phx-click="show_printer"
            phx-value-name={printer.name}
          >
            <div class="printers-panel-row-dot"></div>
            <div class="printers-panel-row-info">
              <span class="printers-panel-row-name">{printer.name}</span>
              <span class="printers-panel-row-uri">{printer.uri}</span>
            </div>
            <span class="printers-panel-row-state">{printer_state_label(printer[:state])}</span>
          </div>
          <div :if={filtered_printers(@printers, @printer_search) == []} class="printers-panel-empty">
            No printers found
          </div>
        </div>
      </div>

      <%!-- Footer --%>
      <footer class="thermal-footer">
        <span>THERMAL PRINT SERVER</span>
        <span class="footer-dot"></span>
        <span>{length(@printers)} DEVICE(S)</span>
        <span class="footer-dot"></span>
        <span>{length(@jobs)} JOB(S)</span>
      </footer>
    </div>
    """
  end

  # Helpers

  @spec status_class(atom()) :: String.t()
  defp status_class(:completed), do: "status-completed"
  defp status_class(:failed), do: "status-failed"
  defp status_class(:printing), do: "status-printing"
  defp status_class(_), do: "status-queued"

  @spec status_label(atom()) :: String.t()
  defp status_label(:completed), do: "DONE"
  defp status_label(:failed), do: "FAIL"
  defp status_label(:printing), do: "SEND"
  defp status_label(_), do: "WAIT"

  @spec status_row_class(atom()) :: String.t()
  defp status_row_class(:failed), do: "row-failed"
  defp status_row_class(:printing), do: "row-printing"
  defp status_row_class(_), do: ""

  @spec truncate_id(String.t() | nil) :: String.t()
  defp truncate_id(id) when is_binary(id) and byte_size(id) > 16 do
    String.slice(id, 0, 8) <> "..." <> String.slice(id, -4, 4)
  end

  defp truncate_id(id), do: id || "—"

  @spec has_chunks?(map()) :: boolean()
  defp has_chunks?(%{chunk_index: idx, total_chunks: total})
       when is_integer(idx) and is_integer(total),
       do: true

  defp has_chunks?(_), do: false

  @spec chunk_pct(map()) :: non_neg_integer()
  defp chunk_pct(%{chunk_index: idx, total_chunks: total}) when total > 0 do
    round((idx + 1) / total * 100)
  end

  defp chunk_pct(_), do: 0

  @spec chunk_display(map()) :: String.t()
  defp chunk_display(%{chunk_index: idx, total_chunks: total})
       when is_integer(idx) and is_integer(total) do
    "#{idx + 1}/#{total}"
  end

  defp chunk_display(_), do: "—"

  @spec format_time(DateTime.t() | term()) :: String.t()
  defp format_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  end

  defp format_time(_), do: "—"

  defp printer_state_label(3), do: "Idle"
  defp printer_state_label(4), do: "Processing"
  defp printer_state_label(5), do: "Stopped"
  defp printer_state_label(_), do: "Unknown"

  defp format_resolution(%{x: x, y: y, unit: unit}) do
    unit_str = if unit == :dpi, do: "dpi", else: "dpcm"
    if x == y, do: "#{x} #{unit_str}", else: "#{x}x#{y} #{unit_str}"
  end

  defp format_resolution(_), do: "—"

  defp format_resolutions(resolutions) when is_list(resolutions) do
    resolutions |> Enum.map(&format_resolution/1) |> Enum.join(", ")
  end

  defp format_resolutions(res), do: format_resolution(res)

  defp format_media_list(media) when is_list(media), do: Enum.join(media, ", ")
  defp format_media_list(media) when is_binary(media), do: media
  defp format_media_list(_), do: "—"

  defp job_device_names(jobs) do
    jobs
    |> Enum.map(& &1[:printer])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp filtered_jobs(jobs, device, status, time) do
    jobs
    |> filter_by_device(device)
    |> filter_by_status(status)
    |> filter_by_time(time)
  end

  defp filter_by_device(jobs, ""), do: jobs
  defp filter_by_device(jobs, device), do: Enum.filter(jobs, &(&1[:printer] == device))

  defp filter_by_status(jobs, ""), do: jobs

  defp filter_by_status(jobs, status) do
    status_atom = String.to_existing_atom(status)
    Enum.filter(jobs, &(&1[:status] == status_atom))
  end

  defp filter_by_time(jobs, ""), do: jobs

  defp filter_by_time(jobs, minutes) do
    cutoff = DateTime.add(DateTime.utc_now(), -String.to_integer(minutes), :minute)
    Enum.filter(jobs, &(DateTime.compare(&1.timestamp, cutoff) != :lt))
  end

  defp filtered_printers(printers, ""), do: printers

  defp filtered_printers(printers, search) do
    term = String.downcase(search)

    Enum.filter(printers, fn p ->
      String.contains?(String.downcase(p.name), term) or
        String.contains?(String.downcase(p.uri), term)
    end)
  end
end
