// src/components/admin/AdminUsersPanel.tsx
import React, { useEffect, useState } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog, ModalClose,
  Input, Select, Option, Checkbox, CircularProgress, Alert, Chip, Textarea,
  FormLabel, FormControl, Stack,
} from '@mui/joy';
import { useAdminStore } from '../../store/adminStore';
import { useAuth } from '../../hooks/useAuth';
import { resetUserPassword, allocateCreditsBatch } from '../../api/admin';
import type { AdminUser } from '../../types/admin';

const ROLE_OPTIONS = ['user', 'enduser', 'teacher', 'supervisor', 'admin'];

function roleColor(role: string): 'danger' | 'warning' | 'success' | 'primary' | 'neutral' {
  if (role === 'admin') return 'danger';
  if (role === 'supervisor') return 'warning';
  if (role === 'teacher') return 'primary';
  return 'neutral';
}

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

const AdminUsersPanel: React.FC = () => {
  const { user: currentUser } = useAuth();
  const {
    users,
    isLoading,
    error,
    fetchUsers,
    createUser,
    createUsersBatch,
    verifyUser,
    deleteUser,
    updateUserRole,
    updateUsersRolesBatch,
    clearError,
  } = useAdminStore();

  const [success, setSuccess] = useState<string | null>(null);

  // Create user modal
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({ username: '', email: '', password: '', role: 'enduser', skipVerification: true });
  const [createError, setCreateError] = useState<string | null>(null);

  // Batch create modal
  const [showBatch, setShowBatch] = useState(false);
  const [batchLines, setBatchLines] = useState('');
  const [batchDefaultPassword, setBatchDefaultPassword] = useState('');
  const [batchDefaultCredits, setBatchDefaultCredits] = useState('0');
  const [batchSkipVerification, setBatchSkipVerification] = useState(true);
  const [batchError, setBatchError] = useState<string | null>(null);
  // simple = username+password only (default); advanced = email+username+password
  const [batchMode, setBatchMode] = useState<'simple' | 'advanced'>('simple');
  const [batchCreateRole, setBatchCreateRole] = useState('enduser');
  const [batchResults, setBatchResults] = useState<Array<{ username: string; email: string; success: boolean; message: string; userId?: string }> | null>(null);
  const [creditResultMap, setCreditResultMap] = useState<Record<string, { success: boolean; message: string }>>({});
  const [creditErrors, setCreditErrors] = useState<string | null>(null);

  // Batch role update state
  const [selectedUserIds, setSelectedUserIds] = useState<string[]>([]);
  const [showBatchRoleModal, setShowBatchRoleModal] = useState(false);
  const [batchRole, setBatchRole] = useState('enduser');
  const [batchRoleError, setBatchRoleError] = useState<string | null>(null);

  // Role change modal
  const [showRoleModal, setShowRoleModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<AdminUser | null>(null);
  const [newRole, setNewRole] = useState('user');

  // Reset password modal
  const [showResetPwd, setShowResetPwd] = useState(false);
  const [resetTarget, setResetTarget] = useState<AdminUser | null>(null);
  const [newPassword, setNewPassword] = useState('');
  const [resetLoading, setResetLoading] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);

  useEffect(() => {
    fetchUsers().catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    setSelectedUserIds((prev) => prev.filter((id) => users.some((u) => u._id === id)));
  }, [users]);

  const flash = (msg: string) => {
    setSuccess(msg);
    setTimeout(() => setSuccess(null), 3500);
  };

  const closeCreateModal = () => {
    setShowCreate(false);
    setCreateError(null);
    clearError();
  };

  const handleCreate = async () => {
    clearError();
    setCreateError(null);
    if (createForm.password.length < 8) {
      setCreateError('Password must be at least 8 characters.');
      return;
    }

    try {
      await createUser(createForm);
      setShowCreate(false);
      setCreateError(null);
      setCreateForm({ username: '', email: '', password: '', role: 'enduser', skipVerification: true });
      flash('User created successfully');
    } catch (err: unknown) {
      setCreateError(getErrorMessage(err, 'User creation failed.'));
    }
  };

  const parseBatchLines = (raw: string): Array<{ username: string; email?: string; password: string; role: string }> => {
    const lines = raw.split('\n').map((l) => l.trim()).filter(Boolean);
    if (batchMode === 'simple') {
      // Format: username password
      return lines.map((line) => {
        const parts = line.split(/\s+/);
        const username = parts[0];
        const password = parts[1] || batchDefaultPassword;
        return { username, password, role: batchCreateRole };
      });
    } else {
      // Advanced format: email username password
      return lines.map((line) => {
        const parts = line.split(/[\s,]+/);
        const email = parts[0];
        const username = parts[1] || email.split('@')[0];
        const password = parts[2] || batchDefaultPassword;
        return { email, username, password, role: batchCreateRole };
      });
    }
  };

  const handleCsvUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      const text = ev.target?.result as string;
      if (!text) return;
      const rows = text.split(/\r?\n/).map((r) => r.trim()).filter(Boolean);
      // Strip header row if present
      const firstRow = rows[0]?.toLowerCase() ?? '';
      const isHeader = firstRow.startsWith('username') || firstRow.startsWith('email');
      const dataRows = isHeader ? rows.slice(1) : rows;
      // Convert CSV columns to space-separated lines for the textarea
      const lines = dataRows.map((row) => row.split(',').map((c) => c.trim()).join(' '));
      setBatchLines(lines.join('\n'));
    };
    reader.readAsText(file);
    // Reset input so the same file can be re-uploaded
    e.target.value = '';
  };

  const parseBatchLines = (raw: string): Array<{ username: string; email?: string; password: string; role: string }> => {
    const lines = raw.split('\n').map((l) => l.trim()).filter(Boolean);
    if (batchMode === 'simple') {
      // Format: username password
      return lines.map((line) => {
        const parts = line.split(/\s+/);
        const username = parts[0];
        const password = parts[1] || batchDefaultPassword;
        return { username, password, role: batchCreateRole };
      });
    } else {
      // Advanced format: email username password
      return lines.map((line) => {
        const parts = line.split(/[\s,]+/);
        const email = parts[0];
        const username = parts[1] || email.split('@')[0];
        const password = parts[2] || batchDefaultPassword;
        return { email, username, password, role: batchCreateRole };
      });
    }
  };

  const handleCsvUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (ev) => {
      const text = ev.target?.result as string;
      if (!text) return;
      const rows = text.split(/\r?\n/).map((r) => r.trim()).filter(Boolean);
      // Strip header row if present
      const firstRow = rows[0]?.toLowerCase() ?? '';
      const isHeader = firstRow.startsWith('username') || firstRow.startsWith('email');
      const dataRows = isHeader ? rows.slice(1) : rows;
      // Convert CSV columns to space-separated lines for the textarea
      const lines = dataRows.map((row) => row.split(',').map((c) => c.trim()).join(' '));
      setBatchLines(lines.join('\n'));
    };
    reader.readAsText(file);
    // Reset input so the same file can be re-uploaded
    e.target.value = '';
  };

  const handleBatch = async () => {
    clearError();
    setBatchError(null);
    setBatchResults(null);
    const usersPayload = parseBatchLines(batchLines);
    if (usersPayload.length === 0) {
      setBatchError('Enter at least one user.');
      return;
    }
    const needsFallbackPassword = usersPayload.some((u) => !u.password || u.password.length < 8);
    if (needsFallbackPassword && (!batchDefaultPassword || batchDefaultPassword.length < 8)) {
      setBatchError('Default password must be at least 8 characters (used when a row has no password).');
      return;
    }
    try {
      const result = await createUsersBatch({ users: usersPayload, skipVerification: batchSkipVerification });
      const defaultCredits = parseInt(batchDefaultCredits, 10);
      setCreditResultMap({});
      setCreditErrors(null);
      if (defaultCredits > 0 && result?.results) {
        const successfulUsers = (result.results as Array<{ success: boolean; userId?: string }>)
          .filter((r) => r.success && r.userId)
          .map((r) => ({ userId: r.userId!, credits: defaultCredits }));
        if (successfulUsers.length > 0) {
          try {
            const creditResult = await allocateCreditsBatch({ allocations: successfulUsers });
            const map: Record<string, { success: boolean; message: string }> = {};
            for (const cr of creditResult.results) {
              map[cr.userId] = { success: cr.success, message: cr.message };
            }
            setCreditResultMap(map);
            if (creditResult.summary.failed > 0) {
              setCreditErrors(`${creditResult.summary.failed} of ${creditResult.summary.total} credit allocation(s) failed — see Credits column below.`);
            }
          } catch {
            setCreditErrors('Credit allocation failed — users were created but credits may not have been assigned.');
          }
        }
      }
      if (result?.results) {
        setBatchResults(result.results as Array<{ username: string; email: string; success: boolean; message: string; userId?: string }>);
      }
      setBatchLines('');
      const successful = (result?.results as Array<{ success: boolean }>)?.filter((r) => r.success).length ?? usersPayload.length;
      flash(`Batch complete: ${successful} of ${usersPayload.length} users created`);
      await fetchUsers();
    } catch (err: unknown) {
      setBatchError(getErrorMessage(err, 'Batch user creation failed.'));
    }
  };

  const handleVerify = async (u: AdminUser) => {
    try {
      await verifyUser(u._id);
      flash(`${u.username} verified`);
    } catch { /* noop */ }
  };

  const handleDelete = async (u: AdminUser) => {
    if (!window.confirm(`Delete user "${u.username}" (${u.email})? This cannot be undone.`)) return;
    try {
      await deleteUser(u._id);
      flash(`User ${u.username} deleted`);
    } catch { /* noop */ }
  };

  const handleRoleChange = async () => {
    if (!selectedUser) return;
    try {
      await updateUserRole(selectedUser._id, newRole);
      setShowRoleModal(false);
      flash(`Role updated to ${newRole}`);
    } catch { /* noop */ }
  };

  const toggleSelectAll = () => {
    if (selectedUserIds.length === users.length) {
      setSelectedUserIds([]);
      return;
    }
    setSelectedUserIds(users.map((u) => u._id));
  };

  const toggleSelectUser = (userId: string, checked: boolean) => {
    setSelectedUserIds((prev) => {
      if (checked) {
        return [...prev, userId];
      }
      return prev.filter((id) => id !== userId);
    });
  };

  const handleBatchRoleUpdate = async () => {
    setBatchRoleError(null);
    if (selectedUserIds.length === 0) {
      setBatchRoleError('Select at least one user.');
      return;
    }

    try {
      const result = await updateUsersRolesBatch(
        selectedUserIds.map((userId) => ({ userId, role: batchRole }))
      );

      setShowBatchRoleModal(false);
      setSelectedUserIds([]);
      flash(`Batch role update completed. Success: ${result.successful}, Failed: ${result.failed.length}`);
    } catch {
      setBatchRoleError('Batch role update failed.');
    }
  };

  const openRoleModal = (u: AdminUser) => {
    setSelectedUser(u);
    setNewRole(u.role);
    setShowRoleModal(true);
  };

  const openResetPwd = (u: AdminUser) => {
    setResetTarget(u);
    setNewPassword('');
    setResetError(null);
    setShowResetPwd(true);
  };

  const handleResetPassword = async () => {
    if (!resetTarget || newPassword.length < 8) return;
    setResetLoading(true);
    setResetError(null);
    try {
      await resetUserPassword(resetTarget._id, newPassword);
      setShowResetPwd(false);
      flash(`Password reset for ${resetTarget.username}`);
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } }; message?: string };
      setResetError(e?.response?.data?.message || e?.message || 'Password reset failed');
    } finally {
      setResetLoading(false);
    }
  };

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0, overflow: 'hidden' }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Typography level="h3">User Management</Typography>
        <Stack direction="row" spacing={1}>
          <Button size="sm" variant="outlined" onClick={() => fetchUsers()}>Refresh</Button>
          <Button
            size="sm"
            variant="outlined"
            color="primary"
            disabled={selectedUserIds.length === 0}
            onClick={() => {
              setBatchRoleError(null);
              setShowBatchRoleModal(true);
            }}
          >
            Batch Role ({selectedUserIds.length})
          </Button>
          <Button size="sm" variant="outlined" color="neutral" onClick={() => setShowBatch(true)}>Batch Create</Button>
          <Button size="sm" onClick={() => { setCreateError(null); clearError(); setShowCreate(true); }}>+ New User</Button>
        </Stack>
      </Box>

      {success && <Alert color="success" sx={{ mb: 2 }}>{success}</Alert>}
      {error && <Alert color="danger" sx={{ mb: 2 }} endDecorator={<Button size="sm" variant="plain" color="danger" onClick={clearError}>Dismiss</Button>}>{error}</Alert>}

      <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto', flex: 1, minHeight: 0 }}>
        <Table stickyHeader>
          <thead>
            <tr>
              <th>
                <Checkbox
                  checked={users.length > 0 && selectedUserIds.length === users.length}
                  indeterminate={selectedUserIds.length > 0 && selectedUserIds.length < users.length}
                  onChange={() => toggleSelectAll()}
                />
              </th>
              <th>Username</th>
              <th>Email</th>
              <th>Role</th>
              <th>Verified</th>
              <th>Created</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={7} align="center"><CircularProgress size="sm" /></td></tr>
            ) : users.length === 0 ? (
              <tr><td colSpan={7}>No users found.</td></tr>
            ) : users.map((u) => (
              <tr key={u._id}>
                <td>
                  <Checkbox
                    checked={selectedUserIds.includes(u._id)}
                    onChange={(event) => toggleSelectUser(u._id, event.target.checked)}
                  />
                </td>
                <td>{u.username}</td>
                <td>{u.email}</td>
                <td>
                  <Chip size="sm" color={roleColor(u.role)}>{u.role}</Chip>
                </td>
                <td>
                  <Chip size="sm" color={u.isVerified ? 'success' : 'warning'}>
                    {u.isVerified ? 'Verified' : 'Pending'}
                  </Chip>
                </td>
                <td>{u.createdAt ? new Date(u.createdAt).toLocaleDateString() : '—'}</td>
                <td>
                  <Stack direction="row" spacing={0.5} flexWrap="wrap">
                    {!u.isVerified && (
                      <Button size="sm" variant="outlined" color="success" onClick={() => handleVerify(u)}>Verify</Button>
                    )}
                    <Button size="sm" variant="outlined" color="neutral" onClick={() => openRoleModal(u)}>Role</Button>
                    <Button size="sm" variant="outlined" color="warning" onClick={() => openResetPwd(u)}>Reset Pwd</Button>
                    {u._id !== currentUser?.id && (
                      <Button size="sm" variant="outlined" color="danger" onClick={() => handleDelete(u)}>Delete</Button>
                    )}
                  </Stack>
                </td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Sheet>

      {/* Create User Modal */}
      <Modal open={showCreate} onClose={closeCreateModal}>
        <ModalDialog sx={{ minWidth: 360 }}>
          <ModalClose />
          <Typography level="h4">Create User</Typography>
          {createError && <Alert color="danger" sx={{ mt: 1 }}>{createError}</Alert>}
          {!createError && error && <Alert color="danger" sx={{ mt: 1 }}>{error}</Alert>}
          <FormControl>
            <FormLabel>Username</FormLabel>
            <Input value={createForm.username} onChange={(e) => setCreateForm({ ...createForm, username: e.target.value })} />
          </FormControl>
          <FormControl sx={{ mt: 1 }}>
            <FormLabel>Email</FormLabel>
            <Input type="email" value={createForm.email} onChange={(e) => setCreateForm({ ...createForm, email: e.target.value })} />
          </FormControl>
          <FormControl sx={{ mt: 1 }}>
            <FormLabel>Password (min 8 chars)</FormLabel>
            <Input type="password" value={createForm.password} onChange={(e) => setCreateForm({ ...createForm, password: e.target.value })} />
          </FormControl>
          <FormControl sx={{ mt: 1 }}>
            <FormLabel>Role</FormLabel>
            <Select value={createForm.role} onChange={(_, v) => setCreateForm({ ...createForm, role: v as string })}>
              {ROLE_OPTIONS.map((r) => <Option key={r} value={r}>{r}</Option>)}
            </Select>
          </FormControl>
          <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Checkbox
              checked={createForm.skipVerification}
              onChange={(e) => setCreateForm({ ...createForm, skipVerification: e.target.checked })}
            />
            <Typography level="body-sm">Skip email verification</Typography>
          </Box>
          <Button sx={{ mt: 2 }} onClick={handleCreate} loading={isLoading} disabled={!createForm.username || !createForm.email || !createForm.password}>
            Create
          </Button>
        </ModalDialog>
      </Modal>

      {/* Batch Create Modal */}
      <Modal open={showBatch} onClose={() => { setShowBatch(false); clearError(); setBatchError(null); setBatchResults(null); setBatchLines(''); setCreditResultMap({}); setCreditErrors(null); }}>
        <ModalDialog sx={{ minWidth: 540, maxHeight: '90vh', overflowY: 'auto' }}>
          <ModalClose />
          <Typography level="h4">Batch Create Users</Typography>

          {/* Mode toggle */}
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
            <Chip
              size="sm"
              variant={batchMode === 'simple' ? 'solid' : 'outlined'}
              color="primary"
              onClick={() => setBatchMode('simple')}
              sx={{ cursor: 'pointer' }}
            >
              Simple (username + password)
            </Chip>
            <Chip
              size="sm"
              variant={batchMode === 'advanced' ? 'solid' : 'outlined'}
              color="neutral"
              onClick={() => setBatchMode('advanced')}
              sx={{ cursor: 'pointer' }}
            >
              Advanced (with email)
            </Chip>
          </Box>

          <Typography level="body-xs" sx={{ mb: 1, color: 'text.tertiary' }}>
            {batchMode === 'simple'
              ? 'One per line: username password  (password optional if default is set)'
              : 'One per line: email username password'}
          </Typography>

          {batchError && <Alert color="danger" sx={{ mb: 1 }}>{batchError}</Alert>}
          {!batchError && error && <Alert color="danger" sx={{ mb: 1 }}>{error}</Alert>}
          {creditErrors && <Alert color="warning" sx={{ mb: 1 }}>{creditErrors}</Alert>}

          {/* Result summary table */}
          {batchResults && (
            <Box sx={{ mb: 1.5, maxHeight: 180, overflowY: 'auto' }}>
              <Sheet variant="outlined" sx={{ borderRadius: 'sm' }}>
                <Table size="sm">
                  <thead>
                    <tr>
                      <th>Username</th>
                      <th>Email</th>
                      <th>Status</th>
                      <th>Credits</th>
                      <th>Note</th>
                    </tr>
                  </thead>
                  <tbody>
                    {batchResults.map((r, i) => {
                      const creditStatus = r.userId ? creditResultMap[r.userId] : undefined;
                      const showCredits = parseInt(batchDefaultCredits, 10) > 0;
                      return (
                        <tr key={i}>
                          <td>{r.username}</td>
                          <td>{r.email}</td>
                          <td>
                            <Chip size="sm" color={r.success ? 'success' : 'danger'}>
                              {r.success ? 'OK' : 'Failed'}
                            </Chip>
                          </td>
                          <td>
                            {!showCredits || !r.success ? (
                              <Typography level="body-xs" sx={{ color: 'neutral.400' }}>—</Typography>
                            ) : creditStatus ? (
                              <Chip size="sm" color={creditStatus.success ? 'success' : 'danger'}>
                                {creditStatus.success ? 'OK' : 'Failed'}
                              </Chip>
                            ) : (
                              <Typography level="body-xs" sx={{ color: 'neutral.400' }}>—</Typography>
                            )}
                          </td>
                          <td><Typography level="body-xs">{r.message}</Typography></td>
                        </tr>
                      );
                    })}
                  </tbody>
                </Table>
              </Sheet>
            </Box>
          )}

          <Textarea
            minRows={5}
            placeholder={batchMode === 'simple'
              ? 'alice Password1!\nbob Password2!\ncarol'
              : 'alice@school.edu alice Password1!\nbob@school.edu bob_student'}
            value={batchLines}
            onChange={(e) => setBatchLines(e.target.value)}
          />

          {/* CSV upload */}
          <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Button
              size="sm"
              variant="outlined"
              color="neutral"
              component="label"
            >
              Upload CSV
              <input
                type="file"
                accept=".csv,text/csv"
                title="Upload a CSV file with user data"
                aria-label="Upload CSV file"
                className="visually-hidden-file-input"
                onChange={handleCsvUpload}
              />
            </Button>
            <Typography level="body-xs" sx={{ color: 'text.tertiary' }}>
              {batchMode === 'simple' ? 'CSV columns: username,password[,role]' : 'CSV columns: email,username,password[,role]'}
            </Typography>
          </Box>

          <Stack direction="row" spacing={2} sx={{ mt: 1.5 }}>
            <FormControl sx={{ flex: 1 }}>
              <FormLabel>Default Password (min 8 chars)</FormLabel>
              <Input
                type="password"
                placeholder="Fallback when row has no password"
                value={batchDefaultPassword}
                onChange={(e) => setBatchDefaultPassword(e.target.value)}
              />
            </FormControl>
            <FormControl sx={{ width: 130 }}>
              <FormLabel>Default Role</FormLabel>
              <Select value={batchCreateRole} onChange={(_, v) => setBatchCreateRole(v as string)}>
                {ROLE_OPTIONS.filter((r) => r !== 'admin').map((r) => <Option key={r} value={r}>{r}</Option>)}
              </Select>
            </FormControl>
            <FormControl sx={{ width: 100 }}>
              <FormLabel>Credits</FormLabel>
              <Input
                type="number"
                slotProps={{ input: { min: 0 } }}
                value={batchDefaultCredits}
                onChange={(e) => setBatchDefaultCredits(e.target.value)}
              />
            </FormControl>
          </Stack>

          <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Checkbox
              checked={batchSkipVerification}
              onChange={(e) => setBatchSkipVerification(e.target.checked)}
            />
            <Typography level="body-sm">Skip email verification for all</Typography>
          </Box>

          <Stack direction="row" spacing={1} sx={{ mt: 2 }}>
            <Button
              onClick={handleBatch}
              loading={isLoading}
              disabled={!batchLines.trim()}
            >
              Create Users
            </Button>
            {batchResults && (
              <Button variant="outlined" color="neutral" onClick={() => { setShowBatch(false); setBatchResults(null); setBatchLines(''); setCreditResultMap({}); setCreditErrors(null); }}>
                Done
              </Button>
            )}
          </Stack>
        </ModalDialog>
      </Modal>

      {/* Role Change Modal */}
      <Modal open={showRoleModal} onClose={() => setShowRoleModal(false)}>
        <ModalDialog>
          <ModalClose />
          <Typography level="h4">Change Role</Typography>
          {selectedUser && (
            <Typography level="body-sm" sx={{ mb: 2 }}>
              User: <strong>{selectedUser.username}</strong> ({selectedUser.email})
            </Typography>
          )}
          <Select value={newRole} onChange={(_, v) => setNewRole(v as string)}>
            {ROLE_OPTIONS.map((r) => <Option key={r} value={r}>{r}</Option>)}
          </Select>
          <Button sx={{ mt: 2 }} onClick={handleRoleChange} loading={isLoading}>Save</Button>
        </ModalDialog>
      </Modal>

      <Modal open={showBatchRoleModal} onClose={() => setShowBatchRoleModal(false)}>
        <ModalDialog sx={{ minWidth: 360 }}>
          <ModalClose />
          <Typography level="h4">Batch Role Update</Typography>
          <Typography level="body-sm" sx={{ mb: 1 }}>
            Update role for {selectedUserIds.length} selected users.
          </Typography>
          {batchRoleError && <Alert color="danger" sx={{ mb: 1 }}>{batchRoleError}</Alert>}
          <FormControl>
            <FormLabel>New Role</FormLabel>
            <Select value={batchRole} onChange={(_, v) => setBatchRole(v as string)}>
              {ROLE_OPTIONS.map((r) => <Option key={r} value={r}>{r}</Option>)}
            </Select>
          </FormControl>
          <Button sx={{ mt: 2 }} onClick={handleBatchRoleUpdate} loading={isLoading}>
            Apply Role
          </Button>
        </ModalDialog>
      </Modal>

      {/* Reset Password Modal */}
      <Modal open={showResetPwd} onClose={() => setShowResetPwd(false)}>
        <ModalDialog sx={{ minWidth: 340 }}>
          <ModalClose />
          <Typography level="h4">Reset Password</Typography>
          {resetTarget && (
            <Typography level="body-sm" sx={{ mb: 2 }}>
              Set new password for <strong>{resetTarget.username}</strong>
            </Typography>
          )}
          {resetError && <Alert color="danger" sx={{ mb: 1 }}>{resetError}</Alert>}
          <FormControl>
            <FormLabel>New Password (min 8 chars)</FormLabel>
            <Input
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
            />
          </FormControl>
          <Button
            sx={{ mt: 2 }}
            onClick={handleResetPassword}
            loading={resetLoading}
            disabled={newPassword.length < 8}
          >
            Reset Password
          </Button>
        </ModalDialog>
      </Modal>
    </Box>
  );
};

export default AdminUsersPanel;
