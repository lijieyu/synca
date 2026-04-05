import React, { useEffect, useRef } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { api } from '../api/client';

export const LoginView: React.FC = () => {
  const { login } = useAuth();
  const scriptLoaded = useRef(false);

  useEffect(() => {
    // Dynamically load Apple's Sign In JS
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
          usePopup: true // crucial for SPA flow
        });
      }
    };
    
    document.body.appendChild(script);

    // Add event listener for success/failure
    const handleSuccess = async (event: any) => {
      const idToken = event.detail.authorization.id_token;
      try {
        const res = await api.loginWithApple(idToken);
        login(res.token);
      } catch (err) {
        console.error('Login failed to exchange token', err);
        alert('Login failed: ' + err);
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
  }, [login]);

  return (
    <div className="auth-container">
      <h1>Synca</h1>
      <p>Synchronize your thoughts, effortlessly.</p>
      
      <div id="appleid-signin" data-color="black" data-border="true" data-type="sign in"></div>
      
      <p style={{ marginTop: '40px', fontSize: '12px', opacity: 0.5 }}>
        Only Apple ID sign-in is supported to ensure seamless synchronization with your iOS & Mac apps.
      </p>
    </div>
  );
};
