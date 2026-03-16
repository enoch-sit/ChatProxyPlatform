// src/api/admin.ts

/**
 * This file implements the client-side API for all administrative functions.
 * These functions correspond to the backend's admin-only REST endpoints and are
 * used to manage chatflows, users, and system settings. The implementation of
 * each function is based on direct evidence from the provided Python test and
 * administrative scripts, ensuring the frontend client matches the backend contract.
 */

import apiClient from './client';
import type { BulkAssignmentResult, AdminUser, CreditAllocation, AllocateCreditsPayload, SetCreditsPayload, RemoveCreditsPayload, AdjustCreditsPayload, SystemStats, CreateUserPayload, BatchCreateUsersPayload } from '../types/admin';
import type { Chatflow, ChatflowStats, ChatflowUser} from '../types/chatflow';

/**
 * Triggers a synchronization of chatflows from the Flowise instance.
 * Evidence: `quickTestChatflowsSync_01.py` shows a POST request to this endpoint.
 */
export const syncChatflows = async (): Promise<{ message: string }> => {
  const response = await apiClient.post('/api/v1/admin/chatflows/sync', {});
  return response.data;
};

/**
 * Fetches statistics about the chatflows. While not in a specific script, this
 * is a standard administrative dashboard feature.
 */
export const getChatflowStats = async (): Promise<ChatflowStats> => {
  const response = await apiClient.get('/api/v1/admin/chatflows/stats');
  return response.data;
};

/**
 * Retrieves a list of all available chatflows.
 * Evidence: `actual_admin.py` performs a GET request to this endpoint.
 */
export const getAllChatflows = async (): Promise<Chatflow[]> => {
  const response = await apiClient.get('/api/v1/admin/chatflows');
  return response.data.map((chatflow: any) => ({
    ...chatflow,
    id: chatflow.flowise_id, // 將 flowise_id 複製到 id 字段，確保兼容性
  }));
};

/**
 * Fetches the details of a single, specific chatflow by its ID.
 * Evidence: `actual_admin.py` includes a function to get a specific chatflow.
 */
export const getSpecificChatflow = async (id: string): Promise<Chatflow> => {
  const response = await apiClient.get(`/api/v1/admin/chatflows/${id}`);
  return response.data;
};

/**
 * Gets a list of all users assigned to a specific chatflow.
 * Evidence: `quickUserAccessListAndChat_03.py` calls this endpoint.
 */
export const getChatflowUsers = async (flowiseId: string): Promise<ChatflowUser[]> => {
  try {
    const response = await apiClient.get(`/api/v1/admin/chatflows/${flowiseId}/users`);
    
    // 確保返回正確的類型
    return response.data.map((user: any): ChatflowUser => ({
      _id: user.external_user_id || user._id || user.id, // make this more compatible 
      username: user.username || user.name || user.email.split('@')[0],
      email: user.email,
      role: user.role || 'user',
      assigned_at: user.assigned_at || user.created_at || new Date().toISOString(),
      external_user_id: user.external_user_id || user.externalId,
    }));
  } catch (error) {
    console.error('Error fetching chatflow users:', error);
    throw error;
  }
};

/**
 * Assigns a single user to a chatflow by their email address.
 * Evidence: `quickAddUserToChatflow_02.py` demonstrates this POST request.
 */
export const addUserToChatflow = async (id: string, email: string): Promise<{ message: string }> => {
  const response = await apiClient.post(`/api/v1/admin/chatflows/${id}/users`, {
    email
  });
  return response.data;
};

/**
 * Assigns multiple users to a chatflow in a single bulk operation.
 * Evidence: `actual_admin.py` contains logic for this bulk-add operation.
 */
export const bulkAddUsersToChatflow = async (id: string, emails: string[]): Promise<BulkAssignmentResult> => {
  const response = await apiClient.post(`/api/v1/admin/chatflows/${id}/users/bulk-add`, {
    emails
  });
  return response.data;
};

/**
 * Removes a user from a chatflow.
 * Evidence: `actual_admin.py` shows a DELETE request to this endpoint.
 */
export const removeUserFromChatflow = async (id: string, email: string): Promise<void> => {
  await apiClient.delete(`/api/v1/admin/chatflows/${id}/users`, {
    data: { email }
  });
};

