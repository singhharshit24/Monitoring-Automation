from flask import Flask, render_template, request, jsonify
import subprocess
import os

app = Flask(__name__)
VARIABLES_FILE = "variables.sh"
GKE_VARIABLES_FILE = "gke-variables.sh"
SETUP_SCRIPT = "monitoring_setup.sh"
GKE_SETUP_SCRIPT = "gke_monitoring_setup.sh"

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
        # Get absolute path
        script_path = os.path.abspath(script_file)

        # Ensure script exists
        if not os.path.exists(script_path):
            return {"message": f"❌ Error: Script not found at {script_path}"}, 500

        # Make sure the script is executable
        os.chmod(script_path, 0o755)

        # Run script and print output in real-time
        process = subprocess.Popen(
            [script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        # Read and print output live
        output_lines = []
        for line in iter(process.stdout.readline, ""):
            print(line, end="")  # Print to terminal
            output_lines.append(line.strip())  # Store for API response

        # Wait for process to complete
        process.wait()

        if process.returncode != 0:
            return {"message": f"❌ Deployment failed: {process.stderr.read()}"}, 500

        return {"message": "✅ Deployment successful!", "output": output_lines}

    except Exception as e:
        return {"message": f"❌ Unexpected error: {str(e)}"}, 500

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

@app.route("/deploy", methods=["POST"])
def deploy():
    """Update variables and execute the monitoring-setup.sh script."""
    try:
        updated_vars = {key: request.form[key] for key in request.form}
        write_variables(updated_vars, VARIABLES_FILE)  # Ensure this writes correctly

        return jsonify(run_setup(f"./{SETUP_SCRIPT}"))
    except Exception as e:
        return jsonify({"message": f"❌ Failed to update configuration: {str(e)}"}), 500

@app.route("/gke-deploy", methods=["POST"])
def gke_deploy():
    """Update variables and execute the gke-monitoring-setup.sh script."""
    try:
        updated_vars = {key: request.form[key] for key in request.form}
        write_variables(updated_vars, GKE_VARIABLES_FILE)  # Ensure this writes correctly

        return jsonify(run_setup(f"./{GKE_SETUP_SCRIPT}"))
    except Exception as e:
        return jsonify({"message": f"❌ Failed to update configuration: {str(e)}"}), 500

if __name__ == "__main__":
    app.run(debug=True)