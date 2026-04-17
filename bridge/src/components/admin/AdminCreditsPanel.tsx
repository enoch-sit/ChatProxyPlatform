// src/components/admin/AdminCreditsPanel.tsx
import React, { useEffect, useState } from 'react';
import {
  Box, Button, Typography, Sheet, Table, Modal, ModalDialog, ModalClose,
  Input, CircularProgress, Alert, Chip, FormLabel, FormControl, Stack,
} from '@mui/joy';
import { useAdminStore } from '../../store/adminStore';
import { useAuth } from '../../hooks/useAuth';
import type { CreditAllocation } from '../../types/admin';

type CreditAction = 'allocate' | 'set' | 'adjust' | 'remove';

const AdminCreditsPanel: React.FC = () => {
  const { user: currentUser } = useAuth();
  const {
    creditAllocations,
    isLoading,
    error,
    fetchAllCredits,
    allocateCredits,
    setCredits,
    removeCredits,
    adjustCredits,
    clearError,
  } = useAdminStore();

  const [success, setSuccess] = useState<string | null>(null);

  // Credit action modal
  const [showModal, setShowModal] = useState(false);
  const [actionType, setActionType] = useState<CreditAction>('allocate');
  const [targetUserId, setTargetUserId] = useState('');
  const [creditAmount, setCreditAmount] = useState('');
  const [expiryDays, setExpiryDays] = useState('');
  const [adjustReason, setAdjustReason] = useState('');

  // Self-allocate card
  const [selfCredits, setSelfCredits] = useState('');
  const [selfExpiryDays, setSelfExpiryDays] = useState('');

  useEffect(() => {
    fetchAllCredits().catch(() => {});
  }, []);

  const flash = (msg: string) => {
    setSuccess(msg);
    setTimeout(() => setSuccess(null), 3000);
  };

  const openModal = (action: CreditAction, allocation?: CreditAllocation) => {
    setActionType(action);
    setTargetUserId(allocation?.userId ?? '');
    setCreditAmount('');
    setExpiryDays('');
    setAdjustReason('');
    setShowModal(true);
  };

  const getUserLabel = (alloc: CreditAllocation) => {
    if (alloc.username) return `${alloc.username}${alloc.email ? ` (${alloc.email})` : ''}`;
    return alloc.userId;
  };

  const handleSubmit = async () => {
    const amount = parseInt(creditAmount, 10);
    try {
      if (actionType === 'allocate') {
        await allocateCredits({ userId: targetUserId, credits: amount, expiryDays: expiryDays ? parseInt(expiryDays) : undefined });
        flash('Credits allocated');
      } else if (actionType === 'set') {
        await setCredits({ userId: targetUserId, credits: amount });
        flash('Credits set');
      } else if (actionType === 'adjust') {
        await adjustCredits({ userId: targetUserId, adjustment: amount, reason: adjustReason || undefined });
        flash('Credits adjusted');
      } else if (actionType === 'remove') {
        await removeCredits({ userId: targetUserId });
        flash('Credits removed');
      }
      setShowModal(false);
    } catch {}
  };

  const handleSelfAllocate = async () => {
    if (!currentUser?.id) return;
    const amount = parseInt(selfCredits, 10);
    if (isNaN(amount) || amount <= 0) return;
    try {
      await allocateCredits({ userId: currentUser.id, credits: amount, expiryDays: selfExpiryDays ? parseInt(selfExpiryDays, 10) : undefined });
      setSelfCredits('');
      setSelfExpiryDays('');
      flash('Credits allocated to your account');
    } catch {}
  };

  const needsAmount = actionType !== 'remove';
  const submitDisabled = isLoading || !targetUserId || (needsAmount && (!creditAmount || isNaN(parseInt(creditAmount))));

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0, overflow: 'hidden' }}>
      <Typography level="h3" sx={{ mb: 2 }}>Credit Management</Typography>

      {success && <Alert color="success" sx={{ mb: 2 }}>{success}</Alert>}
      {error && <Alert color="danger" sx={{ mb: 2 }} endDecorator={<Button size="sm" variant="plain" color="danger" onClick={clearError}>Dismiss</Button>}>{error}</Alert>}

      {/* Self-Allocate Card */}
      {currentUser && (
        <Sheet variant="soft" color="primary" sx={{ p: 2, borderRadius: 'sm', mb: 3 }}>
          <Typography level="title-md" sx={{ mb: 1 }}>Add Credits to My Account</Typography>
          <Stack direction="row" spacing={1} alignItems="flex-end">
            <FormControl>
              <FormLabel>Credits</FormLabel>
              <Input
                type="number"
                placeholder="e.g. 5000"
                value={selfCredits}
                onChange={(e) => setSelfCredits(e.target.value)}
                sx={{ width: 130 }}
              />
            </FormControl>
            <FormControl>
              <FormLabel>Expiry (days, optional)</FormLabel>
              <Input
                type="number"
                placeholder="e.g. 30"
                value={selfExpiryDays}
                onChange={(e) => setSelfExpiryDays(e.target.value)}
                sx={{ width: 130 }}
              />
            </FormControl>
            <Button
              onClick={handleSelfAllocate}
              loading={isLoading}
              disabled={!selfCredits || isNaN(parseInt(selfCredits)) || parseInt(selfCredits) <= 0}
            >
              Allocate to Myself
            </Button>
          </Stack>
        </Sheet>
      )}

      {/* All Allocations Table */}
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
        <Typography level="title-md">All Users — Credit Balances</Typography>
        <Button size="sm" variant="outlined" onClick={() => fetchAllCredits()}>Refresh</Button>
      </Box>

      <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto', flex: 1, minHeight: 0 }}>
        <Table stickyHeader>
          <thead>
            <tr>
              <th>User</th>
              <th>Credits</th>
              <th>Used</th>
              <th>Remaining</th>
              <th>Expires</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {isLoading ? (
              <tr><td colSpan={6} align="center"><CircularProgress size="sm" /></td></tr>
            ) : creditAllocations.length === 0 ? (
              <tr><td colSpan={6}>No credit allocations found.</td></tr>
            ) : creditAllocations.map((alloc) => (
              <tr key={`${alloc.userId}-${alloc.expiresAt}`}>
                <td>{getUserLabel(alloc)}</td>
                <td>{alloc.totalCredits?.toLocaleString() ?? '—'}</td>
                <td>{alloc.usedCredits?.toLocaleString() ?? '—'}</td>
                <td>
                  <Chip
                    size="sm"
                    color={(alloc.remainingCredits ?? alloc.totalCredits ?? 0) > 0 ? 'success' : 'danger'}
                  >
                    {(alloc.remainingCredits ?? alloc.totalCredits ?? 0).toLocaleString()}
                  </Chip>
                </td>
                <td>{alloc.expiresAt ? new Date(alloc.expiresAt).toLocaleDateString() : 'Never'}</td>
                <td>
                  <Stack direction="row" spacing={0.5}>
                    <Button size="sm" variant="outlined" color="success" onClick={() => openModal('allocate', alloc)}>Add</Button>
                    <Button size="sm" variant="outlined" color="primary" onClick={() => openModal('set', alloc)}>Set</Button>
                    <Button size="sm" variant="outlined" color="neutral" onClick={() => openModal('adjust', alloc)}>Adjust</Button>
                    <Button size="sm" variant="outlined" color="danger" onClick={() => openModal('remove', alloc)}>Remove</Button>
                  </Stack>
                </td>
              </tr>
            ))}
          </tbody>
        </Table>
      </Sheet>

      {/* Credit Action Modal */}
      <Modal open={showModal} onClose={() => setShowModal(false)}>
        <ModalDialog sx={{ minWidth: 360 }}>
          <ModalClose />
          <Typography level="h4" sx={{ textTransform: 'capitalize' }}>{actionType} Credits</Typography>

          <FormControl sx={{ mt: 1 }}>
            <FormLabel>User ID</FormLabel>
            <Input
              value={targetUserId}
              onChange={(e) => setTargetUserId(e.target.value)}
              placeholder="MongoDB user _id"
            />
            {targetUserId && <Typography level="body-xs" sx={{ mt: 0.5 }}>{targetUserId}</Typography>}
          </FormControl>

          {needsAmount && (
            <FormControl sx={{ mt: 1 }}>
              <FormLabel>{actionType === 'adjust' ? 'Adjustment (positive or negative)' : 'Credits'}</FormLabel>
              <Input
                type="number"
                value={creditAmount}
                onChange={(e) => setCreditAmount(e.target.value)}
                placeholder={actionType === 'adjust' ? 'e.g. -500 or 1000' : 'e.g. 5000'}
              />
            </FormControl>
          )}

          {actionType === 'allocate' && (
            <FormControl sx={{ mt: 1 }}>
              <FormLabel>Expiry Days (optional)</FormLabel>
              <Input
                type="number"
                value={expiryDays}
                onChange={(e) => setExpiryDays(e.target.value)}
                placeholder="e.g. 30"
              />
            </FormControl>
          )}

          {actionType === 'adjust' && (
            <FormControl sx={{ mt: 1 }}>
              <FormLabel>Reason (optional)</FormLabel>
              <Input
                value={adjustReason}
                onChange={(e) => setAdjustReason(e.target.value)}
                placeholder="e.g. Promotional bonus"
              />
            </FormControl>
          )}

          {actionType === 'remove' && (
            <Alert color="warning" sx={{ mt: 1 }}>This will remove ALL credits from the user.</Alert>
          )}

          <Button sx={{ mt: 2 }} onClick={handleSubmit} loading={isLoading} disabled={submitDisabled} color={actionType === 'remove' ? 'danger' : 'primary'}>
            Confirm
          </Button>
        </ModalDialog>
      </Modal>
    </Box>
  );
};

export default AdminCreditsPanel;
