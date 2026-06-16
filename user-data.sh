#!/bin/bash

# Update and install required packages
yum update -y
yum install -y python3 python3-pip git

# Install Python packages
pip3 install Flask pymysql boto3

# Create application directory
mkdir -p /opt/app
cd /opt/app

# Note: The db_host provided by Terraform includes the port (endpoint:port).
# We strip the port for pymysql if needed, but pymysql can take host and port separately.
# AWS RDS endpoint format is generally: <instance-id>.<region>.rds.amazonaws.com:3306
DB_ENDPOINT="${db_host}"
DB_HOST=$(echo $DB_ENDPOINT | cut -d':' -f1)

# Write the Flask application
cat << 'EOF' > app.py
from flask import Flask, request
import pymysql
import boto3
import os
import socket

app = Flask(__name__)

DB_HOST = os.environ.get('DB_HOST')
DB_USER = os.environ.get('DB_USER')
DB_PASS = os.environ.get('DB_PASS')
DB_NAME = os.environ.get('DB_NAME')
S3_BUCKET = os.environ.get('S3_BUCKET')

# Initialize DB connection and create table
def init_db():
    try:
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS hits (
                id INT AUTO_INCREMENT PRIMARY KEY,
                ip_address VARCHAR(255),
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error connecting to DB: {e}")

init_db()

@app.route('/')
def hello():
    client_ip = request.remote_addr
    hostname = socket.gethostname()
    
    # Insert hit into RDS
    hit_count = 0
    try:
        conn = pymysql.connect(host=DB_HOST, user=DB_USER, password=DB_PASS, database=DB_NAME)
        cursor = conn.cursor()
        cursor.execute("INSERT INTO hits (ip_address) VALUES (%s)", (client_ip,))
        conn.commit()
        
        cursor.execute("SELECT COUNT(*) FROM hits")
        hit_count = cursor.fetchone()[0]
        conn.close()
    except Exception as e:
        print(f"Error accessing DB: {e}")

    # Write a simple file to S3
    s3_status = "Skipped"
    try:
        s3 = boto3.client('s3', region_name='us-east-1') # region should match your AWS region
        s3.put_object(Bucket=S3_BUCKET, Key=f"hit_{hit_count}.txt", Body=f"Hit from {client_ip}")
        s3_status = f"Successfully wrote to {S3_BUCKET}"
    except Exception as e:
        s3_status = f"S3 Error: {e}"

    html = f"""
    <html>
        <head>
            <title>AWS Final Project</title>
            <style>
                body {{ font-family: Arial; padding: 50px; text-align: center; background-color: #f4f4f9; }}
                .box {{ background: white; padding: 20px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); display: inline-block; }}
                h1 {{ color: #333; }}
                p {{ font-size: 1.2em; color: #666; }}
                .highlight {{ color: #0073e6; font-weight: bold; }}
            </style>
        </head>
        <body>
            <div class="box">
                <h1>High Availability Web Service</h1>
                <p>Hello from instance: <span class="highlight">{hostname}</span></p>
                <p>You are visitor number: <span class="highlight">{hit_count}</span> (Data from RDS)</p>
                <p>S3 Integration Status: <span class="highlight">{s3_status}</span></p>
            </div>
        </body>
    </html>
    """
    return html

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

# Set environment variables for the Flask app (Systemd service needs them)
cat << EOF > /etc/sysconfig/flaskapp
DB_HOST=$DB_HOST
DB_USER=${db_user}
DB_PASS=${db_pass}
DB_NAME=${db_name}
S3_BUCKET=${s3_bucket}
EOF

# Create a systemd service file to run the Flask app on port 80
cat << 'EOF' > /etc/systemd/system/flaskapp.service
[Unit]
Description=Flask App Web Service
After=network.target

[Service]
EnvironmentFile=/etc/sysconfig/flaskapp
User=root
WorkingDirectory=/opt/app
ExecStart=/usr/local/bin/flask run --host=0.0.0.0 --port=80
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# For AL2023, the Flask executable path might be /usr/local/bin/flask or /usr/bin/flask
# If pip3 installs it to /usr/local/bin, we use that. Let's make sure we find it.
FLASK_BIN=$(which flask)
sed -i "s|/usr/local/bin/flask|$FLASK_BIN|g" /etc/systemd/system/flaskapp.service

# Reload systemd, enable and start the app
systemctl daemon-reload
systemctl enable flaskapp
systemctl start flaskapp
