# Client Integration Guide

How to integrate with the Thermal Print Server from a client application (ERP, label editor, etc.).

## Prerequisites

You need access to:

| Resource | How to get it |
|----------|---------------|
| **S3 bucket** | Shared bucket for manifests and large jobs. Configured per environment. |
| **Reply SQS queue** | An SQS queue you own. The print server writes `job_status` responses here; you poll it. Create it once at startup and reuse for all requests. |
| **AWS credentials** | IAM credentials with permissions for `sqs:SendMessage` (request queue), `sqs:ReceiveMessage` and `sqs:DeleteMessage` (reply queue), `s3:GetObject`, `s3:ListBucket`. |
| **AWS region** | All resources (SQS, S3) are in the same region. |

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

### Freshness and liveness

The manifest is rewritten on every heartbeat (default 60s) and on every printer change. Use the **S3 object's `LastModified`** (from the `HeadObject` or `GetObject` response), not the `updatedAt` in the JSON, to determine staleness. Both `LastModified` and the `Date` response header come from S3's own clock, so you avoid any clock-skew issue between the print server and your client.

**Recommended staleness check:**

```
offline = s3_response.Date - object.LastModified > 2 × heartbeat_interval
```

With a 60s heartbeat, consider a site offline after ~3 minutes of no updates. This tolerates one missed write without false alarms.

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
  "replyToQueueUrl": "https://sqs.us-east-1.amazonaws.com/123456789/thermal-replies",
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
| `replyToQueueUrl` | No | string | SQS queue URL for the `job_status` response. Omit for fire-and-forget — no status will be sent. |
| `metadata` | No | object | Arbitrary key-value pairs. Stored with the job but not returned in status events. |

\* Either `data` or `s3Key` is required, not both.

### Job ID

The `jobId` is **client-generated**. Generate a UUID (v4) before sending and store it locally. This is how you correlate `job_status` events back to your job. The print server echoes it back unchanged.

### Reply queue

The `replyToQueueUrl` is the SQS queue where the print server will send the `job_status` response. Create this queue once at client startup (or provision it via infrastructure) and reuse it for all your requests. Do **not** create a new queue per request.

If you omit `replyToQueueUrl`, the server treats the job as fire-and-forget — it will still process the job, but no status response is sent.

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

## Receive Job Status

The print server sends a `job_status` SQS message to the `replyToQueueUrl` you included in the request. Use [long polling](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-short-and-long-polling.html) (`WaitTimeSeconds=20`) on your reply queue — it avoids empty receives and is AWS-recommended.

### SQS message attributes

Every response sets these attributes so you can filter without parsing the body:

| Attribute | Type | Possible values |
|-----------|------|-----------------|
| `site_id` | String | Site ID (e.g., `"warehouse-denver"`) |
| `event_type` | String | `"job_status"` |

### job_status body

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

**Note:** The `metadata` object from the original print job is **not** included in status responses. Use the `jobId` to join status messages with your local job records.

## Site Liveness and Printer State

There is no heartbeat or printer_change event stream. Both live in the S3 manifest:

- **Printer changes**: re-read `sites/{siteId}/manifest.json` periodically (e.g., every 60s). Replace your cached printer list entirely from the response.
- **Site liveness**: compare the S3 object's `LastModified` against the `Date` response header (both from S3's clock). If the gap exceeds ~2–3× the site's heartbeat interval, treat the site as offline.

See the [Freshness and liveness](#freshness-and-liveness) section above for the recommended check.

## Recommended Client Architecture

### On boot

1. Create (or look up) your SQS reply queue
2. List `sites/` in S3 to discover all sites
3. Read each `manifest.json`; cache printer lists, queue URLs, and `LastModified` per site
4. Start long-polling your reply queue

### Sending a job

1. Generate a UUID v4 for `jobId`
2. Store `{ jobId, status: "pending", printer, siteId, submittedAt }` in your local job tracker
3. Send the SQS request to the site's `queueUrl`, including your reply queue's URL as `replyToQueueUrl`
4. When a `job_status` message arrives matching your `jobId`, update the local record and delete the SQS message
5. Clean up completed/failed jobs from the tracker after a retention period

### Staying current

- **Printer state**: re-read `sites/*/manifest.json` on a periodic cadence (60s is fine) and replace your cached printer list
- **Site health**: on each manifest read, check `S3-Date - object.LastModified`; flag a site offline if the gap exceeds ~2–3× the heartbeat interval
- **No event subscription is needed** for state or liveness — polling the manifest covers both
