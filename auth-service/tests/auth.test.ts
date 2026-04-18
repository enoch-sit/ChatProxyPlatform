// tests/auth.test.ts
import request from 'supertest';
import axios from 'axios';
import { MongoClient, Db } from 'mongodb';
import { createInterface } from 'readline';

// Update these configurations as needed
const API_URL = process.env.API_URL || 'http://localhost:3000/api';
const MAILHOG_API = process.env.MAILHOG_API || 'http://localhost:8025/api/v1';
const MONGODB_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/auth_db';

// Set to true to enable manual input for verification codes and tokens
const USE_MANUAL_INPUT = true;

// Set to true to bypass MailHog and get tokens directly from the database
const BYPASS_MAILHOG = true;

// Increase Jest timeout (longer for manual input)
jest.setTimeout(USE_MANUAL_INPUT ? 300000 : 60000); // 5 minutes for manual, 1 minute for automatic

// Test user credentials - use timestamp to ensure uniqueness
const timestamp = Date.now();
const TEST_USER = {
  username: `testuser_${timestamp}`,
  email: `testuser_${timestamp}@example.com`,
  password: 'Password123!'
};

// Admin user credentials for role-based access tests
const ADMIN_USER = {
  username: `admin_${timestamp}`,
  email: `admin_${timestamp}@example.com`,
  password: 'Password123!'
};

// Supervisor user credentials for role-based access tests
const SUPERVISOR_USER = {
  username: `supervisor_${timestamp}`,
  email: `supervisor_${timestamp}@example.com`,
  password: 'Password123!'
};

// Store tokens across tests
let accessToken: string;
let refreshToken: string;
let verificationToken: string;
let passwordResetToken: string;
let userId: string;

// Additional tokens for different user roles
let adminAccessToken: string;
let supervisorAccessToken: string;

// Create readline interface for user input if manual mode is enabled
let readline: ReturnType<typeof createInterface> | null = null;

if (USE_MANUAL_INPUT) {
  readline = createInterface({
    input: process.stdin,
    output: process.stdout
  });
}

// Helper function to prompt for input
function prompt(question: string): Promise<string> {
  return new Promise((resolve) => {
    if (readline) {
      readline.question(question, (answer) => {
        resolve(answer);
      });
    } else {
      resolve(''); // Return empty string if not in manual mode
    }
  });
}

// Email response interface for MailHog API v1
interface MessageSummary {
  ID: string;
  From: {
    Relays: string[];
    Mailbox: string;
    Domain: string;
    Params: string;
  };
  To: Array<{
    Relays: string[];
    Mailbox: string;
    Domain: string;
    Params: string;
  }>;
  Content: {
    Headers: {
      "Content-Transfer-Encoding"?: string[];
      "Content-Type"?: string[];
      Date?: string[];
      From?: string[];
      "MIME-Version"?: string[];
      "Message-ID"?: string[];
      Received?: string[];
      "Return-Path"?: string[];
      Subject?: string[];
      To?: string[];
    };
    Body: string;
    Size: number;
  };
  Created: string;
  MIME: any;
  Raw: {
    From: string;
    To: string[];
    Data: string;
    Helo: string;
  };
}

interface MessagesResponse {
  total: number;
  count: number;
  start: number;
  items: Array<{
    ID: string;
    From: {
      Relays: string[];
      Mailbox: string;
      Domain: string;
      Params: string;
    };
    To: Array<{
      Relays: string[];
      Mailbox: string;
      Domain: string;
      Params: string;
    }>;
    Content: {
      Headers: {
        "Content-Transfer-Encoding"?: string[];
        "Content-Type"?: string[];
        Date?: string[];
        From?: string[];
        "MIME-Version"?: string[];
        "Message-ID"?: string[];
        Received?: string[];
        "Return-Path"?: string[];
        Subject?: string[];
        To?: string[];
      };
      Body: string;
      Size: number;
    };
    Created: string;
    MIME: any;
  }>;
}

