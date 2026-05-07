// src/config/db.config.ts
// Import Mongoose for MongoDB operations
import mongoose from 'mongoose';
// Import logger utility for logging connection status
import { logger } from '../utils/logger';

// Function to establish a connection to MongoDB
export const connectDB = async (): Promise<void> => {
  try {
    // Retrieve MongoDB URI from environment variables
    const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
    
    // Check if MongoDB URI is defined
    if (!mongoUri) {
      throw new Error('MongoDB URI is not defined in environment variables');
    }

    // Attempt to connect to MongoDB using the provided URI
    await mongoose.connect(mongoUri);
    
    // Log successful connection
    logger.info('MongoDB connected successfully');
  } catch (error) {
    // Log any errors that occur during connection
    logger.error('MongoDB connection error:', error);
    // Exit the application if connection fails
    process.exit(1);
  }
};
