import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const origin = 'https://synca.haerth.cn';
const variants = [['', 'zh-Hans'], ['en/', 'en'], ['zh-Hant/', 'zh-Hant']];
const read = name => readFileSync(path.join(root, name), 'utf8');
for (const [folder, language] of variants) {
  test(`public metadata and reciprocal language links: ${language}`, () => {
    const html = read(`web/public/home/${folder}index.html`);
    const url = `${origin}/home/${folder}`;
    assert(html.includes(`<html lang="${language}">`));
    assert(html.includes(`<link rel="canonical" href="${url}">`));
    assert(html.includes(`<meta property="og:url" content="${url}">`));
    for (const [otherFolder, otherLanguage] of variants) {
      assert(html.includes(`<link rel="alternate" hreflang="${otherLanguage}" href="${origin}/home/${otherFolder}">`));
    }
    assert(html.includes('<meta name="twitter:card" content="summary">'));
    const image = html.match(/<meta property="og:image" content="([^"]+)"/)[1];
    assert(image.startsWith(`${origin}/home/assets/`));
    assert(existsSync(path.join(root, 'web/public', new URL(image).pathname)));
    const schema = JSON.parse(html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1]);
    const app = schema['@graph'].find(item => item['@type'] === 'SoftwareApplication');
    assert.equal(app.url, url);
    assert.equal(app.inLanguage, language);
    assert.equal(app.description, html.match(/<meta name="description" content="([^"]+)"/)[1]);
    assert.equal(app.installUrl, 'https://apps.apple.com/app/id6761647007');
    assert(!app.aggregateRating && !app.review, 'No invented reviews or ratings');
    assert(html.includes('href="#download"'));
    assert(html.includes('id="download"'));
  });
}

test('sitemap contains only genuine canonical marketing pages', () => {
  const sitemap = read('web/public/sitemap.xml');
  const urls = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map(match => match[1]);
  assert.deepEqual(urls, variants.map(([folder]) => `${origin}/home/${folder}`));
  const robots = read('web/public/robots.txt');
  assert(robots.startsWith('User-agent: *\nAllow: /\n'));
  assert(robots.includes(`Sitemap: ${origin}/sitemap.xml`));
  assert(!robots.includes('Disallow: /home'));
});

test('deployment adds exact crawler routes once and preserves the SPA', () => {
  const script = read('scripts/deploy-home.sh');
  const patch = script.match(/python3 - "\$config" <<'PY'\n([\s\S]*?)\nPY/)[1];
  const folder = mkdtempSync(path.join(tmpdir(), 'synca-home-routes-'));
  const config = path.join(folder, 'nginx.conf');
  const spa = '    # SPA fallback:\n    location / { try_files $uri $uri/ /index.html; }\n';
  try {
    writeFileSync(config, 'server {\n    server_name synca.haerth.cn;\n' + spa + '}\n');
    execFileSync('python3', ['-', config], { input: patch });
    const first = readFileSync(config, 'utf8');
    assert(first.includes(spa));
    for (const [name, type] of [['robots.txt', 'text/plain'], ['sitemap.xml', 'application/xml']]) {
      assert(first.includes(`location = /${name} {\n        alias /opt/synca/home-current/${name};\n        types { }\n        default_type ${type};`));
    }
    execFileSync('python3', ['-', config], { input: patch });
    assert.equal(readFileSync(config, 'utf8'), first, 'Repeated deployment is idempotent');
    writeFileSync(config, first.replace('alias /opt/synca/home-current/robots.txt;', 'alias /unexpected/robots.txt;'));
    assert.throws(() => execFileSync('python3', ['-', config], { input: patch, stdio: ['pipe', 'pipe', 'pipe'] }), /Unexpected existing robots.txt route/);
    assert(script.includes('cmp -s "$release_dir/$name.response" "$release_dir/$name"'), 'Verify actual document bytes, not just status 200');
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
