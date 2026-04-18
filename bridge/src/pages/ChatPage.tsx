// src/pages/ChatPage.tsx

/**
 * This file implements the main chat user interface page.
 * It serves as the primary view where users interact with chatflows and sessions.
 * The component orchestrates the UI by fetching data from and dispatching actions to
 * the `useChatStore`, effectively decoupling the UI from the business logic.
 *
 * The page is responsible for:
 * - Displaying lists of available chatflows and sessions.
 * - Allowing users to select a chatflow and session to interact with.
 * - Providing a mechanism to create new chat sessions.
 * - Rendering the `MessageList` for the conversation history.
 * - Rendering the `ChatInput` for sending new messages.
 * - Displaying loading and error states to the user.
 */

import React, { useEffect, useState } from 'react';
import {
  Box,
  Sheet,
  Typography,
  Button,
  Select,
  Option,
  Alert,
  Stack, // Add Stack here
  IconButton,
  Tooltip,
} from '@mui/joy';

import { NoSsr } from '@mui/material';
import { useTranslation } from 'react-i18next';
import { useChatStore } from '../store/chatStore';
import MessageList from '../components/chat/MessageList';
import ChatInput from '../components/chat/ChatInput';
import ChatLayout from '../components/layout/ChatLayout';
import PinnedMessagesPanel from '../components/chat/PinnedMessagesPanel';
import QuestionAnswerIcon from '@mui/icons-material/QuestionAnswer';
import AddIcon from '@mui/icons-material/Add';
import ArrowUpwardIcon from '@mui/icons-material/ArrowUpward';
import PushPinIcon from '@mui/icons-material/PushPin';

