// src/components/admin/AdminUsersPanel.tsx
import React, { useEffect, useState } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog, ModalClose,
  Input, Select, Option, Checkbox, CircularProgress, Alert, Chip, Textarea,
  FormLabel, FormControl, Stack,
} from '@mui/joy';
import { useAdminStore } from '../../store/adminStore';
import { useAuth } from '../../hooks/useAuth';
import type { AdminUser } from '../../types/admin';

const ROLE_OPTIONS = ['user', 'enduser', 'supervisor', 'admin'];

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
    clearError,
  } = useAdminStore();

  const [success, setSuccess] = useState<string | null>(null);

  // Create user modal
  const [showCreate, setShowCreate] = useState(false);
  const [createForm, setCreateForm] = useState({ username: '', email: '', password: '', role: 'user', skipVerification: false });

  // Batch create modal
  const [showBatch, setShowBatch] = useState(false);
  const [batchInput, setBatchInput] = useState('');
  const [batchSkipVerification, setBatchSkipVerification] = useState(false);
  const [batchError, setBatchError] = useState<string | null>(null);

  // Role change modal
  const [showRoleModal, setShowRoleModal] = useState(false);
  const [selectedUser, setSelectedUser] = useState<AdminUser | null>(null);
  const [newRole, setNewRole] = useState('user');

  useEffect(() => {
    fetchUsers().catch(() => {});
  }, []);

  const flash = (msg: string) => {
    setSuccess(msg);
    setTimeout(() => setSuccess(null), 3000);
  };

  const handleCreate = async () => {
    try {
      await createUser(createForm);
      setShowCreate(false);
      setCreateForm({ username: '', email: '', password: '', role: 'user', skipVerification: false });
      flash('User created successfully');
    } catch (e: any) {
      // error shown via store
    }
  };

  const handleBatch = async () => {
    setBatchError(null);
    let users: any[];
    try {
      users = JSON.parse(batchInput);
      if (!Array.isArray(users)) throw new Error('Must be a JSON array');
    } catch {
      setBatchError('Invalid JSON — must be an array of user objects like [{"username":"...","email":"...","password":"..."}]');
      return;
    }
    try {
      const result = await createUsersBatch({ users, skipVerification: batchSkipVerification });
      setShowBatch(false);
      setBatchInput('');
      flash(`Batch complete: ${result.results?.length ?? users.length} users processed`);
    } catch (e: any) {
      // error shown via store
    }
  };

  const handleVerify = async (user: AdminUser) => {
    try {
      await verifyUser(user._id);
      flash(`${user.username} verified`);
    } catch {}
  };

  const handleDelete = async (user: AdminUser) => {
    if (!window.confirm(`Delete user "${user.username}" (${user.email})? This cannot be undone.`)) return;
    try {
      await deleteUser(user._id);
      flash(`User ${user.username} deleted`);
    } catch {}
  };

  const handleRoleChange = async () => {
    if (!selectedUser) return;
    try {
      await updateUserRole(selectedUser._id, newRole);
      setShowRoleModal(false);
      flash(`Role updated to ${newRole}`);
    } catch {}
  };

  const openRoleModal = (user: AdminUser) => {
    setSelectedUser(user);
    setNewRole(user.role);
    setShowRoleModal(true);
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

      <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto' }}>
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
              <tr><td colSpan={6} style={{ textAlign: 'center' }}><CircularProgress size="sm" /></td></tr>
            ) : users.length === 0 ? (
              <tr><td colSpan={6}>No users found.</td></tr>
            ) : users.map((u) => (
              <tr key={u._id}>
                <td>{u.username}</td>
                <td>{u.email}</td>
                <td>
                  <Chip
                    size="sm"
                    color={u.role === 'admin' ? 'danger' : u.role === 'supervisor' ? 'warning' : 'neutral'}
                  >
                    {u.role}
                  </Chip>
                </td>
                <td>
                  <Chip size="sm" color={u.isVerified ? 'success' : 'warning'}>
                    {u.isVerified ? 'Verified' : 'Pending'}
                  </Chip>
                </td>
                <td>{u.createdAt ? new Date(u.createdAt).toLocaleDateString() : '—'}</td>
                <td>
                  <Stack direction="row" spacing={0.5}>
                    {!u.isVerified && (
                      <Button size="sm" variant="outlined" color="success" onClick={() => handleVerify(u)}>Verify</Button>
                    )}
                    <Button size="sm" variant="outlined" color="neutral" onClick={() => openRoleModal(u)}>Role</Button>
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
      <Modal open={showBatch} onClose={() => setShowBatch(false)}>
        <ModalDialog sx={{ minWidth: 480 }}>
          <ModalClose />
          <Typography level="h4">Batch Create Users</Typography>
          <Typography level="body-sm" sx={{ mb: 1 }}>
            Paste a JSON array of users: <code>[&#123;"username":"...", "email":"...", "password":"...", "role":"user"&#125;]</code>
          </Typography>
          {batchError && <Alert color="danger" sx={{ mb: 1 }}>{batchError}</Alert>}
          <Textarea
            minRows={6}
            placeholder='[{"username":"alice","email":"alice@example.com","password":"Secret1!"}]'
            value={batchInput}
            onChange={(e) => setBatchInput(e.target.value)}
          />
          <Box sx={{ mt: 1, display: 'flex', alignItems: 'center', gap: 1 }}>
            <Checkbox
              checked={batchSkipVerification}
              onChange={(e) => setBatchSkipVerification(e.target.checked)}
            />
            <Typography level="body-sm">Skip email verification for all</Typography>
          </Box>
          <Button sx={{ mt: 2 }} onClick={handleBatch} loading={isLoading} disabled={!batchInput.trim()}>
            Create Users
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
    </Box>
  );
};

export default AdminUsersPanel;
