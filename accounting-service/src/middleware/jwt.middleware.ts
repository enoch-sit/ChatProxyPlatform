// src/middleware/jwt.middleware.ts
/**
 * JWT Authentication Middleware
 * 
 * This middleware handles JWT token validation and user authentication 
 * for the accounting service. It verifies tokens created by the authentication
 * service and extracts user information to attach to request objects.
 * 
 * The module provides middlewares for:
 * 1. JWT token authentication
 * 2. Role-based access control for admin users
 * 3. Role-based access control for supervisor users
 * 
 * These middlewares can be applied to routes to protect them and
 * enforce access control policies.
 */
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import UserAccount from '../models/user-account.model';
import UserAccountService from '../services/user-account.service';

/**
 * Type Extension for Express Request
 * 
 * Extends the base Request interface to include a user object
 * that contains authenticated user information after successful
 * JWT validation.
 */
declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;     // Unique identifier for the user
        username: string;   // User's display name
        email: string;      // User's email address
        role: string;       // User's role (admin, supervisor, user, etc.)
      };
    }
  }
}

/**
 * JWT Payload Interface
 * 
 * Defines the structure of the decoded JWT token payload.
 * This matches the payload structure created by the authentication
 * service when generating tokens.
 */
interface JwtPayload {
  sub: string;       // Subject (userId)
  username: string;  // User's username
  email: string;     // User's email address 
  role: string;      // User's role for authorization
  type: string;      // Token type (access, refresh, etc.)
  iat: number;       // Issued at timestamp
  exp: number;       // Expiration timestamp
}

/**
 * JWT Authentication Middleware
 * 
 * Validates the JWT token in the request Authorization header and
 * attaches user information to the request object if valid.
 * 
 * Process:
 * 1. Extract the token from the Authorization header
 * 2. Verify the token signature and expiration
 * 3. Ensure it's an access token (not refresh)
 * 4. Find or create the user account in our database
 * 5. Attach user info to the request for downstream handlers
 * 
 * @param req - Express request object
 * @param res - Express response object
 * @param next - Express next function
 * @returns void, calls next() on success or returns error response
 */
export const authenticateJWT = async (req: Request, res: Response, next: NextFunction) => {
  //debugger;
  try {
    const authHeader = req.headers.authorization;
    
    // Check if Authorization header exists and has correct format
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Authentication token required' });
    }
    
    // Extract token from header (remove "Bearer " prefix)
    const token = authHeader.split(' ')[1];
    
    // Verify token using shared JWT secret
    const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET!) as JwtPayload;
    
    // Ensure this is an access token, not a refresh token
    if (decoded.type !== 'access') {
      return res.status(401).json({ message: 'Invalid token type' });
    }
    
    // Find or create user account in accounting database using our service
    try {
      // This ensures our user database stays in sync with the auth service
      await UserAccountService.findOrCreateUser({
        userId: decoded.sub,
        email: decoded.email,
        username: decoded.username,
        role: decoded.role
      });
      
      // Attach user info to request object for use in route handlers
      req.user = {
        userId: decoded.sub,
        username: decoded.username,
        email: decoded.email,
        role: decoded.role
      };
      
      // Continue to the next middleware or route handler
      next();
    } catch (userError) {
      console.error('Error processing user account:', userError);
      return res.status(500).json({ message: 'Failed to process user account' });
    }
  } catch (error: unknown) {
    // Handle specific JWT error types with appropriate responses
    if (error instanceof Error) {
      if (error.name === 'TokenExpiredError') {
        return res.status(401).json({ message: 'Token expired' });
      }
      
      if (error.name === 'JsonWebTokenError') {
        return res.status(401).json({ message: 'Invalid token' });
      }
    }
    
    // Catch-all for other authentication errors
    console.error('JWT authentication error:', error);
    return res.status(401).json({ message: 'Authentication failed' });
  }
};

/**
 * Admin Role Middleware
 * 
 * Ensures that the authenticated user has admin privileges.
 * This middleware should be applied after authenticateJWT.
 * 
 * @param req - Express request object with user info attached
 * @param res - Express response object
 * @param next - Express next function
 * @returns void, calls next() if user is admin or returns 403 Forbidden
 */
