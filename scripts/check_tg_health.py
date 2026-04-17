import boto3
client = boto3.client('elbv2', region_name='us-east-1')
tgs = {
    'flowise-proxy': 'arn:aws:elasticloadbalancing:us-east-1:168437900315:targetgroup/chatproxy-dev-flowise-proxy-tg/9fbeaad5f35abd9a',
    'bridge': 'arn:aws:elasticloadbalancing:us-east-1:168437900315:targetgroup/chatproxy-dev-bridge-tg/917e2fbc02575d70',
    'auth': 'arn:aws:elasticloadbalancing:us-east-1:168437900315:targetgroup/chatproxy-dev-auth-tg/9528a06d8d5fa44c',
    'accounting': 'arn:aws:elasticloadbalancing:us-east-1:168437900315:targetgroup/chatproxy-dev-accounting-tg/cb977f374fffdb12',
}
for name, arn in tgs.items():
    r = client.describe_target_health(TargetGroupArn=arn)
    for t in r['TargetHealthDescriptions']:
        h = t['TargetHealth']
        state = h.get('State', 'unknown')
        desc = h.get('Description', '')
        print(name + ': ' + state + ' - ' + desc)
    if not r['TargetHealthDescriptions']:
        print(name + ': NO TARGETS')
