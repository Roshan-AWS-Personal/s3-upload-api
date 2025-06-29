import os
import boto3
import uuid
import imghdr
import json
import base64
import logging
from urllib.parse import parse_qs

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get("BUCKET_NAME")
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_IMAGE_TYPES = {"jpeg", "png"}

def lambda_handler(event, context):
    try:
        # API Gateway proxy integration sends base64-encoded body
        if event.get("isBase64Encoded"):
            body_bytes = base64.b64decode(event["body"])
        else:
            return response(400, "Expected base64-encoded body")

        content_type = event["headers"].get("Content-Type") or event["headers"].get("content-type")
        if not content_type or "multipart/form-data" not in content_type:
            return response(400, "Unsupported content type. Must be multipart/form-data")

        # Extract boundary from content-type
        boundary = content_type.split("boundary=")[-1]
        boundary_bytes = boundary.encode()

        # Split parts manually (quick and dirty multipart parser)
        parts = body_bytes.split(b"--" + boundary_bytes)
        file_part = next((p for p in parts if b"Content-Disposition" in p and b"filename=" in p), None)

        if not file_part:
            return response(400, "No image file found in multipart data")

        # Separate headers and file content
        headers, file_data = file_part.split(b"\r\n\r\n", 1)
        file_data = file_data.rstrip(b"\r\n--")

        # Validate file size
        if len(file_data) > MAX_FILE_SIZE:
            return response(400, "File too large. Max size is 5MB")

        # Validate file type using imghdr
        image_type = imghdr.what(None, h=file_data)
        if image_type not in ALLOWED_IMAGE_TYPES:
            return response(400, f"Unsupported image type: {image_type}")

        # Upload to S3
        filename = f"{uuid.uuid4()}.{image_type}"
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=filename,
            Body=file_data,
            ContentType=f"image/{image_type}"
        )

        s3_url = f"https://{BUCKET_NAME}.s3.amazonaws.com/{filename}"
        return response(200, {"url": s3_url})

    except Exception as e:
        logging.exception("Error handling upload")
        return response(500, f"Internal server error: {str(e)}")


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": { "Content-Type": "application/json" },
        "body": json.dumps(body if isinstance(body, dict) else { "message": body })
    }
