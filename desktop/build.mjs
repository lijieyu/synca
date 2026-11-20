import { packager } from '@electron/packager'
import { readFile } from 'node:fs/promises'
import { createHash } from 'node:crypto'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const version = JSON.parse(await readFile('package.json')).devDependencies.electron
const checksums = JSON.parse(await readFile('node_modules/electron/checksums.json'))
const targets = [['darwin', 'arm64'], ['win32', 'x64']]
const requestedPlatform = process.argv[2]
if (requestedPlatform && !targets.some(([platform]) => platform === requestedPlatform)) {
  throw new Error('Expected platform darwin or win32')
}
for (const [platform, arch] of targets) {
  if (requestedPlatform && platform !== requestedPlatform) continue
  const electronZipDir = process.env.ELECTRON_ZIP_DIR
  if (electronZipDir) {
    const file = 'electron-v' + version + '-' + platform + '-' + arch + '.zip'
    const bytes = await readFile(path.join(electronZipDir, file))
    if (createHash('sha256').update(bytes).digest('hex') !== checksums[file]) throw Error('Checksum mismatch: ' + file)
  }
  const [directory] = await packager({dir:'app', out:process.env.SYNCA_BUILD_DIR || 'dist', name:'Synca Electron', platform, arch, electronVersion:version,
    electronZipDir, asar:true, overwrite:true, appBundleId:'cn.haerth.synca.electron', appCategoryType:'public.app-category.productivity',
    icon:'icons/Synca', win32metadata:{ProductName:'Synca Electron', FileDescription:'Synca Electron', CompanyName:'Synca'}})
  if (platform === 'darwin') {
    const bundle = path.join(directory, 'Synca Electron.app')
    execFileSync('codesign', ['--force', '--deep', '--sign', '-', bundle])
    execFileSync('codesign', ['--verify', '--deep', '--strict', bundle])
  }
}
