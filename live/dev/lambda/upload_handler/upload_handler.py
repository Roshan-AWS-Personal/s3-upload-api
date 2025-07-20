import os
import boto3
import uuid
import json
import logging
import base64
import re
from datetime import datetime

s3 = boto3.client("s3")
ses = boto3.client('ses')
dynamodb = boto3.resource("dynamodb")

MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB
ALLOWED_IMAGE_TYPES = {"jpeg", "jpg", "png"}
recipient_email = "venkatesanroshan@gmail.com"
table = dynamodb.Table('file_upload_metadata')

IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "gif"}
DOCUMENT_EXTENSIONS = {"pdf", "doc", "docx", "txt"}

logger = logging.getLogger()
logger.setLevel(logging.INFO)

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

def sanitize_filename(name):
    import urllib.parse
    safe_name = re.sub(r"[^\w.\-]", "_", name)
    return urllib.parse.quote(safe_name)

def get_bucket_for_file(filename):
    ext = filename.rsplit('.', 1)[-1].lower()
    if ext in IMAGE_EXTENSIONS:
        return os.environ.get("IMAGES_BUCKET")
    elif ext in DOCUMENT_EXTENSIONS:
        return os.environ.get("DOCUMENTS_BUCKET")
    else:
        raise ValueError(f"Unsupported file type: {ext}")

def lambda_handler(event, context):
    try:
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

        # ✅ Extract Cognito claims
        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        user_email = claims.get("email", "Unknown")
        username = claims.get("cognito:username", "Unknown")
        token_use = claims.get("token_use", "missing")

        logger.info(f"Request from Cognito user: {username}, email: {user_email}, token_use: {token_use}")
        if token_use != "id":
            logger.warning("Token is not an ID token. Rejecting.")
            return response(401, "Unauthorized: ID token required")
        logger.info(f"Upload request from Cognito user: {username}, email: {user_email}")

        query = event.get("queryStringParameters") or {}
        filename = query.get("filename")
        raw_size = query.get("filesize", 0)

        try:
            filesize = int(raw_size)
        except (ValueError, TypeError):
            logger.warning(f"Invalid filesize value: {raw_size}")
            filesize = 0

        content_type = query.get("content_type")
        if not filename or not content_type:
            return response(400, "Missing filename or content_type")

        key = sanitize_filename(filename)
        BUCKET_NAME = get_bucket_for_file(filename)
        logger.info(f"Using bucket: {BUCKET_NAME} for file: {filename}")
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
        upload_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + "Z"
        uploader_ip = event['requestContext']['identity']['sourceIp']
        user_agent = event['headers'].get('User-Agent', 'Unknown')

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
            'status': 'presigned',
            'username': username,
            'user_email': user_email
        }

        subject = f"New Upload URL Issued: {filename}"
        body_text = f"""\
            A new presigned URL was issued:

            Filename: {filename}
            Size: {filesize} bytes
            Uploader IP: {uploader_ip}
            User Agent: {user_agent}
            S3 URL: {file_url}
            User Email: {user_email}
            Timestamp: {timestamp}
            """

        try:
            logger.info("Sending SES email...")
            ses_response = ses.send_email(
                Source=recipient_email,
                Destination={"ToAddresses": [recipient_email]},
                Message={
                    "Subject": {"Data": subject},
                    "Body": {"Text": {"Data": body_text}}
                }
            )
            logger.info("SES email sent successfully.")
        except Exception as e:
            logger.error("SES failed: %s", str(e))

        print("Presigned URL issued (not yet uploaded):", item)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "upload_id": upload_id,
                "upload_url": presigned_url
            }),
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*"
            }
        }

    except Exception as e:
        logger.exception("Error generating presigned URL")
        return response(500, f"Internal server error: {str(e)}")
