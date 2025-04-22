from flask import Flask, request, jsonify
from concurrent.futures import ThreadPoolExecutor, as_completed
import boto3
import json
import os
import paramiko
import subprocess
import shutil
import time
from botocore.exceptions import ClientError
from flask_cors import CORS
from typing import Dict, List, Union
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Get the frontend directory path
FRONTEND_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'frontend')

# Updated AWS_SERVICES configuration in app.py
AWS_SERVICES = {
    'EC2': {
        'namespace': 'AWS/EC2',
        'dimension_key': 'InstanceId',
        'resource_type': 'instances',
        'list_function': 'describe_instances',
        'metrics': [
            {'name': 'CPUUtilization', 'namespace': 'AWS/EC2'},
            {
                'name': 'DiskSpaceUtilization',
                'namespace': 'CWAgent',
                'dimensions': [
                    {'Name': 'InstanceId', 'Value': '${aws:InstanceId}'},
                    {'Name': 'path', 'Value': '/'},
                    {'Name': 'device', 'Value': 'xvda1'},
                    {'Name': 'fstype', 'Value': 'ext4'}
                ]
            },
            {'name': 'MemoryUtilization', 'namespace': 'CWAgent'},
            {'name': 'NetworkIn', 'namespace': 'AWS/EC2'},
            {'name': 'NetworkOut', 'namespace': 'AWS/EC2'}
        ]
    },
    'RDS': {
        'namespace': 'AWS/RDS',
        'dimension_key': 'DBInstanceIdentifier',
        'resource_type': 'db_instances',
        'list_function': 'describe_db_instances',
        'metrics': [
            {'name': 'CPUUtilization', 'namespace': 'AWS/RDS'},
            {'name': 'FreeableMemory', 'namespace': 'AWS/RDS'},
            {'name': 'FreeStorageSpace', 'namespace': 'AWS/RDS'},
            {'name': 'DatabaseConnections', 'namespace': 'AWS/RDS'},
            {'name': 'ReadIOPS', 'namespace': 'AWS/RDS'},
            {'name': 'WriteIOPS', 'namespace': 'AWS/RDS'}
        ]
    },
    'Lambda': {
        'namespace': 'AWS/Lambda',
        'dimension_key': 'FunctionName',
        'resource_type': 'functions',
        'list_function': 'list_functions',
        'metrics': [
            {'name': 'Invocations', 'namespace': 'AWS/Lambda'},
            {'name': 'Errors', 'namespace': 'AWS/Lambda'},
            {'name': 'Duration', 'namespace': 'AWS/Lambda'},
            {'name': 'Throttles', 'namespace': 'AWS/Lambda'},
            {'name': 'ConcurrentExecutions', 'namespace': 'AWS/Lambda'},
            {'name': 'IteratorAge', 'namespace': 'AWS/Lambda'}
        ]
    },
    'DynamoDB': {
        'namespace': 'AWS/DynamoDB',
        'dimension_key': 'TableName',
        'resource_type': 'tables',
        'list_function': 'list_tables',
        'metrics': [
            {'name': 'ConsumedReadCapacityUnits', 'namespace': 'AWS/DynamoDB'},
            {'name': 'ConsumedWriteCapacityUnits', 'namespace': 'AWS/DynamoDB'},
            {'name': 'ReadThrottleEvents', 'namespace': 'AWS/DynamoDB'},
            {'name': 'WriteThrottleEvents', 'namespace': 'AWS/DynamoDB'},
            {'name': 'SuccessfulRequestLatency', 'namespace': 'AWS/DynamoDB'},
            {'name': 'SystemErrors', 'namespace': 'AWS/DynamoDB'}
        ]
    },
    'ECS': {
        'namespace': 'AWS/ECS',
        'dimension_key': 'ClusterName',
        'resource_type': 'clusters',
        'list_function': 'list_clusters',
        'metrics': [
            {'name': 'CPUUtilization', 'namespace': 'AWS/ECS'},
            {'name': 'MemoryUtilization', 'namespace': 'AWS/ECS'},
            {'name': 'RunningTaskCount', 'namespace': 'AWS/ECS'},
            {'name': 'PendingTaskCount', 'namespace': 'AWS/ECS'},
            {'name': 'StorageReadBytes', 'namespace': 'AWS/ECS'},
            {'name': 'StorageWriteBytes', 'namespace': 'AWS/ECS'}
        ]
    },
    'ElastiCache': {
        'namespace': 'AWS/ElastiCache',
        'dimension_key': 'CacheClusterId',
        'resource_type': 'cache_clusters',
        'list_function': 'describe_cache_clusters',
        'metrics': [
            {'name': 'CPUUtilization', 'namespace': 'AWS/ElastiCache'},
            {'name': 'FreeableMemory', 'namespace': 'AWS/ElastiCache'},
            {'name': 'NetworkBytesIn', 'namespace': 'AWS/ElastiCache'},
            {'name': 'NetworkBytesOut', 'namespace': 'AWS/ElastiCache'},
            {'name': 'CurrConnections', 'namespace': 'AWS/ElastiCache'},
            {'name': 'CacheHits', 'namespace': 'AWS/ElastiCache'},
            {'name': 'CacheMisses', 'namespace': 'AWS/ElastiCache'}
        ]
    },
    'ELB': {
        'namespace': 'AWS/ELB',
        'dimension_key': 'LoadBalancerName',
        'resource_type': 'load_balancers',
        'list_function': 'describe_load_balancers',
        'metrics': [
            {'name': 'RequestCount', 'namespace': 'AWS/ELB'},
            {'name': 'HealthyHostCount', 'namespace': 'AWS/ELB'},
            {'name': 'UnHealthyHostCount', 'namespace': 'AWS/ELB'},
            {'name': 'Latency', 'namespace': 'AWS/ELB'},
            {'name': 'HTTPCode_Backend_2XX', 'namespace': 'AWS/ELB'},
            {'name': 'HTTPCode_Backend_5XX', 'namespace': 'AWS/ELB'}
        ]
    },
    'SQS': {
        'namespace': 'AWS/SQS',
        'dimension_key': 'QueueName',
        'resource_type': 'queues',
        'list_function': 'list_queues',
        'metrics': [
            {'name': 'ApproximateNumberOfMessagesVisible', 'namespace': 'AWS/SQS'},
            {'name': 'ApproximateNumberOfMessagesNotVisible', 'namespace': 'AWS/SQS'},
            {'name': 'ApproximateAgeOfOldestMessage', 'namespace': 'AWS/SQS'},
            {'name': 'NumberOfMessagesReceived', 'namespace': 'AWS/SQS'},
            {'name': 'NumberOfMessagesSent', 'namespace': 'AWS/SQS'},
            {'name': 'NumberOfMessagesDeleted', 'namespace': 'AWS/SQS'}
        ]
    },
    'S3': {
        'namespace': 'AWS/S3',
        'dimension_key': 'BucketName',
        'resource_type': 'buckets',
        'list_function': 'list_buckets',
        'metrics': [
            {'name': 'BucketSizeBytes', 'namespace': 'AWS/S3'},
            {'name': 'NumberOfObjects', 'namespace': 'AWS/S3'},
            {'name': 'AllRequests', 'namespace': 'AWS/S3'},
            {'name': '4xxErrors', 'namespace': 'AWS/S3'},
            {'name': '5xxErrors', 'namespace': 'AWS/S3'},
            {'name': 'FirstByteLatency', 'namespace': 'AWS/S3'},
            {'name': 'TotalRequestLatency', 'namespace': 'AWS/S3'}
        ]
    }
}

