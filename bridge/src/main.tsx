import { StrictMode, Suspense } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { debugAuthState, checkRole } from './utils/debugAuth.ts'

// Make debug tools globally available
if (typeof window !== 'undefined') {
  (window as any).__debugAuth = { debugAuthState, checkRole };
  console.log('🐛 Auth debug tools loaded. Run: __debugAuth.debugAuthState()');
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Suspense fallback='Loading...'>
      <App />
    </Suspense>
  </StrictMode>,
)
