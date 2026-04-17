#!/usr/bin/env python3
"""
Test Bedrock authorization - uses boto3 credential chain
This will check AWS_KEY_ID, AWS_KEY_SECRET env vars, or ~/.aws/credentials
"""

import os
import boto3
from botocore.exceptions import ClientError

def test_bedrock():
    print("=== Testing Bedrock Permissions ===\n")
    
    # Try to get current credentials info
    print("1. Checking AWS credentials...")
    try:
        sts = boto3.client('sts')
        identity = sts.get_caller_identity()
        user_arn = identity['Arn']
        account = identity['Account']
        print(f"   ✓ Current User ARN: {user_arn}")
        print(f"   ✓ Account: {account}")
    except Exception as e:
        print(f"   ❌ Cannot determine identity: {e}")
        print("   → Make sure AWS credentials are configured")
        return False
    
    print("\n2. Checking Bedrock model list access...")
    try:
        bedrock_models = boto3.client('bedrock', region_name='us-east-1')
        
        # Try to list models
        models = bedrock_models.list_foundation_models()
        print(f"   ✓ Can list Bedrock models ({len(models.get('modelSummaries', []))} available)")
        
    except ClientError as e:
        print(f"   ⚠ Cannot list models (may not have bedrock:ListFoundationModels): {e.response['Error']['Code']}")
    except Exception as e:
        print(f"   ⚠ Error listing models: {e}")
    
    # Create bedrock-runtime client for invocation tests
    bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')
    
    print("\n3. Testing InvokeModel permission...")
    try:
        # This doesn't actually invoke a model, just tests permission
        response = bedrock.invoke_model(
            modelId='us.amazon.nova-lite-v1:0',
            body='{"messages":[{"role":"user","content":"test"}]}',
            contentType='application/json'
        )
        print(f"   ✓ bedrock:InvokeModel - ALLOWED")
    except ClientError as e:
        code = e.response['Error']['Code']
        msg = e.response['Error']['Message']
        if 'not authorized' in msg.lower() or code == 'AccessDenied':
            print(f"   ❌ bedrock:InvokeModel - DENIED")
            print(f"      {msg}")
        else:
            print(f"   ⚠ Error (may not be permission): {code}")
            print(f"      {msg}")
    except Exception as e:
        print(f"   ⚠ Unexpected error: {e}")
    
    print("\n4. Testing InvokeModelWithResponseStream permission...")
    try:
        response = bedrock.invoke_model_with_response_stream(
            modelId='us.amazon.nova-lite-v1:0',
            body='{"messages":[{"role":"user","content":"test"}]}',
            contentType='application/json'
        )
        print(f"   ✓ bedrock:InvokeModelWithResponseStream - ALLOWED")
        # Try to read first chunk
        try:
            for event in response['body']:
                print(f"   ✓ Stream working - received data")
                break
        except:
            pass
    except ClientError as e:
        code = e.response['Error']['Code']
        msg = e.response['Error']['Message']
        if 'not authorized' in msg.lower() or code == 'AccessDenied':
            print(f"   ❌ bedrock:InvokeModelWithResponseStream - DENIED")
            print(f"      {msg}")
            print("\n   SOLUTION:")
            print("   The IAM user MScProject1 needs this policy:")
            print('   {')
            print('     "Version": "2012-10-17",')
            print('     "Statement": [{')
            print('       "Effect": "Allow",')
            print('       "Action": "bedrock:InvokeModelWithResponseStream",')
            print('       "Resource": "arn:aws:bedrock:*:*:inference-profile/*"')
            print('     }]')
            print('   }')
        else:
            print(f"   ⚠ Error (may not be permission): {code}")
            print(f"      {msg}")
    except Exception as e:
        print(f"   ⚠ Unexpected error: {e}")
    
    print("\n5. Checking other potential models...")
    try:
        models_resp = bedrock.list_foundation_models()
        models = models_resp.get('modelSummaries', [])
        
        # Find all available models
        print(f"   Available models ({len(models)} total):")
        for m in models[:5]:
            print(f"     - {m.get('modelId')}")
        if len(models) > 5:
            print(f"     ... and {len(models)-5} more")
    except:
        pass

if __name__ == '__main__':
    test_bedrock()