const ChatPage: React.FC = () => {
  const { t } = useTranslation();
  const [showPinnedPanel, setShowPinnedPanel] = useState(false);

  // Destructure all necessary state and actions from the central chat store.
  // This is the primary way the component interacts with the application's state.
  const {
    chatflows,
    sessions,
    currentSession,
    currentChatflow,
    messages,
    isLoading,
    error,
    loadChatflows,
    loadSessions,
    setCurrentChatflow,
    setCurrentSession,
    clearSession,
    setError,
    streamAssistantResponse,
  } = useChatStore();

  // On component mount, load the initial data required for the page.
  useEffect(() => {
    loadChatflows();
    loadSessions();
  }, [loadChatflows, loadSessions]);

  /**
   * Handles the user clicking the "New Chat" button.
   * This clears the current session so the next message starts a new conversation.
   */
  const handleNewChat = () => {
    clearSession();
  };

  /**
   * Handles the user selecting a different chatflow from the dropdown.
   * It updates the store, which will trigger a re-render and clear the session.
   */
  const handleChatflowChange = (
    _event: React.SyntheticEvent | null,
    newValue: string | null
  ) => {
    if (newValue) {
      const selectedChatflow = chatflows.find(cf => cf.id === newValue);
      if (selectedChatflow) {
        setCurrentChatflow(selectedChatflow);
        setCurrentSession(null); // Clearing the session prompts the user to select or create one.
      }
    }
  };

  /**
   * Handles the user selecting a different session from the dropdown.
   * The store action will then take care of loading the message history for that session.
   */
  const handleSessionChange = (_event: any, newValue: string | null) => {
    console.log('Session change triggered with value:', newValue);
    if (newValue && sessions) {
      const selectedSession = sessions.find(s => s.session_id === newValue); // ✅ Use session_id
      console.log('Found session:', selectedSession);
      if (selectedSession) {
        setCurrentSession(selectedSession);
      }
    }
  };

  /**
   * Handles the "Let's learn" button click to start the conversation.
   * Sends an initial greeting message to the selected chatflow.
   */
  const handleLetsLearn = async () => {
    if (!currentChatflow) return;
    
    // Send a friendly greeting message to start the conversation
    const greetingMessage = t('chat.quickReplies.letsLearn');
    await streamAssistantResponse(greetingMessage);
  };

  return (
    <Box sx={{ height: '100%', display: 'flex', flexDirection: 'row' }}>
      {/* Main Content - Left Side */}
      <Box sx={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {/* Header Section: Contains controls for selecting chatflows and sessions */}
        <Sheet variant="outlined" sx={{ p: 1.5, borderBottom: '1px solid', borderColor: 'divider' }}>
          <Stack direction="row" spacing={2} alignItems="center">
            <Select 
              placeholder={t('chat.selectChatflow')} 
              value={currentChatflow?.id || ''} 
              onChange={handleChatflowChange} 
              startDecorator={<QuestionAnswerIcon />} 
              sx={{ minWidth: 200 }} 
              disabled={isLoading}>
              {chatflows.map((chatflow) => (<Option key={chatflow.id} value={chatflow.id}>{chatflow.name}</Option>))}
            </Select>
            <NoSsr>
            <Select 
              placeholder={t('chat.selectSession')} 
              value={currentSession?.session_id || ''} 
              onChange={handleSessionChange} 
              sx={{ minWidth: 200 }} 
              disabled={!currentChatflow || isLoading}
            >
              {sessions
                .filter(s => s.chatflow_id === currentChatflow?.id)
                .map((session, idx) => (
                  <Option key={String(session.session_id) + String(idx)} value={session.session_id}>
                    {session.topic}
                  </Option>
                ))}
            </Select>
            </NoSsr>
            
            {/* New Chat Button */}
            <Button
              variant="outlined"
              startDecorator={<AddIcon />}
              onClick={handleNewChat}
              disabled={!currentChatflow || isLoading}
              sx={{ minWidth: 120 }}
            >
              {t('chat.newChat')}
            </Button>
            
            <Box sx={{ flexGrow: 1 }} />
            
            <Tooltip title={showPinnedPanel ? t('chat.hidePinnedMessages') : t('chat.showPinnedMessages')}>
              <IconButton
                variant={showPinnedPanel ? 'solid' : 'outlined'}
                color={showPinnedPanel ? 'primary' : 'neutral'}
                size="sm"
                onClick={() => setShowPinnedPanel(!showPinnedPanel)}
              >
                <PushPinIcon />
              </IconButton>
            </Tooltip>
          </Stack>
        </Sheet>

      {/* Error Display: Shows any errors that occur during API calls or streaming */}
      {error && (<Alert color="danger" variant="soft" endDecorator={<Button size="sm" variant="plain" onClick={() => setError(null)}>{t('common.close')}</Button>} sx={{ m: 2 }}>{error}</Alert>)}

        {/* Main Content Area */}
        <Box sx={{ flex: 1, overflow: 'hidden', minHeight: 0 }}>
          {currentChatflow ? (
          <ChatLayout
            messages={
              messages.length === 0 && !isLoading ? (
                // Show "Let's learn" button when chatflow is selected but no messages exist
                <Box sx={{ 
                  height: '100%', 
                  display: 'flex', 
                  alignItems: 'center', 
                  justifyContent: 'center', 
                  textAlign: 'center',
                  px: 4,
                }}>
                  <Stack spacing={3} alignItems="center">
                    <Typography level="h3" color="primary">
                      {currentChatflow.name}
                    </Typography>
                    <Typography level="body-md" color="neutral" sx={{ opacity: 0.8 }}>
                      {t('chat.selectChatflowDescription', { defaultValue: 'Ready to start learning? Click the button below!' })}
                    </Typography>
                    <Button
                      size="lg"
                      variant="solid"
                      color="primary"
                      onClick={handleLetsLearn}
                      sx={{
                        fontSize: '1.25rem',
                        fontWeight: 'bold',
                        py: 2,
                        px: 4,
                        borderRadius: '12px',
                        boxShadow: '0 4px 12px rgba(0,0,0,0.15)',
                        '&:hover': {
                          transform: 'translateY(-2px)',
                          boxShadow: '0 6px 20px rgba(0,0,0,0.2)',
                        },
                        transition: 'all 0.2s ease-in-out',
                      }}
                    >
                      🚀 {t('chat.quickReplies.letsLearn')}
                    </Button>
                  </Stack>
                </Box>
              ) : (
                <MessageList />
              )
            }
            input={<ChatInput />}
          />
        ) : (
          // Placeholder view when no chatflow is selected with cute arrow pointing up
          <Box sx={{ 
            height: '100%', 
            display: 'flex', 
            alignItems: 'center', 
            justifyContent: 'center', 
            textAlign: 'center',
            px: 4,
            position: 'relative'
          }}>
            {/* Cute bouncing arrow pointing up to chatflow selection */}
            <Box sx={{
              position: 'absolute',
              top: '10%',
              left: '10%',
              transform: 'translateX(-50%)',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 1,
              animation: 'bounce 2s infinite',
              '@keyframes bounce': {
                '0%, 20%, 50%, 80%, 100%': {
                  transform: 'translateX(-50%) translateY(0)',
                },
                '40%': {
                  transform: 'translateX(-50%) translateY(-10px)',
                },
                '60%': {
                  transform: 'translateX(-50%) translateY(-5px)',
                },
              }
            }}>
              <ArrowUpwardIcon 
                sx={{ 
                  fontSize: '3rem', 
                  color: 'primary.500',
                  filter: 'drop-shadow(0 2px 8px rgba(0,0,0,0.2))'
                }} 
              />
              <Typography level="body-sm" color="primary" sx={{ fontWeight: 600 }}>
                {t('chat.selectChatflowHint', { defaultValue: 'Pick a chatflow above! 👆' })}
              </Typography>
            </Box>

            <Stack spacing={2} sx={{ mt: 8 }}>
              <Typography level="h4" color="neutral">
                {t('chat.selectChatflowPrompt')}
              </Typography>
              <Typography level="body-md" color="neutral" sx={{ opacity: 0.7 }}>
                {t('chat.selectChatflowDescription', { defaultValue: 'Choose from the dropdown menu above to start chatting!' })}
              </Typography>
            </Stack>
          </Box>
        )}
        </Box>
      </Box>
      
      {/* Pinned Messages Panel - Fixed at Far Right */}
      {showPinnedPanel && (
        <Box sx={{ 
          width: '600px', 
          minWidth: '600px',
          maxWidth: '600px',
          borderLeft: '1px solid', 
          borderColor: 'divider',
          overflow: 'hidden',
          backgroundColor: 'background.surface',
          boxShadow: '-2px 0 8px rgba(0,0,0,0.1)',
          zIndex: 1,
          transition: 'all 0.3s ease-in-out'
        }}>
          <PinnedMessagesPanel />
        </Box>
      )}
    </Box>
  );
};

export default ChatPage;