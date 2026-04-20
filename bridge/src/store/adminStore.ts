// src/store/adminStore.ts
import { create } from 'zustand';
import {
  getAllChatflows,
  getChatflowStats,
  getSpecificChatflow,
  getChatflowUsers,
  addUserToChatflow,
  bulkAddUsersToChatflow as bulkAddUsersToChatflowApi,
  removeUserFromChatflow,
  listUsers,
  createUser,
  createUsersBatch,
  verifyUser,
  deleteUser,
  updateUserRole,
  updateUsersRolesBatch as updateUsersRolesBatchApi,
  listAllCredits,
  allocateCredits,
  setCredits,
  removeCredits,
  adjustCredits,
  getSystemStats,
  syncChatflows as syncChatflowsApi,
} from '../api/admin';
import type { Chatflow, ChatflowUser, ChatflowStats, ChatflowSyncResult } from '../types/chatflow';
import type {
  AdminUser,
  CreditAllocation,
  AllocateCreditsPayload,
  SetCreditsPayload,
  RemoveCreditsPayload,
  AdjustCreditsPayload,
  SystemStats,
  CreateUserPayload,
  BatchCreateUsersPayload,
  BatchRoleUpdateItem,
} from '../types/admin';

interface AdminState {
  // Chatflow
  chatflows: Chatflow[];
  stats: ChatflowStats | null;
  selectedChatflow: Chatflow | null;
  chatflowUsers: ChatflowUser[];
  // Users
  users: AdminUser[];
  // Credits
  creditAllocations: CreditAllocation[];
  // Usage
  systemStats: SystemStats | null;
  // Shared
  isLoading: boolean;
  error: string | null;
}

interface AdminActions {
  // Chatflow
  fetchChatflows: () => Promise<void>;
  fetchStats: () => Promise<void>;
  fetchChatflowDetails: (flowiseId: string) => Promise<void>;
  fetchChatflowUsers: (flowiseId: string) => Promise<void>;
  addUserToChatflow: (flowiseId: string, userEmail: string) => Promise<void>;
  removeUserFromChatflow: (flowiseId: string, userEmail: string) => Promise<void>;
  bulkAddUsersToChatflow: (flowiseId: string, userEmails: string[]) => Promise<{ successful: number; failed: string[] }>;
  syncChatflows: () => Promise<ChatflowSyncResult>;
  setSelectedChatflow: (chatflow: Chatflow | null) => void;
  clearChatflowUsers: () => void;
  // Users
  fetchUsers: () => Promise<void>;
  createUser: (payload: CreateUserPayload) => Promise<void>;
  createUsersBatch: (payload: BatchCreateUsersPayload) => Promise<{ message: string; results: any[] }>;
  verifyUser: (userId: string) => Promise<void>;
  deleteUser: (userId: string) => Promise<void>;
  updateUserRole: (userId: string, role: string) => Promise<void>;
  updateUsersRolesBatch: (updates: BatchRoleUpdateItem[]) => Promise<{ successful: number; failed: Array<{ userId: string; message: string }> }>;
  // Credits
  fetchAllCredits: () => Promise<void>;
  allocateCredits: (payload: AllocateCreditsPayload) => Promise<void>;
  setCredits: (payload: SetCreditsPayload) => Promise<void>;
  removeCredits: (payload: RemoveCreditsPayload) => Promise<void>;
  adjustCredits: (payload: AdjustCreditsPayload) => Promise<void>;
  // Usage
  fetchSystemStats: () => Promise<void>;
  // Shared
  clearError: () => void;
}

