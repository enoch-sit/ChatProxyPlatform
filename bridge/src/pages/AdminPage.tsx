// src/pages/AdminPage.tsx
import React, { useEffect, useState, useCallback, useRef, useLayoutEffect } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog,
  ModalClose, Input, Textarea, CircularProgress, Alert, Chip, Checkbox,
  Tabs, TabList, Tab, TabPanel,
} from '@mui/joy';
import { useAdminStore } from '../store/adminStore';
import type { Chatflow } from '../types/chatflow';
import { useTranslation } from 'react-i18next';
import { usePermissions } from '../hooks/usePermissions';
import { useLocation } from 'react-router-dom';
import AdminUsersPanel from '../components/admin/AdminUsersPanel';
import AdminCreditsPanel from '../components/admin/AdminCreditsPanel';
import AdminUsagePanel from '../components/admin/AdminUsagePanel';
import AdminChatHistoryPanel from '../components/admin/AdminChatHistoryPanel';
import AdminFlowiseSettingsPanel from '../components/admin/AdminFlowiseSettingsPanel';

function getErrorMessage(error: unknown, fallback: string): string {
  const candidate = error as {
    response?: { data?: { detail?: unknown; message?: unknown } };
    message?: unknown;
  };

  const detail = candidate?.response?.data?.detail;
  if (typeof detail === 'string' && detail.trim()) {
    return detail;
  }

  const message = candidate?.response?.data?.message;
  if (typeof message === 'string' && message.trim()) {
    return message;
  }

  if (typeof candidate?.message === 'string' && candidate.message.trim()) {
    return candidate.message;
  }

  return fallback;
}

