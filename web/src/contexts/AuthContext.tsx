import React, { createContext, useContext, useState, useEffect } from 'react';
import { api } from '../api/client';

interface AuthContextType {
  token: string | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  email: string | null;
  plan: string | null;
  login: (token: string, isAdmin?: boolean, email?: string, plan?: string) => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType>({
  token: null,
  isAuthenticated: false,
  isAdmin: false,
  email: null,
  plan: null,
  login: () => {},
  logout: () => {},
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(localStorage.getItem('authToken'));
  const [isAdmin, setIsAdmin] = useState<boolean>(localStorage.getItem('isAdmin') === 'true');
  const [email, setEmail] = useState<string | null>(localStorage.getItem('userEmail'));
  const [plan, setPlan] = useState<string | null>(localStorage.getItem('userPlan'));

  useEffect(() => {
    if (token) {
      api.getMyProfile().then(res => {
        if (res.isAdmin !== undefined) {
          setIsAdmin(res.isAdmin);
          localStorage.setItem('isAdmin', res.isAdmin ? 'true' : 'false');
        }
        if (res.email) {
          setEmail(res.email);
          localStorage.setItem('userEmail', res.email);
        }
        if (res.accessStatus?.plan) {
          setPlan(res.accessStatus.plan);
          localStorage.setItem('userPlan', res.accessStatus.plan);
        }
      }).catch(() => {});
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
  };

  return (
    <AuthContext.Provider value={{ token, isAuthenticated: !!token, isAdmin, email, plan, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