/**
 * Syncs a user from the external auth provider to the local database.
 * Evidence: `actual_admin.py` contains a function for user synchronization.
 */
export const syncUserByEmail = async (email: string): Promise<{ message: string; user_id: string }> => {
  const response = await apiClient.post('/api/v1/admin/users/sync-by-email', {
    email
  });
  return response.data;
};

// =============================================================================
// User Management
// =============================================================================

export const listUsers = async (): Promise<AdminUser[]> => {
  const response = await apiClient.get('/api/v1/admin/users');
  // auth-service returns { users: [...] } or an array directly
  return Array.isArray(response.data) ? response.data : (response.data.users ?? []);
};

export const createUser = async (payload: CreateUserPayload): Promise<{ message: string; user: AdminUser }> => {
  const response = await apiClient.post('/api/v1/admin/users', payload);
  return response.data;
};

export const createUsersBatch = async (payload: BatchCreateUsersPayload): Promise<{ message: string; results: any[] }> => {
  const response = await apiClient.post('/api/v1/admin/users/batch', payload);
  return response.data;
};

export const verifyUser = async (userId: string): Promise<{ message: string }> => {
  const response = await apiClient.post(`/api/v1/admin/users/${userId}/verify`);
  return response.data;
};

export const deleteUser = async (userId: string): Promise<{ message: string }> => {
  const response = await apiClient.delete(`/api/v1/admin/users/${userId}`);
  return response.data;
};

export const updateUserRole = async (userId: string, role: string): Promise<{ message: string }> => {
  const response = await apiClient.put(`/api/v1/admin/users/${userId}/role`, { role });
  return response.data;
};

// =============================================================================
// Credit Management
// =============================================================================

export const listAllCredits = async (): Promise<CreditAllocation[]> => {
  const response = await apiClient.get('/api/v1/admin/credits');
  return Array.isArray(response.data) ? response.data : (response.data.allocations ?? []);
};

export const getUserCreditBalance = async (userId: string): Promise<CreditAllocation> => {
  const response = await apiClient.get(`/api/v1/admin/credits/balance/${userId}`);
  return response.data;
};

export const allocateCredits = async (payload: AllocateCreditsPayload): Promise<{ message: string }> => {
  const response = await apiClient.post('/api/v1/admin/credits/allocate', payload);
  return response.data;
};

export const setCredits = async (payload: SetCreditsPayload): Promise<{ message: string }> => {
  const response = await apiClient.post('/api/v1/admin/credits/set', payload);
  return response.data;
};

export const removeCredits = async (payload: RemoveCreditsPayload): Promise<{ message: string }> => {
  const response = await apiClient.delete('/api/v1/admin/credits/remove', { data: payload });
  return response.data;
};

export const adjustCredits = async (payload: AdjustCreditsPayload): Promise<{ message: string }> => {
  const response = await apiClient.put('/api/v1/admin/credits/adjust', payload);
  return response.data;
};

// =============================================================================
// Usage / Token Stats
// =============================================================================

export const getSystemStats = async (): Promise<SystemStats> => {
  const response = await apiClient.get('/api/v1/admin/usage/system-stats');
  return response.data;
};

export const getUserUsageStats = async (userId: string): Promise<any> => {
  const response = await apiClient.get(`/api/v1/admin/usage/stats/${userId}`);
  return response.data;
};

// =============================================================================
// Password Reset (admin/teacher)
// =============================================================================

export const resetUserPassword = async (userId: string, newPassword: string): Promise<{ message: string }> => {
  const response = await apiClient.put(`/api/v1/admin/users/${userId}/password`, { newPassword });
  return response.data;
};

// =============================================================================
// Admin Chat History
// =============================================================================

export interface AdminChatUser {
  user_id: string;
  username: string;
  email: string;
  role: string;
  session_count: number;
}

export interface AdminChatSession {
  session_id: string;
  chatflow_id: string;
  topic: string | null;
  is_active: boolean;
  created_at: string | null;
  last_activity_at: string | null;
  message_count: number;
}

export const adminListChatUsers = async (): Promise<AdminChatUser[]> => {
  const response = await apiClient.get('/api/v1/admin/chat/users');
  return response.data;
};

export const adminGetUserSessions = async (userId: string): Promise<AdminChatSession[]> => {
  const response = await apiClient.get(`/api/v1/admin/chat/users/${userId}/sessions`);
  return response.data;
};
