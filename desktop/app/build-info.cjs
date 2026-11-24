const fs = require('node:fs')
const path = require('node:path')

function readBuildInfo(resourcesPath, fallbackVersion) {
  try {
    const info = JSON.parse(fs.readFileSync(path.join(resourcesPath, 'build-info.json'), 'utf8'))
    if (/^\d+\.\d+\.\d+$/.test(info.version) && /^\d+(\.\d+){0,2}$/.test(info.build)) {
      return {version:info.version, build:String(info.build)}
    }
  } catch { /* Development and older unpackaged launches have no build metadata. */ }
  return {version:fallbackVersion, build:''}
}
module.exports = {readBuildInfo}
