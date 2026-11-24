const { app, clipboard, ClipboardItem, dialog, Menu, nativeImage, shell } = require('electron')
const fs = require('node:fs/promises')
const path = require('node:path')
const { Readable } = require('node:stream')
const { pipeline } = require('node:stream/promises')
const { execFile } = require('node:child_process')
const { promisify } = require('node:util')
const openApplication = promisify(execFile)
const actionIds = new Set(['edit', 'copyRecord', 'copySelection', 'openLink', 'copyLink', 'complete',
  'category', 'delete', 'preview', 'save', 'saveAs', 'reveal'])
const attachmentActions = new Set(['preview', 'saveAs', 'reveal'])

function webLink(value) {
  try {
    const url = new URL(value)
    return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password ? url.href : null
  } catch { return null }
}

function attachmentURL(value, home) {
  try {
    const url = new URL(value, home)
    return url.origin === home && !url.username && !url.password && /^\/api\/media\/[A-Za-z0-9_.-]+$/.test(url.pathname)
      && !url.search && !url.hash ? url.href : null
  } catch { return null }
}

const { safeFileName } = require('./file-names.cjs')

function installContextMenus(window, ses, handle, getSession, getDirectory, cfg) {
  const home=cfg.home
  const page = window.webContents
  let currentMenu
  let tempRoot
  let tempCreation
  async function temporaryDirectory() {
    tempCreation ||= fs.mkdtemp(path.join(app.getPath('temp'), 'synca-attachments-')).then(dir => (tempRoot = dir))
    return fs.mkdtemp(path.join(await tempCreation, 'item-'))
  }
  app.once('will-quit', () => { if (tempRoot) require('node:fs').rmSync(tempRoot, {recursive: true, force: true}) })
  async function performAttachment(action, attachment) {
    const url = attachmentURL(attachment?.url, home)
    const token = getSession()
    if (!url || !token || (action === 'preview' && (attachment?.kind !== 'image' || process.platform !== 'darwin'))) throw Error('Invalid attachment')
    const name = safeFileName(attachment.name || new URL(url).pathname.split('/').pop())
    let destination
    if (action === 'saveAs') {
      const chosen = await dialog.showSaveDialog(window, {defaultPath: path.join(getDirectory(), name)})
      if (chosen.canceled || !chosen.filePath) return
      destination = chosen.filePath
    }
    const sessionIsCurrent = () => getSession() === token && !window.isDestroyed() &&
      !page.isDestroyed() && new URL(page.getURL()).origin === home &&
      (!attachment.expiresAt || Date.parse(attachment.expiresAt) > Date.now())
    if (!sessionIsCurrent()) throw Error('Attachment unavailable')
    const response = await ses.fetch(url, {headers: {Authorization: 'Bearer ' + token}, redirect: 'error',
      cache: 'no-store', signal: AbortSignal.timeout(120000), bypassCustomProtocolHandlers: !cfg.local})
    if (!response.ok || !response.body) throw Error('Download failed')
    if (action === 'copyImage') {
      const image = nativeImage.createFromBuffer(Buffer.from(await response.arrayBuffer()))
      if (!sessionIsCurrent() || image.isEmpty()) throw Error('Image unavailable')
      await clipboard.write([new ClipboardItem({'image/png': new Blob([image.toPNG()], {type:'image/png'})})])
      return
    }
    const directory = await temporaryDirectory()
    const local = path.join(directory, name)
    try {
      const file = await fs.open(local, 'wx', 0o600)
      await pipeline(Readable.fromWeb(response.body), file.createWriteStream())
      if (!sessionIsCurrent()) throw Error('Attachment unavailable')
      if (action === 'saveAs') {
        await fs.copyFile(local, destination)
      } else if (action === 'preview') {
        // Never invoke a file's default handler. Preview receives a local file argument only.
        await openApplication('/usr/bin/open', ['-b', 'com.apple.Preview', local])
      } else {
        shell.showItemInFolder(local)
      }
    } catch (error) {
      await fs.rm(directory, {recursive: true, force: true})
      throw error
    } finally {
      if (action === 'saveAs') await fs.rm(directory, {recursive: true, force: true})
    }
  }

  async function copyRecord(args) {
    if (typeof args?.text === 'string') await clipboard.writeText(args.text)
    else if (args?.attachment?.kind === 'image') await performAttachment('copyImage', args.attachment)
    else throw Error('Copy unavailable')
  }
  // The same trusted-main-frame guard as native menus applies to button copies.
  // Keep browser clipboard/read permissions denied; expose only this write action.
  handle('copy-record', copyRecord)

  function popup(template, position, choose) {
    currentMenu?.closePopup(window)
    const menu = Menu.buildFromTemplate(template)
    currentMenu = menu
    menu.popup({window, ...position, callback: () => {
      if (currentMenu === menu) currentMenu = undefined
      // Electron calls popup's close callback before some native click callbacks.
      setImmediate(() => choose?.(null))
    }})
  }

  handle('record-menu', args => new Promise((resolve, reject) => {
    if (!Array.isArray(args?.items) || args.items.length > 20) return resolve(null)
    const link = cfg.isolated ? null : webLink(args.link)
    const template = []
    let chosen = false
    const finish = value => { if (!chosen) { chosen = true; resolve(value) } }
    const select = async id => {
      if (chosen) return
      chosen = true
      try {
        if (id === 'copySelection' && typeof args.selection === 'string') await clipboard.writeText(args.selection)
        else if (id === 'copyRecord') {
          await copyRecord(args)
          resolve('copied')
          return
        }
        else if (id === 'copyLink' && link) await clipboard.writeText(link)
        else if (id === 'openLink' && link) await shell.openExternal(link)
        else if (attachmentActions.has(id)) await performAttachment(id, args.attachment)
        else { resolve(id); return }
        resolve(null)
      } catch (error) { reject(error) }
    }
    for (const item of args.items) {
      if (item === null) { template.push({type: 'separator'}); continue }
      if (!item || !actionIds.has(item.id) || typeof item.label !== 'string') continue
      if (['copyLink','openLink'].includes(item.id) && !link) continue
      const entry = {id: item.id, label: item.label.slice(0, 160), enabled: item.enabled !== false}
      if (item.id === 'category') {
        if (!Array.isArray(item.options)) continue
        entry.submenu = item.options.filter(o => typeof o?.label === 'string' && typeof o.id === 'string')
          .map(o => ({label: o.label.slice(0, 160), type: 'radio', checked: o.checked === true,
            click: () => finish('category:' + o.id)}))
        if (!entry.submenu.length) continue
      } else entry.click = () => { void select(item.id) }
      template.push(entry)
    }
    if (!template.length) return finish(null)
    const position = Number.isFinite(args.x) && Number.isFinite(args.y)
      ? {x: Math.round(args.x * page.getZoomFactor()), y: Math.round(args.y * page.getZoomFactor())} : {}
    popup(template, position, finish)
  }))

  page.on('context-menu', async (event, p) => {
    // Record and sidebar menus prevent the DOM default; Chromium emits this event for the remainder.
    const link = webLink(p.linkURL)
    if (!p.isEditable && !p.selectionText && !link) return
    event.preventDefault()
    const locale = await page.executeJavaScript('document.documentElement.lang').catch(() => app.getLocale())
    if (page.isDestroyed() || !window.isVisible()) return
    const labels = /^zh/i.test(locale) ? (/Hant|TW|HK/i.test(locale)
      ? ['打開連結','拷貝連結'] : ['打开链接','拷贝链接']) : ['Open Link','Copy Link']
    const template = []
    if (link) template.push({id:'openLink',label:labels[0],click:() => void shell.openExternal(link).catch(console.error)},
      {id:'copyLink',label:labels[1],click:() => void clipboard.writeText(link).catch(console.error)})
    if (p.isEditable) {
      if (template.length) template.push({type:'separator'})
      const flags = p.editFlags
      for (const group of [['undo','redo'], ['cut','copy','paste'], ['selectAll']]) {
        if (group[0] !== 'undo') template.push({type:'separator'})
        for (const role of group) template.push({id:role, role, enabled:flags['can'+role[0].toUpperCase()+role.slice(1)]})
      }
    } else if (p.selectionText) template.push({id:'copySelection',role:'copy'})
    popup(template, {x:p.x, y:p.y})
  })
}

module.exports = {installContextMenus}
