// src/App.tsx
import { useEffect } from 'react';
import { CssVarsProvider } from '@mui/joy/styles';
import { BrowserRouter as Router, Routes, Route, Navigate, useNavigate } from 'react-router-dom';
import CssBaseline from '@mui/joy/CssBaseline';
import Box from '@mui/joy/Box';
import CircularProgress from '@mui/joy/CircularProgress';
import { useAuth } from './hooks/useAuth';
import { useAuthStore } from './store/authStore';
import { setNavigate } from './api/navigationService';
import LoginPage from './pages/LoginPage';
import ChatPage from './pages/ChatPage';
import AdminPage from './pages/AdminPage';
import DashboardPage from './pages/DashboardPage';
import ProtectedRoute from './components/auth/ProtectedRoute';
import Layout from './components/layout/Layout';
import { APP_ENTRY_PATH } from './api/config';
import './i18n';

/** Wires the imperative navigation singleton so the Zustand store can redirect. */
function NavigateSetter() {
  const navigate = useNavigate();
  useEffect(() => { setNavigate(navigate); }, [navigate]);
  return null;
}

function App() {
  const { checkAuthStatus, isAuthenticated, tokens, hasHydrated } = useAuth();

  useEffect(() => {
    // On mount, immediately mark as hydrated to unblock UI
    // Zustand's persist middleware handles storage rehydration
    useAuthStore.setState({ hasHydrated: true });
    
    // Check authentication status on app start (foreground check)
    checkAuthStatus();
    
    // Set up background token refresh interval
    const interval = setInterval(() => {
      // Check tokens regardless of page visibility to prevent expiration
      // The server-side refresh handles the actual token validation
      console.log('🕐 Running background token check...');
      checkAuthStatus(true); // Pass true for background check
    }, 50 * 60 * 1000); // 50 minutes (10 min before 1h expiration)

    // Also check when page becomes visible again (user switches back to tab)
    const handleVisibilityChange = () => {
      if (!document.hidden) {
        console.log('👁️ Page became visible - checking token status');
        checkAuthStatus(true);
      }
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);

    // Clean up on component unmount
    return () => {
      clearInterval(interval);
      document.removeEventListener('visibilitychange', handleVisibilityChange);
    };
  }, [checkAuthStatus]);

  const hasAccessToken = !!tokens?.accessToken;

  if (!hasHydrated) {
    return (
      <CssVarsProvider defaultMode="system">
        <CssBaseline />
        <Box
          sx={{
            minHeight: '100vh',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <CircularProgress />
        </Box>
      </CssVarsProvider>
    );
  }

  return (
    <Router>
      <NavigateSetter />
      <CssVarsProvider defaultMode="system">
        <CssBaseline />
        <Routes>
          <Route 
            path="/login" 
            element={
              isAuthenticated && hasAccessToken ? <Navigate to="/chat" replace /> : <LoginPage />
            } 
          />
          
          <Route
            path={APP_ENTRY_PATH}
            element={isAuthenticated && hasAccessToken ? <Navigate to="/chat" replace /> : <LoginPage />}
          />
          
          <Route
            path="/dashboard"
            element={
              <ProtectedRoute>
                <Layout key="dashboard-layout">
                  <DashboardPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          
          <Route
            path="/chat"
            element={
              <ProtectedRoute>
                <Layout key="chat-layout">
                  <ChatPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          
          <Route
            path="/admin"
            element={
              <ProtectedRoute requiredRole={['admin', 'supervisor', 'teacher']}>
                <Layout key="admin-layout">
                  <AdminPage />
                </Layout>
              </ProtectedRoute>
            }
          />
        </Routes>
      </CssVarsProvider>
    </Router>
  );
}

export default App;