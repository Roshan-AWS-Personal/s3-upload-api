import boto3
import json
import logging
import os
from decimal import Decimal
from boto3.dynamodb.conditions import Key

# --- setup DynamoDB, S3 & logging ---
dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table("file_upload_metadata")
s3       = boto3.client("s3")

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# --- custom JSON encoder to handle Decimal ---
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Allow-Methods": "OPTIONS,GET",
            "Content-Type": "application/json"
        },
        "body": json.dumps(body, cls=DecimalEncoder)
    }

def lambda_handler(event, context):
    try:
        # CORS preflight
        if event.get("httpMethod") == "OPTIONS":
            return response(200, {"message": "CORS preflight OK"})

        # Auth check
        claims   = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        username = claims.get("cognito:username")
        if not username:
            return response(401, {"error": "Unauthorized - username missing"})

        logger.info(f"Fetching uploads for user: {username}")

        # Query GSI
        result  = table.query(
            IndexName="username-index",
            KeyConditionExpression=Key("username").eq(username)
        )
        uploads = result.get("Items", [])

        # Pick up both buckets from env
        img_bucket = os.environ.get("IMAGES_BUCKET")
        doc_bucket = os.environ.get("DOCUMENTS_BUCKET")
        if not img_bucket or not doc_bucket:
            missing = [v for v in ("IMAGES_BUCKET","DOCUMENTS_BUCKET") if not os.environ.get(v)]
            logger.error(f"Missing env var(s): {missing}")
            return response(500, {"error":"Internal server error","details":f"Missing {missing}"})

        # Helper to classify doc extensions
        DOC_EXTS = (".pdf", ".doc", ".docx", ".txt", ".xls", ".xlsx")
        
        # Generate presigned URLs
        for item in uploads:
            logger.info(f"DynamoDB item: {item!r}")
            key = item.get("filename") or item.get("upload_id")
            if not isinstance(key, str):
                logger.error(f"No valid key, skipping: {item!r}")
                item["s3_url"] = None
                continue

            # choose bucket based on extension
            lower = key.lower()
            bucket = doc_bucket if lower.endswith(DOC_EXTS) else img_bucket

            try:
                item["s3_url"] = s3.generate_presigned_url(
                    ClientMethod="get_object",
                    Params={"Bucket": bucket, "Key": key},
                    ExpiresIn=3600
                )
                logger.info(f"Presigned URL for {key} in {bucket}")
            except Exception:
                logger.exception(f"Failed to presign URL for key={key}")
                item["s3_url"] = None

        return response(200, {"uploads": uploads})

    except Exception as e:
        logger.exception("Error retrieving uploads")
        return response(500, {"error":"Internal server error","details":str(e)})
