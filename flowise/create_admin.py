import os
import bcrypt
import psycopg2
from datetime import datetime

# User details — load from environment variables, never hardcode
email = os.environ['FLOWISE_ADMIN_EMAIL']
password = os.environ['FLOWISE_ADMIN_PASSWORD']
name = os.environ.get('FLOWISE_ADMIN_NAME', 'Admin User')

# Hash the password
password_bytes = password.encode('utf-8')
salt = bcrypt.gensalt(rounds=10)
hashed = bcrypt.hashpw(password_bytes, salt)
hashed_str = hashed.decode('utf-8')

print(f"Password hashed: {hashed_str}")

# Database connection
try:
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),
        port=int(os.environ.get('DB_PORT', '5433')),
        database=os.environ.get('DB_NAME', 'flowise'),
        user=os.environ.get('DB_USER', 'flowiseuser'),
        password=os.environ['DB_PASSWORD']
    )
    
    cur = conn.cursor()
    
    # Insert the user
    query = """
        INSERT INTO public.user (name, email, credential, status, "createdDate", "updatedDate")
        VALUES (%s, %s, %s, %s, NOW(), NOW())
        RETURNING id, email, name, status;
    """
    
    cur.execute(query, (name, email, hashed_str, 'active'))
    result = cur.fetchone()
    
    conn.commit()
    
    print(f"\nAdmin user created successfully:")
    print(f"ID: {result[0]}")
    print(f"Email: {result[1]}")
    print(f"Name: {result[2]}")
    print(f"Status: {result[3]}")
    
    cur.close()
    conn.close()
    
except Exception as e:
    print(f"Error: {e}")