const AdminPage: React.FC = () => {
  const { t } = useTranslation();
  const location = useLocation();
  
  // Get permissions
  const permissions = usePermissions();
  const {
    canManageUsers,
    canManageChatflows,
    canViewAnalytics,
    canSyncChatflows,
    canAccessAdmin
  } = permissions;

  // Store state
  const {
    chatflows,
    stats,
    selectedChatflow,
    chatflowUsers,
    isLoading,
    error,
    fetchChatflows,
    fetchStats,
    fetchChatflowUsers,
    bulkAddUsersToChatflow,
    bulkRemoveUsersFromChatflow,
    removeUserFromChatflow,
    setSelectedChatflow,
    clearError,
    syncChatflows,
  } = useAdminStore();

  // Local UI state
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<string>('chatflows');
  const [showUserModal, setShowUserModal] = useState(false);
  const [showBulkAssignModal, setShowBulkAssignModal] = useState(false);
  const [userEmail, setUserEmail] = useState('');
  const [bulkUserEmails, setBulkUserEmails] = useState('');
  const [selectedUsersForBulkRemove, setSelectedUsersForBulkRemove] = useState<string[]>([]);
  const [userManagementError, setUserManagementError] = useState<string | null>(null);
  const tabsContainerRef = useRef<HTMLDivElement | null>(null);

  const isBatchProtectedRole = useCallback((role?: string) => {
    const normalizedRole = (role || '').toLowerCase();
    return normalizedRole === 'admin' || normalizedRole === 'supervisor' || normalizedRole === 'teacher';
  }, []);

  const isAdminRole = useCallback((role?: string) => (role || '').toLowerCase() === 'admin', []);

  const selectableUserEmails = chatflowUsers
    .filter((user) => !isBatchProtectedRole(user.role))
    .map((user) => user.email);
  const allSelectableUsersSelected = selectableUserEmails.length > 0
    && selectableUserEmails.every((email) => selectedUsersForBulkRemove.includes(email));
  const someSelectableUsersSelected = selectedUsersForBulkRemove.length > 0
    && !allSelectableUsersSelected;

  const resetAdminViewport = useCallback(() => {
    // Reset every relevant scroll container to avoid opening admin views with displaced content.
    window.scrollTo(0, 0);

    const main = tabsContainerRef.current?.closest('main') as HTMLElement | null;
    if (main) {
      main.scrollTop = 0;
    }

    if (tabsContainerRef.current) {
      tabsContainerRef.current.scrollTop = 0;
    }
  }, []);

  //console.log('AdminPage permissions:', permissions);

  // Fetch initial data
  const loadAdminData = useCallback(async () => {
    if (!canAccessAdmin) {
      console.log('No admin access, skipping data fetch');
      return;
    }

    console.log('Fetching admin data...');
    try {
      await Promise.all([
        fetchChatflows(),
        canViewAnalytics ? fetchStats() : Promise.resolve(),
      ]);
      console.log('Admin data fetched successfully');
    } catch (err) {
      console.error('Failed to fetch admin data:', err);
    }
  }, [canAccessAdmin, canViewAnalytics, fetchChatflows, fetchStats]);

  useEffect(() => {
    console.log('AdminPage useEffect triggered, canAccessAdmin:', canAccessAdmin);
    loadAdminData();
  }, [loadAdminData, canAccessAdmin]);

  useLayoutEffect(() => {
    // Run on route entry and after layout to avoid browser/history scroll restoration artifacts.
    resetAdminViewport();
    requestAnimationFrame(resetAdminViewport);
  }, [location.pathname, resetAdminViewport]);

  useEffect(() => {
    // Keep each tab anchored to the top when switching tabs.
    resetAdminViewport();

    const panels = tabsContainerRef.current?.querySelectorAll('[role="tabpanel"]');
    panels?.forEach((panel) => {
      (panel as HTMLElement).scrollTop = 0;
    });
  }, [activeTab, resetAdminViewport]);

  useEffect(() => {
    setSelectedUsersForBulkRemove((current) => current.filter((email) => selectableUserEmails.includes(email)));
  }, [selectableUserEmails]);

  // Handle sync (placeholder - you might want to add this to the store)
  const handleSync = async () => {
    try {
      const result = await syncChatflows();
      setSuccessMessage(
        `Sync complete: ${result.total_fetched} fetched, ${result.created} created, ` +
        `${result.updated} updated, ${result.deleted} deleted` +
        (result.errors > 0 ? `, ${result.errors} errors` : '')
      );
      await loadAdminData();
    } catch (err) {
      console.error('Sync failed:', err);
      // Error will be handled by store
    }
  };

  // Handle user management modal
  const handleManageUsers = async (chatflow: Chatflow) => {
    try {
      clearError();
      setUserManagementError(null);
      setSelectedChatflow(chatflow);
      setSelectedUsersForBulkRemove([]);
      setShowUserModal(true);
      await fetchChatflowUsers(chatflow.flowise_id);
    } catch (err) {
      console.error('Failed to fetch users:', err);
      // Error handled by store
    }
  };

  // Add single user
  const handleAddUser = async () => {
    if (!selectedChatflow || !userEmail.trim()) return;

    clearError();
    setUserManagementError(null);
    setSuccessMessage(null);

    try {
      const identifier = userEmail.trim();
      const results = await bulkAddUsersToChatflow(selectedChatflow.flowise_id, [identifier]);

      if (results.successful > 0) {
        setSuccessMessage(`User ${identifier} added to ${selectedChatflow.name}.`);
        setUserEmail('');
        return;
      }

      const failedPreview = results.failed[0] || identifier;
      setUserManagementError(`Could not assign ${failedPreview}. Enter a valid username or email.`);
    } catch (err) {
      setUserManagementError(getErrorMessage(err, 'Failed to add user to chatflow.'));
      console.error('Failed to add user:', err);
      // Error handled by store
    }
  };

  // Remove user
  const handleRemoveUser = async (email: string) => {
    if (!selectedChatflow) return;

    clearError();
    setUserManagementError(null);

    try {
      await removeUserFromChatflow(selectedChatflow.flowise_id, email);
      setSuccessMessage(`User removed from ${selectedChatflow.name}.`);
      setUserEmail('');
    } catch (err) {
      console.error('Failed to remove user:', err);
      // Error handled by store
    }
  };

  const toggleUserSelection = (email: string) => {
    setSelectedUsersForBulkRemove((current) => (
      current.includes(email)
        ? current.filter((selectedEmail) => selectedEmail !== email)
        : [...current, email]
    ));
  };

  const toggleSelectAllUsers = () => {
    if (allSelectableUsersSelected) {
      setSelectedUsersForBulkRemove([]);
      return;
    }

    setSelectedUsersForBulkRemove(selectableUserEmails);
  };

  const handleBulkRemoveUsers = async () => {
    if (!selectedChatflow || selectedUsersForBulkRemove.length === 0) return;

    try {
      const results = await bulkRemoveUsersFromChatflow(selectedChatflow.flowise_id, selectedUsersForBulkRemove);
      const failedCount = results.failed.length;
      const failedPreview = failedCount > 0 ? ` Failed: ${results.failed.slice(0, 3).join(', ')}${failedCount > 3 ? '...' : ''}` : '';

      setSuccessMessage(`${results.successful} users removed. ${failedCount} blocked or failed.${failedPreview}`);
      setSelectedUsersForBulkRemove([]);
      await fetchChatflowUsers(selectedChatflow.flowise_id);
    } catch (err) {
      console.error('Failed to bulk remove users:', err);
    }
  };

  // Bulk assign users by username or email
  const handleBulkAssign = async () => {
    if (!selectedChatflow || !bulkUserEmails.trim()) return;
    
    try {
      const identifiers = bulkUserEmails
        .split(/[\s,]+/)
        .map((entry) => entry.trim())
        .filter(Boolean);

      const results = await bulkAddUsersToChatflow(selectedChatflow.flowise_id, identifiers);
      const failedCount = results.failed.length;
      const failedPreview = failedCount > 0 ? ` Failed: ${results.failed.slice(0, 3).join(', ')}${failedCount > 3 ? '...' : ''}` : '';

      setSuccessMessage(`${results.successful} users assigned by username/email. ${failedCount} failed.${failedPreview}`);
      setBulkUserEmails('');
      setShowBulkAssignModal(false);
      
      // Refresh user list
      await fetchChatflowUsers(selectedChatflow.flowise_id);
    } catch (err) {
      console.error('Failed to bulk assign:', err);
      // Error handled by store
    }
  };

  // Format status display
  const getStatusDisplay = (status: string) => {
    switch (status) {
      case 'active': return t('common.active');
      case 'inactive': return t('common.inactive');
      case 'error': return t('common.error');
      default: return status;
    }
  };

  // Handle error and success message dismissal
  const handleCloseError = () => {
    clearError();
  };

  const handleCloseSuccess = () => {
    setSuccessMessage(null);
  };

  // Handle modal close
  const handleCloseUserModal = () => {
    setShowUserModal(false);
    setSelectedChatflow(null);
    setUserEmail('');
    setSelectedUsersForBulkRemove([]);
    setUserManagementError(null);
  };

  const handleCloseBulkModal = () => {
    setShowBulkAssignModal(false);
    setBulkUserEmails('');
  };

  const flexTabPanelSx = {
    p: 0,
    minHeight: 0,
    display: 'flex',
    flexDirection: 'column',
    '&[hidden]': {
      display: 'none !important',
    },
  } as const;

  // Early return for unauthorized access
  if (!canAccessAdmin) {
    return (
      <Box sx={{ p: 3, textAlign: 'center' }}>
        <Typography level="h4" color="danger">
          {t('auth.unauthorized')}
        </Typography>
        <Typography level="body-md">
          {t('admin.unauthorizedDetails')}
        </Typography>
      </Box>
    );
  }

  return (
    <Box sx={{ p: 3, display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0, overflow: 'hidden' }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
        <Typography level="h2">{t('admin.pageTitle')}</Typography>
      </Box>

      {/* Error Alert */}
      {error && (
        <Alert
          color="danger"
          sx={{ mb: 2 }}
          endDecorator={
            <Button size="sm" variant="plain" onClick={handleCloseError}>
              {t('common.close')}
            </Button>
          }
        >
          {error}
        </Alert>
      )}

      {/* Success Alert */}
      {successMessage && (
        <Alert
          color="success"
          sx={{ mb: 2 }}
          endDecorator={
            <Button size="sm" variant="plain" onClick={handleCloseSuccess}>
              {t('common.close')}
            </Button>
          }
        >
          {successMessage}
        </Alert>
      )}

      <Box ref={tabsContainerRef} sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <Tabs
          value={activeTab}
          onChange={(_, v) => setActiveTab(v as string)}
          sx={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}
        >
          <TabList sx={{ mb: 0.5, flexShrink: 0 }}>
          {canManageChatflows && <Tab value="chatflows">Chatflows</Tab>}
          {canManageUsers && <Tab value="users">Users</Tab>}
          {canManageUsers && <Tab value="credits">Credits</Tab>}
          {canViewAnalytics && <Tab value="usage">Token Usage</Tab>}
          {canManageUsers && <Tab value="student-chats">Student Chats</Tab>}
          {canManageChatflows && <Tab value="settings">Settings</Tab>}
          </TabList>

        {/* ---- Chatflows Tab (existing functionality) ---- */}
        {canManageChatflows && (
          <TabPanel value="chatflows" sx={{ p: 0, minHeight: 0, overflow: 'auto' }}>
            <Box sx={{ display: 'flex', justifyContent: 'flex-end', mb: 1 }}>
              {canSyncChatflows && (
                <Button onClick={handleSync} disabled={isLoading}>
                  {isLoading ? t('admin.syncing') : t('admin.syncChatflows')}
                </Button>
              )}
            </Box>

            <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto', maxWidth: '100%' }}>
              <Table
                aria-label="Chatflow management table"
                sx={{
                  minWidth: '800px',
                  '& thead th:nth-of-type(1)': { minWidth: 120 },
                  '& thead th:nth-of-type(2)': { minWidth: 280 },
                  '& thead th:nth-of-type(3)': { minWidth: 80 },
                  '& thead th:nth-of-type(4)': { minWidth: 80 },
                  '& thead th:nth-of-type(5)': { minWidth: 70 },
                  '& thead th:nth-of-type(6)': { minWidth: 80 },
                  '& tbody td:nth-of-type(1)': { maxWidth: 150 },
                  '& tbody td:nth-of-type(2)': { maxWidth: 300 },
                }}
              >
                <thead>
                  <tr>
                    <th>{t('admin.chatflowName')}</th>
                    <th>{t('admin.chatflowId')}</th>
                    <th>Status</th>
                    <th>Deployed</th>
                    <th>Public</th>
                    <th>Type</th>
                    {canManageUsers && <th>{t('admin.chatflowActions')}</th>}
                  </tr>
                </thead>
                <tbody>
                  {chatflows.length === 0 ? (
                    <tr key="ChatflowInfo">
                      <td colSpan={canManageUsers ? 7 : 6}>
                        <Box sx={{ textAlign: 'center', py: 2.5 }}>
                          {isLoading ? 'Loading...' : 'No chatflows found'}
                        </Box>
                      </td>
                    </tr>
                  ) : (
                    chatflows.map((flow, idx) => (
                      <tr key={`${flow.flowise_id}-${idx}`}>
                        <td>
                          <Typography level="body-sm" sx={{ fontWeight: 'bold', wordBreak: 'break-word', whiteSpace: 'normal' }}>
                            {flow.name}
                          </Typography>
                        </td>
                        <td>
                          <Typography level="body-xs" sx={{ fontFamily: 'monospace', fontSize: '11px', wordBreak: 'break-all', whiteSpace: 'normal', lineHeight: 1.2 }}>
                            {flow.flowise_id}
                          </Typography>
                        </td>
                        <td>
                          <Chip size="sm" color={flow.sync_status === 'active' ? 'success' : 'danger'}>
                            {getStatusDisplay(flow.sync_status)}
                          </Chip>
                        </td>
                        <td>
                          <Chip size="sm" color={flow.deployed ? 'success' : 'neutral'}>
                            {flow.deployed ? t('common.active') : t('common.inactive')}
                          </Chip>
                        </td>
                        <td>
                          <Chip size="sm" color={flow.is_public ? 'warning' : 'neutral'}>
                            {flow.is_public ? 'Public' : 'Private'}
                          </Chip>
                        </td>
                        <td>
                          <Typography level="body-sm">{flow.type}</Typography>
                        </td>
                        {canManageUsers && (
                          <td>
                            <Button size="sm" onClick={() => handleManageUsers(flow)}>
                              {t('admin.userManagement')}
                            </Button>
                          </td>
                        )}
                      </tr>
                    ))
                  )}
                </tbody>
              </Table>
            </Sheet>

            {canViewAnalytics && stats && (
              <Box sx={{ mt: 3 }}>
                <Typography level="h3" sx={{ mb: 2 }}>{t('admin.statsTitle')}</Typography>
                <Sheet variant="outlined" sx={{ p: 2, borderRadius: 'sm' }}>
                  <pre>{JSON.stringify(stats, null, 2)}</pre>
                </Sheet>
              </Box>
            )}
          </TabPanel>
        )}

        {/* ---- Users Tab ---- */}
        {canManageUsers && (
          <TabPanel value="users" sx={{ ...flexTabPanelSx, overflow: 'auto' }}>
            <AdminUsersPanel />
          </TabPanel>
        )}

        {/* ---- Credits Tab ---- */}
        {canManageUsers && (
          <TabPanel value="credits" sx={{ ...flexTabPanelSx, overflow: 'auto' }}>
            <AdminCreditsPanel />
          </TabPanel>
        )}

        {/* ---- Usage / Token Stats Tab ---- */}
        {canViewAnalytics && (
          <TabPanel value="usage" sx={{ ...flexTabPanelSx, overflow: 'auto' }}>
            <AdminUsagePanel />
          </TabPanel>
        )}

        {/* ---- Student Chat History Tab ---- */}
        {canManageUsers && (
          <TabPanel value="student-chats" sx={{ ...flexTabPanelSx, flex: 1, overflow: 'hidden' }}>
            <AdminChatHistoryPanel />
          </TabPanel>
        )}

        {/* ---- Runtime Settings Tab ---- */}
        {canManageChatflows && (
          <TabPanel value="settings" sx={{ ...flexTabPanelSx, overflow: 'auto' }}>
            <AdminFlowiseSettingsPanel />
          </TabPanel>
        )}
        </Tabs>
      </Box>

      {/* Chatflow User Management Modal */}
      <Modal open={showUserModal} onClose={handleCloseUserModal}>
        <ModalDialog sx={{ minWidth: '400px' }}>
          <ModalClose />
          <Typography level="h4">{t('admin.userManagement')}</Typography>
          <Typography textColor="neutral.500" sx={{ mb: 2 }}>
            {t('admin.manageUsersFor', { chatflowName: selectedChatflow?.name })}
          </Typography>

          {userManagementError && (
            <Alert color="danger" sx={{ mb: 2 }}>
              {userManagementError}
            </Alert>
          )}

          {canManageUsers && (
            <Box sx={{ display: 'flex', gap: 1, mb: 2 }}>
              <Input
                sx={{ flexGrow: 1 }}
                placeholder={t('admin.userEmailPlaceholder')}
                value={userEmail}
                onChange={(e) => setUserEmail(e.target.value)}
              />
              <Button onClick={handleAddUser} disabled={isLoading || !userEmail.trim()}>
                {t('admin.assignButton')}
              </Button>
              <Button variant="outlined" onClick={() => setShowBulkAssignModal(true)}>
                {t('admin.bulkAssign')}
              </Button>
              <Button
                variant="solid"
                color="danger"
                onClick={handleBulkRemoveUsers}
                disabled={isLoading || selectedUsersForBulkRemove.length === 0}
              >
                {t('admin.bulkRemove')}
              </Button>
            </Box>
          )}

          <Sheet sx={{ maxHeight: 'calc(100vh - 220px)', overflow: 'auto' }}>
            <Table aria-label="User list for chatflow">
              <thead>
                <tr>
                  {canManageUsers && (
                    <th>
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                        <Checkbox
                          checked={allSelectableUsersSelected}
                          indeterminate={someSelectableUsersSelected}
                          disabled={selectableUserEmails.length === 0}
                          onChange={toggleSelectAllUsers}
                          slotProps={{ input: { 'aria-label': 'Select all removable users' } }}
                        />
                        <Typography level="body-sm">{t('admin.selectUsers')}</Typography>
                      </Box>
                    </th>
                  )}
                  <th>{t('admin.userEmail')}</th>
                  <th>{t('admin.userRole')}</th>
                  {canManageUsers && <th>{t('admin.chatflowActions')}</th>}
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr>
                    <td colSpan={canManageUsers ? 4 : 2} align="center">
                      <CircularProgress size="sm" />
                    </td>
                  </tr>
                ) : chatflowUsers.length > 0 ? (
                  chatflowUsers.map((user) => (
                    <tr key={user.email}>
                      {canManageUsers && (
                        <td>
                          <Checkbox
                            checked={selectedUsersForBulkRemove.includes(user.email)}
                            disabled={isBatchProtectedRole(user.role)}
                            onChange={() => toggleUserSelection(user.email)}
                          />
                        </td>
                      )}
                      <td>{user.email}</td>
                      <td>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <Typography level="body-sm">{user.role || 'user'}</Typography>
                          {isBatchProtectedRole(user.role) && (
                            <Chip size="sm" color="warning" variant="soft">
                              {t('admin.protectedBatchRemove')}
                            </Chip>
                          )}
                        </Box>
                      </td>
                      {canManageUsers && (
                        <td>
                          <Button
                            size="sm"
                            variant="outlined"
                            color="danger"
                            disabled={isAdminRole(user.role)}
                            onClick={() => handleRemoveUser(user.email)}
                          >
                            {t('admin.removeButton')}
                          </Button>
                        </td>
                      )}
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={canManageUsers ? 4 : 2}>{t('admin.noUsers')}</td>
                  </tr>
                )}
              </tbody>
            </Table>
          </Sheet>
        </ModalDialog>
      </Modal>

      {/* Bulk Assign Modal */}
      <Modal open={showBulkAssignModal} onClose={handleCloseBulkModal}>
        <ModalDialog>
          <ModalClose />
          <Typography level="h4">{t('admin.bulkAssign')}</Typography>
          <Textarea
            minRows={4}
            placeholder={t('admin.bulkAssignPlaceholder')}
            value={bulkUserEmails}
            onChange={(e) => setBulkUserEmails(e.target.value)}
            sx={{ mt: 2, mb: 2 }}
          />
          <Button onClick={handleBulkAssign} disabled={isLoading || !bulkUserEmails.trim()}>
            {t('admin.assignButton')}
          </Button>
        </ModalDialog>
      </Modal>
    </Box>
  );
};

export default AdminPage;