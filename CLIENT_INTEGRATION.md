# Client Integration Guide

How to integrate with the Thermal Print Server from a client application (ERP, label editor, etc.).

## Prerequisites

You need access to:

| Resource | How to get it |
|----------|---------------|
| **S3 bucket** | Shared bucket for manifests and large jobs. Configured per environment. |
| **SNS topic ARN** | The print server publishes events here. Subscribe your own SQS queue to receive them. |
| **AWS credentials** | IAM credentials with permissions for `sqs:SendMessage`, `sqs:ReceiveMessage`, `s3:GetObject`, `s3:ListBucket`, `sns:Subscribe`. |
| **AWS region** | All resources (SQS, SNS, S3) are in the same region. |

These values are environment-specific. Your infrastructure team or deployment configuration provides them.

## Discover Sites and Printers

Each print server publishes a manifest to S3 at a well-known path:

```
s3://{bucket}/sites/{siteId}/manifest.json
```

### List all sites

List the `sites/` prefix in S3 to discover all active print servers:

```
S3.ListObjectsV2(bucket, prefix: "sites/", delimiter: "/")
```

Each common prefix (e.g., `sites/warehouse-denver/`) is a site. Read its `manifest.json` for details.

### Manifest format

```json
{
  "siteId": "warehouse-denver",
  "siteName": "Denver Warehouse",
  "queueUrl": "https://sqs.us-east-1.amazonaws.com/123456789/denver-print-queue",
  "printers": [
    {
      "name": "ZebraZD420-Dock3",
      "state": 3,
      "info": "Shipping label printer",
      "location": "Dock 3",
      "resolution_default": { "x": 203, "y": 203, "unit": "dpi" },
      "media_default": "oe_4x6-label_4x6in",
      "media_ready": ["oe_4x6-label_4x6in"]
    }
  ],
  "updatedAt": "2026-04-05T22:11:25.081033Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `siteId` | string | Unique identifier for the site |
| `siteName` | string | Human-readable site name (e.g., "Denver Warehouse") |
| `queueUrl` | string | SQS queue URL — send print jobs here |
| `printers` | array | Printers at this site (see below) |
| `updatedAt` | string | ISO 8601 timestamp of last update |

#### Printer fields

All fields except `name` are optional. Availability depends on the printer's CUPS driver.

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Printer name. Use this value in the `printer` field when sending jobs. |
| `state` | integer | `3` = Idle, `4` = Processing, `5` = Stopped |
| `info` | string | Description set in CUPS |
| `location` | string | Location set in CUPS |
| `resolution_default` | object | `{ "x": 203, "y": 203, "unit": "dpi" }` |
| `resolution` | array | All supported resolutions |
| `media_default` | string | Default loaded media (e.g., `"oe_4x6-label_4x6in"`) |
| `media_ready` | array | Currently loaded media sizes |

### Freshness

The manifest is rewritten on every heartbeat (default 60s) and on every printer change. If `updatedAt` is older than a few minutes, the site may be offline.

Consider setting an S3 lifecycle rule on the `sites/` prefix to expire manifests after 24 hours. Live servers continuously refresh their manifest, so only dead servers' manifests will age out.

## Send a Print Job

Send a JSON message to the site's `queueUrl` (from the manifest) via SQS.

### Example

```json
{
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "chunkIndex": 0,
  "totalChunks": 1,
  "printer": "ZebraZD420-Dock3",
  "data": "^XA^FO50,50^A0N,40,40^FDHello World^FS^XZ",
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

### Fields

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `jobId` | Yes | string | Client-generated UUID. Used to correlate status events. |
| `chunkIndex` | Yes | integer | 0-based index. Use `0` for single-message jobs. |
| `totalChunks` | Yes | integer | Total messages for this job. Use `1` for single-message jobs. |
| `printer` | Yes | string | Printer name — must match a `name` from the manifest. |
| `data` | * | string | Print data: raw ZPL string, or raw PDF bytes. |
| `s3Key` | * | string | S3 object key for large jobs. Mutually exclusive with `data`. |
| `contentType` | No | string | `"application/vnd.zebra.zpl"` (default) or `"application/pdf"` |
| `copies` | No | integer | Number of copies. Default `1`. |
| `metadata` | No | object | Arbitrary key-value pairs. Stored with the job but not returned in status events. |

\* Either `data` or `s3Key` is required, not both.

### Job ID

The `jobId` is **client-generated**. Generate a UUID (v4) before sending and store it locally. This is how you correlate `job_status` events back to your job. The print server echoes it back unchanged.

### Large jobs (>200 KB)

SQS has a 256 KB message size limit. For large print data:

1. Gzip the print data
2. Upload to S3: `s3://{bucket}/{your-chosen-key}.gz`
3. Send the SQS message with `"s3Key": "{your-chosen-key}.gz"` instead of `"data"`

The `.gz` extension is required — the print server uses it to know to decompress.

### Error cases

| Scenario | Result |
|----------|--------|
| `printer` name not found in registry | Job fails with `job_status.status = "failed"` |
| Invalid JSON or missing required fields | Job fails |
| `s3Key` points to nonexistent object | Job fails |
| CUPS/printer unreachable | Job fails |
| Valid job, printer idle | Job completes, `job_status.status = "completed"` |

All failures are reported via `job_status` events if the `jobId` could be parsed from the message. If the message is completely unparseable, no event is published.

## Listen for Events

The print server publishes events to an SNS topic. To receive them:

1. Create an SQS queue for your application
2. Subscribe your queue to the SNS topic ARN
3. Optionally set an SNS filter policy to limit which events you receive
4. Poll your SQS queue for messages

### SNS message attributes

Every event includes these attributes for SNS filter policies:

| Attribute | Type | Possible values |
|-----------|------|-----------------|
| `site_id` | String | Site ID (e.g., `"warehouse-denver"`) |
| `event_type` | String | `"job_status"`, `"printer_change"`, `"heartbeat"` |

### Filter policy examples

Only receive events from one site:
```json
{ "site_id": ["warehouse-denver"] }
```

Only receive job status events:
```json
{ "event_type": ["job_status"] }
```

Only receive job results from a specific site:
```json
{ "site_id": ["warehouse-denver"], "event_type": ["job_status"] }
```

### Event: job_status

Published when a print job completes or fails.

```json
{
  "siteId": "warehouse-denver",
  "eventType": "job_status",
  "jobId": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "printer": "ZebraZD420-Dock3",
  "contentType": "application/vnd.zebra.zpl",
  "error": null,
  "timestamp": "2026-04-05T22:15:00.000000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `siteId` | string | Site that processed the job |
| `eventType` | string | Always `"job_status"` |
| `jobId` | string | Matches the `jobId` you sent |
| `status` | string | `"completed"` or `"failed"` |
| `printer` | string | Printer the job was sent to (may be `null` on parse failures) |
| `contentType` | string | Content type of the job (may be `null` on parse failures) |
| `error` | string/null | Error description if failed, `null` if completed |
| `timestamp` | string | ISO 8601 timestamp |

**Note:** The `metadata` object from the original print job is **not** included in status events. Use the `jobId` to join status events with your local job records.

### Event: printer_change

Published when printers are added, removed, or change state at a site.

```json
{
  "siteId": "warehouse-denver",
  "eventType": "printer_change",
  "printers": [
    { "name": "ZebraZD420-Dock3", "state": 3 },
    { "name": "ZebraZD620-Office", "state": 3 }
  ],
  "timestamp": "2026-04-05T22:15:00.000000Z"
}
```

This is the **full printer list** for the site, not a diff. Replace your cached list entirely.

### Event: heartbeat

Published periodically (default every 60s). Indicates the site is online.

```json
{
  "siteId": "warehouse-denver",
  "eventType": "heartbeat",
  "printerCount": 3,
  "uptimeSeconds": 3600,
  "timestamp": "2026-04-05T22:15:00.000000Z"
}
```

Use this to detect offline sites. If heartbeats stop arriving for a site, it's likely down.

## Recommended Client Architecture

### On boot

1. List `sites/` in S3 to discover all sites
2. Read `manifest.json` for each site you care about
3. Cache the printer lists and queue URLs locally
4. Start polling your SNS-subscribed SQS queue for events

### Sending a job

1. Generate a UUID v4 for `jobId`
2. Store `{ jobId, status: "pending", printer, siteId, submittedAt }` in your local job tracker
3. Send the SQS message to the site's `queueUrl`
4. When a `job_status` event arrives matching your `jobId`, update the local record
5. Clean up completed/failed jobs from the tracker after a retention period

### Staying current

- **Printer changes**: Replace your cached printer list when you receive a `printer_change` event for a site
- **Site health**: Track the last heartbeat timestamp per site. If no heartbeat arrives for >2 minutes, consider the site offline
- **Manifest refresh**: Re-read `manifest.json` if the `printerCount` in a heartbeat differs from your cached printer list, or periodically (e.g., every 5 minutes)
