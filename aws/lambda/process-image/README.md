# process-image Lambda

Processes uploaded image posts after S3 receives a new object under `raw/images/`.

## Behavior

- Trigger: S3 `ObjectCreated` for `raw/images/` prefix.
- Input: original uploaded image in S3.
- Runtime: Node.js 20.x, 1024 MB memory, 60 second timeout.
- Output:
  - `processed/images/<userId>/<id>_thumb.webp` at 200px wide
  - `processed/images/<userId>/<id>_feed.webp` at 800px wide
  - `processed/images/<userId>/<id>_full.webp` at 1600px wide
- Encoding: WebP, quality 80, no enlargement.
- Database update:
  - `thumbnail_file_key`
  - `processed_file_key` for the feed-sized image
  - `full_file_key`
  - `width`
  - `height`
  - `processing_status`
  - `processing_started_at`
  - `processing_completed_at`
  - `processing_error`

## Environment

```text
SUPABASE_SECRET_ID=yapp/supabase-service
PROCESSED_PREFIX=processed/images/
WEBP_QUALITY=80
```

## Package

Run from this directory:

```powershell
.\package.ps1
```

The package script bundles Linux x64 Sharp dependencies into `build/` before creating `process-image.zip`.

## Manual test before S3 trigger

Create or pick a known `media_files` row whose `raw_file_key` points to an existing uploaded image, then invoke the Lambda with an S3 event-shaped payload:

```json
{
  "Records": [
    {
      "s3": {
        "bucket": { "name": "YOUR_BUCKET_NAME" },
        "object": { "key": "raw/images/USER_ID/IMAGE_ID.jpg" }
      }
    }
  ]
}
```

Only add the S3 notification after the manual invocation creates all three WebP files and updates the row.
