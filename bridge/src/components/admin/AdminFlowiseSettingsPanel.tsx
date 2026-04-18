import React, { useEffect, useState } from 'react';
import { Box, Button, Typography, Alert, Input, Sheet, CircularProgress, Chip } from '@mui/joy';
import {
  getFlowiseApiKeyStatus,
  updateFlowiseApiKey,
  testFlowiseApiKey,
  type FlowiseApiKeyStatus,
  type FlowiseApiKeyTestResult,
} from '../../api/admin';

const AdminFlowiseSettingsPanel: React.FC = () => {
  const [status, setStatus] = useState<FlowiseApiKeyStatus | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [isTesting, setIsTesting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [testResult, setTestResult] = useState<FlowiseApiKeyTestResult | null>(null);

  const loadStatus = async () => {
    setIsLoading(true);
    setError(null);
    try {
      const result = await getFlowiseApiKeyStatus();
      setStatus(result);
    } catch (e: unknown) {
      const err = e as { response?: { data?: { detail?: string; message?: string } }; message?: string };
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to load Flowise key status');
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    loadStatus().catch(() => {});
  }, []);

  const handleSave = async () => {
    const trimmed = apiKey.trim();
    if (!trimmed) {
      setError('Please enter a Flowise API key.');
      return;
    }

    setIsSaving(true);
    setError(null);
    setSuccess(null);
    try {
      await updateFlowiseApiKey(trimmed);
      setSuccess('Flowise API key updated. New requests will use it immediately.');
      setApiKey('');
      await loadStatus();
    } catch (e: unknown) {
      const err = e as { response?: { data?: { detail?: string; message?: string } }; message?: string };
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to update Flowise API key');
    } finally {
      setIsSaving(false);
    }
  };

  const handleTest = async () => {
    setIsTesting(true);
    setError(null);
    setTestResult(null);
    try {
      const result = await testFlowiseApiKey(apiKey.trim() || undefined);
      setTestResult(result);
    } catch (e: unknown) {
      const err = e as { response?: { data?: { detail?: string; message?: string } }; message?: string };
      setError(err?.response?.data?.detail || err?.response?.data?.message || err?.message || 'Failed to test Flowise API key');
    } finally {
      setIsTesting(false);
    }
  };

  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        justifyContent: 'flex-start',
        alignItems: 'stretch',
        gap: 2,
        minHeight: 0,
        overflow: 'auto',
      }}
    >
      <Typography level="h3">Flowise API Key</Typography>
      <Typography level="body-sm">
        Update the proxy key at runtime. This does not require restarting Docker services.
      </Typography>

      {error && <Alert color="danger">{error}</Alert>}
      {success && <Alert color="success">{success}</Alert>}

      <Sheet variant="outlined" sx={{ borderRadius: 'sm', p: 2 }}>
        {isLoading ? (
          <CircularProgress size="sm" />
        ) : (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Typography level="body-sm">Status:</Typography>
              <Chip color={status?.configured ? 'success' : 'neutral'} size="sm">
                {status?.configured ? 'Configured' : 'Not configured'}
              </Chip>
            </Box>
            <Typography level="body-sm">Source: {status?.source || 'unknown'}</Typography>
            <Typography level="body-sm">Current key: {status?.masked_key || '(not set)'}</Typography>
          </Box>
        )}
      </Sheet>

      <Input
        value={apiKey}
        onChange={(e) => setApiKey(e.target.value)}
        placeholder="Paste Flowise API key"
        type="password"
      />

      <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
        <Button onClick={handleSave} loading={isSaving} disabled={isSaving || isTesting}>
          Save Key
        </Button>
        <Button variant="outlined" onClick={handleTest} loading={isTesting} disabled={isSaving || isTesting}>
          Test Key
        </Button>
        <Button variant="plain" onClick={() => loadStatus()} disabled={isSaving || isTesting}>
          Refresh Status
        </Button>
      </Box>

      {testResult && (
        <Alert color={testResult.valid ? 'success' : 'warning'}>
          {testResult.message}
          {typeof testResult.status_code === 'number' ? ` (status ${testResult.status_code})` : ''}
        </Alert>
      )}
    </Box>
  );
};

export default AdminFlowiseSettingsPanel;
