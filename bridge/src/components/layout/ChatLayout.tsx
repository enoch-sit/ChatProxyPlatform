// src/components/layout/ChatLayout.tsx

import React from 'react';
import { Box } from '@mui/joy';

interface ChatLayoutProps {
  header?: React.ReactNode;
  messages: React.ReactNode;
  input: React.ReactNode;
  children?: React.ReactNode;
}

/**
 * ChatLayout provides a specialized layout for chat interfaces.
 * Uses pure CSS flex — no JS measurement needed.
 * Requires the parent to have a definite height (e.g. flexGrow:1, height:0).
 */
const ChatLayout: React.FC<ChatLayoutProps> = ({
  header,
  messages,
  input,
  children,
}) => {
  return (
    <Box
      sx={{
        height: '100%',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
      }}
    >
      {/* Optional header */}
      {header && (
        <Box sx={{ flexShrink: 0 }}>
          {header}
        </Box>
      )}

      {/* Scrollable messages area — fills all remaining space */}
      <Box
        data-chat-scroll-container="true"
        sx={{
          flex: 1,
          minHeight: 0,
          overflowY: 'auto',
          overflowX: 'hidden',
          position: 'relative',
        }}
      >
        {messages}
      </Box>

      {/* Additional content if needed */}
      {children}

      {/* Input pinned at bottom */}
      <Box
        sx={{
          flexShrink: 0,
          backgroundColor: 'background.body',
          borderTop: '1px solid',
          borderColor: 'divider',
        }}
      >
        {input}
      </Box>
    </Box>
  );
};

export default ChatLayout;
