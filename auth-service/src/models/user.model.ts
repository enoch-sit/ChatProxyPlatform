// src/models/user.model.ts
import mongoose, { Document, Schema, Types } from 'mongoose';
import bcrypt from 'bcryptjs'; // Changed from bcrypt to bcryptjs

// Define user roles
export enum UserRole {
  ADMIN = 'admin',
  SUPERVISOR = 'supervisor',
  TEACHER = 'teacher',
  ENDUSER = 'enduser',
  USER = 'user'  // Add USER as an alias for ENDUSER
}

// Defines the structure of a user document in the database
export interface IUser extends Document {
  _id: Types.ObjectId;
  username: string;
  email: string;
  password: string;
  isVerified: boolean;
  role: UserRole;
  createdAt: Date;
  updatedAt: Date;
  comparePassword(candidatePassword: string): Promise<boolean>;
}

// Defines the schema for the User model, specifying the structure and validation rules for user data
const UserSchema = new Schema<IUser>(
  {
// Username field: must be unique, trimmed, and between 3 to 30 characters long
username: {
  type: String,
  required: true,
  unique: true,
  trim: true,
  minlength: 3,
  maxlength: 30
},
// Email field: must be unique, trimmed, converted to lowercase, and required
email: {
  type: String,
  required: true,
  unique: true,
  trim: true,
  lowercase: true
},
// Password field: must be at least 8 characters long and required
password: {
  type: String,
  required: true,
  minlength: 8
},
// IsVerified field: indicates if the user's email has been verified, defaults to false
isVerified: {
  type: Boolean,
  default: false
},
// Role field: defines the user's role in the system, defaults to enduser
role: {
  type: String,
  enum: Object.values(UserRole),
  default: UserRole.ENDUSER
}
  },
  {
    timestamps: true
  }
);

// Hash password before saving
// Middleware function to hash the password before saving the user document
UserSchema.pre<IUser>('save', async function(next) {
  // Only hash the password if it has been modified (or is new)
  if (!this.isModified('password')) return next();

  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error: any) {
    next(error);
  }
});

// Method to compare password
// Method to compare a provided password with the hashed password stored in the database
UserSchema.methods.comparePassword = async function(candidatePassword: string): Promise<boolean> {
  return bcrypt.compare(candidatePassword, this.password);
};

export const User = mongoose.model<IUser>('User', UserSchema);
