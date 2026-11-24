import { readFileSync } from 'node:fs'

// Share the release version with the Mac archive, instead of duplicating marketing and build numbers.
export function releaseVersion() {
  const project = readFileSync(new URL('./SyncaElectronTF.xcodeproj/project.pbxproj', import.meta.url), 'utf8')
  const version = project.match(/MARKETING_VERSION = ([0-9.]+);/)?.[1]
  const build = project.match(/CURRENT_PROJECT_VERSION = ([0-9.]+);/)?.[1]
  const app = JSON.parse(readFileSync(new URL('./app/package.json', import.meta.url), 'utf8'))
  if (!/^\d+\.\d+\.\d+$/.test(version ?? '') || !/^\d+$/.test(build ?? '') || app.version !== version) {
    throw Error('Desktop package and archive versions must agree before packaging')
  }
  return {version, build}
}
