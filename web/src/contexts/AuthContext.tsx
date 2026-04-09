import React, { createContext, useContext, useState, useEffect } from 'react';
import { api, type AccessStatus } from '../api/client';

interface AuthContextType {
  token: string | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  email: string | null;
  plan: string | null;
  accessStatus: AccessStatus | null;
  login: (token: string, isAdmin?: boolean, email?: string, plan?: string) => void;
  logout: () => void;
  refreshAccessStatus: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType>({
  token: null,
  isAuthenticated: false,
  isAdmin: false,
  email: null,
  plan: null,
  accessStatus: null,
  login: () => {},
  logout: () => {},
  refreshAccessStatus: async () => {},
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(localStorage.getItem('authToken'));
  const [isAdmin, setIsAdmin] = useState<boolean>(localStorage.getItem('isAdmin') === 'true');
  const [email, setEmail] = useState<string | null>(localStorage.getItem('userEmail'));
  const [plan, setPlan] = useState<string | null>(localStorage.getItem('userPlan'));
  const [accessStatus, setAccessStatus] = useState<AccessStatus | null>(null);

  const refreshAccessStatus = async () => {
    if (!token) return;
    try {
      const res = await api.getMyProfile();
      if (res.isAdmin !== undefined) {
        setIsAdmin(res.isAdmin);
        localStorage.setItem('isAdmin', res.isAdmin ? 'true' : 'false');
      }
      if (res.email) {
        setEmail(res.email);
        localStorage.setItem('userEmail', res.email);
      }
      if (res.accessStatus) {
        setPlan(res.accessStatus.plan);
        setAccessStatus(res.accessStatus);
        localStorage.setItem('userPlan', res.accessStatus.plan);
      }
    } catch (err) {
      console.error('[auth] profile fetch failed:', err);
    }
  };

  useEffect(() => {
    if (token) {
      refreshAccessStatus();
    }
  }, [token]);

  const login = (newToken: string, adminStatus?: boolean, userEmail?: string, userPlan?: string) => {
    localStorage.setItem('authToken', newToken);
    if (adminStatus !== undefined) {
      localStorage.setItem('isAdmin', adminStatus ? 'true' : 'false');
      setIsAdmin(adminStatus);
    }
    if (userEmail) {
      localStorage.setItem('userEmail', userEmail);
      setEmail(userEmail);
    }
    if (userPlan) {
      localStorage.setItem('userPlan', userPlan);
      setPlan(userPlan);
    }
    setToken(newToken);
  };

  const logout = () => {
    localStorage.removeItem('authToken');
    localStorage.removeItem('isAdmin');
    localStorage.removeItem('userEmail');
    localStorage.removeItem('userPlan');
    setToken(null);
    setIsAdmin(false);
    setEmail(null);
    setPlan(null);
    setAccessStatus(null);
  };

  return (
    <AuthContext.Provider value={{ 
      token, 
      isAuthenticated: !!token, 
      isAdmin, 
      email, 
      plan, 
      accessStatus,
      login, 
      logout,
      refreshAccessStatus
    }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
