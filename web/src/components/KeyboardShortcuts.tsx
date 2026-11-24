import { useTranslation } from 'react-i18next';

import { desktopClearShortcut } from '../utils/desktopShortcuts';

/** Read-only, platform-specific reference; browser-reserved commands are omitted. */
export function KeyboardShortcuts() {
  const { t } = useTranslation();
  const desktop = window.syncaDesktop;
  const mac = desktop ? desktop.platform === 'macOS' : /Mac/.test(navigator.platform);
  const modifier = mac ? '⌘' : 'Ctrl';
  const clear = desktopClearShortcut(desktop?.platform);
  const rows = [
    { label: 'shortcuts.search', keys: [modifier, 'F'], spoken: mac ? 'Command + F' : 'Control + F' },
    { label: 'shortcuts.sync', keys: [modifier, 'R'], spoken: mac ? 'Command + R' : 'Control + R' },
    ...(clear ? [
      { label: 'message_list.clear_completed', keys: clear.keys, spoken: clear.spoken },
    ] : []),
    ...(desktop ? [
      { label: 'preferences.title', keys: [modifier, ','], spoken: mac ? 'Command + ,' : 'Control + ,' },
      { label: 'shortcuts.close', keys: [modifier, 'W'], spoken: mac ? 'Command + W' : 'Control + W' },
    ] : []),
    ...(desktop?.platform === 'macOS' ? [
      { label: 'shortcuts.hide', keys: ['⌘', 'H'], spoken: 'Command + H' },
    ] : []),
  ];
  return <section className="settings-shortcuts" aria-labelledby="keyboard-shortcuts-heading" aria-describedby="keyboard-shortcuts-note">
    <h3 id="keyboard-shortcuts-heading">{t('shortcuts.title')}</h3>
    <p id="keyboard-shortcuts-note">{t('shortcuts.fixed')}</p>
    <dl>{rows.map(row => <div className="settings-shortcut-row" key={row.label}>
      <dt>{t(row.label)}</dt>
      <dd><span className="shortcut-keys" aria-label={row.spoken}>{row.keys.map(key => <kbd key={key} aria-hidden="true">{key}</kbd>)}</span></dd>
    </div>)}</dl>
  </section>;
}
