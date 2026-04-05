import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const srcDir = path.resolve(__dirname, '../../ios/Synca/Resources');
const destDir = path.resolve(__dirname, '../src/locales');

const langs = [
  { iOS: 'en.lproj/Localizable.strings', web: 'en.json' },
  { iOS: 'zh-Hans.lproj/Localizable.strings', web: 'zh.json' }
];

function parseStringsFile(content) {
  const result = {};
  const lines = content.split('\n');
  
  for (const line of lines) {
    const match = line.match(/^"([^"]+)"\s*=\s*"(.*)";$/);
    if (match) {
      const key = match[1];
      let val = match[2];
      val = val.replace(/\\n/g, '\n');
      result[key] = val;
    }
  }
  return result;
}

for (const lang of langs) {
  const srcPath = path.join(srcDir, lang.iOS);
  const destPath = path.join(destDir, lang.web);
  
  if (fs.existsSync(srcPath)) {
    const content = fs.readFileSync(srcPath, 'utf8');
    const parsed = parseStringsFile(content);
    fs.writeFileSync(destPath, JSON.stringify(parsed, null, 2), 'utf8');
    console.log(`Synced ${lang.iOS} to ${lang.web} (${Object.keys(parsed).length} keys)`);
  } else {
    console.warn(`Source missing: ${srcPath}`);
  }
}
