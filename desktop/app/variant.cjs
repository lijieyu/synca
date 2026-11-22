const production = 'https://synca.haerth.cn'
const preview = 'https://synca-preview.haerth.cn'
function variant(mode = 'production') {
  if (!['production', 'preview', 'local-preview'].includes(mode)) throw Error('Unknown desktop build variant')
  const local = mode === 'local-preview'
  const isolated = mode !== 'production'
  const home = local ? 'https://synca-preview.localhost' : isolated ? preview : production
  const name = local ? 'Synca Electron Local Preview' : isolated ? 'Synca Electron Preview' : 'Synca Electron'
  return Object.freeze({ home, name, isolated, local, upstream: local ? 'http://127.0.0.1:30642' : null,
    bundleId: local ? 'cn.haerth.synca.electron.preview.local' : isolated ? 'cn.haerth.synca.electron.preview' : 'cn.haerth.synca.electron',
    profile: isolated ? name : null, push: !isolated,
    allows(value) { try { const u = new URL(value); return !u.username && !u.password && u.origin === home } catch { return false } },
  })
}
module.exports = { variant }
