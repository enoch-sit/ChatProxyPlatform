// src/components/auth/ProtectedRoute.tsx
import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { Box, CircularProgress, Typography } from '@mui/joy';
import { useAuth } from '../../hooks/useAuth';
import { useTranslation } from 'react-i18next';
import type { UserRole } from '../../types/auth';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredRole?: UserRole | UserRole[];
  requiredPermission?: string | string[];
  fallbackPath?: string;
}

const ProtectedRoute: React.FC<ProtectedRouteProps> = ({
  children,
  requiredRole,
  requiredPermission,
  fallbackPath = '/login',
}) => {
  const { isAuthenticated, isLoading, hasHydrated, user, tokens, hasRole, hasPermission } = useAuth();
  const location = useLocation();
  const { t } = useTranslation();

  // Show loading while checking authentication
  if (!hasHydrated || isLoading) {
    return (
      <Box
        sx={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          minHeight: '100vh',
          gap: 2,
        }}
      >
        <CircularProgress />
        <Typography level="body-md">{t('common.loading')}</Typography>
      </Box>
    );
  }

  // Redirect to login if not authenticated
  if (!isAuthenticated || !user || !tokens?.accessToken) {
    return <Navigate to={fallbackPath} state={{ from: location }} replace />;
  }

  // Check role requirements
  if (requiredRole) {
    const roles = Array.isArray(requiredRole) ? requiredRole : [requiredRole];
    if (!hasRole(roles)) {
      return (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            minHeight: '100vh',
            gap: 2,
            textAlign: 'center',
          }}
        >
          <Typography level="h4" color="danger">
            {t('auth.unauthorized')}
          </Typography>
          <Typography level="body-md">
            Required role: {roles.join(' or ')}
          </Typography>
          <Typography level="body-sm">
            Your role: {user.role}
          </Typography>
        </Box>
      );
    }
  }

  // Check permission requirements
  if (requiredPermission) {
    const permissions = Array.isArray(requiredPermission) ? requiredPermission : [requiredPermission];
    const hasRequiredPermission = permissions.some(permission => hasPermission(permission));
    
    if (!hasRequiredPermission) {
      return (
        <Box
          sx={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            minHeight: '100vh',
            gap: 2,
            textAlign: 'center',
          }}
        >
          <Typography level="h4" color="danger">
            {t('auth.unauthorized')}
          </Typography>
          <Typography level="body-md">
            Required permission: {permissions.join(' or ')}
          </Typography>
        </Box>
      );
    }
  }

  return <>{children}</>;
};

export default ProtectedRoute;