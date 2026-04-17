import boto3, json

ecs = boto3.client('ecs', region_name='us-east-1')

# Get current task definition
td = ecs.describe_task_definition(taskDefinition='chatproxy-dev-flowise-proxy-task')['taskDefinition']

# Print current env and secrets for visibility (no secret values - just names)
cdef = td['containerDefinitions'][0]
print("Current env vars:", [e['name'] for e in cdef.get('environment', [])])
print("Current secrets:", [s['name'] for s in cdef.get('secrets', [])])

# Check if FLOWISE_API_KEY already present
already_has_key = any(s['name'] == 'FLOWISE_API_KEY' for s in cdef.get('secrets', []))
already_has_env = any(e['name'] == 'FLOWISE_API_KEY' for e in cdef.get('environment', []))
print(f"FLOWISE_API_KEY in secrets: {already_has_key}")
print(f"FLOWISE_API_KEY in env: {already_has_env}")

# Get the secret ARN
sm = boto3.client('secretsmanager', region_name='us-east-1')
secret = sm.describe_secret(SecretId='/chatproxy/dev/flowise/api-key')
secret_arn = secret['ARN']
print(f"Secret ARN: {secret_arn}")

# Add FLOWISE_API_KEY as a secret injection (valueFrom = ARN + JSON key)
# ECS supports valueFrom pointing to a specific JSON key using "arn:...:secret:...:KEY::"
secrets = cdef.get('secrets', [])
# Remove any existing FLOWISE_API_KEY entries to avoid duplicates
secrets = [s for s in secrets if s['name'] != 'FLOWISE_API_KEY']
secrets.append({
    'name': 'FLOWISE_API_KEY',
    'valueFrom': f"{secret_arn}:FLOWISE_API_KEY::"
})
cdef['secrets'] = secrets

# Also remove from plain env if present (shouldn't be, but clean up)
cdef['environment'] = [e for e in cdef.get('environment', []) if e['name'] != 'FLOWISE_API_KEY']

# Build the register call (only fields accepted by register-task-definition)
register_kwargs = {
    'family': td['family'],
    'containerDefinitions': td['containerDefinitions'],
    'requiresCompatibilities': td['requiresCompatibilities'],
    'networkMode': td['networkMode'],
    'cpu': td['cpu'],
    'memory': td['memory'],
    'executionRoleArn': td['executionRoleArn'],
}
if td.get('taskRoleArn'):
    register_kwargs['taskRoleArn'] = td['taskRoleArn']
if td.get('volumes'):
    register_kwargs['volumes'] = td['volumes']

new_td = ecs.register_task_definition(**register_kwargs)
new_revision = new_td['taskDefinition']['revision']
print(f"\nRegistered new task definition revision: {new_revision}")

# Update service to use new revision
ecs.update_service(
    cluster='chatproxy-dev-cluster',
    service='chatproxy-dev-flowise-proxy-service',
    taskDefinition=f"chatproxy-dev-flowise-proxy-task:{new_revision}",
    forceNewDeployment=True
)
print(f"Service updated to revision {new_revision} — redeployment triggered.")
print("ECS will restart the task and inject FLOWISE_API_KEY from Secrets Manager.")
