// src/components/layout/Header.tsx
import React from 'react';
import { useTranslation } from 'react-i18next';
import Box from '@mui/joy/Box';
import Typography from '@mui/joy/Typography';
import Button from '@mui/joy/Button';
import { useAuth } from '../../hooks/useAuth';
import LanguageSelector from '../LanguageSelector';
import ThemeToggleButton from '../ThemeToggleButton';
import bLogo from '../../assets/b.svg';
import aidcecLogo from '../../assets/aidcec.png';

const Header: React.FC = () => {
  const { t } = useTranslation();
  const { user, logout } = useAuth();

  const handleLogout = async () => {
    await logout();
  };

  return (
    <Box
      component="header"
      sx={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        py: 3,
        px: 3,
        mb: 4,
        borderBottom: '1px solid',
        borderColor: 'divider',
      }}
    >
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2.5 }}>
        <img 
          src={aidcecLogo} 
          alt="AIDCEC" 
          style={{ 
            height: '36px',
            width: 'auto',
            filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))'
          }} 
        />
        <img 
          src={bLogo} 
          alt="Bridge" 
          style={{ 
            width: '32px', 
            height: '32px',
            filter: 'drop-shadow(0 2px 4px rgba(0,0,0,0.1))'
          }} 
        />
        <Typography level="h4" sx={{ ml: 1, mr: 6 }}>{t('appTitle')}</Typography>
      </Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 3 }}>
        {user && <Typography>{t('common.welcomeUser', { username: user.username })}</Typography>}
        <LanguageSelector />
        <ThemeToggleButton />
        {user && <Button onClick={() => { void handleLogout(); }}>{t('auth.logout')}</Button>}
      </Box>
    </Box>
  );
};

export default Header;

