import React, { createContext, useContext, useState, useEffect } from 'react';
import { api } from '../api/client';

interface AuthContextType {
  token: string | null;
  isAuthenticated: boolean;
  isAdmin: boolean;
  login: (token: string, isAdmin?: boolean) => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextType>({
  token: null,
  isAuthenticated: false,
  isAdmin: false,
  login: () => {},
  logout: () => {},
});

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [token, setToken] = useState<string | null>(localStorage.getItem('authToken'));
  const [isAdmin, setIsAdmin] = useState<boolean>(localStorage.getItem('isAdmin') === 'true');

  useEffect(() => {
    if (token && !isAdmin) {
      api.getMyProfile().then(res => {
        if (res.isAdmin) {
          setIsAdmin(true);
          localStorage.setItem('isAdmin', 'true');
        }
      }).catch(() => {});
    }
  }, [token]);

  const login = (newToken: string, adminStatus?: boolean) => {
    localStorage.setItem('authToken', newToken);
    if (adminStatus !== undefined) {
      localStorage.setItem('isAdmin', adminStatus ? 'true' : 'false');
      setIsAdmin(adminStatus);
    }
    setToken(newToken);
  };

  const logout = () => {
    localStorage.removeItem('authToken');
    localStorage.removeItem('isAdmin');
    setToken(null);
    setIsAdmin(false);
  };

  return (
    <AuthContext.Provider value={{ token, isAuthenticated: !!token, isAdmin, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};

export const useAuth = () => useContext(AuthContext);
