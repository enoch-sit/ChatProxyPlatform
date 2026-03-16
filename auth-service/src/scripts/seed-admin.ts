/**
 * seed-admin.ts
 *
 * Creates the initial admin user if one does not already exist.
 * Safe to run multiple times (idempotent).
 *
 * Usage (local / inside container):
 *   npx ts-node src/scripts/seed-admin.ts
 *   node dist/src/scripts/seed-admin.js
 *
 * AWS ECS:
 *   aws ecs run-task --overrides '{"containerOverrides":[{"name":"auth-service","command":["node","dist/src/scripts/seed-admin.js"]}]}'
 *
 * Environment variables read:
 *   MONGO_URI          - MongoDB connection string (required)
 *   ADMIN_USERNAME     - defaults to "admin"
 *   ADMIN_EMAIL        - defaults to "admin@admin.com"
 *   ADMIN_PASSWORD     - defaults to "admin@admin"  (change in production!)
 */

import mongoose from 'mongoose';
import bcrypt from 'bcryptjs';
import { User, UserRole } from '../models/user.model';

const MONGO_URI = process.env.MONGO_URI;
const ADMIN_USERNAME = process.env.ADMIN_USERNAME || 'admin';
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@admin.com';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin@admin';

async function seedAdmin(): Promise<void> {
  if (!MONGO_URI) {
    console.error('ERROR: MONGO_URI environment variable is not set.');
    process.exit(1);
  }

  await mongoose.connect(MONGO_URI);
  console.log('Connected to MongoDB.');

  const existing = await User.findOne({ role: UserRole.ADMIN });
  if (existing) {
    console.log('='.repeat(50));
    console.log('Admin user already exists — skipping creation.');
    console.log(`  username : ${existing.username}`);
    console.log(`  email    : ${existing.email}`);
    console.log(`  password : ${ADMIN_PASSWORD}  (configured value — unchanged if not rotated)`);
    console.log('='.repeat(50));
    await mongoose.disconnect();
    return;
  }

  // Hash password manually here because we are using insertOne-level save,
  // but actually we use new User() + save() so the pre('save') hook fires correctly.
  const admin = new User({
    username: ADMIN_USERNAME,
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD, // pre('save') hook will hash this
    isVerified: true,
    role: UserRole.ADMIN,
  });

  await admin.save();
  console.log('='.repeat(50));
  console.log('Admin user created successfully!');
  console.log(`  username : ${ADMIN_USERNAME}`);
  console.log(`  email    : ${ADMIN_EMAIL}`);
  console.log(`  password : ${ADMIN_PASSWORD}`);
  console.log('='.repeat(50));
  console.log('IMPORTANT: Change the default password after first login.');

  await mongoose.disconnect();
}

seedAdmin()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('seed-admin failed:', err);
    process.exit(1);
  });
