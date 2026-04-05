import React, { useState, useEffect } from 'react';
import { api } from '../api/client';
import { useAuth } from '../contexts/AuthContext';
import { RefreshCcw, LogOut, User, MessageSquare, BarChart3, Heart, CreditCard } from 'lucide-react';
import { Modal } from './Modal';

export const AdminLayout: React.FC = () => {
  const [activeTab, setActiveTab] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [stats, setStats] = useState<any>(null);
  const [showLogoutModal, setShowLogoutModal] = useState(false);
  const { logout } = useAuth();

  const tabs = [
    { name: 'Dashboard', icon: <BarChart3 size={18} /> },
    { name: 'Users', icon: <User size={18} /> },
    { name: 'Messages', icon: <MessageSquare size={18} /> },
    { name: 'Revenue', icon: <CreditCard size={18} /> },
    { name: 'Feedback', icon: <Heart size={18} /> },
  ];

  const fetchData = async () => {
    setIsLoading(true);
    try {
      let res;
      setStats(null); // Clear previous stats to prevent rendering with old data
      if (activeTab === 0) res = await api.getAdminOverview();
      else if (activeTab === 1) res = await api.getAdminUsers();
      else if (activeTab === 2) res = await api.getAdminMessageStats();
      else if (activeTab === 3) res = await api.getAdminRevenueStats();
      else if (activeTab === 4) res = await api.getAdminFeedback();
      setStats(res);
    } catch (err) {
      console.error(err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    const originalTitle = document.title;
    document.title = 'Synca Admin';
    fetchData();
    return () => { document.title = originalTitle; };
  }, [activeTab]);

  return (
    <div className="admin-layout">
      {showLogoutModal && (
        <Modal 
          title="Sign Out"
          message="Are you sure you want to log out from the Admin Dashboard?"
          confirmText="Confirm"
          cancelText="Cancel"
          onConfirm={logout}
          onCancel={() => setShowLogoutModal(false)}
          destructive
        />
      )}
      <div className="header" style={{ borderBottom: 'none' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
          <img src="/logo.png" alt="Logo" style={{ width: '32px', height: '32px', borderRadius: '8px' }} />
          <h1 className="header-title" style={{ fontSize: '18px' }}>Synca Admin</h1>
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button className="header-btn" onClick={fetchData} title="Refresh">
            <RefreshCcw size={18} />
          </button>
          <button className="header-btn" onClick={() => setShowLogoutModal(true)} title="Logout">
            <LogOut size={18} />
          </button>
        </div>
      </div>

      <div className="admin-nav">
        {tabs.map((tab, idx) => (
          <div 
            key={idx} 
            className={`admin-nav-item ${activeTab === idx ? 'active' : ''}`}
            onClick={() => setActiveTab(idx)}
          >
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              {tab.icon}
              <span>{tab.name}</span>
            </div>
          </div>
        ))}
      </div>

      <div className="admin-content">
        {isLoading ? (
          <div style={{ textAlign: 'center', padding: '40px 0', opacity: 0.5 }}>Loading...</div>
        ) : (
          <>
            {activeTab === 0 && stats && (
              <div className="tab-pane">
                <div className="admin-stats-grid">
                  <div className="admin-stat-card">
                    <div className="admin-stat-label">Total Users</div>
                    <div className="admin-stat-value">{stats.totalUsers}</div>
                  </div>
                  <div className="admin-stat-card">
                    <div className="admin-stat-label">Total Revenue</div>
                    <div className="admin-stat-value">¥{stats.totalRevenue}</div>
                  </div>
                  <div className="admin-stat-card">
                    <div className="admin-stat-label">Total Todos</div>
                    <div className="admin-stat-value">{stats.totalTodos}</div>
                  </div>
                  <div className="admin-stat-card">
                    <div className="admin-stat-label">Total Feedback</div>
                    <div className="admin-stat-value">{stats.totalFeedback}</div>
                  </div>
                </div>
              </div>
            )}

            {activeTab === 1 && stats && (
              <div className="admin-table-container">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Plan</th>
                      <th>Todos</th>
                      <th>Last Active</th>
                    </tr>
                  </thead>
                  <tbody>
                    {stats?.users?.map((u: any) => (
                      <tr key={u.id}>
                        <td>
                          <div style={{ fontWeight: 500 }}>{u.email || 'Anonymous'}</div>
                          <div style={{ fontSize: '11px', opacity: 0.5 }}>{u.id}</div>
                        </td>
                        <td>
                          <span className={`admin-tag ${u.plan !== 'Free' ? 'unlimited' : ''}`}>{u.plan}</span>
                        </td>
                        <td>{u.todoCount}</td>
                        <td>{new Date(u.lastActive).toLocaleDateString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}

            {activeTab === 2 && stats && (
              <div className="tab-pane">
                <h3 style={{ marginBottom: 16, fontSize: 16 }}>Daily Volume (Last 30 Days)</h3>
                <div className="admin-table-container">
                  <table className="admin-table">
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Messages</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stats?.dailyVolume?.map((d: any) => (
                        <tr key={d.date}>
                          <td>{d.date}</td>
                          <td>{d.count}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {activeTab === 3 && stats && (
              <div className="tab-pane">
                <h3 style={{ marginBottom: 16, fontSize: 16 }}>Revenue Trends (CNY)</h3>
                <div className="admin-table-container">
                  <table className="admin-table">
                    <thead>
                      <tr>
                        <th>Date</th>
                        <th>Amount</th>
                      </tr>
                    </thead>
                    <tbody>
                      {stats?.dailyRevenue?.map((d: any) => (
                        <tr key={d.date}>
                          <td>{d.date}</td>
                          <td>¥{d.amount}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              </div>
            )}

            {activeTab === 4 && stats && (
              <div className="admin-table-container">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>Content</th>
                      <th>User & Device</th>
                      <th>Time</th>
                    </tr>
                  </thead>
                  <tbody>
                    {stats?.feedbacks?.map((f: any) => (
                      <tr key={f.id}>
                        <td style={{ maxWidth: 300 }}>{f.content}</td>
                        <td>
                          <div style={{ fontWeight: 500 }}>{f.email || f.userEmail}</div>
                          <div style={{ fontSize: '11px', opacity: 0.6 }}>
                            {f.device_model || 'Unknown Device'} · {f.os_version || 'Unknown OS'} (v{f.app_version || '?'})
                          </div>
                        </td>
                        <td>{new Date(f.created_at).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
};
