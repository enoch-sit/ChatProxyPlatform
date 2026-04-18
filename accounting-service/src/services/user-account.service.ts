// src/services/user-account.service.ts
/**
 * User Account Service
 * 
 * Manages user account operations in the Accounting service.
 * Responsible for creating and checking user accounts that are synced from the Auth service.
 */
import UserAccount from '../models/user-account.model';
import logger from '../utils/logger'; // Assuming logger is available
export class UserAccountService {
  /**
   * Finds an existing user account by its primary key (userId) or creates a new one
   * if it doesn't exist. This method is designed to be backward compatible,
   * correctly populating the 'sub' field even if called by older code that
   * only provides 'userId'.
   * 
   * The 'userId' parameter is expected to be the unique identifier from the
   * Authentication service, which is typically the JWT 'sub' claim.
   * 
   * @param {Object} params - The user account parameters.
   * @param {string} params.userId - Unique identifier for the user (required, typically the 'sub' from JWT).
   * @param {string} [params.email='unknown@example.com'] - User's email address.
   * @param {string} [params.username='unknown'] - User's username.
   * @param {string} [params.role='enduser'] - User's role.
   * @param {string} [params.sub] - JWT subject claim (explicitly). If not provided, defaults to `params.userId`.
   * @returns {Promise<UserAccount>} - The existing or newly created user account.
   * @throws {Error} If the database operation fails.
   */
  async findOrCreateUser(params: {
    userId: string;    // This is the PK, and should be the 'sub' from Auth service
    email?: string;
    username?: string;
    role?: string;
    sub?: string;      // Explicitly passing sub, which should match userId if both are from JWT sub
  }): Promise<UserAccount> {
    // Default values for optional parameters.
    // Crucially, if 'sub' is not provided in params, it defaults to the value of 'userId'.
    // This ensures that the 'sub' field in the database is populated correctly even for calls
    // from older code that only knew about 'userId' (which was intended to be the JWT sub).
    
    const { 
      userId, 
      email = 'unknown@example.com', 
      username = 'unknown', 
      role = 'enduser', // Ensure this default role aligns with your system's standard
      sub = userId     // Default 'sub' to 'userId' if not explicitly provided
    } = params;
    
    try {
      // Check if user already exists
      const existingUser = await UserAccount.findByPk(userId);
      
      if (existingUser) {
        logger.info(`UserAccountService.findOrCreateUser - User found by PK: ${userId}. Existing sub: ${existingUser.sub}`);
        return existingUser;
      }

      // PK lookup missed — also search by email to handle cases where the JWT sub
      // changed (e.g. admin user was re-created in the auth DB with a new ObjectId).
      // Returning the existing row avoids a SequelizeUniqueConstraintError and lets
      // the request succeed. The DB fix (updating user_id to the new sub) should be
      // applied separately so that per-user credit lookups remain consistent.
      if (email && email !== 'unknown@example.com') {
        const existingByEmail = await UserAccount.findOne({ where: { email } });
        if (existingByEmail) {
          logger.info(`UserAccountService.findOrCreateUser - User found by email fallback: ${email}. Existing userId: ${existingByEmail.userId}. Requested userId: ${userId}`);
          return existingByEmail;
        }
      }
      
      logger.info(`UserAccountService.findOrCreateUser - Creating new user account for userId (sub): ${userId}, email: ${email}, role: ${role}, explicit sub provided: ${params.sub !== undefined}`);
      const newUser = await UserAccount.create({
        userId,    // Primary Key, set to the 'sub' from Auth service (which is params.userId)
        email,
        username,
        role,
        sub,       // Storing the 'sub' explicitly in the new 'sub' field.
                   // If params.sub was undefined, this 'sub' variable holds the value of params.userId.
      });
      logger.info(`UserAccountService.findOrCreateUser - Successfully created new user: ${newUser.userId}, sub: ${newUser.sub}`);
      
      return newUser;
    } catch (error) {
      console.error('Error in findOrCreateUser:', error);
      throw new Error('Failed to find or create user account');
    }
  }
  
  /**
   * Check if a user exists in the Accounting service
   * 
   * @param {string} userId - Unique identifier for the user
   * @returns {Promise<boolean>} - True if the user exists, false otherwise
   */
  async userExists(userId: string): Promise<boolean> {
    try {
      const user = await UserAccount.findByPk(userId);
      return !!user;
    } catch (error) {
      console.error('Error checking if user exists:', error);
      return false;
    }
  }

  /**
   * Find a user account by username
   * 
   * @param {string} username - The username to search for
   * @returns {Promise<UserAccount | null>} - The user account if found, otherwise null
   */
  async findByUsername(username: string): Promise<UserAccount | null> {
    try {
      const user = await UserAccount.findOne({ where: { username } });
      return user;
    } catch (error) {
      console.error('Error finding user by username:', error);
      // Optionally, rethrow or handle as per application's error strategy
      return null;
    }
  }

  /**
   * Find a user account by email address
   * 
   * @param {string} email - The email address to search for
   * @returns {Promise<UserAccount | null>} - The user account if found, otherwise null
   */
  async findByEmail(email: string): Promise<UserAccount | null> {
    if (!email) {
      logger.warn('UserAccountService.findByEmail - Attempted to find user with null or empty email.');
      return null;
    }
    try {
      const user = await UserAccount.findOne({ where: { email } });
      if (user) {
        logger.info(`UserAccountService.findByEmail - User found for email: ${email}`);
      } else {
        logger.info(`UserAccountService.findByEmail - No user found for email: ${email}`);
      }
      return user;
    } catch (error) {
      logger.error(`UserAccountService.findByEmail - Error finding user by email '${email}':`, error);
      // Depending on error strategy, you might want to rethrow or return null
      // For consistency with findByUsername, returning null on error.
      return null;
    }
  }
}

export default new UserAccountService();