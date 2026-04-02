// src/components/admin/AdminUsersPanel.tsx
import React, { useEffect, useState } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog, ModalClose,
  Input, Select, Option, Checkbox, CircularProgress, Alert, Chip, Textarea,
  FormLabel, FormControl, Stack,
} from '@mui/joy';
import { useAdminStore } from '../../store/adminStore';
import { useAuth } from '../../hooks/useAuth';
import { resetUserPassword } from '../../api/admin';
import type { AdminUser } from '../../types/admin';

const ROLE_OPTIONS = ['user', 'enduser', 'teacher', 'supervisor', 'admin'];

function roleColor(role: string): 'danger' | 'warning' | 'success' | 'primary' | 'neutral' {
  if (role === 'admin') return 'danger';
  if (role === 'supervisor') return 'warning';
  if (role === 'teacher') return 'primary';
  return 'neutral';
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
    allocateCredits,
    clearError,
  } = useAdminStore();

  const [success, setSuccess] = useState<string | null>(null);

  // Create user modal
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({ username: '', email: '', password: '', role: 'enduser', skipVerification: true });

  // Batch create modal
  const [showBatch, setShowBatch] = useState(false);
  const [batchLines, setBatchLines] = useState('');
  const [batchDefaultPassword, setBatchDefaultPassword] = useState('');
  const [batchDefaultCredits, setBatchDefaultCredits] = useState('0');
  const [batchSkipVerification, setBatchSkipVerification] = useState(true);
  const [batchError, setBatchError] = useState<string | null>(null);

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

  const flash = (msg: string) => {
    setSuccess(msg);
    setTimeout(() => setSuccess(null), 3500);
  };

  const handleCreate = async () => {
    try {
      await createUser(createForm);
      setShowCreate(false);
      setCreateForm({ username: '', email: '', password: '', role: 'enduser', skipVerification: true });
      flash('User created successfully');
    } catch { /* error shown via store */ }
  };

  const handleBatch = async () => {
    setBatchError(null);
    if (!batchDefaultPassword || batchDefaultPassword.length < 8) {
      setBatchError('Default password must be at least 8 characters.');
      return;
    }
    const lines = batchLines.split('\n').map((l) => l.trim()).filter(Boolean);
    if (lines.length === 0) {
      setBatchError('Enter at least one email.');
      return;
    }
    const usersPayload = lines.map((line) => {
      const parts = line.split(/[\s,]+/);
      const email = parts[0];
      const username = parts[1] || email.split('@')[0];
      const password = parts[2] || batchDefaultPassword;
      return { email, username, password, role: 'enduser' };
    });
    try {
      const result = await createUsersBatch({ users: usersPayload, skipVerification: batchSkipVerification });
      const defaultCredits = parseInt(batchDefaultCredits, 10);
      if (defaultCredits > 0 && result?.results) {
        for (const r of (result.results as Array<{ success: boolean; userId?: string }>) ) {
          if (r.success && r.userId) {
            await allocateCredits({ userId: r.userId, credits: defaultCredits }).catch(() => {});
          }
        }
      }
      setShowBatch(false);
      setBatchLines('');
      flash(`Batch complete: ${usersPayload.length} users processed`);
    } catch { /* error shown via store */ }
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
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Typography level="h3">User Management</Typography>
        <Stack direction="row" spacing={1}>
          <Button size="sm" variant="outlined" onClick={() => fetchUsers()}>Refresh</Button>
          <Button size="sm" variant="outlined" color="neutral" onClick={() => setShowBatch(true)}>Batch Create</Button>
          <Button size="sm" onClick={() => setShowCreate(true)}>+ New User</Button>
        </Stack>
      </Box>

      {success && <Alert color="success" sx={{ mb: 2 }}>{success}</Alert>}
      {error && <Alert color="danger" sx={{ mb: 2 }} endDecorator={<Button size="sm" variant="plain" color="danger" onClick={clearError}>Dismiss</Button>}>{error}</Alert>}

      <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto', maxHeight: '60vh' }}>
        <Table stickyHeader>
          <thead>
            <tr>
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
              <tr><td colSpan={6} align="center"><CircularProgress size="sm" /></td></tr>
            ) : users.length === 0 ? (
              <tr><td colSpan={6}>No users found.</td></tr>
            ) : users.map((u) => (
              <tr key={u._id}>
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
      <Modal open={showCreate} onClose={() => setShowCreate(false)}>
        <ModalDialog sx={{ minWidth: 360 }}>
          <ModalClose />
          <Typography level="h4">Create User</Typography>
          <FormControl>
            <FormLabel>Username</FormLabel>
            <Input value={createForm.username} onChange={(e) => setCreateForm({ ...createForm, username: e.target.value })} />
          </FormControl>
          <FormControl sx={{ mt: 1 }}>
            <FormLabel>Email</FormLabel>
            <Input type="email" value={createForm.email} onChange={(e) => setCreateForm({ ...createForm, email: e.target.value })} />
          </FormControl>
          <FormControl sx={{ mt: 1 }}>
            <FormLabel>Password</FormLabel>
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
      <Modal open={showBatch} onClose={() => { setShowBatch(false); setBatchError(null); }}>
        <ModalDialog sx={{ minWidth: 500 }}>
          <ModalClose />
          <Typography level="h4">Batch Create Students</Typography>
          <Typography level="body-sm" sx={{ mb: 1 }}>
            One entry per line. Formats accepted:
          </Typography>
          <Typography level="body-xs" sx={{ mb: 1.5, color: 'text.tertiary' }}>
            <code>email</code> &nbsp;|&nbsp; <code>email username</code> &nbsp;|&nbsp; <code>email username password</code>
          </Typography>
          {batchError && <Alert color="danger" sx={{ mb: 1 }}>{batchError}</Alert>}
          <Textarea
            minRows={5}
            placeholder={'alice@school.edu\nbob@school.edu bob_student\ncarol@school.edu carol Pass@word1'}
            value={batchLines}
            onChange={(e) => setBatchLines(e.target.value)}
          />
          <Stack direction="row" spacing={2} sx={{ mt: 1.5 }}>
            <FormControl sx={{ flex: 1 }}>
              <FormLabel>Default Password (min 8 chars)</FormLabel>
              <Input
                type="password"
                placeholder="Used when not specified per-row"
                value={batchDefaultPassword}
                onChange={(e) => setBatchDefaultPassword(e.target.value)}
              />
            </FormControl>
            <FormControl sx={{ width: 120 }}>
              <FormLabel>Default Credits</FormLabel>
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
          <Button sx={{ mt: 2 }} onClick={handleBatch} loading={isLoading} disabled={!batchLines.trim() || !batchDefaultPassword}>
            Create Students
          </Button>
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
