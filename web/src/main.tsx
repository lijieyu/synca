import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App.tsx';
import { SettingsFrame } from './components/SettingsPanel';
import { AuthProvider } from './contexts/AuthContext.tsx';
import './i18n';
import './index.css';
import './calm.css';
import './focus.css';
import './DesktopDesign.css';
import { installFocusModality } from './utils/focusModality';

installFocusModality();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AuthProvider>
      <BrowserRouter>
        <SettingsFrame><App /></SettingsFrame>
      </BrowserRouter>
    </AuthProvider>
  </StrictMode>,
);
