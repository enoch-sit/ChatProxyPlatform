// src/components/admin/AdminChatHistoryPanel.tsx
import React, { useEffect, useState } from 'react';
import {
  Box, Button, Typography, Sheet, Input, CircularProgress, Alert, Chip, Stack,
} from '@mui/joy';
import { adminListChatUsers, adminGetUserSessions } from '../../api/admin';
import { getSessionHistory } from '../../api/sessions';
import type { AdminChatUser, AdminChatSession } from '../../api/admin';
import type { Message } from '../../types/chat';

const AdminChatHistoryPanel: React.FC = () => {
  // User list
  const [users, setUsers] = useState<AdminChatUser[]>([]);
  const [usersLoading, setUsersLoading] = useState(false);
  const [usersError, setUsersError] = useState<string | null>(null);
  const [userSearch, setUserSearch] = useState('');

  // Sessions list for selected user
  const [selectedUser, setSelectedUser] = useState<AdminChatUser | null>(null);
  const [sessions, setSessions] = useState<AdminChatSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);

  // Messages for selected session
  const [selectedSession, setSelectedSession] = useState<AdminChatSession | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [messagesLoading, setMessagesLoading] = useState(false);

  useEffect(() => {
    setUsersLoading(true);
    adminListChatUsers()
      .then(setUsers)
      .catch((e) => setUsersError(e?.message || 'Failed to load users'))
      .finally(() => setUsersLoading(false));
  }, []);

  const handleSelectUser = async (u: AdminChatUser) => {
    setSelectedUser(u);
    setSelectedSession(null);
    setMessages([]);
    setSessionsLoading(true);
    try {
      const result = await adminGetUserSessions(u.user_id);
      setSessions(result);
    } catch {
      setSessions([]);
    } finally {
      setSessionsLoading(false);
    }
  };

  const handleSelectSession = async (s: AdminChatSession) => {
    setSelectedSession(s);
    setMessagesLoading(true);
    try {
      const msgs = await getSessionHistory(s.session_id);
      setMessages(msgs);
    } catch {
      setMessages([]);
    } finally {
      setMessagesLoading(false);
    }
  };

  const handleExport = () => {
    if (!selectedSession || messages.length === 0) return;
    const lines = messages.map(
      (m) => `[${m.timestamp ? new Date(m.timestamp).toLocaleString() : ''}] ${m.role === 'user' ? 'Student' : 'AI'}: ${m.content}`
    );
    const header = [
      `Student Chat Export`,
      `User: ${selectedUser?.username ?? selectedUser?.email ?? ''}`,
      `Session: ${selectedSession.session_id}`,
      `Date: ${selectedSession.created_at ? new Date(selectedSession.created_at).toLocaleString() : 'unknown'}`,
      `Messages: ${messages.length}`,
      '',
      '---',
      '',
    ];
    const blob = new Blob([[...header, ...lines].join('\n')], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `chat_${selectedUser?.username ?? 'user'}_${selectedSession.session_id.slice(0, 8)}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const filteredUsers = users.filter((u) => {
    const q = userSearch.toLowerCase();
    return !q || u.username.toLowerCase().includes(q) || u.email.toLowerCase().includes(q);
  });

  return (
    <Box sx={{ display: 'flex', height: 'calc(100vh - 220px)', gap: 1 }}>
      {/* Left pane: user list */}
      <Sheet
        variant="outlined"
        sx={{ width: 220, borderRadius: 'sm', display: 'flex', flexDirection: 'column', overflow: 'hidden', flexShrink: 0 }}
      >
        <Box sx={{ p: 1, borderBottom: '1px solid', borderColor: 'divider' }}>
          <Typography level="title-sm" sx={{ mb: 0.5 }}>Students</Typography>
          <Input
            size="sm"
            placeholder="Search..."
            value={userSearch}
            onChange={(e) => setUserSearch(e.target.value)}
          />
        </Box>
        <Box sx={{ flex: 1, overflowY: 'auto' }}>
          {usersLoading && <Box sx={{ p: 2, textAlign: 'center' }}><CircularProgress size="sm" /></Box>}
          {usersError && <Alert color="danger" size="sm" sx={{ m: 1 }}>{usersError}</Alert>}
          {filteredUsers.map((u) => (
            <Box
              key={u.user_id}
              onClick={() => handleSelectUser(u)}
              sx={{
                px: 1.5, py: 1, cursor: 'pointer',
                bgcolor: selectedUser?.user_id === u.user_id ? 'primary.softBg' : 'transparent',
                '&:hover': { bgcolor: 'neutral.softHoverBg' },
                borderBottom: '1px solid', borderColor: 'divider',
              }}
            >
              <Typography level="body-sm" noWrap>{u.username}</Typography>
              <Typography level="body-xs" noWrap sx={{ color: 'text.tertiary' }}>{u.email}</Typography>
              <Chip size="sm" color="neutral" sx={{ mt: 0.25 }}>{u.session_count} sessions</Chip>
            </Box>
          ))}
        </Box>
      </Sheet>

      {/* Middle pane: session list */}
      <Sheet
        variant="outlined"
        sx={{ width: 240, borderRadius: 'sm', display: 'flex', flexDirection: 'column', overflow: 'hidden', flexShrink: 0 }}
      >
        <Box sx={{ p: 1, borderBottom: '1px solid', borderColor: 'divider' }}>
          <Typography level="title-sm">
            {selectedUser ? `${selectedUser.username}'s Sessions` : 'Select a student'}
          </Typography>
        </Box>
        <Box sx={{ flex: 1, overflowY: 'auto' }}>
          {sessionsLoading && <Box sx={{ p: 2, textAlign: 'center' }}><CircularProgress size="sm" /></Box>}
          {!sessionsLoading && selectedUser && sessions.length === 0 && (
            <Typography level="body-sm" sx={{ p: 2, color: 'text.tertiary' }}>No sessions found.</Typography>
          )}
          {sessions.map((s) => (
            <Box
              key={s.session_id}
              onClick={() => handleSelectSession(s)}
              sx={{
                px: 1.5, py: 1, cursor: 'pointer',
                bgcolor: selectedSession?.session_id === s.session_id ? 'primary.softBg' : 'transparent',
                '&:hover': { bgcolor: 'neutral.softHoverBg' },
                borderBottom: '1px solid', borderColor: 'divider',
              }}
            >
              <Typography level="body-sm" noWrap>{s.topic || `Session ${s.session_id.slice(0, 8)}`}</Typography>
              <Typography level="body-xs" sx={{ color: 'text.tertiary' }}>
                {s.created_at ? new Date(s.created_at).toLocaleDateString() : '—'}
              </Typography>
              <Typography level="body-xs" sx={{ color: 'text.tertiary' }}>
                {s.message_count} messages
              </Typography>
            </Box>
          ))}
        </Box>
      </Sheet>

      {/* Right pane: conversation */}
      <Sheet
        variant="outlined"
        sx={{ flex: 1, borderRadius: 'sm', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}
      >
        <Box sx={{ p: 1, borderBottom: '1px solid', borderColor: 'divider', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Typography level="title-sm">
            {selectedSession
              ? (selectedSession.topic || `Session ${selectedSession.session_id.slice(0, 8)}`)
              : 'Select a session'}
          </Typography>
          {selectedSession && messages.length > 0 && (
            <Button size="sm" variant="outlined" onClick={handleExport}>Export .txt</Button>
          )}
        </Box>

        <Box sx={{ flex: 1, overflowY: 'auto', p: 1.5 }}>
          {messagesLoading && <Box sx={{ textAlign: 'center', p: 4 }}><CircularProgress /></Box>}
          {!messagesLoading && selectedSession && messages.length === 0 && (
            <Typography level="body-sm" sx={{ color: 'text.tertiary' }}>No messages in this session.</Typography>
          )}
          {!messagesLoading && !selectedSession && (
            <Typography level="body-sm" sx={{ color: 'text.tertiary' }}>
              Select a student and then a session to view the conversation.
            </Typography>
          )}
          {messages.map((msg, idx) => (
            <Box
          key={msg.id ?? String(idx)}
              sx={{
                mb: 1.5,
                display: 'flex',
                flexDirection: 'column',
                alignItems: msg.role === 'user' ? 'flex-end' : 'flex-start',
              }}
            >
              <Box
                sx={{
                  maxWidth: '75%',
                  bgcolor: msg.role === 'user' ? 'primary.softBg' : 'neutral.softBg',
                  borderRadius: 'md',
                  px: 1.5,
                  py: 0.75,
                }}
              >
                <Stack direction="row" spacing={1} sx={{ mb: 0.5 }} alignItems="center">
                  <Chip size="sm" color={msg.role === 'user' ? 'primary' : 'neutral'}>
                    {msg.role === 'user' ? 'Student' : 'AI'}
                  </Chip>
                  {msg.timestamp && (
                    <Typography level="body-xs" sx={{ color: 'text.tertiary' }}>
                      {new Date(msg.timestamp).toLocaleString()}
                    </Typography>
                  )}
                </Stack>
                <Typography level="body-sm" sx={{ whiteSpace: 'pre-wrap', wordBreak: 'break-word' }}>
                  {msg.content}
                </Typography>
              </Box>
            </Box>
          ))}
        </Box>
      </Sheet>
    </Box>
  );
};

export default AdminChatHistoryPanel;
