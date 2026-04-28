// src/routes/api.routes.ts
/**
 * Accounting Service API Routes
 * 
 * This file defines all API endpoints for the Accounting Service,
 * organizing endpoints into logical groups with appropriate authentication
 * and authorization middleware.
 * 
 * The Accounting Service provides endpoints for:
 * - Credit management (balance checks, allocations)
 * - Usage tracking (recording usage, retrieving statistics)
 * - Streaming session management (initialization, finalization)
 * 
 * Authentication:
 * - JWT required for all routes except /api/health
 * - Admin/supervisor role required for accessing other users' data
 * - Admin role required for system-wide operations
 * 
 * Base path: /api
 */
import { Router } from 'express';
import { authenticateJWT, requireAdmin, requireSupervisor } from '../middleware/jwt.middleware';

// Import controllers
import CreditController from '../controllers/credit.controller';
import StreamingSessionController from '../controllers/streaming-session.controller';
import UsageController from '../controllers/usage.controller';
import { UserAccountController } from '../controllers/UserAccountController';

const router = Router();

// ===== PUBLIC ENDPOINTS =====

/**
 * Health check endpoint (public)
 * GET /api/health
 * 
 * Returns basic service status information. [20250522_10:11_test_credit_check.py]
 * 
 * Response:
 *   200 OK: { status: string, service: string, version: string, timestamp: string }
 */
