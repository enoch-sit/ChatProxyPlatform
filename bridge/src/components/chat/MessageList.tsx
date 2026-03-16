import React, { useEffect, useRef } from 'react';
import { Box } from '@mui/joy';
import { useChatStore } from '../../store/chatStore';
import MessageBubble from './MessageBubble';

const MessageList: React.FC = () => {
  const messages = useChatStore((state) => state.messages);
  const isStreaming = useChatStore((state) => state.isStreaming);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new messages arrive or streaming updates.
  // Scroll only the dedicated chat scroll container to avoid moving page/main.
  useEffect(() => {
    if (messagesEndRef.current) {
      const container = messagesEndRef.current.closest('[data-chat-scroll-container="true"]') as HTMLElement | null;
      if (container) {
        container.scrollTop = container.scrollHeight;
      }
    }
  }, [messages, isStreaming]);

  return (
    <Box sx={{ 
      height: '100%',
      p: 2,
    }}>
      {messages.map((msg, idx) => (
        <MessageBubble key={String(msg.id) + String(idx)} message={msg} />
      ))}
      {/* Invisible element to scroll to */}
      <div ref={messagesEndRef} />
    </Box>
  );
};

export default MessageList;

