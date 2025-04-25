from flask import Flask, render_template, request, jsonify, Response
import subprocess
from pathlib import Path
import os
import time
import json
import logging
import boto3
from botocore.exceptions import ClientError
from werkzeug.utils import secure_filename

UPLOAD_FOLDER = '/opt/observability/EKS/PEM_FILES'  # or another secure location
ALLOWED_EXTENSIONS = {'pem'}

app = Flask(__name__)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# Create upload folder if it doesn't exist
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

# Set up logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s %(levelname)s: %(message)s',
    handlers=[
        logging.FileHandler('/var/log/eksmonitoring.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

BASE_DIR = "/opt/observability/EKS/"
VARIABLES_FILE = "variables.sh"
GKE_VARIABLES_FILE = "gke-variables.sh"
SETUP_SCRIPT = f"{BASE_DIR}monitoring_setup.sh"
GKE_SETUP_SCRIPT = f"{BASE_DIR}gke_monitoring_setup.sh"

deployment_progress = {"progress": 0, "status": "Initializing..."}

def read_variables(var_file):
    """Read variables from variables.sh and return them as a dictionary."""
    variables = {}
    with open(var_file, "r") as file:
        for line in file:
            line = line.strip()
            if line and not line.startswith("#"):  # Ignore comments
                key, value = line.split("=", 1)
                variables[key.strip()] = value.strip().strip('"')  # Remove quotes if present
    return variables

def write_variables(updated_vars, var_file):
    """Write updated variables to variables.sh."""
    with open(var_file, "r") as file:
        lines = file.readlines()

    with open(var_file, "w") as file:
        for line in lines:
            if line.strip() and not line.startswith("#"):  # Ignore empty and comment lines
                key = line.split("=")[0].strip()
                if key in updated_vars:
                    # Handle array variables
                    if key in ['EC2_INSTANCES', 'EC2_INSTANCE_IDS', 'EC2_INSTANCE_NAMES', 'EC2_PEM_FILES']:
                        file.write(f'{key}={updated_vars[key]}\n')  # Arrays are already formatted
                    else:
                        file.write(f'{key}="{updated_vars[key]}"\n')
                else:
                    file.write(line)
            else:
                file.write(line)

def run_setup(script_file):
    try:
        script_path = Path(script_file)

        logger.info(f"Attempting to execute script: {script_path}")
        logger.info(f"Current working directory: {os.getcwd()}")
        logger.info(f"Current user: {os.getuid()}")
        logger.info(f"Script exists: {script_path.exists()}")
        
        # Check if script exists
        if not script_path.exists():
            return {
                "success": False,
                "message": f"❌ Script not found: {script_file}"
            }

        # Make script executable
        script_path.chmod(0o755)
        
        # Execute the script
        # result = subprocess.run(
        #     [str(script_path.absolute())],
        #     check=True,
        #     capture_output=True,
        #     text=True
        # )

        # *****************

        result = subprocess.run(
            ["/bin/bash", str(script_path)],
            check=True,
            capture_output=True,
            text=True,
            cwd=str(script_path.parent),
            env={
                **os.environ.copy(),
                'PWD': str(script_path.parent),
                'SHELL': '/bin/bash',
                'PATH': '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
            }
        )
        
        logger.info(f"Script stdout: {result.stdout}")
        logger.info(f"Script stderr: {result.stderr}")

        #  ************************
        
        # Check if script executed successfully
        if result.returncode == 0:
            return {
                "success": True,
                "message": "✅ Script executed successfully!"
            }
        else:
            return {
                "success": False,
                "message": f"❌ Script execution failed: {result.stderr}"
            }
    
    except subprocess.CalledProcessError as e:
        print(f"Script execution failed: {e.stderr}")
        return {
            "success": False,
            "message": f"❌ Script execution failed: {e.stderr}"
        }
    
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        return {
            "success": False,
            "message": f"❌ Unexpected error: {str(e)}"
        }

@app.route("/")
def index():
    return render_template("home.html")

@app.route("/eks", methods=["GET"])
def form():
    variables = read_variables(VARIABLES_FILE)
    return render_template("eks-form.html", variables=variables)

@app.route("/gke", methods=["GET"])
def gke_form():
    variables = read_variables(GKE_VARIABLES_FILE)
    return render_template("gke-form.html", variables=variables)

@app.route("/documentation")
def decumentation():
    return render_template("documentation.html")

@app.route('/deployment-progress')
def deployment_progress():
    def generate():
        while deployment_progress["progress"] < 100:
            yield f"data: {json.dumps(deployment_progress)}\n\n"
            time.sleep(0.5)
    return Response(generate(), mimetype='text/event-stream')

@app.route('/api/fetch-instances', methods=['POST'])
def fetch_instances():
    try:
        data = request.get_json()
        region = data.get('region')
        
        if not region:
            return jsonify({'error': 'Region is required'}), 400

        # Create EC2 client without explicitly providing credentials
        # It will automatically use the IAM role attached to the instance
        ec2 = boto3.client('ec2', region_name=region)

        # Fetch running instances
        response = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['running']}]
        )

        instances = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_data = {
                    'id': instance['InstanceId'],
                    'ip': instance.get('PrivateIpAddress', ''),
                    'name': next((tag['Value'] for tag in instance.get('Tags', []) 
                                if tag['Key'] == 'Name'), 'Unnamed')
                }
                instances.append(instance_data)

        return jsonify({
            'success': True,
            'instances': instances
        })

    except ClientError as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500
    except Exception as e:
        return jsonify({
            'success': False,
            'error': 'An unexpected error occurred'
        }), 500

