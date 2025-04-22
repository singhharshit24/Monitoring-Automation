import os
import subprocess
from flask import Flask, render_template, redirect, url_for, request, jsonify
import socket
import logging
from logging.handlers import RotatingFileHandler

# Application setup
BASE_DIR = "/opt/observability/main"
LOGS_DIR = f"{BASE_DIR}/logs"
STATIC_DIR = f"{BASE_DIR}/static"
TEMPLATES_DIR = f"{BASE_DIR}/templates"

# Create necessary directories if they don't exist
for directory in [BASE_DIR, LOGS_DIR, STATIC_DIR, TEMPLATES_DIR]:
    os.makedirs(directory, exist_ok=True)

# Configure logging
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
handler = RotatingFileHandler(f"{LOGS_DIR}/app.log", maxBytes=10000000, backupCount=5)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

app = Flask(__name__, 
            static_folder=STATIC_DIR,
            template_folder=TEMPLATES_DIR)

# Helper function to get server IP
def get_server_ip():
    try:
        # This gets the primary IP that would be used for external connections
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception as e:
        logger.error(f"Error getting server IP: {e}")
        return "localhost"

# Service management functions
def start_service(service_name):
    """Start a systemd service and return status"""
    try:
        logger.info(f"Starting service: {service_name}")
        result = subprocess.run(
            ["sudo", "systemctl", "start", service_name],
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            logger.info(f"Successfully started {service_name}")
            return True, "Service started successfully"
        else:
            logger.error(f"Failed to start {service_name}: {result.stderr}")
            return False, f"Failed to start service: {result.stderr}"
    
    except Exception as e:
        logger.error(f"Exception while starting {service_name}: {str(e)}")
        return False, f"Error: {str(e)}"

def check_service_status(service_name):
    """Check if a service is running"""
    try:
        result = subprocess.run(
            ["systemctl", "is-active", service_name],
            capture_output=True,
            text=True
        )
        return result.stdout.strip() == "active"
    except Exception as e:
        logger.error(f"Error checking service status: {e}")
        return False

# Routes
@app.route('/')
def index():
    """Main landing page"""
    server_ip = get_server_ip()
    return render_template('index.html', server_ip=server_ip)

@app.route('/select_resource_type')
def select_resource_type():
    """Page to select which AWS resources to monitor"""
    return render_template('select_resource_type.html')

@app.route('/general_resources')
def general_resources():
    """Page for general AWS resources monitoring options"""
    return render_template('general_resources.html')

@app.route('/eks_monitoring')
def eks_monitoring_page():
    """Page for EKS monitoring options"""
    # Start the EKS monitoring service
    success, message = start_service("eksmonitoring")
    status = "running" if check_service_status("eksmonitoring") else "stopped"
    
    return render_template('eks_monitoring.html', 
                          service_status=status,
                          message=message)

@app.route('/start_service/<service_name>', methods=['POST'])
def start_monitoring_service(service_name):
    """API endpoint to start a monitoring service"""
    valid_services = {
        "grafanamonitoring", 
        "ansiblemonitoring", 
        "cloudwatch_monitoring", 
        "eksmonitoring"
    }
    
    if service_name not in valid_services:
        logger.warning(f"Invalid service name requested: {service_name}")
        return jsonify({
            "success": False,
            "message": "Invalid service name"
        }), 400
    
    success, message = start_service(service_name)
    
    return jsonify({
        "success": success,
        "message": message,
        "redirect": f"/{service_name.replace('monitoring', '').rstrip('_')}" if success else None
    })

@app.route('/grafana')
def grafana_page():
    """Grafana monitoring setup page"""
    status = "running" if check_service_status("grafanamonitoring") else "stopped"
    return render_template('grafana.html', service_status=status)

@app.route('/ansible')
def ansible_page():
    """Ansible monitoring setup page"""
    status = "running" if check_service_status("ansiblemonitoring") else "stopped"
    return render_template('ansible.html', service_status=status)

@app.route('/cloudwatch')
def cloudwatch_page():
    """CloudWatch monitoring setup page"""
    status = "running" if check_service_status("cloudwatch_monitoring") else "stopped"
    return render_template('cloudwatch.html', service_status=status)

@app.route('/eks')
def eks_page():
    """EKS monitoring setup page"""
    status = "running" if check_service_status("eksmonitoring") else "stopped"
    return render_template('eks_setup.html', service_status=status)

@app.route('/service_status/<service_name>')
def service_status(service_name):
    """API endpoint to check service status"""
    valid_services = {
        "grafanamonitoring", 
        "ansiblemonitoring", 
        "cloudwatch_monitoring", 
        "eksmonitoring"
    }
    
    if service_name not in valid_services:
        return jsonify({"status": "unknown", "error": "Invalid service name"}), 400
    
    status = "running" if check_service_status(service_name) else "stopped"
    return jsonify({"status": status})

if __name__ == '__main__':
    server_ip = get_server_ip()
    logger.info(f"Starting application on {server_ip}")
    # For production, you would use a proper WSGI server
    # This is just for development or simple deployments
    app.run(host='0.0.0.0', port=8000, debug=False)