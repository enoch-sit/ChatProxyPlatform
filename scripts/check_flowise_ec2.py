import boto3, time

ssm = boto3.client('ssm', region_name='us-east-1')

cmds = [
    "systemctl list-units --type=service --state=running | grep -i flowise || echo 'no flowise service'",
    "ps aux | grep -i flowise | grep -v grep || echo 'no flowise process'",
    "ss -tlnp | grep -E '3000|3001|3002|8080' || echo 'no ports'",
]

r = ssm.send_command(
    InstanceIds=['i-0daeb69c63517a4e2'],
    DocumentName='AWS-RunShellScript',
    Parameters={'commands': cmds}
)
cid = r['Command']['CommandId']
print('CmdId:', cid)
time.sleep(6)
out = ssm.get_command_invocation(CommandId=cid, InstanceId='i-0daeb69c63517a4e2')
print('Status:', out['Status'])
print(out['StandardOutputContent'])
if out['StandardErrorContent']:
    print('STDERR:', out['StandardErrorContent'])
