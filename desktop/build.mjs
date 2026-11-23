import { packager } from '@electron/packager'
import { readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import variantModule from './app/variant.cjs'
import { createHash } from 'node:crypto'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const version = JSON.parse(await readFile('package.json')).devDependencies.electron
const checksums = JSON.parse(await readFile('node_modules/electron/checksums.json'))
const targets = [['darwin', 'arm64'], ['win32', 'x64']]
const requestedPlatform = process.argv[2]
const cfg = variantModule.variant(process.argv[3])
if (existsSync(path.join('app', 'preview-build.json'))) throw Error('Preview marker may only exist inside packaging staging')
if (cfg.isolated && requestedPlatform !== 'darwin') throw Error('Preview packaging supported only on macOS')
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
  const [directory] = await packager({dir:'app', out:process.env.SYNCA_BUILD_DIR || 'dist', name:cfg.name, platform, arch, electronVersion:version,
    ...(cfg.isolated ? {afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode:cfg.local ? 'local-preview' : 'preview'}))]} : {}),
    electronZipDir, asar:true, overwrite:true, appBundleId:cfg.bundleId, appCategoryType:'public.app-category.productivity',
    icon:'icons/Synca', win32metadata:{ProductName:'Synca Electron', FileDescription:'Synca Electron', CompanyName:'Synca'}})
  if (platform === 'darwin') {
    const bundle = path.join(directory, cfg.name + '.app')
    execFileSync('codesign', ['--force', '--deep', '--sign', '-', bundle])
    execFileSync('codesign', ['--verify', '--deep', '--strict', bundle])
  }
}
