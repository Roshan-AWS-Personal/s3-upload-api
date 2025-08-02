import boto3
import json
import logging
from decimal import Decimal
from boto3.dynamodb.conditions import Key

# --- setup DynamoDB & logging ---
dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("file_upload_metadata")

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# --- custom JSON encoder to handle Decimal ---
class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            # if it's a whole number, cast to int; otherwise float
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
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
        # use our DecimalEncoder here
        "body": json.dumps(body, cls=DecimalEncoder)
    }


def lambda_handler(event, context):
    try:
        # handle CORS preflight
        if event.get("httpMethod") == "OPTIONS":
            return response(200, {"message": "CORS preflight OK"})

        # pull the Cognito username from the authorizer
        claims = event.get("requestContext", {}) \
                      .get("authorizer", {}) \
                      .get("claims", {})
        username = claims.get("cognito:username")
        if not username:
            return response(401, {"error": "Unauthorized - username missing"})

        logger.info(f"Fetching uploads for user: {username}")

        # query your GSI
        result = table.query(
            IndexName="username-index",
            KeyConditionExpression=Key("username").eq(username)
        )

        uploads = result.get("Items", [])
        return response(200, {"uploads": uploads})

    except Exception as e:
        logger.exception("Error retrieving uploads")
        return response(
            500,
            {"error": "Internal server error", "details": str(e)}
        )
