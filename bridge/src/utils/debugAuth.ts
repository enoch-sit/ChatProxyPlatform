/**
 * Debug utilities for investigating auth/permission issues
 * Run from browser console: import and call debugAuthState()
 */

import { jwtDecode } from 'jwt-decode';

interface DecodedToken {
  sub: string;
  username: string;
  email: string;
  role: string;
  exp: number;
  iat: number;
}

/**
 * Main debug function - shows all relevant auth state
 */
export const debugAuthState = () => {
  console.log('🔍 ===== AUTH DEBUG STATE =====');
  
  // 1. Check localStorage
  const storedAuth = localStorage.getItem('auth-storage');
  if (!storedAuth) {
    console.error('❌ No auth-storage in localStorage');
    return;
  }

  let authData: any;
  try {
    authData = JSON.parse(storedAuth);
  } catch (e) {
    console.error('❌ Failed to parse auth-storage:', e);
    return;
  }

  console.log('📦 Auth Storage State:', {
    hasUser: !!authData.state?.user,
    hasTokens: !!authData.state?.tokens,
    isAuthenticated: authData.state?.isAuthenticated,
  });

  // 2. Check user object
  const user = authData.state?.user;
  if (!user) {
    console.error('❌ No user in auth state');
    return;
  }

  console.log('👤 User Object:', {
    id: user.id,
    username: user.username,
    email: user.email,
    role: user.role,
    permissions: user.permissions,
  });

  // 3. Decode JWT token
  const tokens = authData.state?.tokens;
  if (!tokens?.accessToken) {
    console.error('❌ No access token in auth state');
    return;
  }

  try {
    const decoded: DecodedToken = jwtDecode(tokens.accessToken);
    console.log('🔐 Decoded JWT Payload:', {
      sub: decoded.sub,
      username: decoded.username,
      email: decoded.email,
      role: decoded.role,
      issuedAt: new Date(decoded.iat * 1000).toISOString(),
      expiresAt: new Date(decoded.exp * 1000).toISOString(),
      isExpired: decoded.exp * 1000 < Date.now(),
    });
  } catch (e) {
    console.error('❌ Failed to decode JWT:', e);
    return;
  }

  // 4. Check permission derivation
  console.log('🔑 Permission Check:', {
    hasAdminRole: user.role === 'admin',
    canAccessAdmin: user.permissions?.includes('access_admin_panel'),
    allPermissions: user.permissions,
  });

  // 5. Summary
  const hasAdminRole = user.role === 'admin';
  const isTokenValid = tokens?.accessToken && jwtDecode<DecodedToken>(tokens.accessToken).exp * 1000 > Date.now();
  
  if (hasAdminRole && isTokenValid) {
    console.log('✅ AUTH STATE LOOKS GOOD - Admin role present, token valid');
    console.log('   Issue is likely UI-specific (layout/tabs not rendering)');
  } else if (!hasAdminRole) {
    console.error('❌ ADMIN ROLE MISSING - User does not have admin role in JWT');
    console.error('   Next step: Promote user to admin role in auth-service database');
  } else if (!isTokenValid) {
    console.error('❌ TOKEN EXPIRED - Access token is no longer valid');
    console.error('   Next step: Re-login to get fresh token');
  }

  return {
    userRole: user.role,
    hasAdminRole,
    isTokenValid,
    tokenExpiry: tokens?.accessToken ? new Date(jwtDecode<DecodedToken>(tokens.accessToken).exp * 1000) : null,
  };
};

/**
 * Quick check - just show role
 */
export const checkRole = () => {
  try {
    const storedAuth = localStorage.getItem('auth-storage');
    if (!storedAuth) return console.error('No auth stored');
    const data = JSON.parse(storedAuth);
    const role = data.state?.user?.role;
    console.log(`👤 Current role: ${role}`);
    return role;
  } catch (e) {
    console.error('Error checking role:', e);
  }
};

/**
 * Export for global console access
 */
if (typeof window !== 'undefined') {
  (window as any).__debugAuth = {
    debugAuthState,
    checkRole,
  };
  console.log('🐛 Auth debug tools loaded. Run: __debugAuth.debugAuthState()');
}
