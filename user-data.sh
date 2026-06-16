#!/bin/bash

# Update and install required packages
yum update -y
yum install -y python3 python3-pip git

# Install Python packages
pip3 install Flask pymysql boto3 werkzeug gunicorn

# Create application directory
mkdir -p /opt/app/templates
mkdir -p /opt/app/static/uploads
cd /opt/app

# Parse DB_HOST from the endpoint (removing port if present)
DB_ENDPOINT="${db_host}"
DB_HOST=$(echo $DB_ENDPOINT | cut -d':' -f1)

# --- Write the Python Flask Backend ---
cat << 'EOF' > app.py
import os
import uuid
import pymysql
import boto3
from flask import Flask, request, render_template, redirect, url_for, flash
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.secret_key = "super_secret_premium_key" # Required for flash messages

DB_HOST = os.environ.get('DB_HOST')
DB_USER = os.environ.get('DB_USER')
DB_PASS = os.environ.get('DB_PASS')
DB_NAME = os.environ.get('DB_NAME')
S3_BUCKET = os.environ.get('S3_BUCKET')
AWS_REGION = 'us-east-1'

s3_client = boto3.client('s3', region_name=AWS_REGION)

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )

def init_db():
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS gallery_posts (
                    id INT AUTO_INCREMENT PRIMARY KEY,
                    title VARCHAR(255) NOT NULL,
                    description TEXT,
                    s3_key VARCHAR(255) NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Error initializing DB: {e}")

init_db()

def get_presigned_url(s3_key):
    try:
        response = s3_client.generate_presigned_url('get_object',
                                                    Params={'Bucket': S3_BUCKET, 'Key': s3_key},
                                                    ExpiresIn=3600)
        return response
    except Exception as e:
        print(e)
        return None

@app.route('/', methods=['GET', 'POST'])
def index():
    if request.method == 'POST':
        title = request.form.get('title')
        description = request.form.get('description')
        file = request.files.get('image')

        if not file or file.filename == '':
            flash('No selected file', 'error')
            return redirect(request.url)

        if file:
            filename = secure_filename(file.filename)
            unique_filename = f"{uuid.uuid4()}_{filename}"
            
            # Upload to S3
            try:
                s3_client.upload_fileobj(
                    file, 
                    S3_BUCKET, 
                    unique_filename,
                    ExtraArgs={'ContentType': file.content_type}
                )
                
                # Save metadata to RDS
                conn = get_db_connection()
                with conn.cursor() as cursor:
                    sql = "INSERT INTO gallery_posts (title, description, s3_key) VALUES (%s, %s, %s)"
                    cursor.execute(sql, (title, description, unique_filename))
                conn.commit()
                conn.close()
                flash('Image uploaded successfully!', 'success')
            except Exception as e:
                flash(f'Error uploading image: {str(e)}', 'error')
            
            return redirect(url_for('index'))

    # GET request - fetch all posts
    posts = []
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM gallery_posts ORDER BY created_at DESC")
            posts = cursor.fetchall()
        conn.close()
        
        # Inject presigned URLs into posts
        for post in posts:
            post['image_url'] = get_presigned_url(post['s3_key'])
            
    except Exception as e:
        flash(f'Error connecting to database: {str(e)}', 'error')

    import socket
    instance_hostname = socket.gethostname()
    
    return render_template('index.html', posts=posts, hostname=instance_hostname)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
EOF

# --- Write the Frontend HTML/CSS Template ---
cat << 'EOF' > templates/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CloudGallery</title>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;600;800&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #0f172a;
            --text-color: #f8fafc;
            --card-bg: rgba(30, 41, 59, 0.7);
            --accent-color: #3b82f6;
            --accent-hover: #2563eb;
            --border-color: rgba(255, 255, 255, 0.1);
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: 'Inter', sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            min-height: 100vh;
            background-image: 
                radial-gradient(circle at 15% 50%, rgba(59, 130, 246, 0.15), transparent 25%),
                radial-gradient(circle at 85% 30%, rgba(139, 92, 246, 0.15), transparent 25%);
        }

        header {
            padding: 2rem;
            text-align: center;
            border-bottom: 1px solid var(--border-color);
            background: rgba(15, 23, 42, 0.8);
            backdrop-filter: blur(10px);
            position: sticky;
            top: 0;
            z-index: 10;
        }

        h1 {
            font-size: 2.5rem;
            font-weight: 800;
            background: linear-gradient(135deg, #60a5fa, #a78bfa);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            margin-bottom: 0.5rem;
        }

        .subtitle {
            color: #94a3b8;
            font-weight: 300;
            font-size: 0.9rem;
        }

        main {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
        }

        /* Upload Section */
        .upload-section {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 16px;
            padding: 2rem;
            margin-bottom: 3rem;
            backdrop-filter: blur(10px);
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            transition: transform 0.3s ease;
        }

        .upload-section:hover {
            transform: translateY(-2px);
        }

        .form-group {
            margin-bottom: 1.5rem;
        }

        label {
            display: block;
            margin-bottom: 0.5rem;
            font-weight: 600;
            color: #cbd5e1;
            font-size: 0.9rem;
        }

        input[type="text"], 
        textarea, 
        input[type="file"] {
            width: 100%;
            padding: 0.75rem 1rem;
            background: rgba(15, 23, 42, 0.6);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            color: white;
            font-family: inherit;
            transition: all 0.2s ease;
        }

        input[type="text"]:focus, 
        textarea:focus {
            outline: none;
            border-color: var(--accent-color);
            box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.2);
        }

        input[type="file"] {
            padding: 0.5rem;
        }

        input[type="file"]::file-selector-button {
            padding: 0.5rem 1rem;
            border-radius: 6px;
            background: #334155;
            border: none;
            color: white;
            cursor: pointer;
            transition: background 0.2s;
            margin-right: 1rem;
        }

        input[type="file"]::file-selector-button:hover {
            background: #475569;
        }

        button {
            background: var(--accent-color);
            color: white;
            border: none;
            padding: 0.75rem 2rem;
            border-radius: 8px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.2s ease;
            width: 100%;
            font-size: 1rem;
        }

        button:hover {
            background: var(--accent-hover);
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(59, 130, 246, 0.3);
        }

        /* Gallery Grid */
        .gallery-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
            gap: 2rem;
        }

        .card {
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 12px;
            overflow: hidden;
            backdrop-filter: blur(10px);
            transition: all 0.3s ease;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 30px rgba(0,0,0,0.3);
            border-color: rgba(255,255,255,0.2);
        }

        .card-image-wrapper {
            width: 100%;
            height: 250px;
            overflow: hidden;
            background: #0f172a;
        }

        .card-image {
            width: 100%;
            height: 100%;
            object-fit: cover;
            transition: transform 0.5s ease;
        }

        .card:hover .card-image {
            transform: scale(1.05);
        }

        .card-content {
            padding: 1.5rem;
        }

        .card-title {
            font-size: 1.25rem;
            font-weight: 600;
            margin-bottom: 0.5rem;
        }

        .card-desc {
            color: #94a3b8;
            font-size: 0.9rem;
            line-height: 1.5;
            margin-bottom: 1rem;
        }

        .card-meta {
            font-size: 0.8rem;
            color: #64748b;
            border-top: 1px solid rgba(255,255,255,0.05);
            padding-top: 1rem;
        }

        /* Flashes */
        .flash {
            padding: 1rem;
            border-radius: 8px;
            margin-bottom: 1.5rem;
            text-align: center;
        }
        .flash.success { background: rgba(16, 185, 129, 0.1); border: 1px solid #10b981; color: #10b981; }
        .flash.error { background: rgba(239, 68, 68, 0.1); border: 1px solid #ef4444; color: #ef4444; }
        
        .empty-state {
            text-align: center;
            padding: 4rem 0;
            color: #64748b;
            grid-column: 1 / -1;
        }
    </style>
</head>
<body>

    <header>
        <h1>CloudGallery</h1>
        <p class="subtitle">Served by EC2 Instance: {{ hostname }}</p>
    </header>

    <main>
        {% with messages = get_flashed_messages(with_categories=true) %}
            {% if messages %}
                {% for category, message in messages %}
                    <div class="flash {{ category }}">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}

        <section class="upload-section">
            <h2 style="margin-bottom: 1.5rem; font-size: 1.2rem; color: #cbd5e1;">Share a new memory</h2>
            <form action="/" method="POST" enctype="multipart/form-data">
                <div class="form-group">
                    <label for="title">Title</label>
                    <input type="text" id="title" name="title" required placeholder="A beautiful sunset...">
                </div>
                <div class="form-group">
                    <label for="description">Description</label>
                    <textarea id="description" name="description" rows="3" placeholder="Tell us more about this picture..."></textarea>
                </div>
                <div class="form-group">
                    <label for="image">Choose Image</label>
                    <input type="file" id="image" name="image" accept="image/*" required>
                </div>
                <button type="submit">Upload to AWS</button>
            </form>
        </section>

        <section class="gallery-grid">
            {% if posts %}
                {% for post in posts %}
                <div class="card">
                    <div class="card-image-wrapper">
                        {% if post.image_url %}
                            <img src="{{ post.image_url }}" alt="{{ post.title }}" class="card-image" loading="lazy">
                        {% else %}
                            <div style="height: 100%; display: flex; align-items: center; justify-content: center; color: #ef4444;">Image unavailable</div>
                        {% endif %}
                    </div>
                    <div class="card-content">
                        <h3 class="card-title">{{ post.title }}</h3>
                        <p class="card-desc">{{ post.description }}</p>
                        <p class="card-meta">Uploaded on {{ post.created_at.strftime('%Y-%m-%d %H:%M') }}</p>
                    </div>
                </div>
                {% endfor %}
            {% else %}
                <div class="empty-state">
                    <h3>No images uploaded yet.</h3>
                    <p>Be the first to share something!</p>
                </div>
            {% endif %}
        </section>
    </main>

</body>
</html>
EOF

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
ExecStart=/usr/local/bin/gunicorn -w 4 -b 0.0.0.0:80 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

GUNICORN_BIN=$(which gunicorn)
sed -i "s|/usr/local/bin/gunicorn|$GUNICORN_BIN|g" /etc/systemd/system/flaskapp.service

systemctl daemon-reload
systemctl enable flaskapp
systemctl restart flaskapp
systemctl start flaskapp
