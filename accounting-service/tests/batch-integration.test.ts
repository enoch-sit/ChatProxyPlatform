/**
 * Batch Integration Tests for Accounting Service
 * Tests the integration between Auth Service batch user creation
 * and Accounting Service user account creation
 */

import { Request, Response } from 'express';
import { UserAccountController } from '../src/controllers/UserAccountController';
import UserAccountService from '../src/services/user-account.service';

jest.mock('../src/services/user-account.service');

describe('Batch Account Integration Tests', () => {
  let mockRequest: Partial<Request>;
  let mockResponse: Partial<Response>;
  
  beforeEach(() => {
    mockRequest = {
      body: {},
      user: { userId: 'admin-user-id' }
    };
    mockResponse = {
      status: jest.fn().mockReturnThis(),
      json: jest.fn().mockReturnThis()
    };
    jest.clearAllMocks();
  });
  
  describe('createAccountByAdmin - Batch Scenario', () => {
    
    test('should accept batch-created user from auth service with sub field', async () => {
      const authServiceBatchResponse = {
        userId: 'user-id-from-auth-batch-123',
        username: 'batchuser1',
        email: 'batchuser1@example.com',
        role: 'enduser'
      };
      
      mockRequest.body = {
        sub: authServiceBatchResponse.userId,
        email: authServiceBatchResponse.email,
        username: authServiceBatchResponse.username,
        role: authServiceBatchResponse.role
      };
      
      (UserAccountService.userExists as jest.Mock).mockResolvedValue(false);
      (UserAccountService.findByEmail as jest.Mock).mockResolvedValue(null);
      (UserAccountService.findOrCreateUser as jest.Mock).mockResolvedValue({
        userId: authServiceBatchResponse.userId,
        sub: authServiceBatchResponse.userId,
        email: authServiceBatchResponse.email,
        username: authServiceBatchResponse.username,
        role: authServiceBatchResponse.role,
        createdAt: new Date(),
        updatedAt: new Date()
      });
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.status).toHaveBeenCalledWith(201);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: authServiceBatchResponse.userId,
          sub: authServiceBatchResponse.userId,
          email: authServiceBatchResponse.email
        })
      );
    });
    
    test('should reject batch user creation without sub field', async () => {
      mockRequest.body = {
        email: 'batchuser2@example.com',
        username: 'batchuser2',
        role: 'enduser'
      };
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.status).toHaveBeenCalledWith(400);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('sub, email, and role are required')
        })
      );
    });
    
    test('should handle 409 conflict when user already exists (idempotent batch)', async () => {
      const batchUserId = 'duplicate-user-id-from-batch';
      
      mockRequest.body = {
        sub: batchUserId,
        email: 'duplicate@example.com',
        username: 'duplicateuser',
        role: 'enduser'
      };
      
      (UserAccountService.userExists as jest.Mock).mockResolvedValue(true);
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.status).toHaveBeenCalledWith(409);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('already exists')
        })
      );
    });
    
    test('should validate role normalization for batch users', async () => {
      mockRequest.body = {
        sub: 'batch-user-with-role-123',
        email: 'roletest@example.com',
        username: 'roletest',
        role: 'user'
      };
      
      (UserAccountService.userExists as jest.Mock).mockResolvedValue(false);
      (UserAccountService.findByEmail as jest.Mock).mockResolvedValue(null);
      (UserAccountService.findOrCreateUser as jest.Mock).mockResolvedValue({
        userId: 'batch-user-with-role-123',
        sub: 'batch-user-with-role-123',
        email: 'roletest@example.com',
        username: 'roletest',
        role: 'enduser',
        createdAt: new Date(),
        updatedAt: new Date()
      });
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(UserAccountService.findOrCreateUser).toHaveBeenCalledWith(
        expect.objectContaining({
          role: 'enduser'
        })
      );
      expect(mockResponse.status).toHaveBeenCalledWith(201);
    });
    
    test('should reject batch user with invalid sub format', async () => {
      mockRequest.body = {
        sub: 'invalid-short-id',
        email: 'test@example.com',
        username: 'test',
        role: 'enduser'
      };
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.status).toHaveBeenCalledWith(400);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('Invalid sub format')
        })
      );
    });
    
    test('should handle database errors gracefully', async () => {
      mockRequest.body = {
        sub: 'batch-user-db-error-123',
        email: 'dberror@example.com',
        username: 'dberror',
        role: 'enduser'
      };
      
      (UserAccountService.userExists as jest.Mock).mockResolvedValue(false);
      (UserAccountService.findByEmail as jest.Mock).mockResolvedValue(null);
      (UserAccountService.findOrCreateUser as jest.Mock).mockRejectedValue(
        new Error('Database connection failed')
      );
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.status).toHaveBeenCalledWith(500);
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          message: expect.stringContaining('internal server error'),
          error: expect.any(String)
        })
      );
    });
    
    test('should populate userId in response for credit allocation (critical)', async () => {
      const batchUserId = 'critical-batch-user-id-456';
      
      mockRequest.body = {
        sub: batchUserId,
        email: 'critical@example.com',
        username: 'critical',
        role: 'enduser'
      };
      
      (UserAccountService.userExists as jest.Mock).mockResolvedValue(false);
      (UserAccountService.findByEmail as jest.Mock).mockResolvedValue(null);
      (UserAccountService.findOrCreateUser as jest.Mock).mockResolvedValue({
        userId: batchUserId,
        sub: batchUserId,
        email: 'critical@example.com',
        username: 'critical',
        role: 'enduser',
        createdAt: new Date(),
        updatedAt: new Date()
      });
      
      await UserAccountController.createAccountByAdmin(
        mockRequest as Request,
        mockResponse as Response
      );
      
      expect(mockResponse.json).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: batchUserId,
          sub: batchUserId
        })
      );
    });
  });
});
