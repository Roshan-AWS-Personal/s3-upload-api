import boto3
import os
import json
import logging
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table("file_upload_metadata")

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type, Authorization",
            "Access-Control-Allow-Methods": "OPTIONS,GET",
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }

def lambda_handler(event, context):
    try:
        if event["httpMethod"] == "OPTIONS":
            return response(200, {"message": "CORS preflight OK"})

        claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
        username = claims.get("cognito:username", None)
        if not username:
            return response(401, {"error": "Unauthorized - username missing"})

        logger.info(f"Fetching uploads for user: {username}")

        # Query DynamoDB using GSI or primary key depending on your schema
        # Assuming 'username' is a GSI partition key
        result = table.query(
            IndexName="username-index",  # optional: if username is a GSI
            KeyConditionExpression=Key("username").eq(username)
        )

        uploads = result.get("Items", [])
        return response(200, {"uploads": uploads})

    except Exception as e:
        logger.exception("Error retrieving uploads")
        return response(500, {"error": "Internal server error", "details": str(e)})
