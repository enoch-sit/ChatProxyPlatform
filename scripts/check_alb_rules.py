import boto3, json

client = boto3.client('elbv2', region_name='us-east-1')
rules = client.describe_rules(
    ListenerArn='arn:aws:elasticloadbalancing:us-east-1:168437900315:listener/app/chatproxy-dev-alb/a1c04b5847b4af9a/704a3e7d121c4b29'
)['Rules']

tg_map = {
    'chatproxy-dev-auth-tg': 'auth',
    'chatproxy-dev-accounting-tg': 'accounting',
    'chatproxy-dev-flowise-proxy-tg': 'flowise-proxy',
    'chatproxy-dev-bridge-tg': 'bridge',
}

for rule in sorted(rules, key=lambda x: int(x['Priority']) if x['Priority'] != 'default' else 9999):
    priority = rule['Priority']
    paths = []
    for cond in rule.get('Conditions', []):
        if 'PathPatternConfig' in cond:
            paths.extend(cond['PathPatternConfig']['Values'])
    
    tg_name = 'none'
    for action in rule.get('Actions', []):
        tg_arn = action.get('TargetGroupArn', '')
        for k, v in tg_map.items():
            if k in tg_arn:
                tg_name = v
    
    print(f"Priority {priority:>8}: paths={paths} -> {tg_name}")
