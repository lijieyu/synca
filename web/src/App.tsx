import { useAuth } from './contexts/AuthContext';
import { LoginView } from './components/LoginView';
import { MessageListView } from './components/MessageListView';

function App() {
  const { isAuthenticated } = useAuth();

  if (!isAuthenticated) {
    return <LoginView />;
  }

  return <MessageListView />;
}

export default App;
