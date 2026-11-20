import { createContext } from 'react';

export type SettingsAction = 'categories' | 'ai' | 'feedback';
export const SettingsSurface = createContext<{
  action: SettingsAction | null;
  host: HTMLElement | null;
  continueEditing: () => void;
  finish: () => void;
} | null>(null);
