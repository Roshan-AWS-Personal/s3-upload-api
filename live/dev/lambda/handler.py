import os
import boto3
import uuid
import json
import logging
import base64
import re

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get("BUCKET_NAME")
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB
ALLOWED_IMAGE_TYPES = {"jpeg", "png"}


def lambda_handler(event, context):
    try:
        # --- Handle CORS preflight ---
        if event["httpMethod"] == "OPTIONS":
            return {
                "statusCode": 200,
                "headers": {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Allow-Methods": "OPTIONS,GET",
                },
                "body": json.dumps({"message": "CORS preflight OK"})
            }

        # --- Auth check ---
        auth_header = event["headers"].get("Authorization")
        if not auth_header or not is_authorized(auth_header):
            return response(401, "Unauthorized")

        # --- Query parsing ---
        query = event.get("queryStringParameters") or {}
        filename = query.get("filename")
        content_type = query.get("content_type")

        if not filename or not content_type:
            return response(400, "Missing filename or content_type")

        if not content_type.startswith("image/"):
            return response(400, "Only image uploads are allowed")

        ext = filename.rsplit(".", 1)[-1].lower()
        if ext not in ALLOWED_IMAGE_TYPES:
            return response(400, f"Unsupported image type: {ext}")

        # --- S3 Key Generation ---
        key = f"{uuid.uuid4()}_{sanitize_filename(filename)}"

        presigned_url = s3.generate_presigned_url(
            ClientMethod='put_object',
            Params={
                'Bucket': BUCKET_NAME,
                'Key': key,
                'ContentType': content_type
            },
            ExpiresIn=300
        )

        file_url = f"https://{BUCKET_NAME}.s3.amazonaws.com/{key}"
        print("Authorization header:", auth_header)
        return response(200, {"upload_url": presigned_url, "file_url": file_url})

    except Exception as e:
        logging.exception("Error generating presigned URL")
        return response(500, f"Internal server error: {str(e)}")


def sanitize_filename(name):
    return re.sub(r"[^\w.\-]", "_", name)


def is_authorized(auth_header):
    # expected = os.environ.get("UPLOAD_API_SECRET")
    expected = "gW75T+AcsXW4LLPMhup9Rv944JZ64EA9D6te5b/RxDI="
    if not expected:
        return False
    scheme, _, value = auth_header.partition(" ")
    return scheme.lower() == "bearer" and value == expected


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Allow-Methods": "OPTIONS,GET,PUT",
        },
        "body": json.dumps(body if isinstance(body, dict) else {"message": body})
    }

