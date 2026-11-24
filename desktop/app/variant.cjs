const production = 'https://synca.haerth.cn'
const preview = 'https://synca-preview.haerth.cn'
function variant(mode = 'production') {
  if (!['production', 'preview', 'local-preview', 'mas-preflight', 'mas-testflight', 'mas-production'].includes(mode)) throw Error('Unknown desktop build variant')
  const offline = mode === 'mas-preflight'
  const gate = mode === 'mas-testflight'
  const liveMAS = mode === 'mas-production'
  const mas = offline || gate || liveMAS
  const local = mode === 'local-preview'
  const isolated = mode !== 'production' && !liveMAS
  const home = offline ? 'https://synca-testflight.invalid' : local ? 'https://synca-preview.localhost' : isolated ? preview : production
  const name = mas ? 'Synca' : local ? 'Synca Electron Local Preview' : isolated ? 'Synca Electron Preview' : 'Synca Electron'
  return Object.freeze({ home, name, isolated, local, offline, gate, upstream: local ? 'http://127.0.0.1:30642' : null,
    bundleId: mas ? 'org.haerth.synca' : local ? 'cn.haerth.synca.electron.preview.local' : isolated ? 'cn.haerth.synca.electron.preview' : 'cn.haerth.synca.electron',
    profile: liveMAS ? 'Synca Electron Production' : mas ? 'Synca Electron TestFlight' : isolated ? name : null, push: !isolated,
    allows(value) { try { const u = new URL(value); return !u.username && !u.password && u.origin === home } catch { return false } },
  })
}
module.exports = { variant }
