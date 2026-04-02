import boto3

ec2 = boto3.client('ec2', region_name='us-east-1')
ecs = boto3.client('ecs', region_name='us-east-1')
elbv2 = boto3.client('elbv2', region_name='us-east-1')
rds = boto3.client('rds', region_name='us-east-1')
ecr = boto3.client('ecr', region_name='us-east-1')
sm = boto3.client('secretsmanager', region_name='us-east-1')
r53 = boto3.client('route53')
s3 = boto3.client('s3', region_name='us-east-1')

print("=== EC2 Instances ===")
instances = ec2.describe_instances(Filters=[{'Name':'instance-state-name','Values':['running']}])
for r in instances['Reservations']:
    for i in r['Instances']:
        name = next((t['Value'] for t in i.get('Tags',[]) if t['Key']=='Name'), 'unnamed')
        print(f"  {i['InstanceType']} - {name}")

print("\n=== RDS Instances ===")
dbs = rds.describe_db_instances()
for db in dbs['DBInstances']:
    print(f"  {db['DBInstanceClass']} {db['Engine']} {db['AllocatedStorage']}GB MultiAZ={db['MultiAZ']} - {db['DBInstanceIdentifier']}")

print("\n=== Load Balancers ===")
lbs = elbv2.describe_load_balancers()
for lb in lbs['LoadBalancers']:
    print(f"  {lb['Type']} - {lb['LoadBalancerName']}")

print("\n=== ECS Fargate Services ===")
clusters = ecs.list_clusters()['clusterArns']
for cluster_arn in clusters:
    cluster_name = cluster_arn.split('/')[-1]
    svcs = ecs.list_services(cluster=cluster_arn)['serviceArns']
    if svcs:
        details = ecs.describe_services(cluster=cluster_arn, services=svcs)['services']
        for s in details:
            td = ecs.describe_task_definition(taskDefinition=s['taskDefinition'])['taskDefinition']
            cpu = td['cpu']
            mem = td['memory']
            running = s['runningCount']
            print(f"  {s['serviceName']} cpu={cpu} mem={mem}MB x{running} tasks")

print("\n=== ECR Repositories ===")
repos = ecr.describe_repositories()['repositories']
total_size_mb = 0
for repo in repos:
    images = ecr.describe_images(repositoryName=repo['repositoryName'])['imageDetails']
    size = sum(i.get('imageSizeInBytes',0) for i in images) / (1024*1024)
    total_size_mb += size
    print(f"  {repo['repositoryName']} = {size:.0f} MB")
print(f"  TOTAL: {total_size_mb:.0f} MB = {total_size_mb/1024:.2f} GB")

print("\n=== Secrets Manager ===")
secrets = sm.list_secrets()['SecretList']
print(f"  {len(secrets)} secrets")

print("\n=== Route53 ===")
zones = r53.list_hosted_zones()['HostedZones']
print(f"  {len(zones)} hosted zones")

print("\n=== NAT Gateways ===")
nats = ec2.describe_nat_gateways(Filters=[{'Name':'state','Values':['available']}])['NatGateways']
for n in nats:
    print(f"  NAT Gateway: {n['NatGatewayId']}")

print("\n=== Elastic IPs ===")
eips = ec2.describe_addresses()['Addresses']
for eip in eips:
    assoc = eip.get('AssociationId', 'UNATTACHED')
    print(f"  EIP: {eip.get('PublicIp')} - {assoc}")

print("\n=== S3 Buckets ===")
try:
    buckets = s3.list_buckets()['Buckets']
    print(f"  {len(buckets)} buckets: {[b['Name'] for b in buckets]}")
except Exception as e:
    print(f"  Error: {e}")
