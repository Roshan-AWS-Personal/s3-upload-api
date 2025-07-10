import os
import boto3
import uuid
import json
import logging
import base64
import re
from datetime import datetime

s3 = boto3.client("s3")
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5MB
ALLOWED_IMAGE_TYPES = {"jpeg", "jpg", "png"}

ses = boto3.client('ses')
recipient_email = "venkatesanroshan@gmail.com"

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table('file_upload_metadata')

IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "gif"}
DOCUMENT_EXTENSIONS = {"pdf", "doc", "docx", "txt"}

logger = logging.getLogger()

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

        # --- S3 Key Generation ---
        key = f"{sanitize_filename(filename)}"
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

        subject = f"New Upload: {filename}"
        body_text = f"""\
        New image uploaded:

        Filename: {filename}
        Size: {filesize} bytes
        Uploader IP: {uploader_ip}
        User Agent: {user_agent}
        S3 URL: {file_url}
        Timestamp: {timestamp}
        """
        logger.setLevel(logging.INFO)
        try:
            logger.info("Sending SES email...")
            response = ses.send_email(
            Source=recipient_email,
            Destination={"ToAddresses": [recipient_email]},
            Message={
                "Subject": {"Data": subject},
                "Body": {"Text": {"Data": body_text}}
                }
            )  # same as above
        except Exception as e:
            logger.error("Error sending SES email: %s", str(e))
        
        logger.info("SES email sent successfully. Response: %s", response)
        print("Putting item in DynamoDB:", item)
        
        table.put_item(Item=item)
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
            'Content-Type': 'application/json'
        },
        "body": json.dumps(body if isinstance(body, dict) else {"message": body})
    }


def get_bucket_for_file(filename):
    ext = filename.rsplit('.', 1)[-1].lower()
    if ext in IMAGE_EXTENSIONS:
        return os.environ.get("IMAGES_BUCKET")
    elif ext in DOCUMENT_EXTENSIONS:
        return os.environ.get("DOCUMENTS_BUCKET")
    else:
        raise ValueError(f"Unsupported file type: {ext}")
