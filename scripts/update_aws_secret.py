import boto3
import json
import sys

def update_secret():
    secret_id = "/chatproxy/dev/jwt"
    region = "us-east-1"
    new_key = "ACCOUNTING_SERVICE_URL"
    new_value = "http://accounting-service:3001"

    client = boto3.client('secretsmanager', region_name=region)

    try:
        # Get current secret
        response = client.get_secret_value(SecretId=secret_id)
        secret_string = response['SecretString']
        secret_dict = json.loads(secret_string)

        # Update value
        secret_dict[new_key] = new_value
        updated_string = json.dumps(secret_dict)

        # Put back to AWS
        client.put_secret_value(
            SecretId=secret_id,
            SecretString=updated_string
        )
        print(f"Successfully updated {secret_id} with {new_key}={new_value}")
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    update_secret()
