import { Request, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import UserAccountService from '../services/user-account.service'; // Assuming the service is exported as default
import logger from '../utils/logger'; // Assuming a logger utility
import UserAccount from '../models/user-account.model'; // Import UserAccount model for type checking

const isValidIdentifier = (id:string) => {
    const flexibleHexRegex = /^[0-9a-f]{24,32}$/i; // Allows IDs between 24 and 32 characters
    return flexibleHexRegex.test(id);
};

export class UserAccountController {
    /**
     * Creates a new user account. Intended for use by administrators.
     * The administrator must provide the user's 'sub' (JWT subject claim from Auth service),
     * email, and role.
     *
     * @param req Express Request object. Expected body: { sub: string, email: string, username?: string, role: string }
     * @param res Express Response object.
     */
    static async createAccountByAdmin(req: Request, res: Response): Promise<Response> {
        const { sub, email, username, role } = req.body; // Expect 'sub' from body
        const performingAdminId = req.user?.userId;

        // Validate essential input parameters
        if (!sub || typeof sub !== 'string' || !email || typeof email !== 'string' || !role || typeof role !== 'string') {
            logger.warn(`UserAccountController.createAccountByAdmin - Invalid input from admin ${performingAdminId}`, { body: req.body });
            return res.status(400).json({ message: 'Invalid request body. sub, email, and role are required.' });
        }

        // Validate 'sub' format
        if (!isValidIdentifier(sub)) {
            logger.warn(`UserAccountController.createAccountByAdmin - Invalid sub format '${sub}' by admin ${performingAdminId}`);
            return res.status(400).json({ message: 'Invalid sub format. Must be a valid identifier from the Authentication service.' });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            logger.warn(`UserAccountController.createAccountByAdmin - Invalid email format by admin ${performingAdminId}`, { email });
            return res.status(400).json({ message: 'Invalid email format provided.' });
        }

        // Ensure 'user' is treated as 'enduser' if that's the canonical role name, or adjust valid roles.
        const validRoles = ['enduser', 'supervisor', 'admin'];
        const normalizedRole = role === 'user' ? 'enduser' : role; // Normalize 'user' to 'enduser'

        if (!validRoles.includes(normalizedRole)) {
            logger.warn(`UserAccountController.createAccountByAdmin - Invalid role '${role}' (normalized to '${normalizedRole}') specified by admin ${performingAdminId}`);
            return res.status(400).json({ message: `Invalid role specified. Valid roles are: ${validRoles.join(', ')}.` });
        }

        try {
            // Check if user with this 'sub' (as userId PK) already exists
            // UserAccountService.userExists expects the PK, which is `userId` field in the model,
            // and we are using the provided 'sub' as this PK.
            const existingUserById = await UserAccountService.userExists(sub);
            if (existingUserById) {
                logger.warn(`UserAccountController.createAccountByAdmin - Attempt to create user with existing sub (userId) '${sub}' by admin ${performingAdminId}`);
                return res.status(409).json({ message: `User with identifier (sub) '${sub}' already exists.` });
            }

            // Check if user with this email already exists
            const existingUserByEmail = await UserAccountService.findByEmail(email);
            if (existingUserByEmail) {
                // If email exists, ensure it's not for a different sub/userId.
                // This check is important if email must be unique across all users.
                if (existingUserByEmail.userId !== sub) { // Assuming findByEmail returns the full UserAccount object
                    logger.warn(`UserAccountController.createAccountByAdmin - Attempt to create user with existing email '${email}' (associated with different sub ${existingUserByEmail.userId}) by admin ${performingAdminId}`);
                    return res.status(409).json({ message: `User with email '${email}' already exists for a different user.` });
                }
                // If email exists for the same sub, it's an inconsistent state or this check is redundant if sub check passed.
                // For now, we assume sub is the primary unique identifier.
            }

            const finalUsername = username || email.split('@')[0] || `user_${sub.substring(0, 8)}`;

            logger.info(`UserAccountController.createAccountByAdmin - Admin ${performingAdminId} attempting to create user: sub='${sub}', email='${email}', username='${finalUsername}', role='${normalizedRole}'`);

            // findOrCreateUser will use the provided 'sub' as the 'userId' (PK).
            // We also pass 'sub' explicitly for the new 'sub' field in the model.
            const newUserAccount = await UserAccountService.findOrCreateUser({
                userId: sub, // Use the 'sub' from request body as the primary key 'userId'
                email,
                username: finalUsername,
                role: normalizedRole,
                sub: sub // Explicitly pass 'sub' for the new 'sub' field in the UserAccount model
            });

            logger.info(`UserAccountController.createAccountByAdmin - Admin ${performingAdminId} successfully created user ${newUserAccount.userId} (sub: ${newUserAccount.sub}) with email ${email}`);
            
            const responseUser = {
                userId: newUserAccount.userId, // This is the 'sub'
                sub: newUserAccount.sub,       // This is also the 'sub'
                email: newUserAccount.email,
                username: newUserAccount.username,
                role: newUserAccount.role,
                createdAt: newUserAccount.createdAt,
                updatedAt: newUserAccount.updatedAt,
            };

            return res.status(201).json(responseUser);

        } catch (error: any) {
            logger.error(`UserAccountController.createAccountByAdmin - Error creating account for sub '${sub}', email '${email}' by admin ${performingAdminId}:`, error);
            return res.status(500).json({
                message: 'Failed to create user account due to an internal server error.',
                error: error instanceof Error ? error.message : String(error)
            });
        }
    }

    /**
     * Idempotent "ensure" endpoint. Used by other services (e.g. auth-service)
     * to make sure a UserAccount row exists for a given user immediately after
     * that user is created in the auth database, so admins can find and
     * allocate credits to them before the user has logged in once.
     *
     * Accepts the same shape as createAccountByAdmin (sub/email/username/role)
     * but is safe to call repeatedly: returns 200 with the existing account if
     * the user is already known, 201 if a new row was created.
     *
     * Authentication: JWT, supervisor/admin/teacher (requireSupervisor).
     */
    static async ensureAccount(req: Request, res: Response): Promise<Response> {
        const { sub, userId, email, username, role } = req.body;
        const effectiveSub = (typeof sub === 'string' && sub) || (typeof userId === 'string' && userId) || '';
        const callerId = req.user?.userId;

        if (!effectiveSub || !email || typeof email !== 'string') {
            return res.status(400).json({ message: 'sub (or userId) and email are required.' });
        }

        if (!isValidIdentifier(effectiveSub)) {
            return res.status(400).json({ message: 'Invalid sub format.' });
        }

        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            return res.status(400).json({ message: 'Invalid email format provided.' });
        }

        const normalizedRole = role === 'user' ? 'enduser' : (role || 'enduser');
        const finalUsername = username || email.split('@')[0] || `user_${effectiveSub.substring(0, 8)}`;

        try {
            const existed = await UserAccountService.userExists(effectiveSub);
            const account = await UserAccountService.findOrCreateUser({
                userId: effectiveSub,
                email,
                username: finalUsername,
                role: normalizedRole,
                sub: effectiveSub,
            });

            logger.info(`UserAccountController.ensureAccount - caller=${callerId} sub=${effectiveSub} existed=${existed}`);

            const responseUser = {
                userId: account.userId,
                sub: account.sub,
                email: account.email,
                username: account.username,
                role: account.role,
                createdAt: account.createdAt,
                updatedAt: account.updatedAt,
            };

            return res.status(existed ? 200 : 201).json(responseUser);
        } catch (error: any) {
            logger.error(`UserAccountController.ensureAccount - Error for sub '${effectiveSub}' by caller ${callerId}:`, error);
            return res.status(500).json({
                message: 'Failed to ensure user account.',
                error: error instanceof Error ? error.message : String(error),
            });
        }
    }
}