from flask import Flask, render_template, request, redirect, url_for, flash
import subprocess
import os
import yaml
import shutil

app = Flask(__name__)
app.secret_key = 'your_secret_key'

PROMETHEUS_CONFIG_PATH = '/etc/prometheus/prometheus.yml'
ALERT_RULES_FILE_PATH = '/etc/prometheus/alert.rules.yml'
ALERTMANAGER_CONFIG_PATH = "/etc/alertmanager/alertmanager.yml"
EMAIL_TEMPLATE_PATH = "/etc/alertmanager/templates/email.tmpl"

def install_prometheus():
    """Install Prometheus and handle the installation process."""
    try:
        # Run installation commands with output capture
        subprocess.run(["apt-get", "update"], check=True, capture_output=True, text=True)
        subprocess.run(["apt-get", "install", "-y", "prometheus"], check=True, capture_output=True, text=True)
        subprocess.run(["systemctl", "enable", "prometheus"], check=True, capture_output=True, text=True)
        subprocess.run(["systemctl", "start", "prometheus"], check=True, capture_output=True, text=True)
        
        # Verify installation
        status = subprocess.run(["systemctl", "is-active", "prometheus"], capture_output=True, text=True)
        if status.stdout.strip() == "active":
            return True, "Prometheus installed and started successfully!"
        else:
            return False, "Prometheus installed but service is not running."
    except subprocess.CalledProcessError as e:
        error_message = f"Installation error: {e.stderr}"
        return False, error_message
    except Exception as e:
        return False, f"Unexpected error: {str(e)}"

@app.route('/install_prometheus', methods=['GET', 'POST'])
def install_prometheus_route():
    if request.method == 'POST':
        print("Received POST request for Prometheus installation")  # Debug print
        
        success, message = install_prometheus()
        if success:
            flash(message, 'success')
            return redirect(url_for('index'))
        else:
            flash(message, 'error')
            return redirect(url_for('install_prometheus_route'))
            
    return render_template('install_prometheus.html')

def install_grafana():
    try:
        # Run Grafana installation script
        subprocess.run(["bash", "./scripts/install_grafana.sh"], check=True)
        flash('Grafana installed and started successfully!', 'success')
        return True
    except subprocess.CalledProcessError as e:
        flash(f'Error installing Grafana: {e}', 'error')
        return False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/install_grafana', methods=['GET', 'POST'])
def install_grafana_route():
    if request.method == 'POST':
        # Debug print to verify the route is being hit
        print("Received POST request for Grafana installation")
        
        try:
            # Run the Grafana installation script
            subprocess.run(["bash", "./scripts/install_grafana.sh"], check=True, capture_output=True, text=True)
            flash('Grafana installed and started successfully!', 'success')
            return redirect(url_for('install_grafana_route'))
        except subprocess.CalledProcessError as e:
            flash(f'Error installing Grafana: {e.stderr}', 'error')
            return redirect(url_for('install_grafana_route'))
        except Exception as e:
            flash(f'Unexpected error installing Grafana: {str(e)}', 'error')
            return redirect(url_for('install_grafana_route'))
    
    return render_template('install_grafana.html')

def install_node_exporter(remote_ip, username, key_file):
    """Install Node Exporter on a remote server."""
    try:
        subprocess.run(["ssh", "-i", key_file, f"{username}@{remote_ip}", "bash", "-s"], 
                       input=open("./scripts/install_node_exporter.sh").read(), text=True, check=True)
        flash('Node Exporter installed successfully!', 'success')
    except subprocess.CalledProcessError as e:
        flash(f'Error installing Node Exporter: {e}', 'error')

@app.route('/node_exporter')
def node_exporter():
    """Render the Node Exporter installation page."""
    return render_template('node_exporter.html')

