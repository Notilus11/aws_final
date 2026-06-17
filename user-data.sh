#!/bin/bash

# Update and install required packages
yum update -y
yum install -y python3 python3-pip git nginx

# Install Python packages
pip3 install Flask pymysql boto3 werkzeug gunicorn

# Create application directory
mkdir -p /opt/app/templates
mkdir -p /opt/app/static/uploads
cd /opt/app

# Parse DB_HOST from the endpoint (removing port if present)
DB_ENDPOINT="${db_host}"
DB_HOST=$(echo $DB_ENDPOINT | cut -d':' -f1)

# --- Fetch the App Code from S3 ---
# Use Python with boto3 to download from S3 securely using the EC2 instance role
python3 -c "import boto3; s3 = boto3.client('s3'); s3.download_file('${s3_bucket}', 'app.py', 'app.py')"
python3 -c "import boto3; s3 = boto3.client('s3'); s3.download_file('${s3_bucket}', 'index.html', 'templates/index.html')"

# --- Configure and start the Systemd Service ---

cat << EOF > /etc/sysconfig/flaskapp
DB_HOST=$DB_HOST
DB_USER=${db_user}
DB_PASS=${db_pass}
DB_NAME=${db_name}
S3_BUCKET=${s3_bucket}
EOF

cat << 'EOF' > /etc/systemd/system/flaskapp.service
[Unit]
Description=CloudGallery Flask App
After=network.target

[Service]
EnvironmentFile=/etc/sysconfig/flaskapp
User=root
WorkingDirectory=/opt/app
ExecStart=/usr/local/bin/gunicorn -w 4 --timeout 120 -b 127.0.0.1:8000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

GUNICORN_BIN=$(which gunicorn)
sed -i "s|/usr/local/bin/gunicorn|$GUNICORN_BIN|g" /etc/systemd/system/flaskapp.service

cat << 'EOF' > /etc/nginx/conf.d/flask.conf
server {
    listen 80;
    server_name _;

    client_max_body_size 50M;
    proxy_read_timeout 120s;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
    }

    location = /favicon.ico {
        access_log off; 
        log_not_found off; 
        return 204;
    }
}
EOF

systemctl daemon-reload
systemctl enable flaskapp
systemctl restart flaskapp
systemctl start flaskapp

systemctl enable nginx
systemctl restart nginx
