# Thermal Print Server

Elixir/Phoenix service that consumes print jobs from SQS and sends ZPL to Zebra thermal printers via IPP. Companion to [Thermal](../thermal), a ZPL label editor.

## Architecture

```
SQS --> Broadway Pipeline --> HMAC Verify --> IPP (Hippy) --> Zebra Printer
                                                  |
                                        LiveView Dashboard
```

- **Broadway** consumes from SQS with backpressure and batching
- **HMAC-SHA256** signature verification on every message (shared secret with Thermal)
- **Hippy** sends ZPL to printers over IPP
- **Virtual printers** (`virtual:labelary` URI) render ZPL via Labelary API for testing
- **LiveView dashboard** at `/` shows real-time job status via PubSub

## SQS Message Format

Signature = `HMAC-SHA256(secret, jobId + chunkIndex + zpl)`. Large batches are chunked by Thermal — each message stays under 240 KB.

## Key Modules

- `Broadway.PrintPipeline` — SQS consumer, wires parse -> verify -> print -> track
- `Broadway.MessageParser` — JSON parsing/validation
- `Jobs.Verifier` — HMAC signature verification
- `Jobs.Store` — ETS-backed job tracking for dashboard
- `Jobs.TestJob` — Submit test jobs directly (bypasses SQS/HMAC)
- `Printer.Registry` — GenServer mapping printer names to IPP URIs
- `Printer.Worker` — Sends ZPL via Hippy (real) or Labelary (virtual)
- `Printer.Labelary` — Renders ZPL to PNG via Labelary API

## Development

Virtual printers are configured in `dev.exs` — no real printer or SQS needed. Use the "Send Test Job" panel on the dashboard to submit ZPL and see rendered label previews.

## Configuration

All runtime config via environment variables in `runtime.exs`:
- `PRINT_QUEUE_URL` — SQS queue (Broadway only starts when set)
- `PRINT_SIGNING_SECRET` — shared HMAC secret
- `PRINTER_N_NAME` / `PRINTER_N_URI` — printer definitions
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`

## Commands

- `mix phx.server` — start dev server on port 4000
- `mix test` — run tests
- `mix test test/thermal_print_server/` — unit tests only
- `mix lint` — compile (warnings as errors) + format check + dialyzer
