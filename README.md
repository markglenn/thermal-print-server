# Thermal Print Server

Print server for [Thermal](https://github.com/markglenn/thermal) — real-time label dispatch with live monitoring and preview.

Thermal generates ZPL and publishes print jobs to SQS. This server consumes those jobs, verifies their HMAC signatures, and sends the ZPL to Zebra printers via IPP. A Phoenix LiveView dashboard provides real-time job monitoring and label preview.

## Architecture

```
SQS --> Broadway --> HMAC Verify --> IPP (Hippy) --> Zebra Printer
                                         |
                                   LiveView Dashboard
```

## Features

- **Broadway pipeline** for SQS consumption with backpressure and graceful shutdown
- **HMAC-SHA256 verification** on every message (shared secret with Thermal)
- **Real-time dashboard** with live job feed via PubSub
- **Virtual printers** that render ZPL via [Labelary](http://labelary.com) for testing
- **Label preview** directly in the dashboard
- **OTP supervision tree** with restart strategies

## Getting Started

```bash
mix setup
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to see the dashboard. In development, two virtual printers are preconfigured — use the "Send Test Job" panel to submit ZPL and see rendered labels.

## Configuration

All runtime configuration is via environment variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `PRINT_QUEUE_URL` | Yes | SQS queue URL |
| `PRINT_SIGNING_SECRET` | Yes | Shared HMAC secret (must match Thermal) |
| `AWS_ACCESS_KEY_ID` | Yes* | AWS credentials (*or use IAM role) |
| `AWS_SECRET_ACCESS_KEY` | Yes* | AWS credentials |
| `AWS_REGION` | No | Default: `us-east-1` |
| `PRINTER_N_NAME` | No | Printer name (e.g. `PRINTER_1_NAME=dock3`) |
| `PRINTER_N_URI` | No | Printer IPP URI (e.g. `PRINTER_1_URI=ipp://10.0.1.50:631/ipp/print`) |
| `SECRET_KEY_BASE` | Prod | Phoenix secret key |

## Docker

```bash
docker compose up --build
```

## Testing

```bash
mix test
```

## License

MIT
