# Thermal Print Server

Elixir/Phoenix service that consumes print jobs from SQS and sends them to printers via CUPS/IPP. Supports ZPL and PDF content types. Companion to [Thermal](../thermal), a label editor.

## Architecture

```
SQS --> Broadway Pipeline --> [S3 fetch if needed] --> IPP (Hippy) --> CUPS --> Printer
                                                            |
                                              Preview (Labelary / PDF)
                                                            |
                                                  LiveView Dashboard

Events.Publisher ---> SNS Topic (fan-out to ERP, label editor, etc.)
                 ---> S3 printer snapshot (sites/{site_id}/printers.json)
```

- **Broadway** consumes from SQS with backpressure and batching
- **CUPS** manages printers — the app discovers them via IPP `GetPrinters`
- **Hippy** sends print data to CUPS over IPP
- **S3** stores large jobs (>200 KB); client gzips and uploads, server fetches and decompresses
- **Preview** renders ZPL via Labelary API or passes PDF through for dashboard display
- **LiveView dashboard** at `/` shows real-time job status, printer info, and label previews

## SQS Message Format

```json
{
  "jobId": "abc-123",
  "chunkIndex": 0,
  "totalChunks": 1,
  "printer": "TestZebra-4x6",
  "data": "^XA...^XZ",
  "contentType": "application/vnd.zebra.zpl",
  "copies": 1,
  "metadata": {
    "labelId": "lbl-1",
    "labelVersion": 3,
    "labelName": "Shipping Label"
  }
}
```

- `contentType` — `application/vnd.zebra.zpl` (default) or `application/pdf`
- `data` — inline print data (for jobs <200 KB)
- `s3Key` — S3 key for large jobs (mutually exclusive with `data`); data is gzipped
- Legacy `zpl` field is accepted for backward compatibility

## Key Modules

- `Broadway.PrintPipeline` — SQS consumer, wires parse -> S3 fetch -> print -> preview -> track
- `Broadway.MessageParser` — JSON parsing/validation, supports inline and S3-backed messages
- `Jobs.S3Fetcher` — Fetches and decompresses large jobs from S3
- `Jobs.Preview` — Generates preview images (ZPL via Labelary, PDF passthrough)
- `Jobs.Store` — ETS-backed job tracking for dashboard
- `Jobs.TestJob` — Submit test jobs directly (bypasses SQS)
- `Printer.Registry` — GenServer mapping printer names to configs, CUPS auto-discovery every 5 min
- `Printer.CupsDiscovery` — Discovers printers from CUPS via IPP `GetPrinters` + `GetPrinterAttributes`
- `Printer.Worker` — Sends print data via Hippy, sets IPP document format per content type
- `Printer.Labelary` — Renders ZPL to PNG via Labelary API
- `Events.Publisher` — Publishes job status, printer changes, and heartbeats to SNS; writes printer snapshots to S3

## Development

Development uses Docker Compose with a devcontainer:

- **CUPS container** — runs test printers (`TestZebra-4x6`, `TestZebra-4x2`, `TestZebra-Capture`)
- **goaws container** — local SQS + SNS mock (replaces ElasticMQ), with a response queue subscribed to the SNS topic
- **App container** — Elixir with live reload, auto-discovers printers from CUPS

Start with `docker compose up --build` or open in VS Code via **Dev Containers: Reopen in Container**.

The dashboard at `localhost:4000` shows discovered printers and a test panel for submitting ZPL/PDF. CUPS admin UI is at `localhost:631`.

## Configuration

All runtime config via environment variables in `runtime.exs`:
- `CUPS_URI` — CUPS server for printer discovery (e.g., `ipp://cups:631`)
- `PRINT_QUEUE_URL` — SQS queue (Broadway only starts when set)
- `PRINT_BUCKET` — S3 bucket for large jobs
- `PRINTER_N_NAME` / `PRINTER_N_URI` — static printer definitions (merged with CUPS discovery)
- `RESPONSE_TOPIC_ARN` — SNS topic for outbound events (Publisher only starts when set)
- `SITE_ID` — identifies this print server instance (required when `RESPONSE_TOPIC_ARN` is set)
- `SITE_NAME` — human-readable site name (e.g., "Denver Warehouse"); defaults to `SITE_ID`
- `HEARTBEAT_INTERVAL` — seconds between heartbeat events (default 60)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`

## Commands

- `mix phx.server` — start dev server on port 4000
- `mix test` — run tests (excludes integration tests)
- `mix test --include cups_integration` — include CUPS integration tests (requires CUPS)
- `mix test --include external_api` — include Labelary API tests (requires network)
- `mix test --include s3_integration` — include S3 integration tests (requires AWS)
- `mix test test/thermal_print_server/` — unit tests only
- `mix lint` — compile (warnings as errors) + format check + dialyzer
