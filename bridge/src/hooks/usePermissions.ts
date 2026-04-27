// src/hooks/usePermissions.ts
import { useMemo } from 'react';
import { useAuth } from './useAuth';

export const usePermissions = () => {
  const { user, hasPermission, hasRole } = useAuth();

  // Memoize all permission checks as boolean values
  const permissionValues = useMemo(() => {
    if (!user) {
      return {
        isStrictlyAdmin: false,
        canAccessAdmin: false,
        canManageUsers: false,
        canManageChatflows: false,
        canViewAnalytics: false,
        canViewAllSessions: false,
        canViewAllMessages: false,
        canSyncChatflows: false,
      };
    }

    return {
      isStrictlyAdmin: hasRole('admin'),
      canAccessAdmin: hasRole(['admin', 'supervisor', 'teacher']),
      canManageUsers: hasPermission('manage_users'),
      canManageChatflows: hasPermission('manage_chatflows'),
      canViewAnalytics: hasPermission('view_analytics'),
      canViewAllSessions: hasPermission('view_all_sessions'),
      canViewAllMessages: hasPermission('view_all_messages'),
      canSyncChatflows: hasPermission('sync_chatflows'),
    };
  }, [user, hasPermission, hasRole]);

  return {
    user,
    hasPermission,
    hasRole,
    ...permissionValues,
  };
};