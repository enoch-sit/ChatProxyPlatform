// src/types/auth.ts
export type UserRole = 'admin' | 'supervisor' | 'teacher' | 'enduser' | 'user';

export interface User {
  id: string;
  username: string;
  email: string;
  role: UserRole;
  permissions: string[]; // Keep this for runtime use, but it's derived from role
  profile?: {
    firstName?: string;
    lastName?: string;
    avatar?: string;
  };
}

export interface AuthTokens {
  accessToken: string;
  refreshToken?: string;
  expiresIn: number;
  tokenType: 'Bearer';
}

export interface LoginCredentials {
  username: string;
  password: string;
}

export interface AuthState {
  user: User | null;
  tokens: AuthTokens | null;
  isAuthenticated: boolean;
  isLoading: boolean;
  error: string | null;
}

export interface LoginResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
  user: User;
  role?: 'admin' | 'supervisor' | 'enduser' | 'user';//   role?: string;
}