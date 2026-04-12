# Architecture

Elixir/Phoenix service that consumes print jobs from SQS, sends them to thermal printers via CUPS/IPP, and publishes status events to SNS. Supports ZPL and PDF content types with real-time monitoring through a LiveView dashboard.

## System Overview

```
                                  ┌──────────────────────┐
                                  │   Label Editor /     │
                                  │   ERP / Client App   │
                                  └───────┬──────────────┘
                                          │
                            SQS message   │   SNS subscription
                            (print job)   │   (status events)
                                          ▼
┌──────────┐          ┌───────────────────────────────────────────────┐
│          │  poll    │           Thermal Print Server                │
│   SQS    │◄─────────┤                                               │
│  Queue   │──────────►  Broadway ──► Registry ──► Worker ──► CUPS ──►│──► Printer
│          │          │  Pipeline     lookup       (Hippy)    (IPP)   │
└──────────┘          │      │                                        │
                      │      ├──► S3Fetcher (large jobs)              │
┌──────────┐          │      ├──► Preview (ZPL/PDF)                   │
│          │  fetch   │      └──► Store (ETS) ──► PubSub              │
│    S3    │◄─────────┤                               │               │
│  Bucket  │──────────►                    ┌──────────┤               │
│          │          │                    │          │               │
└──────────┘          │              Dashboard    Publisher           │
                      │              (LiveView)   (GenServer)         │
┌──────────┐          │                               │               │
│   SNS    │          │                               │               │
│  Topic   │◄─────────┤  publish events ──────────────┘               │
└──────────┘          │                                               │
                      │  write snapshot                               │
┌──────────┐          │       │                                       │
│    S3    │◄─────────┤───────┘                                       │
│ Manifest │          └───────────────────────────────────────────────┘
└──────────┘
```

## Print Job Lifecycle

A print job flows through these stages:

### 1. Message Arrival

`BroadwaySQS.Producer` long-polls the SQS queue (20-second wait, 1 producer, 4 concurrent processors). Each message is a JSON payload containing the job ID, target printer, print data, content type, and optional metadata.

### 2. Parse & Validate

`MessageParser.parse/1` validates the JSON:

- **Required**: `jobId` (string), `printer` (string)
- **Data source**: exactly one of `data` (inline), `s3Key` (S3 reference), or `zpl` (legacy)
- **Content type**: `application/vnd.zebra.zpl` (default) or `application/pdf`
- **Copies**: positive integer, defaults to 1
- **Metadata**: optional `labelId`, `labelVersion`, `labelName`, `labelSize`, `dpmm`

### 3. Data Resolution

If the message contains `s3Key` instead of inline `data`, `S3Fetcher.fetch/1` retrieves the object from S3. Files ending in `.gz` are automatically decompressed. This path handles jobs exceeding the ~200 KB SQS inline limit — the client gzips and uploads to S3, then sends only the key via SQS.

### 4. Printer Lookup

`Registry.lookup/1` resolves the printer name to a configuration map containing the IPP URI and capabilities. The registry merges static env-var printers with CUPS-discovered printers (static takes precedence).

### 5. Print

`Worker.print/4` constructs a `Hippy.Operation.PrintJob` and sends it to CUPS over IPP. The operation includes the printer URI, raw print data, copy count, and document format (set for PDF; omitted for ZPL since Zebra printers handle raw ZPL natively).

### 6. Preview

`Preview.generate/3` prepares data for the dashboard:

- **ZPL**: passes the raw ZPL through (rendered client-side via `zpl-renderer-js`)
- **PDF**: base64-encodes the binary (embedded in an iframe)

Preview failures do not fail the job.

### 7. Track & Notify

`Store.record/2` writes the job to an ETS table (capped at 500 entries, oldest pruned). A PubSub broadcast notifies the dashboard (live update) and the Publisher (SNS event).

### 8. Acknowledge

`handle_message/3` always returns the message, so BroadwaySQS auto-acknowledges regardless of success or failure. Failed jobs are tracked in ETS and published to SNS, but the SQS message is removed.

