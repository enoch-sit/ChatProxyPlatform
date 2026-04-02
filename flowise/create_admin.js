const bcrypt = require('bcryptjs');
const { Client } = require('pg');

const email = process.env.FLOWISE_ADMIN_EMAIL;
const password = process.env.FLOWISE_ADMIN_PASSWORD;
const name = process.env.FLOWISE_ADMIN_NAME || 'Admin User';

// Database connection config
const client = new Client({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5433'),
  database: process.env.DB_NAME || 'flowise',
  user: process.env.DB_USER || 'flowiseuser',
  password: process.env.DB_PASSWORD
});

async function createAdmin() {
  try {
    await client.connect();
    console.log('Connected to database');

    // Hash the password
    const hashedPassword = await bcrypt.hash(password, 10);
    console.log('Password hashed');

    // Insert the user
    const query = `
      INSERT INTO public.user (name, email, credential, status, "createdDate", "updatedDate")
      VALUES ($1, $2, $3, $4, NOW(), NOW())
      RETURNING id, email, name, status;
    `;

    const result = await client.query(query, [name, email, hashedPassword, 'active']);
    
    console.log('Admin user created successfully:');
    console.log(result.rows[0]);

  } catch (error) {
    console.error('Error creating admin user:', error.message);
  } finally {
    await client.end();
  }
}

createAdmin();
