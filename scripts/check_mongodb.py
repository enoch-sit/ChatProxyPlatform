import boto3, time

ssm = boto3.client('ssm', region_name='us-east-1')
instance_id = 'i-0f836e61b8e3f8131'

r = ssm.send_command(
    InstanceIds=[instance_id],
    DocumentName='AWS-RunShellScript',
    Parameters={
        'commands': [
            'systemctl status mongod | grep -E "Active|running|failed" | head -3',
            'ss -tlnp | grep 27017 || echo "NOT LISTENING on 27017"',
            'mongosh --quiet --eval "db.adminCommand({ping:1})" 2>&1 | head -3'
        ]
    },
    TimeoutSeconds=30
)
cmd_id = r['Command']['CommandId']
print(f"Command ID: {cmd_id}")
time.sleep(8)

result = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=instance_id)
print(f"Status: {result['Status']}")
print(f"Output:\n{result['StandardOutputContent']}")
if result['StandardErrorContent']:
    print(f"Stderr:\n{result['StandardErrorContent']}")
