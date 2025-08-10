import os
import boto3
import uuid
import json
import logging
import base64
import re
from datetime import datetime

s3          = boto3.client("s3")
ses         = boto3.client('ses')
dynamodb    = boto3.resource("dynamodb")
table       = dynamodb.Table('file_upload_metadata')

MAX_FILE_SIZE       = 5 * 1024 * 1024
ALLOWED_IMAGE_TYPES = {"jpeg", "jpg", "png"}
# --- SES config (add) ---
SENDER_EMAIL      = os.environ.get("SENDER_EMAIL", "venkatesanroshan@gmail.com")  # must be SES-verified
NOTIFY_RECIPIENTS = os.environ.get("NOTIFY_RECIPIENTS", SENDER_EMAIL)    # comma-separated allowed


IMAGE_EXTENSIONS    = {"jpg", "jpeg", "png", "gif"}
DOCUMENT_EXTENSIONS = {"pdf", "doc", "docx", "txt"}

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin":  "*",
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
                    "Access-Control-Allow-Origin":  "*",
                    "Access-Control-Allow-Headers": "Content-Type, Authorization",
                    "Access-Control-Allow-Methods": "OPTIONS,GET,PUT",
                },
                "body": json.dumps({"message": "CORS preflight OK"})
            }

        claims     = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        username   = claims.get("cognito:username", "Unknown")
        user_email = claims.get("email", "Unknown")
        token_use  = claims.get("token_use", "missing")

        logger.info(f"Request from {username} ({user_email}), token_use={token_use}")

        query       = event.get("queryStringParameters") or {}
        filename    = query.get("filename")
        raw_size    = query.get("filesize", 0)
        content_type= query.get("content_type")

        try:
            filesize = int(raw_size)
        except (ValueError, TypeError):
            filesize = 0

        if not filename or not content_type:
            return response(400, "Missing filename or content_type")

        if filesize > MAX_FILE_SIZE:
            return response(413, "File too large")

        key    = sanitize_filename(filename)
        BUCKET = get_bucket_for_file(filename)
        presigned_url = s3.generate_presigned_url(
            ClientMethod='put_object',
            Params={'Bucket': BUCKET, 'Key': key, 'ContentType': content_type},
            ExpiresIn=300
        )
        file_url   = f"https://{BUCKET}.s3.amazonaws.com/{key}"
        upload_id  = str(uuid.uuid4())
        timestamp  = datetime.utcnow().isoformat() + "Z"
        uploader_ip= event['requestContext']['identity']['sourceIp']
        user_agent = event['headers'].get('User-Agent', 'Unknown')

        item = {
            'upload_id':     upload_id,
            'filename':      filename,
            'filesize':      filesize,
            's3_bucket':     BUCKET,
            's3_key':        key,
            'timestamp':     timestamp,
            'uploader_ip':   uploader_ip,
            'uploader_agent':user_agent,
            'file_url':      file_url,
            'content_type':  content_type,
            'status':        'presigned',
            'username':      username,
            'user_email':    user_email
        }
        table.put_item(Item=item)

        # send SES email (re-added)
        send_upload_notification(item)

        # ←—— THIS RETURN NOW INCLUDES *ALL* CORS HEADERS ———→
        return {
            "statusCode": 200,
            "body": json.dumps({
                "upload_id":  upload_id,
                "upload_url": presigned_url
            }),
            "headers": {
                "Content-Type":                "application/json",
                "Access-Control-Allow-Origin":  "*",
                "Access-Control-Allow-Headers": "Content-Type, Authorization",
                "Access-Control-Allow-Methods": "OPTIONS,GET,PUT"
            }
        }

    except Exception as e:
        logger.exception("Error generating presigned URL")
        return response(500, f"Internal server error: {str(e)}")

def send_upload_notification(item: dict):
    """Fire-and-forget SES email about a newly issued presigned upload."""
    try:
        to_addresses = [addr.strip() for addr in NOTIFY_RECIPIENTS.split(",") if addr.strip()]
        subject = f"[Upload Requested] {item.get('filename','')} ({item.get('filesize',0)} bytes)"

        body_text = (
            f"An upload was requested.\n\n"
            f"Filename: {item.get('filename')}\n"
            f"Size: {item.get('filesize')} bytes\n"
            f"Content-Type: {item.get('content_type')}\n"
            f"Bucket/Key: {item.get('s3_bucket')}/{item.get('s3_key')}\n"
            f"Upload ID: {item.get('upload_id')}\n"
            f"User: {item.get('username')} <{item.get('user_email')}>\n"
            f"IP: {item.get('uploader_ip')}\n"
            f"User-Agent: {item.get('uploader_agent')}\n"
            f"Time (UTC): {item.get('timestamp')}\n"
        )

        body_html = f"""<html><body>
            <h3>Upload Requested</h3>
            <ul>
              <li><strong>Filename</strong>: {item.get('filename')}</li>
              <li><strong>Size</strong>: {item.get('filesize')} bytes</li>
              <li><strong>Content-Type</strong>: {item.get('content_type')}</li>
              <li><strong>Bucket/Key</strong>: {item.get('s3_bucket')}/{item.get('s3_key')}</li>
              <li><strong>Upload ID</strong>: {item.get('upload_id')}</li>
              <li><strong>User</strong>: {item.get('username')} &lt;{item.get('user_email')}&gt;</li>
              <li><strong>IP</strong>: {item.get('uploader_ip')}</li>
              <li><strong>User-Agent</strong>: {item.get('uploader_agent')}</li>
              <li><strong>Time (UTC)</strong>: {item.get('timestamp')}</li>
            </ul>
        </body></html>"""

        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={"ToAddresses": to_addresses},
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Text": {"Data": body_text, "Charset": "UTF-8"},
                    "Html": {"Data": body_html, "Charset": "UTF-8"}
                }
            }
        )
        logger.info("SES notification sent to %s", to_addresses)
    except Exception as e:
        # Do not fail the API if email fails; just log it.
        logger.warning("SES notification failed: %s", e, exc_info=True)    