## Service Integrations

### AWS SQS — Job Queue

|              |                                                                |
| ------------ | -------------------------------------------------------------- |
| **Library**  | `broadway_sqs` (~> 0.7) via `ex_aws_sqs`                       |
| **Protocol** | HTTP REST (AWS SQS API)                                        |
| **Config**   | `PRINT_QUEUE_URL` env var                                      |
| **Auth**     | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` or instance role |
| **Dev mock** | GoAWS on port 4100                                             |

Broadway starts only when `PRINT_QUEUE_URL` is set. The producer uses long-polling (20s) with concurrency 1; processing parallelism comes from 4 processor workers.

`TestJob.submit/4` publishes test messages back to the same queue for dashboard testing.

### AWS S3 — Large Job Storage & Manifests

|              |                        |
| ------------ | ---------------------- |
| **Library**  | `ex_aws_s3` (~> 2.5)   |
| **Protocol** | HTTP REST (AWS S3 API) |
| **Config**   | `PRINT_BUCKET` env var |
| **Dev mock** | MinIO on port 9000     |

Two distinct uses:

1. **Job data** — `S3Fetcher` reads objects by key, auto-decompresses `.gz` files. The client is responsible for uploading large payloads before sending the SQS message.
2. **Printer manifest** — `Publisher` writes `sites/{site_id}/manifest.json` containing the current printer list, site metadata, and queue URL. Updated on startup, printer changes, and each heartbeat.

### AWS SNS — Event Publishing

|              |                                                           |
| ------------ | --------------------------------------------------------- |
| **Library**  | `ex_aws_sns` (~> 2.3)                                     |
| **Protocol** | HTTP REST (AWS SNS API)                                   |
| **Config**   | `RESPONSE_TOPIC_ARN` env var                              |
| **Dev mock** | GoAWS on port 4100 (topic subscribed to a response queue) |

Publisher starts only when `RESPONSE_TOPIC_ARN` is set. All messages include `site_id` and `event_type` as SNS message attributes for subscriber filtering.

**Event types:**

| Event            | Trigger                                                    | Key Fields                                           |
| ---------------- | ---------------------------------------------------------- | ---------------------------------------------------- |
| `job_status`     | Job completes or fails                                     | `jobId`, `status`, `printer`, `contentType`, `error` |
| `printer_change` | Registry refresh detects changes                           | `printers` (full list with capabilities)             |
| `heartbeat`      | Timer (default 60s, configurable via `HEARTBEAT_INTERVAL`) | `printerCount`, `uptimeSeconds`                      |

### CUPS/IPP — Printer Management

|              |                                                                                           |
| ------------ | ----------------------------------------------------------------------------------------- |
| **Library**  | `hippy` (fork: `MBXSystems/hippy`)                                                        |
| **Protocol** | IPP (RFC 8010) over TCP, port 631                                                         |
| **Config**   | `CUPS_URI` for discovery; `PRINTER_N_NAME`/`PRINTER_N_URI` for static                     |
| **Dev**      | CUPS container with test printers (`TestZebra-4x6`, `TestZebra-4x2`, `TestZebra-Capture`) |

**Discovery** (`CupsDiscovery`):

1. `GetPrinters` — lists all printers on the CUPS server
2. `GetPrinterAttributes` — fetches capabilities per printer: resolution, media support, state, location, description

**Printing** (`Worker`):

- `PrintJob` operation with URI, data, job name, copies, and document format
- ZPL sent as raw data (no document format attribute); PDF includes `document_format`

### ZPL Preview — Client-Side Rendering

|              |                                                              |
| ------------ | ------------------------------------------------------------ |
| **Library**  | `zpl-renderer-js` (npm, loaded async in browser)             |
| **Protocol** | N/A — runs entirely in the browser via the `ZplPreview` hook |
| **Usage**    | Renders ZPL to PNG for the dashboard preview modal           |

The `ZplPreview` LiveView JS hook calls `zplToBase64MultipleAsync` from `zpl-renderer-js` to render ZPL labels as PNG images client-side. Label dimensions and DPI are derived from job metadata (`labelSize`, `dpmm`). Multi-label ZPL streams render as a paged gallery.

## Supervision Tree

```
Application (one_for_one)
├── Telemetry              — metrics collection
├── DNSCluster             — multi-node clustering (optional, via DNS_CLUSTER_QUERY)
├── Phoenix.PubSub         — internal message bus ("print_jobs", "printers" channels)
├── Jobs.Store             — ETS-backed job history (GenServer, max 500 entries)
├── Printer.Registry       — printer name → config map (GenServer, 5-min auto-refresh)
├── Endpoint               — Phoenix HTTP on port 4000 (Bandit adapter)
├── Broadway.PrintPipeline — SQS consumer + processors (conditional: PRINT_QUEUE_URL)
└── Events.Publisher       — SNS/S3 event publisher (conditional: RESPONSE_TOPIC_ARN)
```

Start order matters: PubSub must be up before Store, Registry, Pipeline, and Publisher. Store and Registry must be up before Pipeline processes messages. Publisher subscribes to PubSub on init and writes the initial S3 manifest.

The `one_for_one` strategy means each child restarts independently. A Store crash loses in-memory job history but processing continues. A Registry crash triggers rediscovery on restart. A Pipeline crash stops message consumption but SQS retains unprocessed messages.

## Printer Registry

The Registry GenServer maintains a map of printer names to configuration maps in process state (not ETS).

**Sources** (merged on each refresh, static config wins):

| Source          | Config                                   | Priority                     |
| --------------- | ---------------------------------------- | ---------------------------- |
| CUPS discovery  | `CUPS_URI` env var                       | Lower (overridden by static) |
| Static env vars | `PRINTER_1_NAME` / `PRINTER_1_URI`, etc. | Higher                       |

**Printer config fields:**

```
name, uri, state (3=Idle, 4=Processing, 5=Stopped),
info, location, resolution, resolution_default,
media_supported, media_default, media_ready
```

**Refresh triggers:**

- Automatic: every 5 minutes via `Process.send_after`
- Manual: dashboard "Refresh" button calls `Registry.refresh_sync/0`
- On refresh: broadcasts `:printers_updated` to PubSub → dashboard updates, Publisher writes S3 manifest and SNS event

## Jobs Store

`Jobs.Store` is a GenServer wrapping a public ETS table (`:ThermalPrintServer.Jobs.Store`, read-concurrent). Records are keyed by `job_id` and contain status, printer, label name, content type, copies, page count, preview data, error, and timestamp.

**Page count calculation:**

- ZPL: count `^XA` markers (each = one label) × copies
- PDF: count `/Type /Page` markers × copies

The store caps at 500 entries, pruning the oldest when exceeded. `Store.clear/0` wipes the table (used by the dashboard's "Clear Queue" action).

## LiveView Dashboard

Single-page app at `/` providing real-time monitoring:

- **Job feed** — last 100 jobs with status (DONE/FAIL/SEND/WAIT), filterable by device, status, and time window
- **Printer panel** — slide-out list of all printers, searchable, with detail modals showing capabilities (resolution, media, state)
- **Job preview modal** — ZPL rendered client-side via Labelary JS hook; PDF embedded in iframe
- **Test job form** — select printer, content type, label size, DPI; editable ZPL textarea; submits to SQS
- **Real-time updates** — LiveView subscribes to PubSub `"print_jobs"` and `"printers"` channels; no polling

**JS hooks:**

- `UtcClock` — client-side UTC time display (1-second interval)
- `ZplPreview` — client-side ZPL rendering via `zpl-renderer-js`

## S3 Printer Manifest

The Publisher writes a JSON manifest to `sites/{site_id}/manifest.json` in the print bucket, enabling external systems to discover printers without an SNS subscription:

```json
{
  "siteId": "warehouse-dock-1",
  "siteName": "Denver Warehouse",
  "queueUrl": "https://sqs.us-east-1.amazonaws.com/.../thermal-print-queue",
  "printers": [
    {
      "name": "thermal-1",
      "state": 3,
      "info": "Zebra GK420t",
      "location": "Dock 1",
      "resolution": [{ "x": 203, "y": 203, "unit": "dpi" }],
      "media_supported": ["4x6", "4x4"],
      "media_default": "4x6"
    }
  ],
  "updatedAt": "2026-04-11T10:30:45Z"
}
```

Updated on: app startup, printer changes, and each heartbeat.

## SQS Message Format

```json
{
  "jobId": "abc-123",
  "printer": "TestZebra-4x6",
  "data": "^XA...^XZ",
  "contentType": "application/vnd.zebra.zpl",
  "copies": 1,
  "metadata": {
    "labelId": "lbl-1",
    "labelVersion": 3,
    "labelName": "Shipping Label",
    "labelSize": "4x6",
    "dpmm": "8dpmm"
  }
}
```

| Field         | Type    | Required                    | Notes                                                      |
| ------------- | ------- | --------------------------- | ---------------------------------------------------------- |
| `jobId`       | string  | yes                         | Unique job identifier                                      |
| `printer`     | string  | yes                         | Must match a registered printer name                       |
| `data`        | string  | one of `data`/`s3Key`/`zpl` | Inline print data (< 200 KB)                               |
| `s3Key`       | string  | one of `data`/`s3Key`/`zpl` | S3 key for large jobs; data is gzipped                     |
| `zpl`         | string  | one of `data`/`s3Key`/`zpl` | Legacy field, treated as ZPL                               |
| `contentType` | string  | no                          | `application/vnd.zebra.zpl` (default) or `application/pdf` |
| `copies`      | integer | no                          | Positive integer, defaults to 1                            |
| `metadata`    | object  | no                          | Passed through to tracking and events                      |

## SNS Event Format

All events include these top-level fields:

```json
{
  "siteId": "warehouse-dock-1",
  "eventType": "job_status|printer_change|heartbeat",
  "timestamp": "2026-04-11T10:30:45Z"
}
```

**job_status** adds: `jobId`, `status` ("completed"/"failed"), `printer`, `contentType`, `error`

**printer_change** adds: `printers` (full array with capabilities)

**heartbeat** adds: `printerCount`, `uptimeSeconds`

SNS message attributes (`site_id`, `event_type`) enable subscriber-side filtering.

## Local Development

Docker Compose runs four services:

| Service | Image          | Port       | Purpose                                            |
| ------- | -------------- | ---------- | -------------------------------------------------- |
| `app`   | Elixir 1.18    | 4000       | Phoenix dev server with live reload                |
| `cups`  | Debian + CUPS  | 631        | Test printers (TestZebra-4x6, 4x2, Capture)        |
| `goaws` | pafortin/goaws | 4100       | SQS + SNS mock (queue + topic + subscription)      |
| `minio` | minio/minio    | 9000, 9001 | S3-compatible storage (bucket: thermal-print-jobs) |

A `minio-init` sidecar creates the bucket on first start. The app container waits for CUPS (healthcheck) and MinIO (healthcheck) before starting.

Start with `docker compose up --build` or use the VS Code devcontainer (`.devcontainer/devcontainer.json`).

## Production Deployment

Multi-stage Dockerfile:

1. **Build** (elixir:1.18) — deps, compile, asset deploy, release
2. **Runtime** (debian:bookworm-slim) — minimal OS with the release binary

Expects real AWS services (SQS, S3, SNS) and either a CUPS server or static printer config. Supports Kubernetes clustering via `DNS_CLUSTER_QUERY`.

Required env vars: `SECRET_KEY_BASE`, `PRINT_QUEUE_URL`, `PHX_HOST`, `PHX_SERVER=true`. See the Configuration section in CLAUDE.md for the full list.
