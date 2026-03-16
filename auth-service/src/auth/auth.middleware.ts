// src/auth/auth.middleware.ts
import { Request, Response, NextFunction } from 'express';
import { tokenService } from './token.service';
import { logger } from '../utils/logger';
import { UserRole } from '../models/user.model';

declare global {
  namespace Express {
    interface Request {
      user?: {
        userId: string;
        username: string;
        role: UserRole;
      };
    }
  }
}

/**
 * Authentication middleware that verifies JWT tokens
 */
export const authenticate = (req: Request, res: Response, next: NextFunction) => {
  try {
    // Get token from header or cookie
    let token: string | undefined;
    
    // Check Authorization header
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7);
    } 
    // Check cookie
    else if (req.cookies && req.cookies.accessToken) {
      token = req.cookies.accessToken;
    }
    
    if (!token) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    
    // Verify token
    const decoded = tokenService.verifyAccessToken(token);
    
    if (!decoded) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
    
    // Attach user info to request including role
    req.user = {
      userId: decoded.sub,
      username: decoded.username,
      role: decoded.role
    };
    
    next();
  } catch (error) {
    logger.error('Authentication error:', error);
    return res.status(401).json({ error: 'Authentication failed' });
  }
};

/**
 * Authorization middleware to check if the user is an admin
 */
export const isAdmin = (req: Request, res: Response, next: NextFunction) => {
  if (req.user && req.user.role === UserRole.ADMIN) {
    next();
  } else {
    logger.warn(`Forbidden: Admin access required for user ${req.user?.userId} with role ${req.user?.role} at ${req.originalUrl}`);
    return res.status(403).json({ error: 'Forbidden: Admin access required' });
  }
};

/**
 * Check if user is authenticated but don't require authentication
 */
export const optionalAuth = (req: Request, res: Response, next: NextFunction) => {
  try {
    // Get token from header or cookie
    let token: string | undefined;
    
    // Check Authorization header
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      token = authHeader.substring(7);
    } 
    // Check cookie
    else if (req.cookies && req.cookies.accessToken) {
      token = req.cookies.accessToken;
    }
    
    if (token) {
      // Verify token
      const decoded = tokenService.verifyAccessToken(token);
      
      if (decoded) {
        // Attach user info to request including role
        req.user = {
          userId: decoded.sub,
          username: decoded.username,
          role: decoded.role
        };
      }
    }
    
    next();
  } catch (error) {
    // Just continue without authentication
    next();
  }
};

/**
 * Middleware to restrict access to admin users only
 */
export const requireAdmin = (req: Request, res: Response, next: NextFunction) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  if (req.user.role !== UserRole.ADMIN) {
    return res.status(403).json({ error: 'Admin access required' });
  }
  
  next();
};

/**
 * Middleware to restrict access to admin and teacher users
 * Teachers have elevated privileges to manage student accounts
 */
export const requireAdminOrTeacher = (req: Request, res: Response, next: NextFunction) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  if (req.user.role !== UserRole.ADMIN && req.user.role !== UserRole.TEACHER) {
    return res.status(403).json({ error: 'Admin or teacher access required' });
  }
  
  next();
};

/**
 * Middleware to restrict access to supervisors and admins
 */
export const requireSupervisor = (req: Request, res: Response, next: NextFunction) => {
  if (!req.user) {
    return res.status(401).json({ error: 'Authentication required' });
  }
  
  if (req.user.role !== UserRole.SUPERVISOR && req.user.role !== UserRole.ADMIN && req.user.role !== UserRole.TEACHER) {
    return res.status(403).json({ error: 'Supervisor access required' });
  }
  
  next();
};