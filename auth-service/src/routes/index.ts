// src/routes/index.ts
import { Router, Request, Response, NextFunction } from 'express';
import { authenticate, isAdmin, requireAdmin, requireAdminOrTeacher, requireSupervisor, optionalAuth } from '../auth/auth.middleware';
import { User, UserRole } from '../models/user.model';
import { authService } from '../auth/auth.service';
import { passwordService } from '../services/password.service';
import { tokenService } from '../auth/token.service';
import { logger } from '../utils/logger';
import { Verification, VerificationType } from '../models/verification.model';
import mongoose, { Types } from 'mongoose';

// Create routers
const router = Router();
const authRouter = Router();
const protectedRouter = Router();
const adminRouter = Router();
const testingRouter = Router();

const durationToMs = (value: string | undefined, fallbackMs: number): number => {
  const input = (value || '').trim();
  const match = input.match(/^(\d+)(ms|s|m|h|d)$/i);

  if (!match) {
    return fallbackMs;
  }

  const amount = parseInt(match[1], 10);
  const unit = match[2].toLowerCase();

  switch (unit) {
    case 'ms':
      return amount;
    case 's':
      return amount * 1000;
    case 'm':
      return amount * 60 * 1000;
    case 'h':
      return amount * 60 * 60 * 1000;
    case 'd':
      return amount * 24 * 60 * 60 * 1000;
    default:
      return fallbackMs;
  }
};

const accessTokenCookieMaxAgeMs = durationToMs(process.env.JWT_ACCESS_EXPIRES_IN, 15 * 60 * 1000);
const refreshTokenCookieMaxAgeMs = durationToMs(process.env.JWT_REFRESH_EXPIRES_IN, 7 * 24 * 60 * 60 * 1000);

const clearAuthCookies = (res: Response): void => {
  const secure = process.env.NODE_ENV === 'production';
  res.clearCookie('accessToken', {
    httpOnly: true,
    secure,
    sameSite: 'strict',
  });
  res.clearCookie('refreshToken', {
    httpOnly: true,
    secure,
    sameSite: 'strict',
    path: '/api/auth/refresh',
  });
};

// =============================================================================
// Auth Routes (previously in auth.routes.ts)
// =============================================================================