router.get('/health', (_, res) => {
  res.status(200).json({ 
    status: 'ok',
    service: 'accounting-service',
    version: process.env.npm_package_version || '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// ===== AUTHENTICATION MIDDLEWARE =====
// Apply authentication to all routes under these paths
router.use('/credits', authenticateJWT);
router.use('/streaming-sessions', authenticateJWT);
router.use('/usage', authenticateJWT);

// ===== CREDIT MANAGEMENT ENDPOINTS =====

/**
 * Get current user's credit balance
 * GET /api/credits/balance
 * 
 * Returns the authenticated user's current credit balance. [20250522_10:11_test_credit_check.py]
 * 
 * Authentication: JWT required
 * 
 * Response:
 *   200 OK: { totalCredits: number, activeAllocations: Array }
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If retrieval fails
 */
router.get('/credits/balance', CreditController.getUserBalance);

/**
 * Get current user's total credit balance
 * GET /api/credits/total-balance
 *
 * Returns the authenticated user's total credit balance.
 *
 * Authentication: JWT required
 *
 * Response:
 *   200 OK: { totalCredits: number }
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If retrieval fails
 */
router.get('/credits/total-balance', CreditController.getTotalCreditBalance);

/**
 * Check if user has sufficient credits
 * POST /api/credits/check
 * 
 * Verifies if the user has enough credits for an operation. [20250522_10:11_test_credit_check.py]
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   { requiredCredits: number } - Amount of credits needed for the operation
 * 
 * Response:
 *   200 OK: { sufficient: boolean, credits?: number, requiredCredits?: number, message?: string }
 *   400 Bad Request: If requiredCredits field is missing/invalid
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If check fails
 */
router.post('/credits/check', CreditController.checkCredits);

/**
 * Calculate credits for a specific operation
 * POST /api/credits/calculate
 * 
 * Calculates the credit cost for a specific operation.
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   { modelId: string, tokens: number }
 * 
 * Response:
 *   200 OK: { credits: number }
 *   400 Bad Request: If required fields are missing
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If calculation fails
 */
router.post('/credits/calculate', CreditController.calculateCredits);

/**
 * Deduct credits from the authenticated user's own account.
 * POST /api/credits/deduct
 *
 * Allows a user to deduct a specified amount of credits from their own balance.
 *
 * Authentication: JWT required
 *
 * Request body:
 *   {
 *     "credits": number (required)
 *   }
 *
 * Response:
 *   200 OK: { success: boolean, message: string, remainingBalance: number }
 *   400 Bad Request: If 'credits' is missing, invalid, or exceeds balance.
 *   401 Unauthorized: If no user authenticated.
 *   500 Server Error: If deduction fails.
 */
router.post('/credits/deduct', CreditController.deductUserCredits);

/**
 * Get a user's credit balance (admin and supervisors only)
 * GET /api/credits/balance/:userId
 * 
 * Returns a specific user's credit balance (admin/supervisor only).
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Path parameters:
 *   userId: string - ID of the user to check
 * 
 * Response:
 *   200 OK: { totalCredits: number, activeAllocations: Array }
 *   400 Bad Request: If userId is missing
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   404 Not Found: If user doesn't exist
 *   500 Server Error: If retrieval fails
 */
router.get('/credits/balance/:userId', requireSupervisor, CreditController.getUserBalanceByAdmin);

/**
 * Allocate credits to a user (admin and supervisors only)
 * POST /api/credits/allocate
 * 
 * Allocates credits to a specific user (admin/supervisor only). [20250522_10:11_test_credit_check.py]
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Request body:
 *   { 
 *     userId: string,
 *     credits: number,
 *     expiryDays: number (optional),
 *     notes: string (optional)
 *   }
 * 
 * Response:
 *   201 Created: { id: string, userId: string, totalCredits: number, remainingCredits: number, expiresAt: string }
 *   400 Bad Request: If required fields are missing
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If allocation fails
 */
router.post('/credits/allocate', requireSupervisor, CreditController.allocateCredits);

/**
 * Batch-allocate credits to multiple users (admin and supervisors only)
 * POST /api/credits/allocate-batch
 *
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 *
 * Request body:
 *   { allocations: Array<{ userId: string, credits: number, expiryDays?: number, notes?: string }> }
 *
 * Response:
 *   200 OK: { results: Array<{ userId, success, message }>, summary: { total, successful, failed } }
 */
router.post('/credits/allocate-batch', requireSupervisor, CreditController.allocateBatchCredits);

/**
 * Allocate credits to a user by email (Supervisor/Admin only)
 * POST /api/credits/allocate-by-email
 *
 * Allocates a specified amount of credits to a user identified by their email.
 *
 * Authentication: JWT required, Supervisor/Admin role required
 *
 * Request body:
 *   {
 *     email: string,     // Email of the user to allocate credits to
 *     credits: number,   // Amount of credits to allocate
 *     expiryDays?: number, // Optional: Number of days until credits expire
 *     notes?: string     // Optional: Notes for the allocation
 *   }
 *
 * Response:
 *   200 OK: { message: string, allocationId: string }
 *   400 Bad Request: If required fields are missing/invalid (e.g., invalid email format)
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user is not a admin
 *   404 Not Found: If user with the given email is not found
 *   500 Server Error: If allocation fails
 */
router.post('/credits/allocate-by-email', requireAdmin, CreditController.allocateCreditsByEmail); // New controller method


/**
 * Set absolute credit amount for a user (admin and supervisors only)
 * POST /api/credits/set
 * 
 * Sets the total credit amount for a specific user, replacing current balance.
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Request body:
 *   { 
 *     userId: string,
 *     credits: number,
 *     expiryDays: number (optional),
 *     notes: string (optional)
 *   }
 * 
 * Response:
 *   200 OK: { userId: string, previousCredits: number, newCredits: number, message: string }
 *   400 Bad Request: If required fields are missing or credits is negative
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   404 Not Found: If user doesn't exist
 *   500 Server Error: If operation fails
 */
router.post('/credits/set', requireSupervisor, CreditController.setCredits);

/**
 * Remove/deduct credits from a user (admin and supervisors only)
 * DELETE /api/credits/remove
 * 
 * Removes or deducts a specific amount of credits from a user.
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Request body:
 *   { 
 *     userId: string,
 *     credits: number,
 *     notes: string (optional)
 *   }
 * 
 * Response:
 *   200 OK: { userId: string, previousCredits: number, newCredits: number, removedCredits: number, message: string }
 *   400 Bad Request: If required fields are missing, credits is negative, or insufficient credits
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   404 Not Found: If user doesn't exist
 *   500 Server Error: If operation fails
 */
router.delete('/credits/remove', requireSupervisor, CreditController.removeCredits);

/**
 * Adjust credits for a user (admin and supervisors only)
 * PUT /api/credits/adjust
 * 
 * Adjusts credits by a positive or negative amount (add or subtract).
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Request body:
 *   { 
 *     userId: string,
 *     adjustment: number, // positive to add, negative to subtract
 *     expiryDays: number (optional, only for positive adjustments),
 *     notes: string (optional)
 *   }
 * 
 * Response:
 *   200 OK: { userId: string, previousCredits: number, newCredits: number, adjustment: number, message: string }
 *   400 Bad Request: If required fields are missing or adjustment would result in negative balance
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   404 Not Found: If user doesn't exist
 *   500 Server Error: If operation fails
 */
router.put('/credits/adjust', requireSupervisor, CreditController.adjustCredits);

/**
 * Get all credit allocations for all users (admin and supervisors only)
 * GET /api/credits/allocations/all
 *
 * Returns a list of all credit allocations, ordered by user.
 *
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 *
 * Response:
 *   200 OK: { allocations: Array }
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If retrieval fails
 */
router.get('/credits/allocations/all', requireSupervisor, CreditController.getAllAllocations);

/**
 * Get current non-expired credit totals for all users (admin and supervisors only)
 * GET /api/credits/current-balances
 */
router.get('/credits/current-balances', requireSupervisor, CreditController.getAllCurrentBalances);

/**
 * Get directory of ALL user accounts (including zero-balance) with aggregated
 * active credit info (admin/supervisor only).
 * GET /api/credits/users-directory
 */
router.get('/credits/users-directory', requireSupervisor, CreditController.getUsersDirectory);

// ===== STREAMING SESSION ENDPOINTS =====

/**
 * Initialize a streaming session
 * POST /api/streaming-sessions/initialize
 * 
 * Creates a new streaming session and pre-allocates credits.
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   {
 *     sessionId: string,
 *     modelId: string,
 *     estimatedTokens: number
 *   }
 * 
 * Response:
 *   201 Created: { sessionId: string, allocatedCredits: number, status: string }
 *   400 Bad Request: If required fields are missing
 *   401 Unauthorized: If no user authenticated
 *   402 Payment Required: If user has insufficient credits
 *   500 Server Error: If initialization fails
 */
router.post('/streaming-sessions/initialize', StreamingSessionController.initializeSession);

/**
 * Finalize a streaming session
 * POST /api/streaming-sessions/finalize
 * 
 * Completes a streaming session and reconciles credit usage.
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   {
 *     sessionId: string,
 *     actualTokens: number,
 *     success: boolean (optional)
 *   }
 * 
 * Response:
 *   200 OK: { sessionId: string, actualCredits: number, refund: number }
 *   400 Bad Request: If required fields are missing
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If finalization fails
 */
router.post('/streaming-sessions/finalize', StreamingSessionController.finalizeSession);

/**
 * Abort a streaming session
 * POST /api/streaming-sessions/abort
 * 
 * Aborts an active streaming session and handles partial credits.
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   {
 *     sessionId: string,
 *     tokensGenerated: number (optional)
 *   }
 * 
 * Response:
 *   200 OK: { sessionId: string, partialCredits: number, refund: number }
 *   400 Bad Request: If sessionId is missing
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If abort fails
 */
router.post('/streaming-sessions/abort', StreamingSessionController.abortSession);

/**
 * Get active sessions for the current user
 * GET /api/streaming-sessions/active
 * 
 * Returns all active streaming sessions for the current user.
 * 
 * Authentication: JWT required
 * 
 * Response:
 *   200 OK: Array of active session objects
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If retrieval fails
 */
router.get('/streaming-sessions/active', StreamingSessionController.getActiveSessions);

/**
 * Get active sessions for a specific user (admin and supervisors only)
 * GET /api/streaming-sessions/active/:userId
 * 
 * Returns active streaming sessions for a specific user.
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Path parameters:
 *   userId: string - ID of the user to check
 * 
 * Response:
 *   200 OK: Array of active session objects for the user
 *   400 Bad Request: If userId is missing
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If retrieval fails
 */
router.get('/streaming-sessions/active/:userId', requireSupervisor, StreamingSessionController.getUserActiveSessions);

/**
 * Get all active sessions (admin only)
 * GET /api/streaming-sessions/active/all
 * 
 * Returns all active streaming sessions across all users.
 * 
 * Authentication: JWT required
 * Authorization: Admin role required
 * 
 * Response:
 *   200 OK: Array of all active session objects
 *   403 Forbidden: If user lacks admin permission
 *   500 Server Error: If retrieval fails
 */
router.get('/streaming-sessions/active/all', requireAdmin, StreamingSessionController.getAllActiveSessions);

/**
 * Get recent sessions (active + recently completed) (admin and supervisors only)
 * GET /api/streaming-sessions/recent
 * 
 * Returns recent streaming sessions (active and recently completed).
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Query parameters:
 *   minutes: number (optional) - Look back period in minutes, default 5
 * 
 * Response:
 *   200 OK: { sessions: Array, timestamp: string, filter: Object }
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If retrieval fails
 */
router.get('/streaming-sessions/recent', requireSupervisor, StreamingSessionController.getRecentSessions);

/**
 * Get recent sessions for a specific user (admin and supervisors only)
 * GET /api/streaming-sessions/recent/:userId
 * 
 * Returns recent streaming sessions for a specific user.
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Path parameters:
 *   userId: string - ID of the user to check
 * 
 * Query parameters:
 *   minutes: number (optional) - Look back period in minutes, default 5
 * 
 * Response:
 *   200 OK: { sessions: Array, timestamp: string, filter: Object }
 *   400 Bad Request: If userId is missing
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If retrieval fails
 */
router.get('/streaming-sessions/recent/:userId', requireSupervisor, StreamingSessionController.getUserRecentSessions);

// ===== USAGE TRACKING ENDPOINTS =====

/**
 * Record a usage event
 * POST /api/usage/record
 * 
 * Records a service usage event for the current user.
 * 
 * Authentication: JWT required
 * 
 * Request body:
 *   {
 *     service: string,
 *     operation: string,
 *     credits: number,
 *     metadata: object (optional)
 *   }
 * 
 * Response:
 *   201 Created: { id: string, service: string, operation: string, credits: number, timestamp: string }
 *   400 Bad Request: If required fields are missing or invalid
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If recording fails
 */
router.post('/usage/record', UsageController.recordUsage);

/**
 * Get current user's usage statistics
 * GET /api/usage/stats
 * 
 * Returns usage statistics for the current user.
 * 
 * Authentication: JWT required
 * 
 * Query parameters:
 *   startDate: ISO date string (optional)
 *   endDate: ISO date string (optional)
 * 
 * Response:
 *   200 OK: { totalRecords: number, totalCredits: number, byService: object, byDay: object, byModel: object, recentActivity: Array }
 *   401 Unauthorized: If no user authenticated
 *   500 Server Error: If retrieval fails
 */
router.get('/usage/stats', UsageController.getUserStats);

/**
 * Get usage statistics for a specific user (admin and supervisors only)
 * GET /api/usage/stats/:userId
 * 
 * Returns usage statistics for a specific user.
 * 
 * Authentication: JWT required
 * Authorization: Admin or Supervisor role required
 * 
 * Path parameters:
 *   userId: string - ID of the user to check
 * 
 * Query parameters:
 *   startDate: ISO date string (optional)
 *   endDate: ISO date string (optional)
 * 
 * Response:
 *   200 OK: { totalRecords: number, totalCredits: number, byService: object, byDay: object, byModel: object, recentActivity: Array }
 *   400 Bad Request: If userId is missing
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks permission
 *   500 Server Error: If retrieval fails
 */
router.get('/usage/stats/:userId', requireSupervisor, UsageController.getUserStatsByAdmin);

/**
 * Get system-wide usage statistics (admin only)
 * GET /api/usage/system-stats
 * 
 * Returns system-wide usage statistics across all users.
 * 
 * Authentication: JWT required
 * Authorization: Admin role required
 * 
 * Query parameters:
 *   startDate: ISO date string (optional)
 *   endDate: ISO date string (optional)
 * 
 * Response:
 *   200 OK: { totalRecords: number, totalCredits: number, byUser: object, byService: object, byDay: object, byModel: object }
 *   401 Unauthorized: If no user authenticated
 *   403 Forbidden: If user lacks admin permission
 *   500 Server Error: If retrieval fails
 */
router.get('/usage/system-stats', requireAdmin, UsageController.getSystemStats);

// ===== USER ACCOUNT MANAGEMENT ENDPOINTS (ADMIN) =====

/**
 * Create a new user account (Admin only)
 * POST /api/admin/users
 *
 * Allows an administrator to create a new user account record in the Accounting service
 * using a specific userId (UUID), typically obtained from the primary Authentication service.
 *
 * Authentication: JWT required, Admin role required
 *
 * Request body:
 *   {
 *     userId: string,       // Required: The UUID for the new user (must be unique)
 *     email: string,        // Email address for the new user (must be unique)
 *     username?: string,     // Optional: Username for the new user
 *     role: string          // Role for the new user (e.g., 'enduser', 'supervisor', 'admin')
 *   }
 *
 * Response:
 *   201 Created: { userId: string, email: string, username: string, role: string, createdAt: date, updatedAt: date } - Details of the created user.
 *   400 Bad Request: If required fields (userId, email, role) are missing or invalid (e.g., invalid UUID format for userId, invalid email format, invalid role).
 *   401 Unauthorized: If the request lacks a valid JWT.
 *   403 Forbidden: If the authenticated user is not an admin.
 *   409 Conflict: If a user with the given userId or email already exists.
 *   500 Internal Server Error: If an unexpected error occurs during account creation.
 */
router.post(
    '/admin/users',
    requireAdmin,
    UserAccountController.createAccountByAdmin
);

/**
 * Idempotently ensure a UserAccount row exists for a given user. Designed to
 * be called by other services (e.g. auth-service) right after they create a
 * user, so admins can immediately allocate credits without waiting for the
 * user's first login. Safe to retry; returns 200 if account already existed,
 * 201 if newly created.
 *
 * POST /api/users/ensure
 * Auth: JWT, supervisor/admin/teacher
 * Body: { sub | userId: string, email: string, username?: string, role?: string }
 */
router.post(
    '/users/ensure',
    requireSupervisor,
    UserAccountController.ensureAccount
);

export default router;