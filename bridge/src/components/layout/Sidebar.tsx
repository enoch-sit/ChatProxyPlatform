// src/components/layout/Sidebar.tsx
import React from 'react';
import { useTranslation } from 'react-i18next';
import { useLocation } from 'react-router-dom';
import Box from '@mui/joy/Box';
import List from '@mui/joy/List';
import ListItem from '@mui/joy/ListItem';
import ListItemButton from '@mui/joy/ListItemButton';
import ListItemDecorator from '@mui/joy/ListItemDecorator';
import Typography from '@mui/joy/Typography';
import DashboardIcon from '@mui/icons-material/Dashboard';
import ChatIcon from '@mui/icons-material/Chat';
import AdminPanelSettingsIcon from '@mui/icons-material/AdminPanelSettings';
import { usePermissions } from '../../hooks/usePermissions';

const Sidebar: React.FC = () => {
  const { t } = useTranslation();
  const { canAccessAdmin } = usePermissions();
  const location = useLocation();

  const handleNavigate = (to: string) => {
    if (location.pathname === to) {
      return;
    }

    window.location.assign(to);
  };

  const navItems = [
    { 
      to: '/dashboard', 
      label: t('navigation.dashboard'), 
      icon: <DashboardIcon />, 
      show: true 
    },
    { 
      to: '/chat', 
      label: t('navigation.chat'), 
      icon: <ChatIcon />, 
      show: true 
    },
    { 
      to: '/admin', 
      label: t('navigation.admin'), 
      icon: <AdminPanelSettingsIcon />, 
      show: canAccessAdmin // Now this is a boolean, not a function call
    },
  ];

  return (
    <Box 
      component="nav" 
      sx={{ 
        width: 240, 
        flexShrink: 0, 
        bgcolor: 'background.surface', 
        borderRight: '1px solid', 
        borderColor: 'divider',
        display: 'flex',
        flexDirection: 'column',
        height: '100%'
      }}
    >
      <List size="lg" sx={{ '--ListItem-radius': '8px', '--List-gap': '4px', flex: 1 }}>
        <ListItem nested>
          <Typography level="title-sm" sx={{ textTransform: 'uppercase', letterSpacing: '0.1rem', color: 'text.secondary', px: 2, py: 1 }}>
            {t('appTitle')}
          </Typography>
          <List>
            {navItems.map((item) => (
              item.show && (
                <ListItem key={item.to}>
                  <ListItemButton
                    selected={location.pathname === item.to}
                    onClick={() => handleNavigate(item.to)}
                    sx={{ fontWeight: 'md' }}
                  >
                    <ListItemDecorator>{item.icon}</ListItemDecorator>
                    {item.label}
                  </ListItemButton>
                </ListItem>
              )
            ))}
          </List>
        </ListItem>
      </List>
      
      {/* AI Disclaimer */}
      <Box
        sx={{
          p: 2,
          borderTop: '1px solid',
          borderColor: 'divider',
          backgroundColor: 'background.level1',
        }}
      >
        <Typography 
          level="body-xs" 
          color="neutral" 
          sx={{ 
            textAlign: 'center',
            fontStyle: 'italic',
            opacity: 0.7
          }}
        >
          {t('chat.aiDisclaimer')}
        </Typography>
      </Box>
    </Box>
  );
};

export default Sidebar;