// Register a new user
authRouter.post('/signup', async (req: Request, res: Response) => {
  try {
    const { username, email, password } = req.body;
    
    if (!username || !email || !password) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const result = await authService.signup(username, email, password);
    
    if (!result.success) {
      return res.status(400).json({ error: result.message });
    }
    
    res.status(201).json({
      message: result.message,
      userId: result.userId
    });
  } catch (error: any) {
    logger.error(`Signup error: ${error.message}`);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Verify email with confirmation code
authRouter.post('/verify-email', async (req: Request, res: Response) => {
  try {
    const { token } = req.body;
    
    if (!token) {
      return res.status(400).json({ error: 'Token is required' });
    }
    
    const verified = await authService.verifyEmail(token);
    
    if (!verified) {
      return res.status(400).json({ error: 'Email verification failed' });
    }
    
    res.status(200).json({ message: 'Email verified successfully' });
  } catch (error: any) {
    logger.error(`Verify email error: ${error.message}`);
    res.status(500).json({ error: 'Email verification failed' });
  }
});

// Resend verification code
authRouter.post('/resend-verification', async (req: Request, res: Response) => {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    const sent = await authService.resendVerificationCode(email);
    
    if (!sent) {
      return res.status(400).json({ error: 'Failed to resend verification code' });
    }
    
    res.status(200).json({ message: 'Verification code resent' });
  } catch (error: any) {
    logger.error(`Resend verification error: ${error.message}`);
    res.status(500).json({ error: 'Failed to resend verification code' });
  }
});

// Login
authRouter.post('/login', async (req: Request, res: Response) => {
  try {
    const { username, password } = req.body;
    
    if (!username || !password) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    const result = await authService.login(username, password);
    
    if (!result.success) {
      return res.status(401).json({ error: result.message });
    }
    
    // Set HTTP-only cookie with access token
    if (result.accessToken) {
      res.cookie('accessToken', result.accessToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: accessTokenCookieMaxAgeMs,
      });
    }
    
    // Set HTTP-only cookie with refresh token
    if (result.refreshToken) {
      res.cookie('refreshToken', result.refreshToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        path: '/api/auth/refresh',
        maxAge: refreshTokenCookieMaxAgeMs,
      });
    }
    
    res.status(200).json({
      message: result.message,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken,
      user: result.user
    });
  } catch (error: any) {
    logger.error(`Login error: ${error.message}`);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Refresh token
authRouter.post('/refresh', async (req: Request, res: Response) => {
  try {
    // Get refresh token from cookie or request body
    const refreshToken = req.cookies.refreshToken || req.body.refreshToken;
    
    if (!refreshToken) {
      return res.status(400).json({ error: 'Refresh token is required' });
    }
    
    const result = await authService.refreshToken(refreshToken);
    
    if (!result.success) {
      return res.status(401).json({ error: result.message });
    }
    
    // Set HTTP-only cookie with new access token
    if (result.accessToken) {
      res.cookie('accessToken', result.accessToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        maxAge: accessTokenCookieMaxAgeMs,
      });
    }
    
    // Set HTTP-only cookie with new refresh token
    if (result.refreshToken) {
      res.cookie('refreshToken', result.refreshToken, {
        httpOnly: true,
        secure: process.env.NODE_ENV === 'production',
        sameSite: 'strict',
        path: '/api/auth/refresh',
        maxAge: refreshTokenCookieMaxAgeMs,
      });
    }
    
    res.status(200).json({
      message: result.message,
      accessToken: result.accessToken,
      refreshToken: result.refreshToken
    });
  } catch (error: any) {
    logger.error(`Token refresh error: ${error.message}`);
    res.status(500).json({ error: 'Token refresh failed' });
  }
});

// Logout
authRouter.post('/logout', async (req: Request, res: Response) => {
  try {
    // Get refresh token from cookie or request body
    const refreshToken = req.cookies.refreshToken || req.body.refreshToken;
    
    if (refreshToken) {
      await authService.logout(refreshToken);
    }
    
    clearAuthCookies(res);
    
    res.status(200).json({ message: 'Logout successful' });
  } catch (error: any) {
    logger.error(`Logout error: ${error.message}`);
    res.status(500).json({ error: 'Logout failed' });
  }
});

// Logout from all devices
authRouter.post('/logout-all', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      return res.status(401).json({ error: 'Authentication required' });
    }
    
    await authService.logoutAll(userId);
    
    clearAuthCookies(res);
    
    res.status(200).json({ message: 'Logged out from all devices' });
  } catch (error: any) {
    logger.error(`Logout all error: ${error.message}`);
    res.status(500).json({ error: 'Logout failed' });
  }
});

// Request password reset
authRouter.post('/forgot-password', async (req: Request, res: Response) => {
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    await passwordService.generateResetToken(email);
    
    // Always return success to prevent email enumeration
    res.status(200).json({
      message: 'If your email exists in our system, you will receive a password reset link'
    });
  } catch (error: any) {
    logger.error(`Forgot password error: ${error.message}`);
    // Still return success to prevent email enumeration
    res.status(200).json({
      message: 'If your email exists in our system, you will receive a password reset link'
    });
  }
});

// Reset password
authRouter.post('/reset-password', async (req: Request, res: Response) => {
  try {
    const { token, newPassword } = req.body;
    
    if (!token || !newPassword) {
      return res.status(400).json({ error: 'Token and new password are required' });
    }
    
    const success = await passwordService.resetPassword(token, newPassword);
    
    if (!success) {
      return res.status(400).json({ error: 'Password reset failed' });
    }
    
    res.status(200).json({ message: 'Password reset successful' });
  } catch (error: any) {
    logger.error(`Reset password error: ${error.message}`);
    res.status(500).json({ error: 'Password reset failed' });
  }
});

// Check user existence and activity (called by external services like Python script)
authRouter.get('/users/:userId', optionalAuth, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    const user = await User.findById(userId);

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Base response for all authenticated or unauthenticated requests
    const responseData: any = {
      _id: user._id,
      username: user.username,
      active: user.isVerified, // 'active' field for the Python script
      deleted: false           // 'deleted' field for the Python script (false as user is found)
    };

    // If an admin is making the request, add more details
    if (req.user && req.user.role === UserRole.ADMIN) {
      responseData.email = user.email;
      responseData.role = user.role;
      responseData.isVerified = user.isVerified; // Include original isVerified as well
      responseData.createdAt = user.createdAt;
      responseData.updatedAt = user.updatedAt;
    }

    res.status(200).json(responseData);

  } catch (error: any) {
    logger.error(`Error checking user existence: ${error.message}`);
    res.status(500).json({ error: 'Failed to check user existence' });
  }
});