@app.route('/install_node_exporter', methods=['POST'])
def install_node_exporter():
    try:
        server_ip = request.form['server_ip']  # Check if this is being accessed correctly
        username = request.form['username']
        key_pair = request.files['key_pair']
        
        # Save the uploaded key to a temporary location
        key_pair_path = f"/tmp/{key_pair.filename}"
        key_pair.save(key_pair_path)
        
        # Change permissions of the key file
        os.chmod(key_pair_path, 0o400)
        
        # Call your installation script with necessary parameters
        subprocess.run(["bash", "./scripts/install_node_exporter.sh", server_ip, username, key_pair_path], check=True)
        flash('Node Exporter installed successfully!', 'success')
    except KeyError as e:
        flash(f'Missing field: {e}', 'error')
    except subprocess.CalledProcessError as e:
        flash(f'Error installing Node Exporter: {e}', 'error')
    
    return redirect(url_for('index'))

def update_prometheus_config(targets):
    try:
        with open(PROMETHEUS_CONFIG_PATH, 'r') as f:
            config_lines = f.readlines()

        if not any('scrape_configs:' in line for line in config_lines):
            config_lines.append('scrape_configs:\n')

        for target in targets:
            job_name = target['job_name']
            target_ip_port = target['target']
            scrape_interval = target.get('scrape_interval', '15s')
            scrape_timeout = target.get('scrape_timeout', '10s')

            job_entry = f"""
  - job_name: '{job_name}'
    scrape_interval: {scrape_interval}
    scrape_timeout: {scrape_timeout}
    static_configs:
      - targets: ['{target_ip_port}']
"""
            config_lines.append(job_entry)

        with open(PROMETHEUS_CONFIG_PATH, 'w') as f:
            f.writelines(config_lines)

        subprocess.run(["systemctl", "restart", "prometheus"], check=True)
        subprocess.run(["systemctl", "restart", "grafana-server"], check=True)
        os.system("service alertmanager restart") # Check if this command is correct for your system
        flash('Prometheus configuration updated with new targets!', 'success')
    except Exception as e:
        flash(f'Error updating Prometheus configuration: {e}', 'error')



