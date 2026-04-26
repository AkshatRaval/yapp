import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import {
  GetSecretValueCommand,
  SecretsManagerClient,
} from "@aws-sdk/client-secrets-manager";
import sharp from "sharp";

const s3 = new S3Client({});
const secretsManager = new SecretsManagerClient({});

const SECRET_ID = process.env.SUPABASE_SECRET_ID;
const PROCESSED_PREFIX = process.env.PROCESSED_PREFIX ?? "processed/images/";
const WEBP_QUALITY = Number.parseInt(process.env.WEBP_QUALITY ?? "80", 10);

const VARIANTS = [
  { column: "thumbnail_file_key", suffix: "thumb", width: 200 },
  { column: "processed_file_key", suffix: "feed", width: 800 },
  { column: "full_file_key", suffix: "full", width: 1600 },
];

let cachedSecret;

export const handler = async (event) => {
  const records = event.Records ?? [];
  const results = [];

  for (const record of records) {
    const bucket = record.s3.bucket.name;
    const rawKey = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

    if (!rawKey.startsWith("raw/images/")) {
      results.push({ rawKey, skipped: "not raw image" });
      continue;
    }

    try {
      const result = await processObject(bucket, rawKey);
      results.push({ rawKey, ...result });
    } catch (error) {
      await updateMediaStatus(rawKey, "failed", error.message);
      throw error;
    }
  }

  return { results };
};

async function processObject(bucket, rawKey) {
  const mediaFile = await findMediaFile(rawKey);
  await updateMediaStatus(rawKey, "processing");

  const rawBytes = await downloadObject(bucket, rawKey);
  const metadata = await sharp(rawBytes).metadata();
  const outputKeys = buildProcessedKeys(rawKey, mediaFile.user_id);

  await Promise.all(
    VARIANTS.map(async (variant) => {
      const output = await sharp(rawBytes)
        .rotate()
        .resize({
          width: variant.width,
          withoutEnlargement: true,
        })
        .webp({ quality: WEBP_QUALITY })
        .toBuffer();

      await s3.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: outputKeys[variant.column],
          Body: output,
          ContentType: "image/webp",
          CacheControl: "public, max-age=31536000, immutable",
        }),
      );
    }),
  );

  await updateMediaCompleted(mediaFile.id, outputKeys, metadata);

  return {
    mediaFileId: mediaFile.id,
    thumbKey: outputKeys.thumbnail_file_key,
    processedKey: outputKeys.processed_file_key,
    fullKey: outputKeys.full_file_key,
    width: metadata.width ?? null,
    height: metadata.height ?? null,
  };
}

async function downloadObject(bucket, key) {
  const response = await s3.send(
    new GetObjectCommand({
      Bucket: bucket,
      Key: key,
    }),
  );

  const chunks = [];
  for await (const chunk of response.Body) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function findMediaFile(rawKey) {
  const response = await supabaseRequest(
    "GET",
    `/rest/v1/media_files?raw_file_key=eq.${quoteQueryValue(rawKey)}&select=id,user_id`,
  );
  if (!response?.length) {
    throw new Error(`No media_files row found for raw_file_key=${rawKey}`);
  }
  return response[0];
}

async function updateMediaStatus(rawKey, status, processingError = null) {
  const body = { processing_status: status };
  if (status === "processing") {
    body.processing_started_at = utcNow();
    body.processing_error = null;
  }
  if (processingError) {
    body.processing_error = processingError.slice(0, 2000);
  }

  await supabaseRequest(
    "PATCH",
    `/rest/v1/media_files?raw_file_key=eq.${quoteQueryValue(rawKey)}`,
    body,
    "return=minimal",
  );
}

async function updateMediaCompleted(mediaId, outputKeys, metadata) {
  await supabaseRequest(
    "PATCH",
    `/rest/v1/media_files?id=eq.${mediaId}`,
    {
      thumbnail_file_key: outputKeys.thumbnail_file_key,
      processed_file_key: outputKeys.processed_file_key,
      full_file_key: outputKeys.full_file_key,
      width: metadata.width ?? null,
      height: metadata.height ?? null,
      processing_status: "completed",
      processing_completed_at: utcNow(),
      processing_error: null,
    },
    "return=minimal",
  );
}

async function supabaseRequest(method, path, body = null, prefer = null) {
  const secret = await getSupabaseSecret();
  const url = `${secret.SUPABASE_URL.replace(/\/$/, "")}${path}`;

  const headers = {
    apikey: secret.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${secret.SUPABASE_SERVICE_ROLE_KEY}`,
    "Content-Type": "application/json",
  };
  if (prefer) {
    headers.Prefer = prefer;
  }

  const response = await fetch(url, {
    method,
    headers,
    body: body === null ? undefined : JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(
      `Supabase ${method} ${path} failed: ${response.status} ${await response.text()}`,
    );
  }

  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function getSupabaseSecret() {
  if (!cachedSecret) {
    if (!SECRET_ID) {
      throw new Error("SUPABASE_SECRET_ID env var is required");
    }
    const response = await secretsManager.send(
      new GetSecretValueCommand({ SecretId: SECRET_ID }),
    );
    cachedSecret = JSON.parse(response.SecretString);
  }
  return cachedSecret;
}

function buildProcessedKeys(rawKey, userId) {
  const parts = rawKey.split("/");
  const ownerId = userId ?? parts[2];
  const filename = parts.at(-1) ?? "image";
  const stem = filename.replace(/\.[^.]+$/, "");

  return Object.fromEntries(
    VARIANTS.map((variant) => [
      variant.column,
      `${PROCESSED_PREFIX}${ownerId}/${stem}_${variant.suffix}.webp`,
    ]),
  );
}

function quoteQueryValue(value) {
  return encodeURIComponent(value);
}

function utcNow() {
  return new Date().toISOString();
}
