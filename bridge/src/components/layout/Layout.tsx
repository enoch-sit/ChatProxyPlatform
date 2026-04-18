// src/components/layout/Layout.tsx
import React, { useLayoutEffect, useRef } from 'react';
import { useLocation } from 'react-router-dom';
import Box from '@mui/joy/Box';
import Header from './Header';
import Sidebar from './Sidebar';

interface LayoutProps {
  children: React.ReactNode;
}

const Layout: React.FC<LayoutProps> = ({ children }) => {
  const location = useLocation();
  const mainRef = useRef<HTMLElement>(null);

  // Reset Box[main] scroll offset on every route change.
  // Without this, scrolling admin page then navigating to chat
  // leaves the viewport displaced, causing the smooth-scroll animation
  // in MessageList to play from the wrong starting position.
  useLayoutEffect(() => {
    if (mainRef.current) {
      mainRef.current.scrollTop = 0;
    }
  }, [location.pathname]);

  return (
    <Box sx={{ display: 'flex', height: '100vh' }}>
      <Sidebar />
      <Box
        ref={mainRef}
        component="main"
        sx={{
          flexGrow: 1,
          minWidth: 0,
          overflow: location.pathname.startsWith('/admin') ? 'hidden' : 'auto',
          bgcolor: 'background.body',
          p: 3,
          display: 'flex',
          flexDirection: 'column',
        }}
      >
        <Header />
        <Box sx={{ flexGrow: 1, minHeight: 0, overflow: location.pathname.startsWith('/admin') ? 'hidden' : 'hidden' }}>
          {children}
        </Box>
      </Box>
    </Box>
  );
};

export default Layout;

