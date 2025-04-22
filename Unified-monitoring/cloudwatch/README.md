# AWS Monitoring Tool

This tool automates the setup of CloudWatch monitoring and alerting for EC2 instances.

## Prerequisites

*   Python 3.x
*   Flask, boto3 libraries (`pip install Flask boto3`)
*   Terraform
*   AWS Credentials (configured as described in the code)

## Usage

1.  Clone the repository.
2.  Navigate to the `backend` directory and run `python app.py`.
3.  Navigate to the `frontend` directory and serve the `index.html` file (e.g., `python -m http.server`).
4.  Open the web page in your browser and follow the instructions.