// =============================================================================
// Protected Routes (previously in protected.routes.ts)
// =============================================================================

// Get user profile
protectedRouter.get('/profile', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }
    
    const user = await User.findById(userId).select('-password');
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.status(200).json({ user });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch profile' });
  }
});

// Update user profile
protectedRouter.put('/profile', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }
    
    const { username, email } = req.body;
    const updateData: { username?: string; email?: string } = {};
    
    if (username) updateData.username = username;
    if (email) updateData.email = email;
    
    // Check if username is already taken
    if (username) {
      const existingUser = await User.findOne({ username, _id: { $ne: userId } });
      if (existingUser) {
        return res.status(400).json({ error: 'Username already taken' });
      }
    }
    
    // Check if email is already taken
    if (email) {
      const existingUser = await User.findOne({ email, _id: { $ne: userId } });
      if (existingUser) {
        return res.status(400).json({ error: 'Email already taken' });
      }
    }
    
    const updatedUser = await User.findByIdAndUpdate(
      userId,
      { $set: updateData },
      { new: true }
    ).select('-password');
    
    if (!updatedUser) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.status(200).json({ user: updatedUser });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// Change password
protectedRouter.post('/change-password', authenticate, async (req: Request, res: Response) => {
  try {
    const userId = req.user?.userId;
    
    if (!userId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }
    
    const { currentPassword, newPassword } = req.body;
    
    if (!currentPassword || !newPassword) {
      return res.status(400).json({ error: 'Current password and new password are required' });
    }
    
    const user = await User.findById(userId);
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Verify current password
    const isPasswordValid = await user.comparePassword(currentPassword);
    if (!isPasswordValid) {
      return res.status(400).json({ error: 'Current password is incorrect' });
    }
    
    // Update password
    user.password = newPassword;
    await user.save();
    
    res.status(200).json({ message: 'Password changed successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to change password' });
  }
});

// Protected resource example
protectedRouter.get('/dashboard', authenticate, (req: Request, res: Response) => {
  res.status(200).json({
    message: 'This is protected content for your dashboard',
    user: req.user
  });
});

// =============================================================================
// Admin Routes (previously in admin.routes.ts)
// =============================================================================

// Get all users (admin only)
adminRouter.get('/users', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const users = await User.find().select('-password');
    res.status(200).json({ users });
  } catch (error) {
    logger.error('Error fetching users:', error);
    res.status(500).json({ error: 'Failed to fetch users' });
  }
});

// Get user by ID (Admin or teacher)
adminRouter.get('/users/:userId', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    const user = await User.findById(userId).select('-password'); // Exclude password

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Normalize the response to match the Python server's expected format
    const userData = {
        user_id: user._id,
        username: user.username,
        email: user.email,
        role: user.role,
        is_verified: user.isVerified,
        created_at: user.createdAt,
        updated_at: user.updatedAt
    };

    res.status(200).json({ user: userData }); // Wrapped in 'user' key

  } catch (error: any) {
    logger.error(`Error fetching user by ID: ${error.message}`);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Get user by email (admin or teacher)
adminRouter.get('/users/by-email/:email', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  // GET /api/admin/users/by-email/:email
  try {
    const { email } = req.params;
    
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }
    
    const user = await User.findOne({ email }).select('-password');
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.status(200).json({ user });
  } catch (error) {
    logger.error('Error fetching user by email:', error);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});


// Create a new user (admin or teacher)
adminRouter.post('/users', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { username, email, password, role, skipVerification = true } = req.body;
    
    // Validate required fields
    if (!username || !email || !password) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    
    // Validate role if provided
    if (role && !Object.values(UserRole).includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }

    // Prevent non-admins from creating admin users
    if (role === UserRole.ADMIN) {
      logger.warn(`Admin user creation attempt by ${req.user?.username} - This action is restricted`);
      return res.status(403).json({ error: 'Creating admin users is restricted' });
    }
    
    // Create the user with the provided information
    const result = await authService.adminCreateUser(
      username,
      email,
      password,
      role || UserRole.ENDUSER,
      skipVerification !== false
    );
    
    if (!result.success) {
      return res.status(400).json({ error: result.message });
    }
    
    logger.info(`User ${username} created by admin ${req.user?.username}`);
    res.status(201).json({
      message: result.message,
      userId: result.userId
    });
  } catch (error) {
    logger.error('Admin create user error:', error);
    res.status(500).json({ error: 'User creation failed' });
  }
});

