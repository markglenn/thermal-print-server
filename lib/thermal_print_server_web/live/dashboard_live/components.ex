defmodule ThermalPrintServerWeb.DashboardLive.Components do
  @moduledoc false
  use Phoenix.Component

  # -- Shared icons --

  defp close_icon(assigns) do
    ~H"""
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
      <line x1="3" y1="3" x2="13" y2="13" stroke="currentColor" stroke-width="1.5" />
      <line x1="13" y1="3" x2="3" y2="13" stroke="currentColor" stroke-width="1.5" />
    </svg>
    """
  end

  # -- Header --

  attr :printers, :list, required: true
  attr :total_completed, :integer, required: true
  attr :total_failed, :integer, required: true

  def dashboard_header(assigns) do
    ~H"""
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
          <span class="stat-value stat-time" id="utc-clock" phx-hook=".UtcClock" phx-update="ignore">
            {Calendar.strftime(DateTime.utc_now(), "%H:%M:%S")}
          </span>
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
    """
  end

  # -- Test Job Modal --

  attr :printers, :list, required: true
  attr :test_printer, :string, required: true
  attr :test_content_type, :string, required: true
  attr :test_label_size, :string, required: true
  attr :test_dpmm, :string, required: true
  attr :test_data, :string, required: true

  def test_job_modal(assigns) do
    ~H"""
    <div class="preview-modal-backdrop">
      <div class="preview-modal test-modal" phx-click-away="toggle_test_form">
        <div class="preview-modal-header">
          <span class="preview-modal-title">SEND TEST JOB</span>
          <button class="preview-modal-close" phx-click="toggle_test_form">
            <.close_icon />
          </button>
        </div>
        <form class="test-modal-body" phx-change="update_form" phx-submit="submit_test_job">
          <div class="test-modal-fields">
            <div class="test-field">
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
            </div>

            <div class="test-field">
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
            </div>

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
          </div>

          <label class="test-label">DATA</label>
          <textarea
            class="test-textarea"
            name="data"
            spellcheck="false"
            rows="10"
            phx-debounce="300"
          >{@test_data}</textarea>

          <button type="submit" class="test-submit">
            SEND TO PRINTER
          </button>
        </form>
      </div>
    </div>
    """
  end

  # -- Job Feed --

  attr :jobs, :list, required: true
  attr :filter_device, :string, required: true
  attr :filter_status, :string, required: true
  attr :filter_time, :string, required: true

  def job_feed(assigns) do
    ~H"""
    <section class="jobs-section">
      <div class="section-label">
        <span class="label-line"></span>
        <span class="label-text">JOB FEED</span>
        <span class="label-line"></span>
        <button class="feed-action-btn" phx-click="toggle_test_form">
          TEST JOB
        </button>
        <button
          :if={@jobs != []}
          class="clear-queue-btn"
          phx-click="clear_queue"
          data-confirm="Clear the SQS queue and all job history?"
        >
          CLEAR
        </button>
      </div>

      <form :if={@jobs != []} class="feed-filters" phx-change="update_filters">
        <select name="device" class="feed-filter-select">
          <option value="">ALL DEVICES</option>
          <option
            :for={name <- job_device_names(@jobs)}
            value={name}
            selected={@filter_device == name}
          >
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
              <th class="th-qty">PAGES</th>
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
                <.status_indicator status={job[:status]} />
              </td>
              <td class="td-id">
                <span class="job-id-text">{truncate_id(job.job_id)}</span>
              </td>
              <td class="td-printer">{job[:printer] || "\u2014"}</td>
              <td class="td-label">{job[:label_name] || "\u2014"}</td>
              <td class="td-qty">{job[:page_count] || job[:copies] || 1}</td>
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
    """
  end

  # -- Job Detail Modal --

  attr :job, :map, required: true

  def job_detail_modal(assigns) do
    ~H"""
    <div class="preview-modal-backdrop">
      <div class="preview-modal job-detail-modal" phx-click-away="close_preview">
        <div class="preview-modal-header">
          <span class="preview-modal-title">JOB DETAILS</span>
          <button class="preview-modal-close" phx-click="close_preview">
            <.close_icon />
          </button>
        </div>
        <div class="job-detail-body">
          <dl class="printer-detail-list">
            <dt>STATUS</dt>
            <dd>
              <.status_indicator status={@job[:status]} />
            </dd>

            <dt>JOB ID</dt>
            <dd class="printer-detail-mono">{@job.job_id}</dd>

            <dt>DEVICE</dt>
            <dd>{@job[:printer] || "\u2014"}</dd>

            <dt :if={@job[:label_name]}>LABEL</dt>
            <dd :if={@job[:label_name]}>{@job[:label_name]}</dd>

            <dt :if={@job[:content_type]}>FORMAT</dt>
            <dd :if={@job[:content_type]}>{@job[:content_type]}</dd>

            <dt>PAGES</dt>
            <dd>{@job[:page_count] || @job[:copies] || 1}</dd>

            <dt>TIME</dt>
            <dd>{format_time(@job[:timestamp])}</dd>

            <dt :if={@job[:error]}>ERROR</dt>
            <dd :if={@job[:error]} class="job-detail-error">{@job[:error]}</dd>
          </dl>

          <div :if={@job[:preview_data]} class="job-detail-preview">
            <div class="printer-jobs-header">
              <span class="printer-jobs-title">PREVIEW</span>
            </div>
            <div class="preview-frame">
              <div
                :if={@job[:preview_content_type] == "application/vnd.zebra.zpl"}
                id={"zpl-detail-#{@job.job_id}"}
                phx-hook="ZplPreview"
                phx-update="ignore"
                data-zpl={@job[:preview_data]}
                data-size={@job[:preview_label_size] || "4x6"}
                data-dpmm={@job[:preview_dpmm] || "8dpmm"}
              />
              <iframe
                :if={@job[:preview_content_type] == "application/pdf"}
                src={"data:application/pdf;base64,#{@job[:preview_data]}"}
                class="preview-pdf-modal"
              />
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Printer Detail Modal --

  attr :printer, :map, required: true
  attr :jobs, :list, required: true

  def printer_detail_modal(assigns) do
    ~H"""
    <div class="preview-modal-backdrop">
      <div class="preview-modal printer-modal" phx-click-away="close_printer">
        <div class="preview-modal-header">
          <span class="preview-modal-title">{String.upcase(@printer.name)}</span>
          <button class="preview-modal-close" phx-click="close_printer">
            <.close_icon />
          </button>
        </div>
        <div class="printer-modal-body">
          <dl class="printer-detail-list">
            <dt>URI</dt>
            <dd class="printer-detail-mono">{@printer.uri}</dd>

            <dt>STATE</dt>
            <dd>{printer_state_label(@printer[:state])}</dd>

            <dt :if={@printer[:info]}>DESCRIPTION</dt>
            <dd :if={@printer[:info]}>{@printer[:info]}</dd>

            <dt :if={@printer[:location]}>LOCATION</dt>
            <dd :if={@printer[:location]}>{@printer[:location]}</dd>

            <dt :if={@printer[:resolution_default]}>RESOLUTION</dt>
            <dd :if={@printer[:resolution_default]}>
              {format_resolution(@printer[:resolution_default])}
            </dd>

            <dt :if={@printer[:resolution]}>SUPPORTED RESOLUTIONS</dt>
            <dd :if={@printer[:resolution]}>
              {format_resolutions(@printer[:resolution])}
            </dd>

            <dt :if={@printer[:media_default]}>DEFAULT MEDIA</dt>
            <dd :if={@printer[:media_default]}>{@printer[:media_default]}</dd>

            <dt :if={@printer[:media_ready]}>LOADED MEDIA</dt>
            <dd :if={@printer[:media_ready]}>
              {format_media_list(@printer[:media_ready])}
            </dd>

          </dl>

          <div class="printer-jobs-section">
            <div class="printer-jobs-header">
              <span class="printer-jobs-title">PRINT HISTORY</span>
              <span class="printer-jobs-count">{length(@jobs)}</span>
            </div>
            <div :if={@jobs == []} class="printer-jobs-empty">
              No jobs sent to this printer yet
            </div>
            <table :if={@jobs != []} class="printer-jobs-table">
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
                  :for={job <- @jobs}
                  class="printer-jobs-row-clickable"
                  phx-click="show_job_from_printer"
                  phx-value-job-id={job.job_id}
                >
                  <td>
                    <.status_indicator status={job[:status]} />
                  </td>
                  <td class="printer-jobs-id">{truncate_id(job.job_id)}</td>
                  <td>{job[:label_name] || "\u2014"}</td>
                  <td>{format_time(job.timestamp)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # -- Printers Slide-Out Panel --

  attr :show, :boolean, required: true
  attr :printers, :list, required: true
  attr :search, :string, required: true

  def printers_panel(assigns) do
    ~H"""
    <div
      class={"printers-panel-backdrop #{if @show, do: "printers-panel-backdrop-visible"}"}
      phx-click="toggle_printers_panel"
    >
    </div>
    <div class={"printers-panel #{if @show, do: "printers-panel-open"}"}>
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
            <.close_icon />
          </button>
        </div>
      </div>
      <form class="printers-panel-search" phx-change="search_printers">
        <input
          type="text"
          placeholder="Search printers..."
          value={@search}
          name="search"
          class="printers-search-input"
          autocomplete="off"
          phx-debounce="150"
        />
      </form>
      <div class="printers-panel-list">
        <div
          :for={printer <- filtered_printers(@printers, @search)}
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
        <div :if={filtered_printers(@printers, @search) == []} class="printers-panel-empty">
          No printers found
        </div>
      </div>
    </div>
    """
  end

  # -- Footer --

  attr :printers, :list, required: true
  attr :jobs, :list, required: true

  def dashboard_footer(assigns) do
    ~H"""
    <footer class="thermal-footer">
      <span>THERMAL PRINT SERVER</span>
      <span class="footer-dot"></span>
      <span>{length(@printers)} DEVICE(S)</span>
      <span class="footer-dot"></span>
      <span>{length(@jobs)} JOB(S)</span>
    </footer>
    """
  end

  # -- Shared sub-components --

  attr :status, :atom, required: true

  defp status_indicator(assigns) do
    ~H"""
    <div class={"status-indicator #{status_class(@status)}"}>
      <div class="status-dot"></div>
      <span class="status-text">{status_label(@status)}</span>
    </div>
    """
  end

  # -- Helpers --

  defp status_class(:completed), do: "status-completed"
  defp status_class(:failed), do: "status-failed"
  defp status_class(:printing), do: "status-printing"
  defp status_class(_), do: "status-queued"

  defp status_label(:completed), do: "DONE"
  defp status_label(:failed), do: "FAIL"
  defp status_label(:printing), do: "SEND"
  defp status_label(_), do: "WAIT"

  defp status_row_class(:failed), do: "row-failed"
  defp status_row_class(:printing), do: "row-printing"
  defp status_row_class(_), do: ""

  defp truncate_id(id) when is_binary(id) and byte_size(id) > 16 do
    String.slice(id, 0, 8) <> "..." <> String.slice(id, -4, 4)
  end

  defp truncate_id(id), do: id || "\u2014"

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_time(_), do: "\u2014"

  defp printer_state_label(3), do: "Idle"
  defp printer_state_label(4), do: "Processing"
  defp printer_state_label(5), do: "Stopped"
  defp printer_state_label(_), do: "Unknown"

  defp format_resolution(%{x: x, y: y, unit: unit}) do
    unit_str = if unit == :dpi, do: "dpi", else: "dpcm"
    if x == y, do: "#{x} #{unit_str}", else: "#{x}x#{y} #{unit_str}"
  end

  defp format_resolution(_), do: "\u2014"

  defp format_resolutions(resolutions) when is_list(resolutions) do
    resolutions |> Enum.map(&format_resolution/1) |> Enum.join(", ")
  end

  defp format_resolutions(res), do: format_resolution(res)

  defp format_media_list(media) when is_list(media), do: Enum.join(media, ", ")
  defp format_media_list(media) when is_binary(media), do: media
  defp format_media_list(_), do: "\u2014"

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

  @valid_statuses %{
    "completed" => :completed,
    "failed" => :failed,
    "printing" => :printing,
    "queued" => :queued
  }

  defp filter_by_status(jobs, status) do
    case Map.fetch(@valid_statuses, status) do
      {:ok, status_atom} -> Enum.filter(jobs, &(&1[:status] == status_atom))
      :error -> jobs
    end
  end

  defp filter_by_time(jobs, ""), do: jobs

  defp filter_by_time(jobs, minutes) do
    case Integer.parse(minutes) do
      {mins, ""} ->
        cutoff = DateTime.add(DateTime.utc_now(), -mins, :minute)
        Enum.filter(jobs, &(DateTime.compare(&1.timestamp, cutoff) != :lt))

      _ ->
        jobs
    end
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
