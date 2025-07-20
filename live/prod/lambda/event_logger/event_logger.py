import json
import uuid
import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("file_upload_metadata")

def lambda_handler(event, context):
    logger.info("Received S3 event: %s", json.dumps(event))

    for record in event.get("Records", []):
        if record.get("eventName", "").startswith("ObjectCreated:"):
            bucket = record["s3"]["bucket"]["name"]
            key = record["s3"]["object"]["key"]
            size = record["s3"]["object"].get("size", 0)
            timestamp = record.get("eventTime") or datetime.utcnow().isoformat() + "Z"

            # Infer metadata
            filename = os.path.basename(key)
            ext = filename.rsplit(".", 1)[-1].lower()
            file_type = infer_type(ext)

            upload_id = str(uuid.uuid4())

            item = {
                "upload_id": upload_id,  # Using key as id if upload_id not generated elsewhere
                "filename": filename,
                "s3_bucket": bucket,
                "s3_key": key,
                "filesize": size,
                "timestamp": timestamp,
                "status": "uploaded",
                "content_type": file_type
            }

            try:
                logger.info("Writing item to DynamoDB: %s", item)
                table.put_item(Item=item)
            except Exception as e:
                logger.error("Failed to write to DynamoDB: %s", str(e))

    return {"statusCode": 200, "body": "Processed S3 event"}

def infer_type(ext):
    if ext in {"jpg", "jpeg", "png", "gif"}:
        return "image"
    elif ext in {"pdf", "doc", "docx", "txt"}:
        return "document"
    else:
        return "unknown"
