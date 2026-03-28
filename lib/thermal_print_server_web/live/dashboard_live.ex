defmodule ThermalPrintServerWeb.DashboardLive do
  use ThermalPrintServerWeb, :live_view

  alias ThermalPrintServer.Jobs.{Store, TestJob}
  alias ThermalPrintServer.Printer.Registry

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(ThermalPrintServer.PubSub, "print_jobs")
      :timer.send_interval(1000, self(), :tick)
    end

    jobs = Store.recent(100)
    printers = Registry.list_all()

    {:ok,
     assign(socket,
       jobs: jobs,
       printers: printers,
       page_title: "Print Dashboard",
       now: DateTime.utc_now(),
       total_completed: Enum.count(jobs, &(&1[:status] == :completed)),
       total_failed: Enum.count(jobs, &(&1[:status] == :failed)),
       test_zpl: TestJob.sample_zpl(),
       test_printer: List.first(printers)[:name] || "",
       preview_job: nil,
       show_test_form: false
     )}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, now: DateTime.utc_now())}
  end

  def handle_info({:job_updated, _job_id, _attrs}, socket) do
    jobs = Store.recent(100)

    # Auto-show preview for the latest completed job with a preview
    preview_job =
      Enum.find(jobs, socket.assigns.preview_job, fn job ->
        job[:status] == :completed and job[:preview_png] != nil
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
  def handle_event("toggle_test_form", _params, socket) do
    {:noreply, assign(socket, show_test_form: !socket.assigns.show_test_form)}
  end

  def handle_event("update_form", %{"zpl" => zpl, "printer" => printer}, socket) do
    {:noreply, assign(socket, test_zpl: zpl, test_printer: printer)}
  end

  def handle_event("update_form", %{"printer" => printer}, socket) do
    {:noreply, assign(socket, test_printer: printer)}
  end

  def handle_event("update_form", %{"zpl" => zpl}, socket) do
    {:noreply, assign(socket, test_zpl: zpl)}
  end

  def handle_event("submit_test_job", _params, socket) do
    zpl = socket.assigns.test_zpl
    printer = socket.assigns.test_printer

    {:ok, _job_id} = TestJob.submit(printer, zpl)
    {:noreply, socket}
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
            <span class="stat-value stat-time">{Calendar.strftime(@now, "%H:%M:%S")}</span>
          </div>
        </div>
      </header>

      <%!-- Devices --%>
      <section class="printer-section">
        <div class="section-label">
          <span class="label-line"></span>
          <span class="label-text">DEVICES</span>
          <span class="label-line"></span>
        </div>

        <div class="printer-grid">
          <div :for={printer <- @printers} class="printer-card">
            <div class="printer-card-inner">
              <div class={"printer-status-dot #{if String.starts_with?(printer.uri, "virtual:"), do: "virtual-dot"}"}>
              </div>
              <div class="printer-info">
                <div class="printer-name">{String.upcase(printer.name)}</div>
                <div class="printer-uri">
                  {if String.starts_with?(printer.uri, "virtual:"),
                    do: "Labelary virtual printer",
                    else: printer.uri}
                </div>
              </div>
              <div class="printer-icon">
                <svg
                  :if={!String.starts_with?(printer.uri, "virtual:")}
                  width="32"
                  height="32"
                  viewBox="0 0 32 32"
                  fill="none"
                >
                  <rect
                    x="4"
                    y="12"
                    width="24"
                    height="12"
                    rx="2"
                    stroke="currentColor"
                    stroke-width="1.2"
                  />
                  <path d="M8 12V6h16v6" stroke="currentColor" stroke-width="1.2" />
                  <rect
                    x="8"
                    y="20"
                    width="16"
                    height="8"
                    rx="1"
                    stroke="currentColor"
                    stroke-width="1.2"
                  />
                  <circle cx="22" cy="16" r="1.5" fill="currentColor" opacity="0.4" />
                </svg>
                <svg
                  :if={String.starts_with?(printer.uri, "virtual:")}
                  width="32"
                  height="32"
                  viewBox="0 0 32 32"
                  fill="none"
                >
                  <rect
                    x="6"
                    y="4"
                    width="20"
                    height="24"
                    rx="2"
                    stroke="currentColor"
                    stroke-width="1.2"
                  />
                  <circle cx="16" cy="14" r="5" stroke="currentColor" stroke-width="1.2" />
                  <line x1="16" y1="11" x2="16" y2="17" stroke="currentColor" stroke-width="1" />
                  <line x1="13" y1="14" x2="19" y2="14" stroke="currentColor" stroke-width="1" />
                  <line
                    x1="10"
                    y1="24"
                    x2="22"
                    y2="24"
                    stroke="currentColor"
                    stroke-width="0.8"
                    opacity="0.3"
                  />
                </svg>
              </div>
            </div>
          </div>

          <div :if={@printers == []} class="no-printers">
            <span class="no-printers-text">NO DEVICES REGISTERED</span>
          </div>
        </div>
      </section>

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

              <label class="test-label">ZPL</label>
              <textarea
                class="test-textarea"
                name="zpl"
                spellcheck="false"
                rows="12"
                phx-debounce="300"
              >{@test_zpl}</textarea>

              <button type="submit" class="test-submit">
                SEND TO PRINTER
              </button>
            </form>

            <div :if={@preview_job && @preview_job[:preview_png]} class="test-preview-col">
              <label class="test-label">LABEL PREVIEW</label>
              <div class="preview-frame">
                <img src={"data:image/png;base64,#{@preview_job[:preview_png]}"} alt="Label preview" />
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
                :for={job <- @jobs}
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
                    :if={job[:preview_png]}
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

      <%!-- Label Preview Modal --%>
      <div
        :if={@preview_job && @preview_job[:preview_png] && !@show_test_form}
        class="preview-modal-backdrop"
        phx-click="close_preview"
      >
        <div class="preview-modal" phx-click-away="close_preview">
          <div class="preview-modal-header">
            <span class="preview-modal-title">LABEL PREVIEW</span>
            <button class="preview-modal-close" phx-click="close_preview">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <line x1="3" y1="3" x2="13" y2="13" stroke="currentColor" stroke-width="1.5" />
                <line x1="13" y1="3" x2="3" y2="13" stroke="currentColor" stroke-width="1.5" />
              </svg>
            </button>
          </div>
          <div class="preview-modal-body">
            <img src={"data:image/png;base64,#{@preview_job[:preview_png]}"} alt="Label preview" />
          </div>
          <div class="preview-modal-footer">
            <span>{@preview_job[:printer] || "—"}</span>
            <span>{truncate_id(@preview_job.job_id)}</span>
            <span>{format_time(@preview_job[:timestamp])}</span>
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
end