export const useAdminStore = create<AdminState & AdminActions>((set) => ({
  // Initial state
  chatflows: [],
  stats: null,
  selectedChatflow: null,
  chatflowUsers: [],
  users: [],
  creditAllocations: [],
  systemStats: null,
  isLoading: false,
  error: null,

  // Actions
  fetchChatflows: async () => {
    set({ isLoading: true, error: null });
    try {
      const chatflows = await getAllChatflows();
      set({ chatflows, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to fetch chatflows';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  fetchStats: async () => {
    set({ isLoading: true, error: null });
    try {
      const stats = await getChatflowStats();
      set({ stats, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to fetch stats';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  fetchChatflowDetails: async (flowiseId: string) => {
    set({ isLoading: true, error: null });
    try {
      const chatflow = await getSpecificChatflow(flowiseId);
      set({ selectedChatflow: chatflow, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to fetch chatflow details';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  fetchChatflowUsers: async (flowiseId: string) => {
    set({ isLoading: true, error: null });
    try {
      const users = await getChatflowUsers(flowiseId);
      set({ chatflowUsers: users, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to fetch chatflow users';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  addUserToChatflow: async (flowiseId: string, userEmail: string) => {
    set({ isLoading: true, error: null });
    try {
      await addUserToChatflow(flowiseId, userEmail);
      // 重新獲取用戶列表以獲得最新的 ChatflowUser 數據
      const users = await getChatflowUsers(flowiseId);
      set({ chatflowUsers: users, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to add user to chatflow';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  removeUserFromChatflow: async (flowiseId: string, userEmail: string) => {
    set({ isLoading: true, error: null });
    try {
      await removeUserFromChatflow(flowiseId, userEmail);
      // 重新獲取用戶列表
      const users = await getChatflowUsers(flowiseId);
      set({ chatflowUsers: users, isLoading: false });
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to remove user from chatflow';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  bulkAddUsersToChatflow: async (flowiseId: string, userEmails: string[]) => {
    set({ isLoading: true, error: null });
    try {
      const result = await bulkAddUsersToChatflowApi(flowiseId, userEmails);
      const successful = Array.isArray(result.successful_assignments)
        ? result.successful_assignments.length
        : Number(result.successful_assignments || 0);
      const failed = (result.failed_assignments || []).map((assignment) => assignment.email);

      // 重新獲取用戶列表
      const users = await getChatflowUsers(flowiseId);
      set({ chatflowUsers: users, isLoading: false });

      return { successful, failed };
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to bulk add users to chatflow';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  syncChatflows: async () => {
    set({ isLoading: true, error: null });
    try {
      const syncResult = await syncChatflowsApi();
      
      // Refresh chatflows and stats after sync
      const [chatflows, stats] = await Promise.all([
        getAllChatflows(),
        getChatflowStats(),
      ]);
      
      set({ chatflows, stats, isLoading: false });
      return syncResult;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to sync chatflows';
      set({ isLoading: false, error: errorMessage });
      throw error;
    }
  },

  clearError: () => set({ error: null }),

  setSelectedChatflow: (chatflow: Chatflow | null) => {
    set({ selectedChatflow: chatflow });
    // 清除之前的用戶列表
    if (!chatflow) {
      set({ chatflowUsers: [] });
    }
  },

  clearChatflowUsers: () => set({ chatflowUsers: [] }),

  // -------------------------------------------------------------------------
  // User Management
  // -------------------------------------------------------------------------

  fetchUsers: async () => {
    set({ isLoading: true, error: null });
    try {
      const users = await listUsers();
      set({ users, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to fetch users' });
      throw error;
    }
  },

  createUser: async (payload: CreateUserPayload) => {
    set({ isLoading: true, error: null });
    try {
      await createUser(payload);
      const users = await listUsers();
      set({ users, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to create user' });
      throw error;
    }
  },

  createUsersBatch: async (payload: BatchCreateUsersPayload) => {
    set({ isLoading: true, error: null });
    try {
      const result = await createUsersBatch(payload);
      const users = await listUsers();
      set({ users, isLoading: false });
      return result;
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to batch create users' });
      throw error;
    }
  },

  verifyUser: async (userId: string) => {
    set({ isLoading: true, error: null });
    try {
      await verifyUser(userId);
      const users = await listUsers();
      set({ users, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to verify user' });
      throw error;
    }
  },

  deleteUser: async (userId: string) => {
    set({ isLoading: true, error: null });
    try {
      await deleteUser(userId);
      const users = await listUsers();
      set({ users, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to delete user' });
      throw error;
    }
  },

  updateUserRole: async (userId: string, role: string) => {
    set({ isLoading: true, error: null });
    try {
      await updateUserRole(userId, role);
      const users = await listUsers();
      set({ users, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to update user role' });
      throw error;
    }
  },

  updateUsersRolesBatch: async (updates: BatchRoleUpdateItem[]) => {
    set({ isLoading: true, error: null });
    try {
      const result = await updateUsersRolesBatchApi(updates);
      const users = await listUsers();
      set({ users, isLoading: false });

      const failed = result.results
        .filter((item) => !item.success)
        .map((item) => ({ userId: item.userId, message: item.message }));

      return {
        successful: result.summary.successful,
        failed,
      };
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to batch update user roles' });
      throw error;
    }
  },

  // -------------------------------------------------------------------------
  // Credit Management
  // -------------------------------------------------------------------------

  fetchAllCredits: async () => {
    set({ isLoading: true, error: null });
    try {
      const creditAllocations = await listAllCredits();
      set({ creditAllocations, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to fetch credits' });
      throw error;
    }
  },

  allocateCredits: async (payload: AllocateCreditsPayload) => {
    set({ isLoading: true, error: null });
    try {
      await allocateCredits(payload);
      const creditAllocations = await listAllCredits();
      set({ creditAllocations, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to allocate credits' });
      throw error;
    }
  },

  setCredits: async (payload: SetCreditsPayload) => {
    set({ isLoading: true, error: null });
    try {
      await setCredits(payload);
      const creditAllocations = await listAllCredits();
      set({ creditAllocations, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to set credits' });
      throw error;
    }
  },

  removeCredits: async (payload: RemoveCreditsPayload) => {
    set({ isLoading: true, error: null });
    try {
      await removeCredits(payload);
      const creditAllocations = await listAllCredits();
      set({ creditAllocations, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to remove credits' });
      throw error;
    }
  },

  adjustCredits: async (payload: AdjustCreditsPayload) => {
    set({ isLoading: true, error: null });
    try {
      await adjustCredits(payload);
      const creditAllocations = await listAllCredits();
      set({ creditAllocations, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to adjust credits' });
      throw error;
    }
  },

  // -------------------------------------------------------------------------
  // Usage / Token Stats
  // -------------------------------------------------------------------------

  fetchSystemStats: async () => {
    set({ isLoading: true, error: null });
    try {
      const systemStats = await getSystemStats();
      set({ systemStats, isLoading: false });
    } catch (error) {
      set({ isLoading: false, error: error instanceof Error ? error.message : 'Failed to fetch system stats' });
      throw error;
    }
  },
}));