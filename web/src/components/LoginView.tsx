import React, { useEffect, useRef } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { api } from '../api/client';
import { useTranslation } from 'react-i18next';

export const LoginView: React.FC = () => {
  const { login } = useAuth();
  const { t } = useTranslation();
  const scriptLoaded = useRef(false);

  useEffect(() => {
    if (scriptLoaded.current) return;
    
    const script = document.createElement('script');
    script.src = 'https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js';
    script.async = true;
    
    script.onload = () => {
      scriptLoaded.current = true;
      // @ts-ignore
      if (window.AppleID) {
        // @ts-ignore
        window.AppleID.auth.init({
          clientId: 'cn.haerth.synca.web',
          scope: 'email',
          redirectURI: 'https://synca.haerth.cn/api/auth/apple/callback',
          usePopup: true
        });
      }
    };
    
    document.body.appendChild(script);

    const handleSuccess = async (event: any) => {
      const idToken = event.detail.authorization.id_token;
      try {
        const res = await api.loginWithApple(idToken);
        login(res.token, res.user.isAdmin);
      } catch (err) {
        console.error('Login failed to exchange token', err);
        alert(t('login.failed') + ': ' + err);
      }
    };

    const handleFailure = (event: any) => {
      console.error('Apple Sign In failed', event.detail);
    };

    document.addEventListener('AppleIDSignInOnSuccess', handleSuccess);
    document.addEventListener('AppleIDSignInOnFailure', handleFailure);

    return () => {
      document.removeEventListener('AppleIDSignInOnSuccess', handleSuccess);
      document.removeEventListener('AppleIDSignInOnFailure', handleFailure);
    };
  }, [login, t]);

  return (
    <div className="auth-container">
      <img 
        src="/logo.png" 
        alt="Synca" 
        style={{ 
          width: '96px', 
          height: '96px', 
          borderRadius: '22px'
        }} 
      />
      <h1>{t('app.name', 'Synca')}</h1>
      <p>{t('app.slogan', 'Sync Your Aha Moment')}</p>
      
      <div id="appleid-signin" data-color="black" data-border="true" data-type="sign in"></div>
    </div>
  );
};