# Helper function to ensure required IAM role and policies on EC2 instances
def ensure_instance_role(instance_id: str, region: str) -> None:
    required_policy_arns = [
        'arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess',
        'arn:aws:iam::aws:policy/AmazonSNSFullAccess',
        'arn:aws:iam::aws:policy/AmazonSSMFullAccess',
        'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore',
        'arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy',
        'arn:aws:iam::aws:policy/CloudWatchFullAccess'
    ]
    ec2 = create_aws_client('ec2', region)
    iam = boto3.client('iam')
    try:
        desc = ec2.describe_instances(InstanceIds=[instance_id])
        instance = desc['Reservations'][0]['Instances'][0]
    except Exception as e:
        logger.error(f"Error fetching details for instance {instance_id}: {str(e)}")
        return

    # If the instance already has an IAM instance profile attached:
    if 'IamInstanceProfile' in instance:
        profile_arn = instance['IamInstanceProfile']['Arn']
        profile_name = profile_arn.split('/')[-1]
        try:
            profile_details = iam.get_instance_profile(InstanceProfileName=profile_name)
            if profile_details['InstanceProfile']['Roles']:
                role_name = profile_details['InstanceProfile']['Roles'][0]['RoleName']
                attached = iam.list_attached_role_policies(RoleName=role_name)['AttachedPolicies']
                attached_arns = [p['PolicyArn'] for p in attached]
                for policy_arn in required_policy_arns:
                    if policy_arn not in attached_arns:
                        iam.attach_role_policy(RoleName=role_name, PolicyArn=policy_arn)
            else:
                role_name = "MonitoringRole"
                _create_and_attach_role(iam, ec2, instance_id, role_name, required_policy_arns)
        except Exception as e:
            logger.error(f"Error processing instance profile for {instance_id}: {str(e)}")
    else:
        role_name = "MonitoringRole"
        _create_and_attach_role(iam, ec2, instance_id, role_name, required_policy_arns)