// Create multiple users at once (admin or teacher)
adminRouter.post('/users/batch', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { users, skipVerification = true } = req.body;

    // Validate input
    if (!users || !Array.isArray(users) || users.length === 0) {
      return res.status(400).json({ error: 'A non-empty array of users is required' });
    }
    
    // Validate each user has required fields
    for (const user of users) {
      if (!user.username || !user.email) {
        return res.status(400).json({ 
          error: 'Each user must have a username and email',
          invalidUser: user
        });
      }

      if (user.password && typeof user.password === 'string' && user.password.length < 8) {
        return res.status(400).json({
          error: 'Provided batch password must be at least 8 characters',
          invalidUser: user
        });
      }
      
      // Validate role if provided
      if (user.role && !Object.values(UserRole).includes(user.role)) {
        return res.status(400).json({ 
          error: 'Invalid role provided',
          invalidUser: user
        });
      }
      
      // Prevent creating admin users
      if (user.role === UserRole.ADMIN) {
        logger.warn(`Batch admin user creation attempt by ${req.user?.username} - This action is restricted`);
        return res.status(403).json({ 
          error: 'Creating admin users is restricted',
          invalidUser: user
        });
      }
    }
    
    // Create the users in batch
    const result = await authService.adminCreateBatchUsers(
      users,
      skipVerification !== false
    );
    
    logger.info(`Batch user creation by admin ${req.user?.username}. Created: ${result.summary.successful}, Failed: ${result.summary.failed}, Total: ${result.summary.total}`);
    
    res.status(201).json({
      message: `${result.summary.successful} of ${result.summary.total} users created successfully`,
      results: result.results,
      summary: result.summary
    });
  } catch (error) {
    logger.error('Admin batch create users error:', error);
    res.status(500).json({ error: 'Batch user creation failed' });
  }
});

// Update user role (admin only)
adminRouter.put('/users/:userId/role', authenticate, requireAdmin, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { role } = req.body;
    
    // Validate role
    if (!Object.values(UserRole).includes(role)) {
      return res.status(400).json({ error: 'Invalid role' });
    }
    
    const updatedUser = await User.findByIdAndUpdate(
      userId,
      { role },
      { new: true }
    ).select('-password');
    
    if (!updatedUser) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    logger.info(`User ${updatedUser.username}'s role updated to ${role} by ${req.user?.username}`);
    res.status(200).json({ user: updatedUser });
  } catch (error) {
    logger.error('Error updating user role:', error);
    res.status(500).json({ error: 'Failed to update user role' });
  }
});

// Update user roles in batch (admin only)
adminRouter.put('/users/roles/batch', authenticate, requireAdmin, async (req: Request, res: Response) => {
  try {
    const { updates } = req.body;

    if (!Array.isArray(updates) || updates.length === 0) {
      return res.status(400).json({ error: 'A non-empty updates array is required' });
    }

    const results: Array<{ userId: string; success: boolean; message: string; role?: string }> = [];
    let successful = 0;
    let failed = 0;

    for (const update of updates) {
      const { userId, role } = update || {};

      if (!userId || !mongoose.Types.ObjectId.isValid(userId)) {
        failed++;
        results.push({ userId: userId || 'unknown', success: false, message: 'Invalid user ID' });
        continue;
      }

      if (!Object.values(UserRole).includes(role)) {
        failed++;
        results.push({ userId, success: false, message: 'Invalid role' });
        continue;
      }

      try {
        const updatedUser = await User.findByIdAndUpdate(
          userId,
          { role },
          { new: true }
        ).select('-password');

        if (!updatedUser) {
          failed++;
          results.push({ userId, success: false, message: 'User not found' });
          continue;
        }

        successful++;
        results.push({ userId, success: true, message: 'Role updated', role: updatedUser.role });
      } catch (error) {
        failed++;
        logger.error(`Error updating role for user ${userId}:`, error);
        results.push({ userId, success: false, message: 'Failed to update role' });
      }
    }

    logger.info(`Batch role update by ${req.user?.username}. Successful: ${successful}, Failed: ${failed}, Total: ${updates.length}`);
    res.status(200).json({
      message: `${successful} of ${updates.length} user roles updated successfully`,
      results,
      summary: {
        total: updates.length,
        successful,
        failed,
      },
    });
  } catch (error) {
    logger.error('Batch role update error:', error);
    res.status(500).json({ error: 'Batch role update failed' });
  }
});

