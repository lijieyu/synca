const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');

test('archive requires the reviewed boolean exemption and rejects missing or conflicting declarations', { skip: process.platform !== 'darwin' }, () => {
  const dir = mkdtempSync(join(tmpdir(), 'synca-export-'));
  try {
    const plist = join(dir, 'Info.plist');
    for (const [name, fields, accepted] of [
      ['reviewed exemption', '<key>ITSAppUsesNonExemptEncryption</key><false/>', true],
      ['missing declaration', '', false],
      ['non-exempt encryption needs review', '<key>ITSAppUsesNonExemptEncryption</key><true/>', false],
      ['string is not a boolean', '<key>ITSAppUsesNonExemptEncryption</key><string>false</string>', false],
      ['unreviewed compliance code', '<key>ITSAppUsesNonExemptEncryption</key><false/><key>ITSEncryptionExportComplianceCode</key><string>unexpected</string>', false],
    ]) {
      writeFileSync(plist, `<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>${fields}</dict></plist>`);
      const result = spawnSync('/bin/bash', [join(__dirname, 'assert-export-compliance.sh'), plist], { encoding: 'utf8' });
      assert.equal(result.status === 0, accepted, `${name}: ${result.stderr}`);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
