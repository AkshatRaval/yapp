import json
import os
import subprocess
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import boto3


s3 = boto3.client("s3")
secretsmanager = boto3.client("secretsmanager")

SECRET_ID = os.environ["SUPABASE_SECRET_ID"]
PROCESSED_PREFIX = os.environ.get("PROCESSED_PREFIX", "processed/audio/")
FFMPEG_PATH = os.environ.get("FFMPEG_PATH", "/opt/bin/ffmpeg")
TARGET_LUFS = os.environ.get("TARGET_LUFS", "-16")
TARGET_LRA = os.environ.get("TARGET_LRA", "11")
TARGET_TP = os.environ.get("TARGET_TP", "-1.5")


def handler(event: dict[str, Any], _context: Any) -> dict[str, Any]:
    records = event.get("Records", [])
    results = []

    for record in records:
        bucket = record["s3"]["bucket"]["name"]
        raw_key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

        if not raw_key.startswith("raw/audio/"):
            results.append({"raw_key": raw_key, "skipped": "not raw audio"})
            continue

        try:
            result = process_object(bucket, raw_key)
            results.append({"raw_key": raw_key, **result})
        except Exception as error:
            update_media_status(raw_key, "failed", processing_error=str(error))
            raise

    return {"results": results}


def process_object(bucket: str, raw_key: str) -> dict[str, Any]:
    media_file = find_media_file(raw_key)
    media_id = media_file["id"]

    update_media_status(raw_key, "processing")

    processed_key = build_processed_key(raw_key)

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        raw_path = temp_path / "raw.ogg"
        processed_path = temp_path / "processed.webm"

        s3.download_file(bucket, raw_key, str(raw_path))

        loudnorm_stats = measure_loudness(raw_path)
        encode_normalized(raw_path, processed_path, loudnorm_stats)

        s3.upload_file(
            str(processed_path),
            bucket,
            processed_key,
            ExtraArgs={
                "ContentType": "audio/webm",
                "CacheControl": "public, max-age=31536000, immutable",
            },
        )

    normalized_loudness_lufs = parse_numeric(loudnorm_stats.get("input_i"))
    update_media_completed(media_id, processed_key, normalized_loudness_lufs)

    return {
        "media_file_id": media_id,
        "processed_key": processed_key,
        "normalized_loudness_lufs": normalized_loudness_lufs,
    }


def measure_loudness(raw_path: Path) -> dict[str, Any]:
    command = [
        FFMPEG_PATH,
        "-hide_banner",
        "-nostats",
        "-i",
        str(raw_path),
        "-af",
        f"loudnorm=I={TARGET_LUFS}:LRA={TARGET_LRA}:TP={TARGET_TP}:print_format=json",
        "-f",
        "null",
        "-",
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"ffmpeg loudness measurement failed: {completed.stderr}")

    return extract_loudnorm_json(completed.stderr)


def encode_normalized(raw_path: Path, processed_path: Path, stats: dict[str, Any]) -> None:
    measured_filter = (
        f"loudnorm=I={TARGET_LUFS}:LRA={TARGET_LRA}:TP={TARGET_TP}:"
        f"measured_I={stats['input_i']}:"
        f"measured_TP={stats['input_tp']}:"
        f"measured_LRA={stats['input_lra']}:"
        f"measured_thresh={stats['input_thresh']}:"
        f"offset={stats['target_offset']}:"
        "linear=true:print_format=summary"
    )

    command = [
        FFMPEG_PATH,
        "-hide_banner",
        "-y",
        "-i",
        str(raw_path),
        "-vn",
        "-af",
        measured_filter,
        "-c:a",
        "libopus",
        "-b:a",
        "48k",
        "-ac",
        "1",
        "-ar",
        "48000",
        str(processed_path),
    ]
    completed = subprocess.run(command, capture_output=True, text=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(f"ffmpeg normalized encode failed: {completed.stderr}")


def find_media_file(raw_key: str) -> dict[str, Any]:
    response = supabase_request(
        "GET",
        f"/rest/v1/media_files?raw_file_key=eq.{quote_query_value(raw_key)}&select=id",
    )
    if not response:
        raise RuntimeError(f"No media_files row found for raw_file_key={raw_key}")
    return response[0]


def update_media_status(
    raw_key: str,
    status: str,
    processing_error: str | None = None,
) -> None:
    body: dict[str, Any] = {"processing_status": status}
    if status == "processing":
        body["processing_started_at"] = utc_now()
        body["processing_error"] = None
    if processing_error:
        body["processing_error"] = processing_error[:2000]

    supabase_request(
        "PATCH",
        f"/rest/v1/media_files?raw_file_key=eq.{quote_query_value(raw_key)}",
        body,
        prefer="return=minimal",
    )


def update_media_completed(
    media_id: str,
    processed_key: str,
    normalized_loudness_lufs: float | None,
) -> None:
    body = {
        "processed_file_key": processed_key,
        "processing_status": "completed",
        "processing_completed_at": utc_now(),
        "processing_error": None,
        "normalized_loudness_lufs": normalized_loudness_lufs,
    }

    supabase_request(
        "PATCH",
        f"/rest/v1/media_files?id=eq.{media_id}",
        body,
        prefer="return=minimal",
    )


def supabase_request(
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
    prefer: str | None = None,
) -> Any:
    secret = get_supabase_secret()
    url = f"{secret['SUPABASE_URL'].rstrip('/')}{path}"
    payload = json.dumps(body).encode("utf-8") if body is not None else None

    headers = {
        "apikey": secret["SUPABASE_SERVICE_ROLE_KEY"],
        "Authorization": f"Bearer {secret['SUPABASE_SERVICE_ROLE_KEY']}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer

    request = urllib.request.Request(url, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            text = response.read().decode("utf-8")
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        text = error.read().decode("utf-8")
        raise RuntimeError(f"Supabase {method} {path} failed: {error.code} {text}") from error


def get_supabase_secret() -> dict[str, str]:
    if not hasattr(get_supabase_secret, "_cache"):
        response = secretsmanager.get_secret_value(SecretId=SECRET_ID)
        setattr(get_supabase_secret, "_cache", json.loads(response["SecretString"]))
    return getattr(get_supabase_secret, "_cache")


def build_processed_key(raw_key: str) -> str:
    filename = Path(raw_key).stem
    parent_parts = Path(raw_key).parts[2:-1]
    parent = "/".join(parent_parts)
    if parent:
        return f"{PROCESSED_PREFIX}{parent}/{filename}.webm"
    return f"{PROCESSED_PREFIX}{filename}.webm"


def extract_loudnorm_json(stderr: str) -> dict[str, Any]:
    start = stderr.rfind("{")
    end = stderr.rfind("}")
    if start == -1 or end == -1 or end <= start:
        raise RuntimeError(f"Could not parse loudnorm output: {stderr}")
    return json.loads(stderr[start : end + 1])


def quote_query_value(value: str) -> str:
    return urllib.parse.quote(value, safe="")


def parse_numeric(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()