// Delete a specific user (admin or teacher)
adminRouter.delete('/users/:userId', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    // Prevent an admin from deleting themselves
    if (req.user?.userId === userId) {
      return res.status(400).json({ error: 'Cannot delete your own account' });
    }
    
    // Find the user to get their info for logging
    const user = await User.findById(userId);
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Check if trying to delete another admin (additional security)
    if (user.role === UserRole.ADMIN) {
      logger.warn(`Admin ${req.user?.username} attempted to delete another admin ${user.username}`);
      return res.status(403).json({ error: 'Cannot delete another admin user' });
    }
    
    // Delete the user
    await User.findByIdAndDelete(userId);
    
    // Delete all refresh tokens for the user (cleanup)
    await tokenService.deleteAllUserRefreshTokens(userId);
    
    logger.info(`User ${user.username} (${user.email}) deleted by admin ${req.user?.username}`);
    res.status(200).json({ 
      message: 'User deleted successfully',
      user: {
        username: user.username,
        email: user.email,
        role: user.role
      }
    });
  } catch (error) {
    logger.error('Error deleting user:', error);
    res.status(500).json({ error: 'Failed to delete user' });
  }
});

// Delete all users except admins (admin only)
adminRouter.delete('/users', authenticate, requireAdmin, async (req: Request, res: Response) => {
  try {
    const { confirmDelete, preserveAdmins = true } = req.body;
    
    // Require explicit confirmation to prevent accidental deletion
    if (confirmDelete !== 'DELETE_ALL_USERS') {
      return res.status(400).json({ 
        error: 'Confirmation required',
        message: 'To delete all users, include {"confirmDelete": "DELETE_ALL_USERS"} in the request body'
      });
    }
    
    let deleteFilter = {};
    
    // By default, preserve admin accounts
    if (preserveAdmins) {
      deleteFilter = { role: { $ne: UserRole.ADMIN } };
    }
    
    // Delete users based on filter
    const result = await User.deleteMany(deleteFilter);
    
    // Delete all associated refresh tokens
    if (!preserveAdmins) {
      // If deleting all users including admins, delete all tokens
      await tokenService.deleteAllRefreshTokens();
    } else {
      // If preserving admins, we'd need to find and delete non-admin tokens
      // This would require a more complex query with aggregation
      // For simplicity, we'll keep all tokens and let them expire naturally
      logger.info('Refresh tokens for non-admin users will expire naturally');
    }
    
    logger.info(`Bulk user deletion by admin ${req.user?.username}. ${result.deletedCount} users deleted.`);
    res.status(200).json({ 
      message: `${result.deletedCount} users deleted successfully`,
      preservedAdmins: preserveAdmins
    });
  } catch (error) {
    logger.error('Error bulk deleting users:', error);
    res.status(500).json({ error: 'Failed to delete users' });
  }
});

// Supervisor routes - accessible by both supervisors and admins
adminRouter.get('/reports', authenticate, requireSupervisor, (req: Request, res: Response) => {
  res.status(200).json({ 
    message: 'Reports accessed successfully',
    role: req.user?.role
  });
});

// Admin/teacher password reset - set a user's password directly
adminRouter.put('/users/:userId/password', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const { newPassword } = req.body;

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }
    if (!newPassword || typeof newPassword !== 'string' || newPassword.length < 8) {
      return res.status(400).json({ error: 'New password must be at least 8 characters' });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Prevent teachers from resetting admin or other teacher accounts
    if (req.user?.role === UserRole.TEACHER && (user.role === UserRole.ADMIN || user.role === UserRole.TEACHER || user.role === UserRole.SUPERVISOR)) {
      return res.status(403).json({ error: 'Teachers can only reset passwords for student accounts' });
    }

    user.password = newPassword;
    await user.save();

    logger.info(`Password reset for user ${user.username} by ${req.user?.username}`);
    res.status(200).json({ message: 'Password reset successfully' });
  } catch (error: any) {
    logger.error(`Admin password reset error: ${error.message}`);
    res.status(500).json({ error: 'Failed to reset password' });
  }
});

