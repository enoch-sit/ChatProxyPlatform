// src/store/authStore.ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import {
  login as apiLogin,
  refreshToken as apiRefreshToken,
  logout as apiLogout,
} from '../api/auth';
import { navigateTo } from '../api/navigationService';
import type { AuthState, LoginCredentials, User, AuthTokens, LoginResponse } from '../types/auth';
import { jwtDecode } from 'jwt-decode';

interface DecodedToken {
  exp: number;
  iat: number;
  username: string;
  role: User['role'];
  // Remove permissions from JWT since we'll derive them from roles
}

interface AuthActions {
  setUser: (user: User) => void;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => Promise<void>;
  refreshToken: (isBackground?: boolean) => Promise<void>;
  checkAuthStatus: (isBackground?: boolean) => void;
  clearError: () => void;
  hasPermission: (permission: string) => boolean;
  hasRole: (role: User['role'] | User['role'][]) => boolean;
  getUserPermissions: () => string[];
}

// Define role-based permissions
const ROLE_PERMISSIONS: Record<User['role'], string[]> = {
  admin: [
    'manage_users',
    'manage_chatflows',
    'view_analytics',
    'sync_chatflows',
    'access_admin_panel',
    'view_all_sessions',
    'view_all_messages',
    'manage_system_settings',
  ],
  supervisor: [
    'manage_users',
    'manage_chatflows',
    'view_analytics',
    'access_admin_panel',
    'view_all_sessions',
    'view_all_messages',
  ],
  teacher: [
    'manage_users',
    'manage_chatflows',
    'view_analytics',
    'access_admin_panel',
    'view_all_sessions',
    'view_all_messages',
  ],
  enduser: [
    'create_sessions',
    'send_messages',
    'view_own_sessions',
  ],
  user: [
    'create_sessions',
    'send_messages',
    'view_own_sessions',
  ],
};

const initialState: AuthState = {
  user: null,
  tokens: null,
  isAuthenticated: false,
  hasHydrated: false,
  isLoading: false,
  error: null,
};

const transformLoginResponse = (data: LoginResponse): { user: User; tokens: AuthTokens } => {
  const { access_token, refresh_token, expires_in, token_type, user } = data;

  const tokens: AuthTokens = {
    accessToken: access_token,
    refreshToken: refresh_token,
    expiresIn: expires_in,
    tokenType: token_type as 'Bearer',
  };

  // Derive permissions from role
  const permissions = ROLE_PERMISSIONS[user?.role] || ROLE_PERMISSIONS.user;
  
  const enrichedUser: User = {
    ...user,
    permissions,
  };

  return { user: enrichedUser, tokens };
};

