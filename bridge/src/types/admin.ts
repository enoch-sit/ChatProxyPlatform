// src/types/admin.ts

/**
 * Represents the result of a bulk user assignment operation.
 * This provides clear feedback to the admin on the success of the operation.
 */
export interface BulkAssignmentResult {
  successful_assignments: Array<{
    identifier: string;
    email: string;
    username?: string;
    status: string;
    message?: string;
  }> | number;
  failed_assignments: Array<{ 
    identifier: string;
    email?: string;
    username?: string;
    reason?: string;
    status?: string;
    message?: string;
  }>;
}

export interface BatchRoleUpdateItem {
  userId: string;
  role: string;
}

export interface BatchRoleUpdateResult {
  userId: string;
  success: boolean;
  message: string;
  role?: string;
}

export interface BatchRoleUpdateResponse {
  message: string;
  results: BatchRoleUpdateResult[];
  summary: {
    total: number;
    successful: number;
    failed: number;
  };
}

// =============================================================================
// User Management
// =============================================================================

export interface AdminUser {
  _id: string;
  username: string;
  email: string;
  role: 'admin' | 'supervisor' | 'teacher' | 'user' | 'enduser';
  isVerified: boolean;
  createdAt: string;
  updatedAt?: string;
}

export interface CreateUserPayload {
  username: string;
  email?: string;
  password: string;
  role?: string;
  skipVerification?: boolean;
}

export interface BatchCreateUsersPayload {
  users: CreateUserPayload[];
  skipVerification?: boolean;
}

// =============================================================================
// Credit Management
// =============================================================================

export interface CreditAllocation {
  userId: string;
  totalCredits: number;
  usedCredits?: number;
  remainingCredits?: number;
  expiresAt?: string | null;
  allocatedAt?: string;
  username?: string;
  email?: string;
}

export interface CurrentCreditBalance {
  userId: string;
  username?: string;
  email?: string;
  currentCredits: number;
  activeAllocationCount: number;
}

export interface AllocateCreditsPayload {
  userId: string;
  credits: number;
  expiryDays?: number;
}

export interface AllocateCreditsBatchPayload {
  allocations: Array<{ userId: string; credits: number; expiryDays?: number; notes?: string }>;
}

export interface AllocateCreditsBatchResult {
  results: Array<{ userId: string; success: boolean; message: string }>;
  summary: { total: number; successful: number; failed: number };
}

export interface SetCreditsPayload {
  userId: string;
  credits: number;
}

export interface RemoveCreditsPayload {
  userId: string;
}

export interface AdjustCreditsPayload {
  userId: string;
  adjustment: number;
  reason?: string;
}

// =============================================================================
// Usage / Token Stats
// =============================================================================

export interface UserUsageStat {
  userId: string;
  username?: string;
  email?: string;
  totalTokens: number;
  totalCost?: number;
  requestCount: number;
  lastUsed?: string;
}

export interface SystemStats {
  totalUsers?: number;
  totalTokensUsed?: number;
  totalCost?: number;
  totalRequests?: number;
  byUser?: UserUsageStat[];
  byModel?: Record<string, number>;
  byDay?: Record<string, number>;
  period?: { start: string; end: string };
}