export const requireAdmin = async (req: Request, res: Response, next: NextFunction) => {
  //debugger;
  try {
    const authHeader = req.headers.authorization;
    
    // Check if Authorization header exists and has correct format
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Authentication token required' });
    }
    
    // Extract token from header (remove "Bearer " prefix)
    const token = authHeader.split(' ')[1];
    
    // Verify token using shared JWT secret
    const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET!) as JwtPayload;
    
    // Ensure this is an access token, not a refresh token
    if (decoded.type !== 'access') {
      return res.status(401).json({ message: 'Invalid token type' });
    }
    
    // Check if user has admin role
    if (decoded.role !== 'admin') {
      return res.status(403).json({ message: 'Admin access required' });
    }
    
    // Find or create user account in accounting database using our service
    try {
      // This ensures our user database stays in sync with the auth service
      await UserAccountService.findOrCreateUser({
        userId: decoded.sub,
        email: decoded.email,
        username: decoded.username,
        role: decoded.role
      });
      
      // Attach user info to request object for use in route handlers
      req.user = {
        userId: decoded.sub,
        username: decoded.username,
        email: decoded.email,
        role: decoded.role
      };
      
      // Continue to the next middleware or route handler
      next();
    } catch (userError) {
      console.error('Error processing user account:', userError);
      return res.status(500).json({ message: 'Failed to process user account' });
    }
  } catch (error: unknown) {
    // Handle specific JWT error types with appropriate responses
    if (error instanceof Error) {
      if (error.name === 'TokenExpiredError') {
        return res.status(401).json({ message: 'Token expired' });
      }
      
      if (error.name === 'JsonWebTokenError') {
        return res.status(401).json({ message: 'Invalid token' });
      }
    }
    
    // Catch-all for other authentication errors
    console.error('JWT authentication error:', error);
    return res.status(401).json({ message: 'Authentication failed' });
  }
};
/**
 * Supervisor Role Middleware
 * 
 * Ensures that the authenticated user has supervisor or admin privileges.
 * This middleware implements a role hierarchy where admins implicitly
 * have supervisor privileges as well.
 * 
 * This middleware should be applied after authenticateJWT.
 * 
 * @param req - Express request object with user info attached
 * @param res - Express response object
 * @param next - Express next function
 * @returns void, calls next() if user is supervisor/admin or returns 403 Forbidden
 */
export const requireSupervisor = async (req: Request, res: Response, next: NextFunction) => {
  //debugger;
  try {
    const authHeader = req.headers.authorization;
    
    // Check if Authorization header exists and has correct format
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ message: 'Authentication token required' });
    }
    
    // Extract token from header (remove "Bearer " prefix)
    const token = authHeader.split(' ')[1];
    
    // Verify token using shared JWT secret
    const decoded = jwt.verify(token, process.env.JWT_ACCESS_SECRET!) as JwtPayload;
    
    // Ensure this is an access token, not a refresh token
    if (decoded.type !== 'access') {
      return res.status(401).json({ message: 'Invalid token type' });
    }
    
    // Check if user has admin role
    if (decoded.role !== 'admin' && decoded.role !== 'supervisor' && decoded.role !== 'teacher') {
      return res.status(403).json({ message: 'Admin access required' });
    }
    
    // Find or create user account in accounting database using our service
    try {
      // This ensures our user database stays in sync with the auth service
      await UserAccountService.findOrCreateUser({
        userId: decoded.sub,
        email: decoded.email,
        username: decoded.username,
        role: decoded.role
      });
      
      // Attach user info to request object for use in route handlers
      req.user = {
        userId: decoded.sub,
        username: decoded.username,
        email: decoded.email,
        role: decoded.role
      };
      
      // Continue to the next middleware or route handler
      next();
    } catch (userError) {
      console.error('Error processing user account:', userError);
      return res.status(500).json({ message: 'Failed to process user account' });
    }
  } catch (error: unknown) {
    // Handle specific JWT error types with appropriate responses
    if (error instanceof Error) {
      if (error.name === 'TokenExpiredError') {
        return res.status(401).json({ message: 'Token expired' });
      }
      
      if (error.name === 'JsonWebTokenError') {
        return res.status(401).json({ message: 'Invalid token' });
      }
    }
    
    // Catch-all for other authentication errors
    console.error('JWT authentication error:', error);
    return res.status(401).json({ message: 'Authentication failed' });
  }
};