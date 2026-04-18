#!/usr/bin/env python3
"""
Test Bedrock authorization for AWS credentials in environment variables
Safely checks permissions without exposing keys
"""

import os
import boto3
from botocore.exceptions import ClientError, NoCredentialsError

def test_bedrock_permissions():
    """Test if current AWS credentials can access Bedrock"""
    
    # Get credentials from environment
    aws_key_id = os.getenv('AWS_KEY_ID')
    aws_key_secret = os.getenv('AWS_KEY_SECRET')
    
    if not aws_key_id or not aws_key_secret:
        print("❌ AWS_KEY_ID or AWS_KEY_SECRET not set in environment")
        return False
    
    print("✓ Credentials loaded from environment variables")
    print(f"  Access Key ID prefix: {aws_key_id[:4]}...{aws_key_id[-4:]}")
    
    # Create Bedrock client using explicit credentials
    try:
        bedrock = boto3.client(
            'bedrock-runtime',
            region_name='us-east-1',
            aws_access_key_id=aws_key_id,
            aws_secret_access_key=aws_key_secret
        )
        print("✓ Bedrock client created successfully")
    except Exception as e:
        print(f"❌ Failed to create Bedrock client: {e}")
        return False
    
    # Get current identity
    print("\n=== 1. Check IAM Identity ===")
    try:
        sts = boto3.client(
            'sts',
            region_name='us-east-1',
            aws_access_key_id=aws_key_id,
            aws_secret_access_key=aws_key_secret
        )
        identity = sts.get_caller_identity()
        print(f"✓ Identity User: {identity['Arn']}")
        print(f"  Account: {identity['Account']}")
    except ClientError as e:
        print(f"❌ Failed to get identity: {e}")
        return False
    
    body = '{"messages":[{"role":"user","content":"Say hello"}],"inferenceConfig":{"maxTokens":10}}'

    # -------------------------------------------------------------------------
    # Test A: Direct foundation model ID — what your IAM policy ALLOWS
    # -------------------------------------------------------------------------
    print("\n=== 3. Test DIRECT foundation model: amazon.nova-lite-v1:0 ===")
    print("   (This is what your IAM policy Resource ARN covers)")
    for action_label, fn in [
        ("InvokeModel", lambda: bedrock.invoke_model(
            modelId='amazon.nova-lite-v1:0', body=body, contentType='application/json')),
        ("InvokeModelWithResponseStream", lambda: bedrock.invoke_model_with_response_stream(
            modelId='amazon.nova-lite-v1:0', body=body, contentType='application/json')),
    ]:
        try:
            fn()
            print(f"   ✓ {action_label}: PASS")
        except ClientError as e:
            code = e.response['Error']['Code']
            msg = e.response['Error']['Message']
            print(f"   ❌ {action_label}: FAIL — {code}: {msg}")
        except Exception as e:
            print(f"   ❌ {action_label}: ERROR — {e}")

    # -------------------------------------------------------------------------
    # Test B: Cross-region inference profile — what Flowise ACTUALLY CALLS
    # -------------------------------------------------------------------------
    print("\n=== 4. Test INFERENCE PROFILE: us.amazon.nova-lite-v1:0 ===")
    print("   (This is what Flowise sends — requires different Resource ARN in policy)")
    for action_label, fn in [
        ("InvokeModel", lambda: bedrock.invoke_model(
            modelId='us.amazon.nova-lite-v1:0', body=body, contentType='application/json')),
        ("InvokeModelWithResponseStream", lambda: bedrock.invoke_model_with_response_stream(
            modelId='us.amazon.nova-lite-v1:0', body=body, contentType='application/json')),
    ]:
        try:
            fn()
            print(f"   ✓ {action_label}: PASS")
        except ClientError as e:
            code = e.response['Error']['Code']
            msg = e.response['Error']['Message']
            print(f"   ❌ {action_label}: FAIL — {code}: {msg}")
        except Exception as e:
            print(f"   ❌ {action_label}: ERROR — {e}")

    print("\n=== 5. Summary ===")
    print("If test 3 passes and test 4 fails:")
    print("  → The IAM policy only covers foundation-model ARNs, not inference-profile ARNs.")
    print("  FIX OPTION A — Add inference-profile to the IAM policy Resource list:")
    print('    "arn:aws:bedrock:*:*:inference-profile/us.amazon.nova-lite-v1:0"')
    print("  FIX OPTION B — Configure Flowise to use the direct model ID instead:")
    print('    Change model ID in Flowise from  us.amazon.nova-lite-v1:0')
    print('                                  to  amazon.nova-lite-v1:0')
    return True

if __name__ == '__main__':
    success = test_bedrock_permissions()
    exit(0 if success else 1)
