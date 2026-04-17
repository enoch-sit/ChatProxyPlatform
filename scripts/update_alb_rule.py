import boto3

client = boto3.client('elbv2', region_name='us-east-1')

rule_arn = 'arn:aws:elasticloadbalancing:us-east-1:168437900315:listener-rule/app/chatproxy-dev-alb/a1c04b5847b4af9a/704a3e7d121c4b29/2574442fd594e512'

response = client.modify_rule(
    RuleArn=rule_arn,
    Conditions=[
        {
            'Field': 'path-pattern',
            'PathPatternConfig': {
                'Values': ['/api/v1/chat', '/api/v1/chat/*', '/api/v1/admin', '/api/v1/admin/*']
            }
        }
    ]
)

for rule in response['Rules']:
    for cond in rule['Conditions']:
        print(f"Updated rule conditions: {cond.get('PathPatternConfig', {}).get('Values')}")
print("Done!")
