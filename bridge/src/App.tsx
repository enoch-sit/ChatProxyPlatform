// src/App.tsx
import { useEffect } from 'react';
import { CssVarsProvider } from '@mui/joy/styles';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import CssBaseline from '@mui/joy/CssBaseline';
import { useAuth } from './hooks/useAuth';
import LoginPage from './pages/LoginPage';
import ChatPage from './pages/ChatPage';
import AdminPage from './pages/AdminPage';
import DashboardPage from './pages/DashboardPage';
import ProtectedRoute from './components/auth/ProtectedRoute';
import Layout from './components/layout/Layout';
import './i18n';

function App() {
  const { checkAuthStatus, user } = useAuth();

  useEffect(() => {
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

  return (
    <Router>
      <CssVarsProvider defaultMode="system">
        <CssBaseline />
        <Routes>
          <Route 
            path="/login" 
            element={
              user ? <Navigate to="/chat" replace /> : <LoginPage />
            } 
          />
          
          <Route path="/" element={<Navigate to="/chat" replace />} />
          
          <Route
            path="/dashboard"
            element={
              <ProtectedRoute>
                <Layout>
                  <DashboardPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          
          <Route
            path="/chat"
            element={
              <ProtectedRoute>
                <Layout>
                  <ChatPage />
                </Layout>
              </ProtectedRoute>
            }
          />
          
          <Route
            path="/admin"
            element={
              <ProtectedRoute requiredRole={['admin', 'supervisor', 'teacher']}>
                <Layout>
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