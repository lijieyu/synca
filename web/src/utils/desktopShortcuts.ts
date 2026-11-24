/** Desktop-only command: never take over a browser's clear browsing data shortcut. */
export function desktopClearShortcut(platform?: string) {
  if (platform === 'macOS') return {
    keys: ['⌘', '⇧', '⌫'], spoken: 'Command + Shift + Delete', aria: 'Meta+Shift+Backspace', key: 'Backspace', mac: true,
  };
  if (platform === 'Windows') return {
    keys: ['Ctrl', 'Shift', 'Delete'], spoken: 'Control + Shift + Delete', aria: 'Control+Shift+Delete', key: 'Delete', mac: false,
  };
}