def _create_and_attach_role(iam, ec2, instance_id: str, role_name: str, required_policy_arns: List[str]) -> None:
    try:
        iam.get_role(RoleName=role_name)
    except iam.exceptions.NoSuchEntityException:
        trust_policy = {
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "ec2.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }
        iam.create_role(RoleName=role_name, AssumeRolePolicyDocument=json.dumps(trust_policy))
    attached = iam.list_attached_role_policies(RoleName=role_name)['AttachedPolicies']
    attached_arns = [p['PolicyArn'] for p in attached]
    for policy_arn in required_policy_arns:
        if policy_arn not in attached_arns:
            iam.attach_role_policy(RoleName=role_name, PolicyArn=policy_arn)
    # Use an instance profile name distinct from the role name
    instance_profile_name = role_name + "Profile"
    try:
        iam.get_instance_profile(InstanceProfileName=instance_profile_name)
    except iam.exceptions.NoSuchEntityException:
        iam.create_instance_profile(InstanceProfileName=instance_profile_name)
        iam.add_role_to_instance_profile(InstanceProfileName=instance_profile_name, RoleName=role_name)
        time.sleep(10)
    profile = iam.get_instance_profile(InstanceProfileName=instance_profile_name)
    profile_arn = profile['InstanceProfile']['Arn']
    associations = ec2.describe_iam_instance_profile_associations(
        Filters=[{'Name': 'instance-id', 'Values': [instance_id]}]
    )
    if associations['IamInstanceProfileAssociations']:
        association_id = associations['IamInstanceProfileAssociations'][0]['AssociationId']
        ec2.replace_iam_instance_profile_association(
            IamInstanceProfile={'Arn': profile_arn},
            AssociationId=association_id
        )
    else:
        ec2.associate_iam_instance_profile(
            IamInstanceProfile={'Arn': profile_arn},
            InstanceId=instance_id
        )

def setup_nginx() -> None:
    try:
        os.makedirs('/var/www/html/css', exist_ok=True)
        os.makedirs('/var/www/html/js', exist_ok=True)
        
        # Copy HTML, CSS, and JS files
        shutil.copy(os.path.join(FRONTEND_DIR, 'index.html'), '/var/www/html/')
        shutil.copy(os.path.join(FRONTEND_DIR, 'css/styles.css'), '/var/www/html/css/')
        shutil.copy(os.path.join(FRONTEND_DIR, 'js/script.js'), '/var/www/html/js/')
        # Copy the images folder (ensure your images folder is in the frontend folder)
        shutil.copytree(os.path.join(FRONTEND_DIR, 'images'), '/var/www/html/images', dirs_exist_ok=True)

        nginx_config = """
        server {
        listen 80;
        server_name _;

        # Serve static files under /cloudwatch
        location /cloudwatch/ {
            alias /var/www/html/;
            try_files $uri $uri/ /cloudwatch/index.html;
        }

        # Proxy API calls under /cloudwatch/api
        location /cloudwatch/api/ {
            proxy_pass http://localhost:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_connect_timeout 600;
            proxy_send_timeout 600;
            proxy_read_timeout 600;
            send_timeout 600;
        }

        # Optionally, block or redirect other requests
        location / {
            return 404;
        }
    }
        """
        
        temp_path = '/tmp/nginx_default'
        with open(temp_path, 'w') as f:
            f.write(nginx_config.strip())
        
        subprocess.run(['sudo', 'mv', temp_path, '/etc/nginx/sites-available/default'], check=True)
        subprocess.run(['sudo', 'nginx', '-t'], check=True)
        subprocess.run(['sudo', 'chown', '-R', 'www-data:www-data', '/var/www/html'])
        subprocess.run(['sudo', 'chmod', '-R', '755', '/var/www/html'])
        subprocess.run(['sudo', 'systemctl', 'restart', 'nginx'], check=True)
        logger.info("Nginx setup completed successfully")
    except Exception as e:
        logger.error(f"Error setting up nginx: {str(e)}")
        raise
    
def create_aws_client(service: str, region: str = None) -> boto3.client:
    try:
        if region:
            return boto3.client(service, region_name=region)
        return boto3.client(service)
    except Exception as e:
        logger.error(f"Error creating AWS {service} client: {str(e)}")
        raise

@app.route('/api/services')
def get_services() -> Dict:
    try:
        services = list(AWS_SERVICES.keys())
        return jsonify(services)
    except Exception as e:
        logger.error(f"Error fetching services: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/regions')
def get_regions() -> Dict:
    try:
        ec2 = create_aws_client('ec2', region='us-east-1')
        response = ec2.describe_regions()
        regions = [region['RegionName'] for region in response['Regions']]
        return jsonify(regions)
    except Exception as e:
        logger.error(f"Error fetching regions: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/resources/<service>', methods=['GET'])
def get_resources_all_regions(service: str) -> dict:
    try:
        # Perform a case-insensitive lookup for the service configuration.
        service_config = next((AWS_SERVICES[k] for k in AWS_SERVICES if k.lower() == service.lower()), None)
        if not service_config:
            return jsonify({'error': 'Invalid service'}), 400

        ec2 = create_aws_client('ec2', region='us-east-1')
        response = ec2.describe_regions()
        regions = [region['RegionName'] for region in response['Regions']]
        resources = []

        def fetch_resources_for_region(region):
            region_resources = []
            try:
                # Use service.lower() for the client name.
                client = create_aws_client(service.lower(), region)
                if service.lower() == 'ec2':
                    instances = client.describe_instances()['Reservations']
                    for reservation in instances:
                        for instance in reservation['Instances']:
                            if instance['State']['Name'] == 'running':
                                region_resources.append({
                                    'Id': instance['InstanceId'],
                                    'Type': instance['InstanceType'],
                                    'State': instance['State']['Name'],
                                    'Name': next((tag['Value'] for tag in instance.get('Tags', []) if tag['Key'] == 'Name'), 'Unnamed'),
                                    'PublicIpAddress': instance.get('PublicIpAddress'),
                                    'PrivateIpAddress': instance.get('PrivateIpAddress'),
                                    'Region': region
                                })
                elif service.lower() == 'rds':
                    instances = client.describe_db_instances()['DBInstances']
                    for instance in instances:
                        region_resources.append({
                            'Id': instance['DBInstanceIdentifier'],
                            'Type': instance['DBInstanceClass'],
                            'State': instance['DBInstanceStatus'],
                            'Name': instance.get('DBName', instance['DBInstanceIdentifier']),
                            'Region': region
                        })
                elif service.lower() == 'lambda':
                    functions = client.list_functions()['Functions']
                    for function in functions:
                        region_resources.append({
                            'Id': function['FunctionName'],
                            'Type': function.get('Runtime', ''),
                            'State': function.get('State', 'Active'),
                            'Name': function['FunctionName'],
                            'Region': region
                        })
                elif service.lower() == 'dynamodb':
                    tables = client.list_tables()['TableNames']
                    for table in tables:
                        region_resources.append({
                            'Id': table,
                            'Type': 'DynamoDB Table',
                            'State': 'Active',
                            'Name': table,
                            'Region': region
                        })
                elif service.lower() == 'ecs':
                    clusters = client.list_clusters()['clusterArns']
                    for cluster_arn in clusters:
                        cluster_name = cluster_arn.split('/')[-1]
                        region_resources.append({
                            'Id': cluster_name,
                            'Type': 'ECS Cluster',
                            'State': 'Active',
                            'Name': cluster_name,
                            'Region': region
                        })
                elif service.lower() == 'elasticache':
                    clusters = client.describe_cache_clusters()['CacheClusters']
                    for cluster in clusters:
                        region_resources.append({
                            'Id': cluster['CacheClusterId'],
                            'Type': cluster['Engine'],
                            'State': cluster['CacheClusterStatus'],
                            'Name': cluster['CacheClusterId'],
                            'Region': region
                        })
                elif service.lower() == 'elb':
                    lbs = client.describe_load_balancers()['LoadBalancerDescriptions']
                    for lb in lbs:
                        region_resources.append({
                            'Id': lb['LoadBalancerName'],
                            'Type': 'Classic Load Balancer',
                            'State': 'Active',
                            'Name': lb['LoadBalancerName'],
                            'Region': region
                        })
                elif service.lower() == 'sqs':
                    queues = client.list_queues()['QueueUrls']
                    for queue in queues:
                        queue_name = queue.split('/')[-1]
                        region_resources.append({
                            'Id': queue_name,
                            'Type': 'SQS Queue',
                            'State': 'Active',
                            'Name': queue_name,
                            'Region': region
                        })
                elif service.lower() == 's3':
                    buckets = client.list_buckets()['Buckets']
                    for bucket in buckets:
                        region_resources.append({
                            'Id': bucket['Name'],
                            'Type': 'S3 Bucket',
                            'State': 'Active',
                            'Name': bucket['Name'],
                            'Region': region
                        })
            except Exception as region_error:
                logger.warning(f"Could not fetch resources for service {service} in region {region}: {str(region_error)}")
            return region_resources

        with ThreadPoolExecutor(max_workers=len(regions)) as executor:
            future_to_region = {executor.submit(fetch_resources_for_region, region): region for region in regions}
            for future in as_completed(future_to_region):
                resources.extend(future.result())
        return jsonify(resources)
    except Exception as e:
        logger.error(f"Error fetching resources for {service} across all regions: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/metrics/<service>')
def get_metrics(service: str) -> Dict:
    try:
        # Perform a case-insensitive lookup for the service configuration.
        service_config = next((AWS_SERVICES[k] for k in AWS_SERVICES if k.lower() == service.lower()), None)
        if not service_config:
            return jsonify({'error': 'Invalid service'}), 400
        return jsonify(service_config['metrics'])
    except Exception as e:
        logger.error(f"Error fetching metrics for {service}: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/configure', methods=['POST'])
def configure_monitoring():
    try:
        # Parse incoming data and process file uploads if any
        if request.content_type.startswith('multipart/form-data'):
            config_data = request.form.get('config')
            if not config_data:
                return jsonify({'error': 'Missing configuration data'}), 400
            data = json.loads(config_data)
            uploaded_keys = {}
            upload_folder = os.path.join(os.getcwd(), 'uploaded_keys')
            os.makedirs(upload_folder, exist_ok=True)
            for field_name, file in request.files.items():
                file_path = os.path.join(upload_folder, file.filename)
                file.save(file_path)
                uploaded_keys[field_name] = file_path
            data['uploaded_keys'] = uploaded_keys
        else:
            data = request.get_json()

        if not data:
            return jsonify({'error': 'No data provided'}), 400

        # Verify required fields
        required_fields = ['region', 'service', 'resources', 'metrics', 'alerts', 'thresholds']
        for field in required_fields:
            if field not in data:
                return jsonify({'error': f'Missing required field: {field}'}), 400

        region = data['region']
        service = data['service'].upper()
        resources = data['resources']
        metrics = data['metrics']
        alerts = data['alerts']
        thresholds = data['thresholds']

        service_config = AWS_SERVICES.get(service)
        if not service_config:
            return jsonify({'error': 'Invalid service'}), 400

        sns = create_aws_client('sns', region)
        cloudwatch = create_aws_client('cloudwatch', region)

        # Compute resource IDs and add fallback if empty
        resource_ids = [r['Id'] if isinstance(r, dict) and 'Id' in r else r for r in resources]
        if not resource_ids or all(not str(r).strip() for r in resource_ids):
            resource_ids = ['None']
        dashboard_name = f"{service}-Monitor_{'-'.join(resource_ids)}"
        topic_name = f"{service}_Monitoring_Alerts_{'-'.join(resource_ids)}"

        try:
            topic_response = sns.create_topic(Name=topic_name)
            topic_arn = topic_response['TopicArn']
        except ClientError as e:
            logger.error(f"Error creating SNS topic: {str(e)}")
            return jsonify({'error': f'Failed to create SNS topic: {str(e)}'}), 500

        alarm_arns = []
        if alerts:
            for resource in resources:
                resource_id = resource['Id'] if isinstance(resource, dict) else resource
                for metric in metrics:
                    try:
                        dimensions = [{'Name': service_config['dimension_key'], 'Value': resource_id}]
                        if 'dimension' in metric:
                            dimensions.append(metric['dimension'])
                        if metric['namespace'] == 'CWAgent':
                            dimensions = [{'Name': 'InstanceId', 'Value': resource_id}]
                            if metric['name'] == 'DiskSpaceUtilization':
                                dimensions.extend([
                                    {'Name': 'path', 'Value': '/'},
                                    {'Name': 'device', 'Value': 'xvda1'},
                                    {'Name': 'fstype', 'Value': 'ext4'}
                                ])
                        warning_alarm_name = f"{resource_id}-{metric['name']}-Warning"
                        warning_alarm_config = {
                            'AlarmName': warning_alarm_name,
                            'MetricName': metric['name'],
                            'Namespace': metric['namespace'],
                            'Statistic': 'Average',
                            'Period': 300,
                            'EvaluationPeriods': 2,
                            'Threshold': float(thresholds[metric['name']]['warning']),
                            'ComparisonOperator': 'GreaterThanThreshold',
                            'AlarmActions': [topic_arn],
                            'OKActions': [topic_arn],
                            'Dimensions': dimensions,
                            'AlarmDescription': f'Warning threshold exceeded for {metric["name"]} on {resource_id}'
                        }
                        cloudwatch.put_metric_alarm(**warning_alarm_config)
                        alarm_arns.append(warning_alarm_name)

                        critical_alarm_name = f"{resource_id}-{metric['name']}-Critical"
                        critical_alarm_config = {
                            'AlarmName': critical_alarm_name,
                            'MetricName': metric['name'],
                            'Namespace': metric['namespace'],
                            'Statistic': 'Average',
                            'Period': 300,
                            'EvaluationPeriods': 2,
                            'Threshold': float(thresholds[metric['name']]['critical']),
                            'ComparisonOperator': 'GreaterThanThreshold',
                            'AlarmActions': [topic_arn],
                            'OKActions': [topic_arn],
                            'Dimensions': dimensions,
                            'AlarmDescription': f'Critical threshold exceeded for {metric["name"]} on {resource_id}'
                        }
                        cloudwatch.put_metric_alarm(**critical_alarm_config)
                        alarm_arns.append(critical_alarm_name)
                    except ClientError as e:
                        logger.error(f"Error creating alarms for {resource_id}: {str(e)}")
                        return jsonify({'error': f'Failed to create alarms for {resource_id}: {str(e)}'}), 500

        # Ensure IAM roles are correct for EC2 instances.
        if service == 'EC2':
            for resource in resources:
                instance_id = resource['Id']
                ensure_instance_role(instance_id, region)
            for resource in resources:
                if isinstance(resource, dict):
                    resource_id = resource.get('Id')
                    ip_address = resource.get('PrivateIpAddress')
                else:
                    resource_id = resource
                    ip_address = None

                if not ip_address:
                    logger.error(f"No private IP found for resource: {resource_id}")
                    continue

                key_field = f"key_{resource_id}"
                key_path = data.get('uploaded_keys', {}).get(key_field)
                if not key_path:
                    logger.error(f"No key file found for resource: {resource_id}")
                    continue

                try:
                    os.chmod(key_path, 0o400)
                    key = paramiko.RSAKey.from_private_key_file(key_path)
                    ssh = paramiko.SSHClient()
                    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                    ssh.connect(ip_address, username="ubuntu", pkey=key)

                    check_cmd = "if [ -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then echo 'installed'; else echo 'not installed'; fi"
                    stdin, stdout, stderr = ssh.exec_command(check_cmd)
                    status = stdout.read().decode('utf-8').strip()
                    if status == 'installed':
                        logger.info(f"CloudWatch agent already installed on {resource_id}, skipping installation.")
                        ssh.close()
                        continue

                    sftp = ssh.open_sftp()
                    local_script_path = os.path.join(os.path.dirname(__file__), "install_cloudwatchagent.sh")
                    remote_script_path = "/home/ubuntu/install_cloudwatchagent.sh"
                    sftp.put(local_script_path, remote_script_path)
                    sftp.close()

                    agent_command = f"chmod +x {remote_script_path} && sudo bash {remote_script_path}"
                    stdin, stdout, stderr = ssh.exec_command(agent_command)
                    exit_status = stdout.channel.recv_exit_status()
                    output = stdout.read().decode('utf-8')
                    errors = stderr.read().decode('utf-8')
                    if exit_status != 0:
                        logger.error(f"SSH command on {resource_id} failed with status {exit_status}. Errors: {errors}")
                    else:
                        logger.info(f"SSH command on {resource_id} succeeded with status {exit_status}. Output: {output}")
                    ssh.close()
                except Exception as e:
                    logger.error(f"Error running agent command on {resource_id}: {str(e)}")
        else:
            logger.info(f"Skipping CloudWatch agent installation since service is {service} (not EC2).")

        # Dashboard creation
        widgets = []
        for metric in metrics:
            metric_data = [[metric['namespace'], metric['name']]]
            for resource in resources:
                resource_id = resource['Id'] if isinstance(resource, dict) else resource
                dimensions = [[service_config['dimension_key'], resource_id]]
                if metric['namespace'] == 'CWAgent':
                    dimensions = [['InstanceId', resource_id]]
                    if metric['name'] == 'DiskSpaceUtilization':
                        dimensions.append(['path', '/'])
                        dimensions.append(['device', 'xvda1'])
                        dimensions.append(['fstype', 'ext4'])
                metric_data.append([metric['namespace'], metric['name'],
                                    *[item for dim in dimensions for item in [dim[0], dim[1]]]])
            widgets.append({
                "type": "metric",
                "x": 0,
                "y": len(widgets) * 6,
                "width": 24,
                "height": 6,
                "properties": {
                    "metrics": metric_data,
                    "period": 300,
                    "stat": "Average",
                    "region": region,
                    "title": f"{metric['name']} across {len(resources)} instances"
                }
            })
        try:
            response = cloudwatch.put_dashboard(
                DashboardName=dashboard_name,
                DashboardBody=json.dumps({"widgets": widgets})
            )
            logger.info(f"Dashboard creation response: {response}")
        except ClientError as e:
            logger.error(f"Error creating dashboard: {str(e)}")
            return jsonify({'error': f'Failed to create dashboard: {str(e)}'}), 500

        return jsonify({
            'message': 'Monitoring configured successfully!',
            'snsTopicArn': topic_arn,
            'topicName': topic_name,
            'dashboardName': dashboard_name,
            'dashboardUrl': f"https://{region}.console.aws.amazon.com/cloudwatch/home?region={region}#dashboards:name={dashboard_name}",
            'alarms': alarm_arns
        })

    except Exception as e:
        logger.error(f"Unexpected error in configure_monitoring: {str(e)}")
        return jsonify({'error': f'Unexpected error: {str(e)}'}), 500

if __name__ == '__main__':
    try:
        sts = create_aws_client('sts')
        sts.get_caller_identity()
        logger.info("AWS credentials verified successfully")
        setup_nginx()
        app.run(host='0.0.0.0', port=5000, debug=False)
    except Exception as e:
        logger.error(f"Startup error: {str(e)}")
        raise
