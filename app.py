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

@app.route('/generate-presigned-url', methods=['GET'])
def generate_presigned_url():
    filename = request.args.get('filename')
    content_type = request.args.get('content_type')
    if not filename:
        return {"error": "Filename is required"}, 400
    
    unique_filename = f"{uuid.uuid4()}_{secure_filename(filename)}"
    try:
        presigned_post = s3_client.generate_presigned_post(
            Bucket=S3_BUCKET,
            Key=unique_filename,
            Fields={"Content-Type": content_type},
            Conditions=[{"Content-Type": content_type}],
            ExpiresIn=3600
        )
        return {"presigned_post": presigned_post, "unique_filename": unique_filename}
    except Exception as e:
        return {"error": str(e)}, 500

@app.route('/confirm-upload', methods=['POST'])
def confirm_upload():
    data = request.json
    title = data.get('title')
    description = data.get('description')
    s3_key = data.get('s3_key')

    if not all([title, s3_key]):
        return {"error": "Missing required fields"}, 400

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            sql = "INSERT INTO gallery_posts (title, description, s3_key) VALUES (%s, %s, %s)"
            cursor.execute(sql, (title, description, s3_key))
        conn.commit()
        conn.close()
        return {"message": "Success"}
    except Exception as e:
        return {"error": str(e)}, 500

@app.route('/delete/<int:post_id>', methods=['POST'])
def delete(post_id):
    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT s3_key FROM gallery_posts WHERE id = %s", (post_id,))
            post = cursor.fetchone()
            if post:
                s3_client.delete_object(Bucket=S3_BUCKET, Key=post['s3_key'])
                cursor.execute("DELETE FROM gallery_posts WHERE id = %s", (post_id,))
                conn.commit()
                flash('Image deleted successfully!', 'success')
            else:
                flash('Image not found.', 'error')
        conn.close()
    except Exception as e:
        flash(f'Error deleting image: {str(e)}', 'error')
    return redirect(url_for('index'), code=303)

@app.route('/', methods=['GET'])
def index():
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
