// src/server.ts
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import dotenv from 'dotenv';
import { rateLimit } from 'express-rate-limit';

// Import consolidated API routes
import apiRoutes from './routes/api.routes';

// Import custom logger
import logger from './utils/logger';

// Import database connection
import sequelize, { testConnection } from './config/sequelize';

// Load environment variables
dotenv.config();

// console.log("DB_USER from env:", process.env.DB_USER);
// console.log("DB_PASSWORD from env:", process.env.DB_PASSWORD);
// console.log("DB_HOST from env:", process.env.DB_HOST);
// console.log("DB_NAME from env:", process.env.DB_NAME);
// console.log("DB_PORT from env:", process.env.DB_PORT);

// Create Express app
const app = express();
const PORT = process.env.PORT || 3001;

// Apply middleware
app.use(helmet()); // Security headers
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*'
}));

// Add a small middleware to log incoming request details before body parsing
app.use((req, res, next) => {
  logger.debug(`[Server Incoming Request] Path: ${req.path}, Method: ${req.method}, Headers: ${JSON.stringify(req.headers)}`);
  next();
});

// POTENTIAL ISSUE AREA: If the incoming request from the Python script
// does not have a 'Content-Type: application/json' header, or if the JSON body is malformed,
// express.json() might fail to parse req.body correctly. 
// This could lead to req.body being undefined or {} when it reaches the controller or other middleware,
// potentially causing a "Missing or invalid required fields" error. [20250522_test_credit_check.py]
app.use(express.json()); // Parse JSON request body

// Add a small middleware to log request body after parsing
app.use((req, res, next) => {
  logger.debug(`[Server Request Body Parsed] Path: ${req.path}, Method: ${req.method}, Body: ${JSON.stringify(req.body)}`);
  next();
});

// // Apply rate limiting
// const limiter = rateLimit({
//   windowMs: 15 * 60 * 1000, // 15 minutes
//   // Increased for development to allow for batch scripts and testing with many concurrent users.
//   max: 1000000, // limit each IP to 1000000 requests per windowMs
//   standardHeaders: true,
//   legacyHeaders: false,
// });
// app.use(limiter);

// POTENTIAL ISSUE AREA: If there is any validation middleware applied within apiRoutes
// or specifically for the /credits/check route before it reaches CreditController.checkCredits,
// that middleware could be the source of the "Missing or invalid required fields" error.
// This is especially true if such middleware has more generic error messages than the controller itself. [20250522_test_credit_check.py]
app.use('/api', apiRoutes);

// Health check endpoint at root path
// 20250523_test_flow
app.get('/health', (_, res) => {
  res.status(200).json({ 
    status: 'ok',
    service: 'accounting-service',
    version: process.env.npm_package_version || '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// Error handling middleware
app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({ message: 'Internal server error' });
});

// Start server
const startServer = async () => {
  try {
    // Test database connection
    await testConnection();
      // Sync database models - create missing tables on startup (non-destructive)
    await sequelize.sync({ force: false });
    logger.info('Database synced');
    
    // Start the server
    app.listen(PORT, () => {
      logger.info(`Accounting service running on port ${PORT}`);
    });
  } catch (error) {
    logger.error('Failed to start server:', error);
    process.exit(1);
  }
};

// Start the server if this file is run directly
if (require.main === module) {
  startServer();
}

export default app;