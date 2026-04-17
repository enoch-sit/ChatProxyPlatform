// src/pages/AdminPage.tsx
import React, { useEffect, useState, useCallback } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog,
  ModalClose, Input, Textarea, CircularProgress, Alert, Chip,
  Tabs, TabList, Tab, TabPanel,
} from '@mui/joy';
import { useAdminStore } from '../store/adminStore';
import type { Chatflow } from '../types/chatflow';
import { useTranslation } from 'react-i18next';
import { usePermissions } from '../hooks/usePermissions';
import AdminUsersPanel from '../components/admin/AdminUsersPanel';
import AdminCreditsPanel from '../components/admin/AdminCreditsPanel';
import AdminUsagePanel from '../components/admin/AdminUsagePanel';
import AdminChatHistoryPanel from '../components/admin/AdminChatHistoryPanel';

const AdminPage: React.FC = () => {
  const { t } = useTranslation();
  
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
    addUserToChatflow,
    bulkAddUsersToChatflow,
    removeUserFromChatflow,
    setSelectedChatflow,
    clearError,
  } = useAdminStore();

  // Local UI state
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<string>('chatflows');
  const [showUserModal, setShowUserModal] = useState(false);
  const [showBulkAssignModal, setShowBulkAssignModal] = useState(false);
  const [userEmail, setUserEmail] = useState('');
  const [bulkUserEmails, setBulkUserEmails] = useState('');

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

  // Handle sync (placeholder - you might want to add this to the store)
  const handleSync = async () => {
    try {
      // Import syncChatflows if you have this API function
      // await syncChatflows();
      setSuccessMessage('Chatflows synced successfully!');
      await loadAdminData();
    } catch (err) {
      console.error('Sync failed:', err);
      // Error will be handled by store
    }
  };

  // Handle user management modal
  const handleManageUsers = async (chatflow: Chatflow) => {
    try {
      setSelectedChatflow(chatflow);
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
    
    try {
      await addUserToChatflow(selectedChatflow.flowise_id, userEmail);
      setSuccessMessage(`User ${userEmail} added to ${selectedChatflow.name}.`);
      setUserEmail('');
    } catch (err) {
      console.error('Failed to add user:', err);
      // Error handled by store
    }
  };

  // Remove user
  const handleRemoveUser = async (email: string) => {
    if (!selectedChatflow) return;
    
    try {
      await removeUserFromChatflow(selectedChatflow.flowise_id, email);
      setSuccessMessage(`User removed from ${selectedChatflow.name}.`);
    } catch (err) {
      console.error('Failed to remove user:', err);
      // Error handled by store
    }
  };

  // Bulk assign users (you might want to add this to the store)
  const handleBulkAssign = async () => {
    if (!selectedChatflow || !bulkUserEmails.trim()) return;
    
    try {
      const emails = bulkUserEmails.split('\n').map(e => e.trim()).filter(Boolean);

      const results = await bulkAddUsersToChatflow(selectedChatflow.flowise_id, emails);
      const failedCount = results.failed.length;
      const failedPreview = failedCount > 0 ? ` Failed: ${results.failed.slice(0, 3).join(', ')}${failedCount > 3 ? '...' : ''}` : '';

      setSuccessMessage(`${results.successful} users assigned. ${failedCount} failed.${failedPreview}`);
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
  };

  const handleCloseBulkModal = () => {
    setShowBulkAssignModal(false);
    setBulkUserEmails('');
  };

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
    <Box sx={{ p: 3, display: 'flex', flexDirection: 'column', height: '100%', minHeight: 0 }}>
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

      <Box sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
        <Tabs
          value={activeTab}
          onChange={(_, v) => setActiveTab(v as string)}
          sx={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}
        >
          <TabList sx={{ mb: 2, flexShrink: 0 }}>
          {canManageChatflows && <Tab value="chatflows">Chatflows</Tab>}
          {canManageUsers && <Tab value="users">Users</Tab>}
          {canManageUsers && <Tab value="credits">Credits</Tab>}
          {canViewAnalytics && <Tab value="usage">Token Usage</Tab>}
          {canManageUsers && <Tab value="student-chats">Student Chats</Tab>}
          </TabList>

        {/* ---- Chatflows Tab (existing functionality) ---- */}
        {canManageChatflows && (
          <TabPanel value="chatflows" sx={{ p: 0, flex: 1, minHeight: 0, overflow: 'auto' }}>
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
          <TabPanel value="users" sx={{ p: 0, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <AdminUsersPanel />
          </TabPanel>
        )}

        {/* ---- Credits Tab ---- */}
        {canManageUsers && (
          <TabPanel value="credits" sx={{ p: 0, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <AdminCreditsPanel />
          </TabPanel>
        )}

        {/* ---- Usage / Token Stats Tab ---- */}
        {canViewAnalytics && (
          <TabPanel value="usage" sx={{ p: 0, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <AdminUsagePanel />
          </TabPanel>
        )}

        {/* ---- Student Chat History Tab ---- */}
        {canManageUsers && (
          <TabPanel value="student-chats" sx={{ p: 0, flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <AdminChatHistoryPanel />
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
            </Box>
          )}

          <Sheet sx={{ maxHeight: 'calc(100vh - 220px)', overflow: 'auto' }}>
            <Table aria-label="User list for chatflow">
              <thead>
                <tr>
                  <th>{t('admin.userEmail')}</th>
                  {canManageUsers && <th>{t('admin.chatflowActions')}</th>}
                </tr>
              </thead>
              <tbody>
                {isLoading ? (
                  <tr>
                    <td colSpan={canManageUsers ? 2 : 1} align="center">
                      <CircularProgress size="sm" />
                    </td>
                  </tr>
                ) : chatflowUsers.length > 0 ? (
                  chatflowUsers.map((user) => (
                    <tr key={user.email}>
                      <td>{user.email}</td>
                      {canManageUsers && (
                        <td>
                          <Button size="sm" variant="outlined" color="danger" onClick={() => handleRemoveUser(user.email)}>
                            {t('admin.removeButton')}
                          </Button>
                        </td>
                      )}
                    </tr>
                  ))
                ) : (
                  <tr>
                    <td colSpan={canManageUsers ? 2 : 1}>{t('admin.noUsers')}</td>
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