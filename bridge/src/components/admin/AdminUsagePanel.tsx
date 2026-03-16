// src/components/admin/AdminUsagePanel.tsx
import React, { useEffect } from 'react';
import {
  Box, Button, Typography, Sheet, Table, CircularProgress, Alert, Stack, Card, CardContent,
} from '@mui/joy';
import { useAdminStore } from '../../store/adminStore';

const AdminUsagePanel: React.FC = () => {
  const { systemStats, isLoading, error, fetchSystemStats, clearError } = useAdminStore();

  useEffect(() => {
    fetchSystemStats().catch(() => {});
  }, []);

  const byUser: any[] = systemStats?.byUser ?? [];

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
        <Typography level="h3">Token Usage &amp; Stats</Typography>
        <Button size="sm" variant="outlined" onClick={() => fetchSystemStats()}>Refresh</Button>
      </Box>

      {error && (
        <Alert color="danger" sx={{ mb: 2 }} endDecorator={
          <Button size="sm" variant="plain" color="danger" onClick={clearError}>Dismiss</Button>
        }>
          {error}
        </Alert>
      )}

      {isLoading && !systemStats && (
        <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
          <CircularProgress />
        </Box>
      )}

      {systemStats && (
        <>
          {/* Summary Cards */}
          <Stack direction="row" spacing={2} sx={{ mb: 3, flexWrap: 'wrap' }}>
            {systemStats.totalUsers !== undefined && (
              <Card variant="soft" color="neutral" sx={{ minWidth: 160 }}>
                <CardContent>
                  <Typography level="body-xs">Total Users</Typography>
                  <Typography level="h2">{systemStats.totalUsers.toLocaleString()}</Typography>
                </CardContent>
              </Card>
            )}
            {systemStats.totalRequests !== undefined && (
              <Card variant="soft" color="primary" sx={{ minWidth: 160 }}>
                <CardContent>
                  <Typography level="body-xs">Total Requests</Typography>
                  <Typography level="h2">{systemStats.totalRequests.toLocaleString()}</Typography>
                </CardContent>
              </Card>
            )}
            {systemStats.totalTokensUsed !== undefined && (
              <Card variant="soft" color="success" sx={{ minWidth: 160 }}>
                <CardContent>
                  <Typography level="body-xs">Total Tokens</Typography>
                  <Typography level="h2">{systemStats.totalTokensUsed.toLocaleString()}</Typography>
                </CardContent>
              </Card>
            )}
            {systemStats.totalCost !== undefined && (
              <Card variant="soft" color="warning" sx={{ minWidth: 160 }}>
                <CardContent>
                  <Typography level="body-xs">Total Cost (USD)</Typography>
                  <Typography level="h2">${systemStats.totalCost.toFixed(4)}</Typography>
                </CardContent>
              </Card>
            )}
          </Stack>

          {/* Per-User Table */}
          {byUser.length > 0 && (
            <>
              <Typography level="title-md" sx={{ mb: 1 }}>Per-User Breakdown</Typography>
              <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto' }}>
                <Table stickyHeader>
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Requests</th>
                      <th>Tokens Used</th>
                      <th>Cost (USD)</th>
                      <th>Last Used</th>
                    </tr>
                  </thead>
                  <tbody>
                    {byUser.map((stat: any) => (
                      <tr key={stat.userId}>
                        <td>{stat.username ?? stat.email ?? stat.userId}</td>
                        <td>{(stat.requestCount ?? 0).toLocaleString()}</td>
                        <td>{(stat.totalTokens ?? 0).toLocaleString()}</td>
                        <td>{stat.totalCost != null ? `$${parseFloat(stat.totalCost).toFixed(4)}` : '—'}</td>
                        <td>{stat.lastUsed ? new Date(stat.lastUsed).toLocaleDateString() : '—'}</td>
                      </tr>
                    ))}
                  </tbody>
                </Table>
              </Sheet>
            </>
          )}

          {/* Chatflow breakdown */}
          {systemStats.byModel && Object.keys(systemStats.byModel).length > 0 && (
            <Box sx={{ mt: 3 }}>
              <Typography level="title-md" sx={{ mb: 1 }}>By Chatflow</Typography>
              <Sheet variant="outlined" sx={{ borderRadius: 'sm', overflow: 'auto' }}>
                <Table>
                  <thead>
                    <tr>
                      <th>Chatflow ID</th>
                      <th>Credits Used</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(systemStats.byModel).map(([model, tokens]) => (
                      <tr key={model}>
                        <td>{model}</td>
                        <td>{(tokens as number).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </Table>
              </Sheet>
            </Box>
          )}

          {/* Raw JSON fallback if there's extra data */}
          {byUser.length === 0 && !systemStats.totalRequests && (
            <Sheet variant="outlined" sx={{ p: 2, borderRadius: 'sm', mt: 2 }}>
              <Typography level="body-sm" sx={{ mb: 1 }}>Raw stats data:</Typography>
              <pre style={{ margin: 0, fontSize: '0.75rem', overflow: 'auto' }}>
                {JSON.stringify(systemStats, null, 2)}
              </pre>
            </Sheet>
          )}
        </>
      )}
    </Box>
  );
};

export default AdminUsagePanel;
