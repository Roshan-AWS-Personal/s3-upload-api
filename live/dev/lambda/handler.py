import os
import boto3
import uuid
import json
import logging
import base64
import re
from datetime import datetime

s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
BUCKET_NAME = os.environ.get("BUCKET_NAME")
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB
ALLOWED_IMAGE_TYPES = {"jpeg", "jpg", "png"}
table = dynamodb.Table('file_upload_metadata')

def lambda_handler(event, context):
    try:
        # --- Handle CORS preflight ---
        if event["httpMethod"] == "OPTIONS":
            return {
                "statusCode": 200,
                "headers": {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Allow-Methods": "OPTIONS,GET,PUT",
                },
                "body": json.dumps({"message": "CORS preflight OK"})
            }

        # --- Auth check ---
        auth_header = event["headers"].get("Authorization")
        if not auth_header or not is_authorized(auth_header):
            return response(401, "Unauthorized")

        # --- Query parsing ---
        print("Authorization header:", auth_header)
        query = event.get("queryStringParameters") or {}
        filename = query.get("filename")
        raw_size = query.get("filesize", 0)
        try:
            filesize = int(raw_size)
        except (ValueError, TypeError):
            logging.warning(f"Invalid filesize value: {raw_size}")
            filesize = 0
        content_type = query.get("content_type")

        if not filename or not content_type:
            return response(400, "Missing filename or content_type")

        if not content_type.startswith("image/"):
            return response(400, "Only image uploads are allowed")

        ext = filename.rsplit(".", 1)[-1].lower()
        if ext not in ALLOWED_IMAGE_TYPES:
            return response(400, f"Unsupported image type: {ext}")

        # --- S3 Key Generation ---
        key = f"{sanitize_filename(filename)}"

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
        # Generate upload ID and timestamp
        upload_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + "Z"
        uploader_ip = event['requestContext']['identity']['sourceIp']
        user_agent = event['headers'].get('User-Agent', 'Unknown')
        # Save metadata to DynamoDB
        item = {
            'upload_id': upload_id,
            'filename': filename,
            'filesize': filesize,
            's3_bucket': BUCKET_NAME,
            's3_key': key,
            'timestamp': timestamp,
            'uploader_ip': uploader_ip,
            'uploader_agent': user_agent,
            'file_url': file_url,
            'content_type': content_type,
            'status': 'uploaded'
        }
        table.put_item(Item=item)
        return {
        "statusCode": 200,
        "body": json.dumps({
            "upload_id": upload_id,
            "presigned_url": presigned_url
        }),
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
            }
        }

    except Exception as e:
        logging.exception("Error generating presigned URL")
        return response(500, f"Internal server error: {str(e)}")


def sanitize_filename(name):
    import urllib.parse
    safe_name = re.sub(r"[^\w.\-]", "_", name)  # Replace spaces and unsafe characters
    return urllib.parse.quote(safe_name)        # URL-encode it properly



def is_authorized(auth_header):
    expected = os.environ.get("UPLOAD_API_SECRET")
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

