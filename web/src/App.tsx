import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './contexts/AuthContext';
import { LoginView } from './components/LoginView';
import { MessageListView } from './components/MessageListView';
import { AdminLayout } from './components/AdminLayout';

function App() {
  const { isAuthenticated, isAdmin } = useAuth();

  return (
    <Routes>
      <Route 
        path="/" 
        element={isAuthenticated ? <MessageListView /> : <LoginView />} 
      />
      <Route 
        path="/admin/*" 
        element={
          isAuthenticated ? (
            isAdmin ? <AdminLayout /> : <div className="admin-access-denied">Access Denied</div>
          ) : <Navigate to="/" />
        } 
      />
    </Routes>
  );
}

export default App;