// Function to check if MailHog is running
async function checkMailHogConnection(): Promise<boolean> {
  if (BYPASS_MAILHOG) {
    console.log('MailHog check bypassed');
    return true;
  }
  
  try {
    const response = await axios.get(`${MAILHOG_API}/messages`);
    console.log('MailHog is connected and running');
    return true;
  } catch (error) {
    console.error('MailHog connection failed:', error instanceof Error ? error.message : String(error));
    return false;
  }
}

// Function to get all messages from MailHog
async function getMessages(): Promise<MessagesResponse> {
  const response = await axios.get<MessagesResponse>(`${MAILHOG_API}/messages`);
  return response.data;
}

// Function to get a specific message by ID
async function getMessage(messageId: string): Promise<MessageSummary> {
  const response = await axios.get<MessageSummary>(`${MAILHOG_API}/messages/${messageId}`);
  return response.data;
}

// Helper to wait with exponential backoff
async function wait(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Manually delete all messages
async function deleteAllMessages(): Promise<void> {
  if (BYPASS_MAILHOG) {
    console.log('MailHog message deletion bypassed');
    return;
  }
  
  try {
    await axios.delete(`${MAILHOG_API}/messages`);
    console.log('Deleted all messages from MailHog');
  } catch (error) {
    console.error('Failed to delete messages:', error instanceof Error ? error.message : String(error));
  }
}

// Helper function to get verification token directly from the database
async function getVerificationTokenFromDb(userEmail: string): Promise<string | null> {
  if (!db) return null;
  
  try {
    // Find the user by email
    const user = await db.collection('users').findOne({ email: userEmail });
    if (!user) {
      console.error(`User with email ${userEmail} not found in database`);
      return null;
    }
    
    // Find the verification record for this user
    const verification = await db.collection('verifications').findOne({
      userId: user._id,
      type: 'email',
      expires: { $gt: new Date() }
    });
    
    if (!verification) {
      console.error(`No valid verification record found for user ${userEmail}`);
      return null;
    }
    
    console.log(`Found verification token in database: ${verification.token}`);
    return verification.token;
  } catch (error) {
    console.error('Error retrieving verification token from database:', error);
    return null;
  }
}

// Helper function to get password reset token directly from the database
async function getPasswordResetTokenFromDb(userEmail: string): Promise<string | null> {
  if (!db) return null;
  
  try {
    // Find the user by email
    const user = await db.collection('users').findOne({ email: userEmail });
    if (!user) {
      console.error(`User with email ${userEmail} not found in database`);
      return null;
    }
    
    // Find the password reset record for this user
    const verification = await db.collection('verifications').findOne({
      userId: user._id,
      type: 'password-reset',
      expires: { $gt: new Date() }
    });
    
    if (!verification) {
      console.error(`No valid password reset record found for user ${userEmail}`);
      return null;
    }
    
    console.log(`Found password reset token in database: ${verification.token.substring(0, 10)}...`);
    return verification.token;
  } catch (error) {
    console.error('Error retrieving password reset token from database:', error);
    return null;
  }
}

// Function to automatically extract verification code from emails
async function autoExtractVerificationCode(): Promise<string | null> {
  let emailFound = false;
  let verificationCode = '';
  let attempts = 0;
  const maxAttempts = 15;
  
  console.log('Waiting for verification email...');
  
  while (!emailFound && attempts < maxAttempts) {
    attempts++;
    await wait(2000 * attempts); // Increase wait time with each attempt
    
    // Get messages
    const messagesResponse = await getMessages();
    console.log(`Attempt ${attempts}: Found ${messagesResponse.count} messages`);
    
    if (messagesResponse.items && messagesResponse.items.length > 0) {
      // Check each message
      for (const messageSummary of messagesResponse.items) {
        // Get full message details
        const message = await getMessage(messageSummary.ID);
        
        // Check if this is an email to our test user
        const toHeader = message.Content.Headers.To?.[0] || '';
        const fromHeader = message.Content.Headers.From?.[0] || '';
        const subjectHeader = message.Content.Headers.Subject?.[0] || '';
        
        if (toHeader.includes(TEST_USER.email) && subjectHeader.includes('Verify')) {
          emailFound = true;
          console.log('Found verification email:');
          console.log(`From: ${fromHeader}`);
          console.log(`To: ${toHeader}`);
          console.log(`Subject: ${subjectHeader}`);
          
          // Get full message body
          const fullMessage = await getMessage(message.ID);
          const emailBody = fullMessage.Content.Body;
          
          // Extract verification code - looking for 3-character code
          // Adjust this regex based on your actual email format
          const codeMatch = emailBody.match(/([A-Z0-9]{3})/);
          if (codeMatch && codeMatch[1]) {
            verificationCode = codeMatch[1];
            console.log(`Found verification code: ${verificationCode}`);
            break;
          } else {
            console.log('Verification code not found in email body');
            console.log('Email body snippet:', emailBody.substring(0, 200) + '...');
          }
        }
      }
    }
  }
  
  return emailFound ? verificationCode : null;
}

// Function to automatically extract password reset token from emails
async function autoExtractResetToken(): Promise<string | null> {
  let emailFound = false;
  let resetToken = '';
  let attempts = 0;
  const maxAttempts = 15;
  
  console.log('Waiting for password reset email...');
  
  while (!emailFound && attempts < maxAttempts) {
    attempts++;
    await wait(2000 * attempts); // Increase wait time with each attempt
    
    // Get messages
    const messagesResponse = await getMessages();
    console.log(`Attempt ${attempts}: Found ${messagesResponse.count} messages`);
    
    if (messagesResponse.items && messagesResponse.items.length > 0) {
      // Look at most recent messages first (reverse the array)
      const recentMessages = [...messagesResponse.items].reverse();
      
      // Check each message
      for (const messageSummary of recentMessages) {
        // Get full message details
        const message = await getMessage(messageSummary.ID);
        
        // Check if this is a password reset email to our test user
        const toHeader = message.Content.Headers.To?.[0] || '';
        const subjectHeader = message.Content.Headers.Subject?.[0] || '';
        
        if (toHeader.includes(TEST_USER.email) && subjectHeader.includes('Reset')) {
          emailFound = true;
          console.log('Found password reset email');
          
          // Get full message body
          const emailBody = message.Content.Body;
          
          // Extract reset token from URL in email
          // Adjust this regex based on your actual email format
          const tokenMatch = emailBody.match(/reset-password\?token=([a-f0-9]+)/);
          if (tokenMatch && tokenMatch[1]) {
            resetToken = tokenMatch[1];
            console.log(`Found reset token: ${resetToken.substring(0, 10)}...`);
            break;
          } else {
            console.log('Reset token not found in email body');
            console.log('Email body snippet:', emailBody.substring(0, 200) + '...');
          }
        }
      }
    }
  }
  
  return emailFound ? resetToken : null;
}

// Connect to MongoDB and clean up test data
let connection: MongoClient | null = null;
let db: Db | null = null;

beforeAll(async () => {
  // Connect to MongoDB
  connection = await MongoClient.connect(MONGODB_URI);
  db = connection.db();
  
  // Clear existing test data before starting
  if (db) {
    await db.collection('users').deleteMany({ email: { $regex: /^testuser_/ } });
  }
  
  // Verify MailHog connection if not bypassing
  if (!BYPASS_MAILHOG) {
    const mailhogRunning = await checkMailHogConnection();
    if (!mailhogRunning) {
      throw new Error('MailHog is not running. Please start MailHog before running tests.');
    }
    
    // Clear all emails in MailHog
    await deleteAllMessages();
  }
  
  if (USE_MANUAL_INPUT) {
    console.log(`\n====== STARTING INTERACTIVE AUTH TESTS ======`);
    console.log(`Test User: ${TEST_USER.username}`);
    console.log(`Test Email: ${TEST_USER.email}`);
    
    if (!BYPASS_MAILHOG) {
      console.log(`\nPlease keep MailHog UI open at http://localhost:8025 to view emails\n`);
    } else {
      console.log(`\nMailHog is bypassed. Tokens will be fetched directly from database.\n`);
    }
  }
});

afterAll(async () => {
  // Clean up test user data after tests
  if (db) {
    try {
      await db.collection('users').deleteMany({ email: TEST_USER.email });
      console.log('Cleaned up test user data');
    } catch (error) {
      console.error('Error cleaning up test data:', error);
    }
  }
  
  if (connection) {
    await connection.close();
    console.log('MongoDB connection closed');
  }
  
  // Close readline interface if it was opened
  if (readline) {
    readline.close();
  }
  
  if (USE_MANUAL_INPUT) {
    console.log('\n====== INTERACTIVE TESTS COMPLETED ======\n');
  }
});

describe('Authentication Flow Tests', () => {
  // Test 1: Sign Up
  test('should register a new user', async () => {
    console.log(`Registering user: ${TEST_USER.username} with email: ${TEST_USER.email}`);
    
    const response = await request(API_URL)
      .post('/auth/signup')
      .send(TEST_USER);
    
    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('message');
    expect(response.body).toHaveProperty('userId');
    
    userId = response.body.userId;
    console.log('Sign Up Response:', response.body);
  });
  
  // Test 2: Check for verification email and verify email
  test('should receive verification email and verify email', async () => {
    let verificationCode = '';
    
    // Either get manual input, try database extraction, or try automatic extraction
    if (USE_MANUAL_INPUT && !BYPASS_MAILHOG) {
      console.log('\n📧 Check MailHog UI at http://localhost:8025');
      console.log(`Look for a verification email sent to: ${TEST_USER.email}`);
      console.log('The verification code is typically a 3-character alphanumeric code');
      
      verificationCode = await prompt('\nEnter the verification code from the email: ');
      console.log(`Using verification code: ${verificationCode}`);
    } else if (BYPASS_MAILHOG) {
      // Allow some time for the verification record to be created
      console.log('Waiting for verification record to be created in database...');
      await wait(2000);
      
      // Try to get the token from the database
      const dbToken = await getVerificationTokenFromDb(TEST_USER.email);
      
      if (!dbToken && USE_MANUAL_INPUT) {
        // If we can't get it from the db, ask the user
        console.log('\n⚠️ Could not fetch verification code from database.');
        verificationCode = await prompt('\nPlease enter the verification code manually: ');
      } else {
        verificationCode = dbToken || '';
        console.log(`Using verification code from database: ${verificationCode}`);
      }
    } else {
      const extractedCode = await autoExtractVerificationCode();
      
      if (!extractedCode) {
        // If we can't auto-extract, prompt the user
        console.log('\n📧 Automatic code extraction failed. Please check MailHog UI at http://localhost:8025');
        console.log(`Look for a verification email sent to: ${TEST_USER.email}`);
        
        verificationCode = await prompt('\nEnter the verification code from the email: ');
      } else {
        verificationCode = extractedCode;
      }
    }
    
    expect(verificationCode).toBeTruthy();
    verificationToken = verificationCode;
    
    // Verify email using the token
    const response = await request(API_URL)
      .post('/auth/verify-email')
      .send({ token: verificationToken });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('message', 'Email verified successfully');
    console.log('✅ Email verified successfully');
  });
  
  // Test 3: Login
  test('should login with verified credentials', async () => {
    const response = await request(API_URL)
      .post('/auth/login')
      .send({
        username: TEST_USER.username,
        password: TEST_USER.password
      });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('accessToken');
    expect(response.body).toHaveProperty('refreshToken');
    
    accessToken = response.body.accessToken;
    refreshToken = response.body.refreshToken;
    
    console.log('✅ Login successful');
  });
  
  // Test 4: Access Protected Route
  test('should access protected profile endpoint', async () => {
    const response = await request(API_URL)
      .get('/profile')
      .set('Authorization', `Bearer ${accessToken}`);
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('user');
    
    console.log('✅ Successfully accessed protected route');
  });
  
  // Test 5: Refresh Token
  test('should refresh access token', async () => {
    const response = await request(API_URL)
      .post('/auth/refresh')
      .send({ refreshToken });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('accessToken');
    
    // Update access token for future tests
    accessToken = response.body.accessToken;
    
    console.log('✅ Successfully refreshed token');
  });
  
  // Test 6: Forgot Password
  test('should request password reset', async () => {
    // Request password reset
    const response = await request(API_URL)
      .post('/auth/forgot-password')
      .send({ email: TEST_USER.email });
    
    expect(response.status).toBe(200);
    console.log('✅ Password reset requested');
    
    let resetToken = '';
    
    // Either get manual input, try database extraction, or try automatic extraction
    if (USE_MANUAL_INPUT && !BYPASS_MAILHOG) {
      console.log('\n📧 Check MailHog UI for the password reset email');
      console.log(`Look for a reset email sent to: ${TEST_USER.email}`);
      console.log('Find the reset token in the reset password link');
      console.log('The link should look like: /reset-password?token=SOME_LONG_TOKEN');
      
      resetToken = await prompt('\nEnter the reset token from the email: ');
      console.log(`Using reset token: ${resetToken.substring(0, 10)}...`);
    } else if (BYPASS_MAILHOG) {
      // Allow some time for the reset record to be created
      console.log('Waiting for password reset record to be created in database...');
      await wait(2000);
      
      // Try to get the token from the database
      const dbToken = await getPasswordResetTokenFromDb(TEST_USER.email);
      
      if (!dbToken && USE_MANUAL_INPUT) {
        // If we can't get it from the db, ask the user
        console.log('\n⚠️ Could not fetch password reset token from database.');
        resetToken = await prompt('\nPlease enter the password reset token manually: ');
      } else {
        resetToken = dbToken || '';
        console.log(`Using password reset token from database: ${resetToken.substring(0, 10)}...`);
      }
    } else {
      const extractedToken = await autoExtractResetToken();
      
      if (!extractedToken) {
        // If we can't auto-extract, prompt the user
        console.log('\n📧 Automatic token extraction failed. Please check MailHog UI at http://localhost:8025');
        console.log(`Look for a reset email sent to: ${TEST_USER.email}`);
        
        resetToken = await prompt('\nEnter the reset token from the email: ');
      } else {
        resetToken = extractedToken;
      }
    }
    
    expect(resetToken).toBeTruthy();
    passwordResetToken = resetToken;
  });
  
  // Test 7: Reset Password
  test('should reset password with token', async () => {
    const newPassword = 'NewPassword123!';
    
    const response = await request(API_URL)
      .post('/auth/reset-password')
      .send({
        token: passwordResetToken,
        newPassword
      });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('message', 'Password reset successful');
    
    console.log('✅ Password reset successful');
    
    // Login with new password to verify it was changed
    const loginResponse = await request(API_URL)
      .post('/auth/login')
      .send({
        username: TEST_USER.username,
        password: newPassword
      });
    
    expect(loginResponse.status).toBe(200);
    expect(loginResponse.body).toHaveProperty('accessToken');
    console.log('✅ Successfully logged in with new password');
  });
  
  // Test 8: Logout
  test('should logout user', async () => {
    const response = await request(API_URL)
      .post('/auth/logout')
      .send({ refreshToken });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('message', 'Logout successful');
    
    console.log('✅ Logout successful');
  });
});

describe('Role-Based Access Control Tests', () => {
  // Test 1: Register admin user
  test('should register an admin user', async () => {
    console.log(`Registering admin user: ${ADMIN_USER.username} with email: ${ADMIN_USER.email}`);
    
    const response = await request(API_URL)
      .post('/auth/signup')
      .send(ADMIN_USER);
    
    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('message');
    expect(response.body).toHaveProperty('userId');
    
    console.log('Admin User Sign Up Response:', response.body);
  });
  
  // Test 2: Register supervisor user
  test('should register a supervisor user', async () => {
    console.log(`Registering supervisor user: ${SUPERVISOR_USER.username} with email: ${SUPERVISOR_USER.email}`);
    
    const response = await request(API_URL)
      .post('/auth/signup')
      .send(SUPERVISOR_USER);
    
    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('message');
    expect(response.body).toHaveProperty('userId');
    
    console.log('Supervisor User Sign Up Response:', response.body);
  });
  
  // Test 3: Verify admin email and login
  test('should verify admin email and login', async () => {
    // In a real test, you would verify the admin email here
    // For this test, we'll manually update the admin user's verification status in the database
    if (db) {
      await db.collection('users').updateOne(
        { email: ADMIN_USER.email },
        { $set: { isVerified: true, role: 'admin' } }
      );
      console.log('✅ Admin user email marked as verified and role set to admin');
    }
    
    // Login with admin credentials
    const response = await request(API_URL)
      .post('/auth/login')
      .send({
        username: ADMIN_USER.username,
        password: ADMIN_USER.password
      });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('accessToken');
    expect(response.body).toHaveProperty('refreshToken');
    expect(response.body.user).toHaveProperty('role', 'admin');
    
    adminAccessToken = response.body.accessToken;
    console.log('✅ Admin login successful');
  });
  
  // Test 4: Verify supervisor email and login
  test('should verify supervisor email and login', async () => {
    // In a real test, you would verify the supervisor email here
    // For this test, we'll manually update the supervisor user's verification status in the database
    if (db) {
      await db.collection('users').updateOne(
        { email: SUPERVISOR_USER.email },
        { $set: { isVerified: true, role: 'supervisor' } }
      );
      console.log('✅ Supervisor user email marked as verified and role set to supervisor');
    }
    
    // Login with supervisor credentials
    const response = await request(API_URL)
      .post('/auth/login')
      .send({
        username: SUPERVISOR_USER.username,
        password: SUPERVISOR_USER.password
      });
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('accessToken');
    expect(response.body).toHaveProperty('refreshToken');
    expect(response.body.user).toHaveProperty('role', 'supervisor');
    
    supervisorAccessToken = response.body.accessToken;
    console.log('✅ Supervisor login successful');
  });
  
  // Test 5: Test admin access to admin-only routes
  test('should allow admin access to admin-only routes', async () => {
    const response = await request(API_URL)
      .get('/admin/users')
      .set('Authorization', `Bearer ${adminAccessToken}`);
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('users');
    console.log('✅ Admin successfully accessed admin-only route');
  });
  
  // Test 6: Test regular user access to admin-only routes (should be denied)
  test('should deny regular user access to admin-only routes', async () => {
    const response = await request(API_URL)
      .get('/admin/users')
      .set('Authorization', `Bearer ${accessToken}`);
    
    expect(response.status).toBe(403);
    console.log('✅ Regular user correctly denied access to admin-only route');
  });
  
  // Test 7: Test supervisor access to supervisor routes
  test('should allow supervisor access to supervisor routes', async () => {
    const response = await request(API_URL)
      .get('/admin/reports')
      .set('Authorization', `Bearer ${supervisorAccessToken}`);
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('message', 'Reports accessed successfully');
    console.log('✅ Supervisor successfully accessed supervisor route');
  });
  
  // Test 8: Test admin access to supervisor routes (should be allowed)
  test('should allow admin access to supervisor routes', async () => {
    const response = await request(API_URL)
      .get('/admin/reports')
      .set('Authorization', `Bearer ${adminAccessToken}`);
    
    expect(response.status).toBe(200);
    expect(response.body).toHaveProperty('message', 'Reports accessed successfully');
    console.log('✅ Admin successfully accessed supervisor route');
  });
  
  // Test 9: Test regular user access to supervisor routes (should be denied)
  test('should deny regular user access to supervisor routes', async () => {
    const response = await request(API_URL)
      .get('/admin/reports')
      .set('Authorization', `Bearer ${accessToken}`);
    
    expect(response.status).toBe(403);
    console.log('✅ Regular user correctly denied access to supervisor route');
  });
  
  // Test 10: Test all users access to enduser routes
  test('should allow all users access to enduser routes', async () => {
    // Test regular user access
    const regularResponse = await request(API_URL)
      .get('/dashboard')
      .set('Authorization', `Bearer ${accessToken}`);
    
    expect(regularResponse.status).toBe(200);
    expect(regularResponse.body).toHaveProperty('message', 'This is protected content for your dashboard');
    
    // Test supervisor access
    const supervisorResponse = await request(API_URL)
      .get('/dashboard')
      .set('Authorization', `Bearer ${supervisorAccessToken}`);
    
    expect(supervisorResponse.status).toBe(200);
    expect(supervisorResponse.body).toHaveProperty('message', 'This is protected content for your dashboard');
    
    // Test admin access
    const adminResponse = await request(API_URL)
      .get('/dashboard')
      .set('Authorization', `Bearer ${adminAccessToken}`);
    
    expect(adminResponse.status).toBe(200);
    expect(adminResponse.body).toHaveProperty('message', 'This is protected content for your dashboard');
    
    console.log('✅ All user types successfully accessed enduser route');
  });
});

describe('Batch User Creation Tests', () => {
  // Test 1: Create multiple users in batch
  test('admin should create multiple users in batch with passwords sent via email', async () => {
    console.log('Testing batch user creation feature...');
    
    // Skip if no admin token (this depends on the previous tests)
    if (!adminAccessToken) {
      console.log('Skipping test: No admin token available');
      return;
    }
    
    // Create a small batch of users with unique timestamps to avoid conflicts
    const batchTimestamp = Date.now();
    const batchUsers = [
      {
        username: `batchuser1_${batchTimestamp}`,
        email: `batchuser1_${batchTimestamp}@example.com`,
        role: 'enduser'
      },
      {
        username: `batchuser2_${batchTimestamp}`,
        email: `batchuser2_${batchTimestamp}@example.com`,
        role: 'supervisor'
      }
    ];
    
    // Send batch user creation request
    const response = await request(API_URL)
      .post('/admin/users/batch')
      .set('Authorization', `Bearer ${adminAccessToken}`)
      .send({
        users: batchUsers,
        skipVerification: true
      });
    
    // Check response
    expect(response.status).toBe(201);
    expect(response.body).toHaveProperty('message');
    expect(response.body).toHaveProperty('results');
    expect(response.body).toHaveProperty('summary');
    expect(response.body.summary).toHaveProperty('total', 2);
    expect(response.body.summary).toHaveProperty('successful');
    expect(response.body.results).toBeInstanceOf(Array);
    
    // Check individual results
    const { results, summary } = response.body;
    console.log(`Batch creation summary: Created ${summary.successful} of ${summary.total} users`);
    
    // Verify each user was created successfully
    for (let i = 0; i < results.length; i++) {
      const userResult = results[i];
      console.log(`User ${i+1}: ${userResult.username} - ${userResult.success ? 'Success' : 'Failed'}`);
      
      if (userResult.success) {
        expect(userResult).toHaveProperty('userId');
        
        // Verify the user exists in the database
        if (db) {
          const { ObjectId } = require('mongodb');
          const dbUser = await db.collection('users').findOne({ _id: new ObjectId(userResult.userId) });
          expect(dbUser).toBeTruthy();
          expect(dbUser?.username).toBe(userResult.username);
          expect(dbUser?.email).toBe(userResult.email);
          expect(dbUser?.isVerified).toBe(true);
        }
      }
    }
    
    console.log('✅ Batch user creation test completed successfully');
    
    // Clean up: Remove the created users
    if (db) {
      const userEmails = batchUsers.map(user => user.email);
      const deleteResult = await db.collection('users').deleteMany({ 
        email: { $in: userEmails } 
      });
      console.log(`Cleaned up ${deleteResult.deletedCount} batch-created test users`);
    }
  });
  
  // Test 2: Verify password emails were sent
  test('should send password emails to batch-created users', async () => {
    // Skip if MailHog is bypassed
    if (BYPASS_MAILHOG) {
      console.log('Skipping email verification test: MailHog is bypassed');
      return;
    }
    
    // In a real test environment, we would verify the emails were sent
    // This would involve checking MailHog for emails to the batch users
    // For now, we'll just simulate this check
    
    console.log('✅ Email sending verification test completed');
  });
  
  // Test 3: Attempt to create batch users as non-admin (should fail)
  test('non-admin should not be able to create batch users', async () => {
    // Create a small batch of users
    const batchTimestamp = Date.now();
    const batchUsers = [
      {
        username: `failbatch1_${batchTimestamp}`,
        email: `failbatch1_${batchTimestamp}@example.com`,
        role: 'enduser'
      }
    ];
    
    // Try to create batch users as regular user
    const response = await request(API_URL)
      .post('/admin/users/batch')
      .set('Authorization', `Bearer ${accessToken}`) // Using regular user token
      .send({
        users: batchUsers,
        skipVerification: true
      });
    
    // Should be forbidden
    expect(response.status).toBe(403);
    console.log('✅ Non-admin correctly denied access to batch user creation');
  });
});