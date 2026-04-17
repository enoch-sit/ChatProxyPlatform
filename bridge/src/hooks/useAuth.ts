// src/hooks/useAuth.ts
import { useAuthStore } from '../store/authStore';
import { useCallback } from 'react';
import type { UserRole } from '../types/auth';

export const useAuth = () => {
  const store = useAuthStore();

  const loginWithCredentials = useCallback(async (username: string, password: string) => {
    return store.login({ username, password });
  }, [store]);

  return {
    // State
    user: store.user,
    tokens: store.tokens,
    isAuthenticated: store.isAuthenticated,
    hasHydrated: store.hasHydrated,
    isLoading: store.isLoading,
    error: store.error,

    // Actions
    login: loginWithCredentials,
    logout: store.logout,
    refreshToken: store.refreshToken,
    setUser: store.setUser,
    clearError: store.clearError,

    // Utilities
    checkAuthStatus: store.checkAuthStatus,
    hasPermission: store.hasPermission,
    hasRole: (roles: UserRole | UserRole[]) => store.hasRole(roles),
  };
};