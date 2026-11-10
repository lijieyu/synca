import { lazy, Suspense } from 'react';
import { AppLoading } from './components/AppLoading';
import { AIPage } from './components/AIPage';
import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './contexts/AuthContext';
import { LoginView } from './components/LoginView';
const MessageListView = lazy(() => import('./components/MessageListView').then(module => ({ default: module.MessageListView })));
const AdminLayout = lazy(() => import('./components/AdminLayout').then(module => ({ default: module.AdminLayout })));

function App() {
  const { isAuthenticated, isAdmin, token } = useAuth();

  return (
    <Suspense fallback={<AppLoading />}><Routes>
      <Route path="/ai" element={<AIPage key={token ?? "anonymous"} />} />
      <Route
        path="/"
        element={isAuthenticated ? <MessageListView key={token} /> : <LoginView />}
      />
      <Route
        path="/admin/*"
        element={
          isAuthenticated ? (
            isAdmin ? <AdminLayout /> : <div className="admin-access-denied">Access Denied</div>
          ) : <Navigate to="/" />
        }
      />
    </Routes></Suspense>
  );
}

export default App;