@app.route('/add_targets', methods=['GET', 'POST'])
def add_targets():
    if request.method == 'POST':
        targets = []
        for i in range(len(request.form) // 4):
            job_name = request.form.get(f'job_name_{i}')
            target = request.form.get(f'target_{i}')
            scrape_interval = request.form.get(f'scrape_interval_{i}', '15s')
            scrape_timeout = request.form.get(f'scrape_timeout_{i}', '10s')

            if job_name and target:
                targets.append({
                    'job_name': job_name,
                    'target': target,
                    'scrape_interval': scrape_interval,
                    'scrape_timeout': scrape_timeout
                })

        if targets:
            update_prometheus_config(targets)
        return redirect(url_for('index'))
    return render_template('add_targets.html')

def install_alertmanager():
    try:
        subprocess.run(["bash", "./scripts/alert.sh"], check=True)  # Script path correct?
        update_prometheus_for_alertmanager()
        flash("Alertmanager installed successfully!", "success")
    except subprocess.CalledProcessError as e:
        flash(f"Error installing Alertmanager: {e}", "error")

def update_prometheus_for_alertmanager():
    try:
        with open(PROMETHEUS_CONFIG_PATH, "r") as f:
            config_lines = f.readlines()

        if not any("rule_files:" in line for line in config_lines):
            config_lines.append("\nrule_files:\n")
            config_lines.append(f"  - {ALERT_RULES_FILE_PATH}\n")
        else:
            if not any(ALERT_RULES_FILE_PATH in line for line in config_lines):
                rule_files_index = next(i for i, line in enumerate(config_lines) if "rule_files:" in line)
                config_lines.insert(rule_files_index + 1, f"  - {ALERT_RULES_FILE_PATH}\n")

        with open(PROMETHEUS_CONFIG_PATH, "w") as f:
            f.writelines(config_lines)

        subprocess.run(["systemctl", "restart", "prometheus"], check=True)
        subprocess.run(["service", "alertmanager", "restart"], check=True) # Command correct?
        flash("Prometheus configuration updated with alert.rules.yml!", "success")
    except Exception as e:
        flash(f"Error updating Prometheus configuration for Alertmanager: {e}", "error")

@app.route('/alertmanager', methods=['GET', 'POST'])
def alertmanager():
    if request.method == 'POST':
        install_alertmanager()
        return redirect(url_for('index'))
    return render_template('alertmanager.html')


#... (apply_alert_rules function remains unchanged)
#... (EMAIL_TEMPLATE_CONTENT remains unchanged)

@app.route('/apply_alert_rules', methods=['POST'])
def apply_alert_rules():
    """
    Apply selected alert rules to the Alertmanager rules file and ensure Prometheus is configured.
    """
    selected_rules = request.form.getlist('alert_rules')
    
    # Get threshold values from form
    threshold_cpu = request.form.get('threshold_cpu', '90')  # Default to 90 if not provided
    threshold_disk = request.form.get('threshold_disk', '0.1')  # Default to 0.1 if not provided
    threshold_memory = request.form.get('threshold_memory', '80')  # Default to 80 if not provided

    # Define source and destination paths
    source_rules_path = './scripts/alert.rules.yml'
    destination_rules_path = '/etc/prometheus/alert.rules.yml'

    predefined_rules = {
        "High CPU Usage": {
            "name": "high_cpu_usage",
            "rules": [
                {
                    "alert": "HighCPUUsage",
                    "expr": f'100 - (avg by(instance) (rate(node_cpu_seconds_total{{mode="idle"}}[5m])) * 100) > {threshold_cpu}',
                    "for": "2m",
                    "labels": {"severity": "critical"},
                    "annotations": {
                        "summary": "High CPU usage detected",
                        "description": f"CPU usage on {{{{ $labels.instance }}}} is above {threshold_cpu}% for more than 2 minutes."
                    }
                }
            ]
        },
        "Low Disk Space": {
            "name": "low_disk_space",
            "rules": [
                {
                    "alert": "LowDiskSpace",
                    "expr": f'node_filesystem_free_bytes / node_filesystem_size_bytes < {threshold_disk}',
                    "for": "2m",
                    "labels": {"severity": "critical"},
                    "annotations": {
                        "summary": "Low disk space detected",
                        "description": f"Disk space on {{{{ $labels.instance }}}} is below {float(threshold_disk)*100}% for more than 2 minutes."
                    }
                }
            ]
        },
        "High Memory Usage": {
            "name": "high_memory_usage",
            "rules": [
                {
                    "alert": "HighMemoryUsage",
                    "expr": f'(node_memory_MemTotal - node_memory_MemAvailable) / node_memory_MemTotal * 100 > {threshold_memory}',
                    "for": "5m",
                    "labels": {"severity": "critical"},
                    "annotations": {
                        "summary": "High Memory Usage on {{ $labels.instance }}",
                        "description": f"Memory usage is above {threshold_memory}% for more than 5 minutes on instance {{{{ $labels.instance }}}}. Total memory: {{{{ $value }}}}."
                    }
                }
            ]
        },
        "Instance Down": {
            "name": "instance_status",
            "rules": [
                {
                    "alert": "InstanceDown",
                    "expr": 'up == 0',
                    "for": "1m",
                    "labels": {"severity": "critical"},
                    "annotations": {
                        "summary": "Instance is Down {{ $labels.instance }}",
                        "description": "{{ $labels.instance }} is Down."
                    }
                }
            ]
        },
        "High Network Traffic": {
            "name": "network_receive_bytes",
            "rules": [
                {
                    "alert": "HighNetworkTraffic",
                    "expr": "node_network_receive_bytes > 100e6",
                    "for": "5m",
                    "labels": {"severity": "warning"},
                    "annotations": {
                        "summary": "High network traffic on host {{ $labels.instance }}",
                        "description": "The inbound network traffic on host {{ $labels.instance }} has exceeded 100 MB/s for 5 minutes."
                    }
                }
            ]
        }
    }

    try:
        # Initialize alert rules structure
        alert_rules = {"groups": []}
        
        # Add selected rules to the configuration
        for rule_name in selected_rules:
            if rule_name in predefined_rules:
                rule_group = predefined_rules[rule_name]
                
                # Check if group already exists
                existing_group = next((group for group in alert_rules["groups"] 
                                    if group["name"] == rule_group["name"]), None)
                
                if existing_group:
                    existing_group["rules"].extend(rule_group["rules"])
                else:
                    alert_rules["groups"].append({
                        "name": rule_group["name"],
                        "rules": rule_group["rules"]
                    })

        # Write updated rules to source file
        with open(source_rules_path, "w") as f:
            yaml.dump(alert_rules, f, default_flow_style=False)

        # Copy to destination
        shutil.copy2(source_rules_path, destination_rules_path)
        
        # Update Prometheus configuration and restart services
        update_prometheus_for_alertmanager()
        subprocess.run(["systemctl", "restart", "alertmanager"], check=True)
        
        flash("Alert rules successfully updated and applied!", "success")
    except Exception as e:
        flash(f"Error applying alert rules: {str(e)}", "error")

    return redirect(url_for("alertmanager"))

EMAIL_TEMPLATE_CONTENT = """{{ define "email.alert" }}
<!DOCTYPE html>
<html>
<head>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f8f9fa;
            padding: 20px;
        }
        .header {
            background-color: #d9534f;
            color: white;
            padding: 10px;
            font-size: 20px;
            font-weight: bold;
            text-align: center;
            border-radius: 5px;
        }
        .alert {
            background-color: #ffffff;
            border: 1px solid #ddd;
            padding: 15px;
            margin-top: 20px;
            border-radius: 5px;
            box-shadow: 2px 2px 8px rgba(0, 0, 0, 0.1);
        }
        .alert-name {
            font-size: 18px;
            font-weight: bold;
            color: #d9534f;
        }
        .alert-details {
            margin-top: 10px;
            font-size: 14px;
        }
        .alert-details p {
            margin: 5px 0;
        }
        .footer {
            margin-top: 20px;
            font-size: 12px;
            text-align: center;
            color: #777;
        }
    </style>
</head>
<body>
    <div class="header">🚨 Alert: {{ (index .Alerts 0).Labels.alertname }} Detected! 🚨</div>
    {{ range .Alerts }}
    <div class="alert">
        <div class="alert-name">🔔 {{ .Labels.alertname }}</div>
        <div class="alert-details">
            <p><strong>Instance:</strong> {{ .Labels.instance }}</p>
            <p><strong>Severity:</strong> {{ .Labels.severity }}</p>

            {{ if .Labels.cpu }}
            <p><strong>CPU Usage:</strong> {{ .Value }}%</p>
            {{ end }}

            {{ if .Labels.memory }}
            <p><strong>Memory Usage:</strong> {{ .Value }}%</p>
            {{ end }}

            {{ if .Labels.disk }}
            <p><strong>Disk Space Used:</strong> {{ .Value }}%</p>
            {{ end }}

            {{ if .Labels.network }}
            <p><strong>Network Traffic:</strong> {{ .Value }} bytes/sec</p>
            {{ end }}

            <p><strong>Summary:</strong> {{ .Annotations.summary }}</p>
            <p><strong>Description:</strong> {{ .Annotations.description }}</p>
            <p><strong>Alert Source:</strong> <a href="{{ .GeneratorURL }}" target="_blank">View in Prometheus</a></p>
        </div>
    </div>
    {{ end }}
    <div class="footer">
        <p>This is an automated alert from Alertmanager. Please take necessary action.</p>
    </div>
</body>
</html>
{{ end }}"""


@app.route("/configure_alerting", methods=["GET", "POST"])
def configure_alerting():
    if request.method == "POST":
        email_from = request.form.get("email_from")
        email_to = request.form.get("email_to")
        smtp_server = request.form.get("smtp_server")
        smtp_auth_password = request.form.get("smtp_auth_password")

        slack_webhook = request.form.get("slack_webhook")
#... (Previous code)

        slack_channel = request.form.get("slack_channel")

        google_chat_webhook = request.form.get("google_chat_webhook")

        alertmanager_config = {"global": {}, "route": {}, "receivers":[]}
        if os.path.exists(ALERTMANAGER_CONFIG_PATH):
            with open(ALERTMANAGER_CONFIG_PATH, "r") as f:
                existing_config = yaml.safe_load(f)
                if existing_config:
                    alertmanager_config = existing_config

        alertmanager_config["global"] = {"resolve_timeout": "1m"}

        new_receivers = []

        if email_from and email_to and smtp_server and smtp_auth_password:
            email_config = {
                "name": "email_alerts",
                "email_configs": [
                    {
                        "to": email_to,
                        "from": email_from,
                        "smarthost": smtp_server,
                        "auth_username": email_from,
                        "auth_password": smtp_auth_password,
                        "html": "{{ template \"email.alert\". }}"
                    }
                ]
            }
            new_receivers.append(email_config)

            os.makedirs(os.path.dirname(EMAIL_TEMPLATE_PATH), exist_ok=True)
            with open(EMAIL_TEMPLATE_PATH, "w") as f:
                f.write(EMAIL_TEMPLATE_CONTENT)

        copy_alertmanager_config = False
        if slack_webhook and slack_channel:
            slack_config = {
                "name": "slack_alerts",
                "slack_configs": [
                    {
                        "channel": slack_channel,
                        "send_resolved": True
                    }
                ]
            }
            new_receivers.append(slack_config)

            source_config_path = "./scripts/alertmanager.yml"
            try:
                with open(source_config_path, "r") as f:
                    config_data = yaml.safe_load(f)

                config_data["global"]["slack_api_url"] = slack_webhook
                # Find the correct slack_configs and update the channel.  More robust.
                for receiver in config_data.get("receivers",):
                    if receiver.get("name") == "slack_alerts":
                        for slack_config in receiver.get("slack_configs",):
                            slack_config["channel"] = slack_channel
                            break # Found the channel, exit inner loop
                        break # Found the receiver, exit outer loop

                with open(source_config_path, "w") as f:
                    yaml.dump(config_data, f, default_flow_style=False)

                flash("Alertmanager template updated with Slack details!", "success")
                copy_alertmanager_config = True

            except Exception as e:
                flash(f"Error updating Alertmanager template: {str(e)}", "error")

        if google_chat_webhook:
            google_chat_config = {
                "name": "google_chat_alerts",
                "webhook_configs": [
                    {"url": google_chat_webhook}
                ]
            }
            new_receivers.append(google_chat_config)

        alertmanager_config["route"] = {
            "receiver": new_receivers[0]["name"] if new_receivers else "default",
            "group_by": ["alertname", "instance"],
            "routes": [{"receiver": receiver["name"]} for receiver in new_receivers]
        }

        alertmanager_config["receivers"] = new_receivers

        try:
            with open(ALERTMANAGER_CONFIG_PATH, "w") as f:
                yaml.dump(alertmanager_config, f, default_flow_style=False)
            update_template_for_alertmanager()
            if copy_alertmanager_config:
                destination_config_path = ALERTMANAGER_CONFIG_PATH
                try:
                    shutil.copy2(source_config_path, destination_config_path)
                    flash("Alertmanager config file copied successfully!", "success")
                except Exception as e:
                    flash(f"Error copying Alertmanager config file: {str(e)}", "error")
                

            subprocess.run(["systemctl", "restart", "alertmanager"], check=True)

            flash("Alerting channels configured successfully!", "success")
        except Exception as e:
            flash(f"Error configuring alerting: {str(e)}", "error")

        return redirect(url_for("configure_alerting"))

    return render_template("configure_alerting.html")


def update_template_for_alertmanager():
    try:
        with open(ALERTMANAGER_CONFIG_PATH, "r") as f:
            config_lines = f.readlines()

        if not any("templates:" in line for line in config_lines):
            config_lines.append("\ntemplates:\n")
            config_lines.append(f"  - {EMAIL_TEMPLATE_PATH}\n")
        else:
            if not any(EMAIL_TEMPLATE_PATH in line for line in config_lines): # Check for EMAIL_TEMPLATE_PATH
                templates_index = next(i for i, line in enumerate(config_lines) if "templates:" in line)
                config_lines.insert(templates_index + 1, f"  - {EMAIL_TEMPLATE_PATH}\n")

        with open(ALERTMANAGER_CONFIG_PATH, "w") as f:
            f.writelines(config_lines)

        subprocess.run(["systemctl", "restart", "prometheus"], check=True)
        subprocess.run(["service", "alertmanager", "restart"], check=True)
        flash("Alertmanager configuration updated with email template path!", "success") # Updated message
    except Exception as e:
        flash(f"Error updating Alertmanager configuration: {e}", "error")


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9000, debug=True)