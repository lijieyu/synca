import React, { useEffect, useState } from 'react';

interface AuthImageProps extends React.ImgHTMLAttributes<HTMLImageElement> {
  url: string;
}

export const AuthImage: React.FC<AuthImageProps> = ({ url, ...props }) => {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [isError, setIsError] = useState(false);

  useEffect(() => {
    let active = true;
    let currentObjectUrl: string | null = null;

    const fetchImage = async () => {
      try {
        const token = localStorage.getItem('authToken');
        const headers: Record<string, string> = {};
        if (token) {
          headers['Authorization'] = `Bearer ${token}`;
        }
        
        const response = await fetch(url, { headers });
        if (!response.ok) {
          throw new Error(`Failed to fetch image: ${response.status}`);
        }
        
        const blob = await response.blob();
        if (!active) return;
        
        currentObjectUrl = URL.createObjectURL(blob);
        setObjectUrl(currentObjectUrl);
        setIsError(false);
      } catch (err) {
        console.error('AuthImage fetch error:', err);
        if (active) {
          setIsError(true);
        }
      }
    };

    fetchImage();

    return () => {
      active = false;
      if (currentObjectUrl) {
        URL.revokeObjectURL(currentObjectUrl);
      }
    };
  }, [url]);

  if (isError) {
    return (
      <div 
        style={{ 
          width: '200px', 
          height: '150px', 
          display: 'flex', 
          alignItems: 'center', 
          justifyContent: 'center', 
          background: '#f0f0f0', 
          color: '#888',
          borderRadius: '8px'
        }}
      >
        Failed to load
      </div>
    );
  }

  if (!objectUrl) {
    return (
      <div 
        style={{ 
          width: '200px', 
          height: '150px', 
          display: 'flex', 
          alignItems: 'center', 
          justifyContent: 'center', 
          background: '#f8f8f8', 
          color: '#bbb',
          borderRadius: '8px'
        }}
      >
        Loading...
      </div>
    );
  }

  return <img src={objectUrl} {...props} />;
};
