from flask import Flask, render_template, request, jsonify, Response
import subprocess
from pathlib import Path
import os
import time
import json

app = Flask(__name__)
VARIABLES_FILE = "variables.sh"
GKE_VARIABLES_FILE = "gke-variables.sh"
SETUP_SCRIPT = "monitoring_setup.sh"
# GKE_SETUP_SCRIPT = "gke_monitoring_setup.sh"
GKE_SETUP_SCRIPT="test.sh"
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
                    file.write(f'{key}="{updated_vars[key]}"\n')  # Write updated value
                else:
                    file.write(line)  # Keep existing line if not updated
            else:
                file.write(line)  # Keep comments and empty lines

def run_setup(script_file):
    try:
        script_path = Path(script_file)
        
        # Check if script exists
        if not script_path.exists():
            return {
                "success": False,
                "message": f"❌ Script not found: {script_file}"
            }

        # Make script executable
        script_path.chmod(0o755)
        
        # Execute the script
        result = subprocess.run(
            [str(script_path.absolute())],
            check=True,
            capture_output=True,
            text=True
        )
        
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

@app.route("/deploy", methods=["POST"])
def deploy():
    global deployment_progress
    try:
        deployment_progress = {"progress": 0, "status": "Initializing deployment..."}
        
        # Update variables
        deployment_progress = {"progress": 20, "status": "Updating configuration..."}
        updated_vars = {key: request.form[key] for key in request.form}
        write_variables(updated_vars, VARIABLES_FILE)

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

if __name__ == "__main__":
    app.run(host='0.0.0.0', port=7000, debug=True)