export const useAuthStore = create<AuthState & AuthActions>()(
  persist(
    (set, get) => ({
      ...initialState,
      setUser: (user) => {
        // Re-derive permissions from role in case they changed
        const permissions = ROLE_PERMISSIONS[user.role] || ROLE_PERMISSIONS.user;
        const enrichedUser = { ...user, permissions };
        set({ user: enrichedUser, isAuthenticated: true });
      },
      login: async (credentials) => {
        set({ isLoading: true, error: null });
        try {
          const data = await apiLogin(credentials);
          const { user, tokens } = transformLoginResponse(data);
          
          // Debug logging to see if refresh token is received and stored
          console.log('🔑 Login response tokens:', {
            hasAccessToken: !!tokens.accessToken,
            hasRefreshToken: !!tokens.refreshToken,
            accessTokenLength: tokens.accessToken?.length || 0,
            refreshTokenLength: tokens.refreshToken?.length || 0,
            expiresIn: tokens.expiresIn
          });
          
          set({ user, tokens, isAuthenticated: true, isLoading: false });
        } catch (error: any) {
          set({ error: error.message || 'Login failed', isLoading: false });
          throw error;
        }
      },
      logout: async () => {
        const { tokens } = get();

        // Clear local auth state first so UI/route transition is immediate
        set(initialState);
        localStorage.removeItem('accessToken');
        localStorage.removeItem('refreshToken');
        navigateTo('/login');

        // Best-effort server token invalidation runs after local logout.
        if (tokens?.refreshToken && tokens?.accessToken) {
          try {
            await apiLogout(tokens.refreshToken, tokens.accessToken);
          } catch (error) {
            console.error('Logout API call failed:', error);
          }
        }
      },
      refreshToken: async (isBackground = false) => {
        // Don't show loading for background refreshes
        if (!isBackground) {
          set({ isLoading: true, error: null });
        }
        
        const { tokens } = get();
        
        // Debug logging to understand what's happening
        console.log('🔍 Debug refresh token attempt:', {
          hasTokens: !!tokens,
          hasAccessToken: !!tokens?.accessToken,
          hasRefreshToken: !!tokens?.refreshToken,
          isBackground,
          refreshTokenLength: tokens?.refreshToken?.length || 0
        });
        
        if (!tokens?.refreshToken) {
          console.error('❌ No refresh token available - this is why the app is "refreshing"');
          if (!isBackground) {
            set({ isLoading: false, error: 'No refresh token available.' });
            get().logout();
          }
          throw new Error('No refresh token available.');
        }
        
        try {
          console.log('🔄 Attempting to refresh token...');
          const data = await apiRefreshToken(tokens.refreshToken);
          const { user, tokens: newTokens } = transformLoginResponse(data);
          set({ 
            user, 
            tokens: newTokens, 
            isAuthenticated: true, 
            isLoading: false,
            error: null // Clear any previous errors on successful refresh
          });
          console.log('✅ Token refreshed successfully');
        } catch (error: any) {
          console.error('❌ Token refresh failed:', {
            error: error.message,
            status: error.response?.status,
            isBackground
          });
          
          if (!isBackground) {
            set({ error: error.message || 'Token refresh failed', isLoading: false });
            get().logout();
          } else {
            // For background refreshes, don't logout immediately
            // Let the user continue and handle it gracefully on next API call
            set({ isLoading: false });
          }
          throw error;
        }
      },
      checkAuthStatus: (isBackground = false) => {
        const { tokens } = get();
        if (tokens?.accessToken) {
          try {
            const decoded: DecodedToken = jwtDecode(tokens.accessToken);
            if (decoded.exp * 1000 < Date.now()) {
              // Pass isBackground flag to refreshToken
              get().refreshToken(isBackground).catch((error) => {
                if (isBackground) {
                  console.warn('⚠️ Background token refresh failed, will retry on next interval or API call:', error.message);
                }
                // For background checks, don't throw - let the user continue
                // The axios interceptor will handle this when they make an API call
              });
            } else {
              // Re-derive permissions from role in case they changed
              const { user } = get();
              if (user) {
                const permissions = ROLE_PERMISSIONS[user.role] || ROLE_PERMISSIONS.user;
                set({ 
                  user: { ...user, permissions },
                  isAuthenticated: true 
                });
              }
            }
          } catch {
            if (!isBackground) {
              get().logout();
            }
          }
        } else {
          const { isAuthenticated, user } = get();
          if (isAuthenticated || user) {
            set(initialState);
          }
        }
      },
      clearError: () => set({ error: null }),
      hasPermission: (permission) => {
        const { user } = get();
        if (!user) return false;
        
        // Get permissions based on role
        const rolePermissions = ROLE_PERMISSIONS[user.role] || [];
        return rolePermissions.includes(permission);
      },
      hasRole: (role) => {
        const { user } = get();
        if (!user) return false;
        if (Array.isArray(role)) {
          return role.includes(user.role);
        }
        return user.role === role;
      },
      getUserPermissions: () => {
        const { user } = get();
        if (!user) return [];
        return ROLE_PERMISSIONS[user.role] || [];
      },
    }),
    {
      name: 'auth-storage',
      storage: createJSONStorage(() => localStorage),
      partialize: (state) => ({ tokens: state.tokens, user: state.user, isAuthenticated: state.isAuthenticated }),
      onRehydrateStorage: () => (state) => {
        state?.checkAuthStatus(true);
        state?.clearError();
        useAuthStore.setState({ hasHydrated: true });
      },
    }
  )
);