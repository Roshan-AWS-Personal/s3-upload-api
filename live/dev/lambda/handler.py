import json
import base64
import boto3
import os
import uuid
import imghdr

s3 = boto3.client("s3")
BUCKET_NAME = os.environ.get("BUCKET_NAME")
MAX_FILE_SIZE = 5 * 1024 * 1024  # 5 MB
ALLOWED_IMAGE_TYPES = {"jpeg", "png"}

def lambda_handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
        image_data_b64 = body.get("image_data")

        if not image_data_b64:
            return response(400, "Missing 'image_data' in request body.")

        image_data = base64.b64decode(image_data_b64)
        file_size = len(image_data)

        if file_size > MAX_FILE_SIZE:
            return response(400, "File too large. Max size is 5MB.")

        image_type = imghdr.what(None, h=image_data)
        if image_type not in ALLOWED_IMAGE_TYPES:
            return response(400, f"Unsupported image type: {image_type}")

        filename = f"{uuid.uuid4()}.{image_type}"
        s3.put_object(Bucket=BUCKET_NAME, Key=filename, Body=image_data, ContentType=f"image/{image_type}")

        s3_url = f"https://{BUCKET_NAME}.s3.amazonaws.com/{filename}"
        return response(200, {"url": s3_url})
 
    except Exception as e:
        return response(500, f"Internal server error: {str(e)}")

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": { "Content-Type": "application/json" },
        "body": json.dumps(body if isinstance(body, dict) else { "message": body })
    }