// Directly verify a user's email (admin or teacher)
adminRouter.post('/users/:userId/verify', authenticate, requireAdminOrTeacher, async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    const user = await User.findByIdAndUpdate(
      userId,
      { isVerified: true },
      { new: true }
    );

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Delete any pending verification tokens for this user
    await Verification.deleteMany({
      userId: new mongoose.Types.ObjectId(userId),
      type: VerificationType.EMAIL
    });

    res.status(200).json({
      message: 'User verified successfully',
      user: {
        id: user._id,
        username: user.username,
        email: user.email,
        isVerified: user.isVerified
      }
    });
  } catch (error: any) {
    logger.error(`Admin verify user error: ${error.message}`);
    res.status(500).json({ error: 'Failed to verify user' });
  }
});

// =============================================================================
// Testing Routes (previously in testing.routes.ts)
// =============================================================================

// Security guard: all testing endpoints are blocked in production unless
// TESTING_SECRET_TOKEN env var is set AND the caller supplies a matching
// x-testing-token header.  Without the env var the routes are fully disabled.
testingRouter.use((req: Request, res: Response, next: NextFunction) => {
  if (process.env.NODE_ENV === 'production') {
    const testingToken = process.env.TESTING_SECRET_TOKEN;
    if (!testingToken) {
      return res.status(403).json({ error: 'Testing endpoints are disabled in production' });
    }
    const providedToken = req.headers['x-testing-token'];
    if (!providedToken || providedToken !== testingToken) {
      return res.status(403).json({ error: 'Forbidden: invalid or missing testing token' });
    }
  }
  return next();
});

// Get verification token for a user (development/testing only)
testingRouter.get('/verification-token/:userId/:type?', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const type = req.params.type || VerificationType.EMAIL;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    // Validate that the userId is a valid ObjectId
    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }
    
    // Find the most recent verification token for this user and type
    const verification = await Verification.findOne({
      userId: new mongoose.Types.ObjectId(userId),
      type
    }).sort({ createdAt: -1 });
    
    if (!verification) {
      return res.status(404).json({ error: 'No verification token found for this user' });
    }
    
    res.status(200).json({
      token: verification.token,
      expires: verification.expires,
      type: verification.type
    });
  } catch (error: any) {
    logger.error(`Testing route error: ${error.message}`);
    res.status(500).json({ error: 'Failed to retrieve verification token' });
  }
});

// Directly verify a user's email without token (development/testing only)
testingRouter.post('/verify-user/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }
    
    // Validate that the userId is a valid ObjectId
    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }
    
    // Find and update the user
    const user = await User.findByIdAndUpdate(
      userId,
      { isVerified: true },
      { new: true }
    );
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    // Optionally: delete any pending verification tokens
    await Verification.deleteMany({
      userId: new mongoose.Types.ObjectId(userId),
      type: VerificationType.EMAIL
    });
    
    res.status(200).json({
      message: 'User email verified successfully',
      user: {
        id: user._id,
        username: user.username,
        email: user.email,
        isEmailVerified: user.isVerified
      }
    });
  } catch (error: any) {
    logger.error(`Testing route error: ${error.message}`);
    res.status(500).json({ error: 'Failed to verify user' });
  }
});

// Promote a user to admin without auth (development/testing bootstrap only)
testingRouter.post('/promote-admin/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;

    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    if (!mongoose.Types.ObjectId.isValid(userId)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    const user = await User.findByIdAndUpdate(
      userId,
      { role: UserRole.ADMIN, isVerified: true },
      { new: true }
    ).select('-password');

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.status(200).json({
      message: 'User promoted to admin successfully',
      user: {
        id: user._id,
        username: user.username,
        email: user.email,
        role: user.role,
        isEmailVerified: user.isVerified,
      },
    });
  } catch (error: any) {
    logger.error(`Testing route error: ${error.message}`);
    res.status(500).json({ error: 'Failed to promote user to admin' });
  }
});

// =============================================================================
// Route Configuration
// =============================================================================

// Register the routers to the main router
router.use('/auth', authRouter);
router.use('/', protectedRouter);
router.use('/admin', adminRouter);
router.use('/testing', testingRouter);

export default router;
export { authRouter, protectedRouter, adminRouter, testingRouter };