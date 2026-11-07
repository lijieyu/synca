export type LanguagePreference = 'system' | 'zh-Hans' | 'zh-Hant' | 'en';
export type AppearancePreference = 'system' | 'light' | 'dark';
export function resolveLanguage(preference: LanguagePreference, languages: readonly string[]): 'zh-Hans' | 'zh-Hant' | 'en' {
  if (preference !== 'system') return preference;
  const language = languages[0]?.toLowerCase() ?? 'en';
  return language.startsWith('zh') ? /hant|tw|hk|mo/.test(language) ? 'zh-Hant' : 'zh-Hans' : 'en';
}
export function readLanguagePreference(): LanguagePreference {
  const value = localStorage.getItem('synca.language');
  return value === 'zh-Hans' || value === 'zh-Hant' || value === 'en' ? value : 'system';
}
export function readAppearancePreference(): AppearancePreference {
  const value = localStorage.getItem('synca.appearance');
  return value === 'light' || value === 'dark' ? value : 'system';
}
export function applyAppearance(value: AppearancePreference) {
  localStorage.setItem('synca.appearance', value);
  document.documentElement.dataset.appearance = value;
}
