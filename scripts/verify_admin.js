// Verify admin user email and set role
db = db.getSiblingDB('auth_db');

// Update admin user
const result = db.users.updateOne(
  { email: 'admin@example.com' },
  { 
    $set: { 
      emailVerified: true,
      role: 'admin'
    } 
  }
);

print('Update result:', JSON.stringify(result));

// Show the updated user
const user = db.users.findOne({ email: 'admin@example.com' });
print('Admin user:', JSON.stringify({ 
  username: user.username, 
  email: user.email, 
  emailVerified: user.emailVerified, 
  role: user.role 
}));