@app.route("/deploy", methods=["POST"])
def deploy():
    global deployment_progress
    try:
        deployment_progress = {"progress": 0, "status": "Initializing deployment..."}
        
        # Update variables
        deployment_progress = {"progress": 20, "status": "Updating configuration..."}
        # Get selected EC2 instances
        selected_instances = []
        instance_ids = []
        instance_names = []
        pem_file_paths = []

        # Create a mapping of instance IDs to their details
        instance_details = {}

        # First, handle file uploads
        for key in request.files:
            if key.startswith('pem_file_'):
                file = request.files[key]
                instance_id = key.replace('pem_file_', '')
                
                if file and file.filename and allowed_file(file.filename):
                    filename = secure_filename(f"{instance_id}_{file.filename}")
                    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
                    file.save(filepath)
                    # Set proper permissions for the PEM file
                    os.chmod(filepath, 0o600)
                    instance_details[instance_id] = {'pem_path': filepath}
        
        # Parse form data for EC2 instances
        instance_count = 0
        while True:
            selection_key = f'EC2_SELECTION_{instance_count}'
            id_key = f'EC2_ID_{instance_count}'
            name_key = f'EC2_NAME_{instance_count}'
            
            if selection_key not in request.form:
                break
                
            selected_instances.append(request.form[selection_key])
            instance_ids.append(request.form[id_key])
            instance_names.append(request.form[name_key])
            
            # Add PEM file path if it exists for this instance
            if request.form[id_key] in instance_details:
                pem_file_paths.append(instance_details[request.form[id_key]]['pem_path'])
            else:
                pem_file_paths.append('')
                
            instance_count += 1


        # Update variables dictionary
        updated_vars = {key: request.form[key] for key in request.form}
        # Format arrays for variables.sh
        updated_vars['EC2_INSTANCES'] = "(" + " ".join([f'"{ip}"' for ip in selected_instances]) + ")"
        updated_vars['EC2_INSTANCE_IDS'] = "(" + " ".join([f'"{id}"' for id in instance_ids]) + ")"
        updated_vars['EC2_INSTANCE_NAMES'] = "(" + " ".join([f'"{name}"' for name in instance_names]) + ")"
        updated_vars['EC2_PEM_FILES'] = "(" + " ".join([f'"{path}"' for path in pem_file_paths]) + ")"
        updated_vars['EC2_INSTANCE_COUNT'] = str(instance_count)
        
        # Debug logging
        app.logger.debug(f"Selected instances: {selected_instances}")
        app.logger.debug(f"Instance IDs: {instance_ids}")
        app.logger.debug(f"Instance names: {instance_names}")
        app.logger.debug(f"PEM file paths: {pem_file_paths}")
        
        write_variables(updated_vars, VARIABLES_FILE)

        deployment_progress = {"progress": 40, "status": "Preparing deployment..."}
        
        # Run setup script
        deployment_progress = {"progress": 60, "status": "Executing deployment script..."}
        result = run_setup(SETUP_SCRIPT)
        
        deployment_progress = {"progress": 100, "status": "Deployment completed successfully!"}
        
        # Make sure to return success: True in the response
        return jsonify({
            "success": True,
            "message": "Configuration updated and deployment completed successfully!"
        })

    except Exception as e:
        deployment_progress = {"progress": 100, "status": "Deployment failed!"}
        print(f"Error during deployment: {str(e)}")
        return jsonify({
            "success": False,
            "message": f"❌ Failed to update configuration: {str(e)}"
        }), 500

@app.route("/gke-deploy", methods=["POST"])
def gke_deploy():
    global deployment_progress
    try:
        deployment_progress = {"progress": 0, "status": "Initializing deployment..."}
        
        # Update variables
        deployment_progress = {"progress": 20, "status": "Updating configuration..."}
        updated_vars = {key: request.form[key] for key in request.form}
        write_variables(updated_vars, GKE_VARIABLES_FILE)

        deployment_progress = {"progress": 40, "status": "Preparing deployment..."}
        
        # Run setup script
        deployment_progress = {"progress": 60, "status": "Executing deployment script..."}
        result = run_setup(GKE_SETUP_SCRIPT)
        
        deployment_progress = {"progress": 100, "status": "Deployment completed successfully!"}
        
        # Make sure to return success: True in the response
        return jsonify({
            "success": True,
            "message": "Configuration updated and deployment completed successfully!"
        })

    except Exception as e:
        deployment_progress = {"progress": 100, "status": "Deployment failed!"}
        print(f"Error during deployment: {str(e)}")
        return jsonify({
            "success": False,
            "message": f"❌ Failed to update configuration: {str(e)}"
        }), 500

@app.route("/test-log")
def test_log():
    app.logger.info("✅ Test log route hit!")
    return "Logged something to /home/ubuntu/flask-app.log"

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=7000, debug=True)