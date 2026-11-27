import {buildCaptureHelper} from './build-capture-helper.mjs'
import { releaseVersion } from './release-version.mjs'
import { packager } from '@electron/packager'
import { readFile, writeFile } from 'node:fs/promises'
import { existsSync } from 'node:fs'
import variantModule from './app/variant.cjs'
import { createHash } from 'node:crypto'
import path from 'node:path'
import { execFileSync } from 'node:child_process'

const identity = releaseVersion()
const version = JSON.parse(await readFile('package.json')).devDependencies.electron
const checksums = JSON.parse(await readFile('node_modules/electron/checksums.json'))
const targets = [['darwin', 'arm64'], ['win32', 'x64'], ['win32', 'arm64']]
const requestedPlatform = process.argv[2]
const storeBuild=process.argv[3]==='store'
const requestedArch=process.env.SYNCA_WINDOWS_ARCH
if(requestedArch&&!['x64','arm64'].includes(requestedArch))throw Error('Invalid Windows architecture')
if(storeBuild&&requestedPlatform!=='win32')throw Error('Store target is Windows only')
const cfg = variantModule.variant(storeBuild?undefined:process.argv[3])
if (existsSync(path.join('app','distribution.json'))||existsSync(path.join('app', 'preview-build.json'))) throw Error('Preview marker may only exist inside packaging staging')
if (cfg.isolated && requestedPlatform !== 'darwin') throw Error('Preview packaging supported only on macOS')
if (requestedPlatform && !targets.some(([platform]) => platform === requestedPlatform)) {
  throw new Error('Expected platform darwin or win32')
}
for (const [platform, arch] of targets) {
  if (requestedPlatform && platform !== requestedPlatform) continue
  if(platform==='win32'&&requestedArch&&arch!==requestedArch)continue
  const electronZipDir = process.env.ELECTRON_ZIP_DIR
  if (electronZipDir) {
    const file = 'electron-v' + version + '-' + platform + '-' + arch + '.zip'
    const bytes = await readFile(path.join(electronZipDir, file))
    if (createHash('sha256').update(bytes).digest('hex') !== checksums[file]) throw Error('Checksum mismatch: ' + file)
  }
  const [directory] = await packager({dir:'app', out:storeBuild?'dist/store-app':process.env.SYNCA_BUILD_DIR || 'dist', name:cfg.name, platform, arch, electronVersion:version,
    ...(cfg.isolated ? {afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'preview-build.json'),JSON.stringify({mode:cfg.local ? 'local-preview' : 'preview'}))]} : {}),
    ...(storeBuild?{afterCopy:[({buildPath})=>writeFile(path.join(buildPath,'distribution.json'),JSON.stringify({channel:'store'}))]}:{}),
    appVersion:identity.version, buildVersion:platform === 'win32' ? identity.version+'.'+identity.build : identity.build,
    electronZipDir, asar:true, overwrite:true, appBundleId:cfg.bundleId, appCategoryType:'public.app-category.productivity',
    icon:'icons/Synca', win32metadata:{ProductName:'Synca Electron', FileDescription:'Synca Electron', CompanyName:'Synca'}})
  const resources = platform === 'darwin' ? path.join(directory, cfg.name+'.app/Contents/Resources') : path.join(directory, 'resources')
  await writeFile(path.join(resources, 'build-info.json'), JSON.stringify(identity))
  if (platform === 'darwin') {
    await buildCaptureHelper(resources)
    const bundle = path.join(directory, cfg.name + '.app')
    execFileSync('codesign', ['--force', '--deep', '--sign', '-', bundle])
    execFileSync('codesign', ['--verify', '--deep', '--strict', bundle])
  }
}
