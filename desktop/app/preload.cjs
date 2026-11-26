const { contextBridge, ipcRenderer } = require('electron')
const masPreflight = process.argv.includes('--synca-mas-preflight')
const localPreview = process.argv.includes('--synca-local-preview')
const preview = masPreflight || localPreview || process.argv.includes('--synca-internal-preview')
const origin = masPreflight ? 'https://synca-testflight.invalid' : localPreview ? 'https://synca-preview.localhost' : preview ? 'https://synca-preview.haerth.cn' : 'https://synca.haerth.cn'
if (process.isMainFrame && location.origin === origin) {
  if (process.platform === 'win32') {
    window.addEventListener('DOMContentLoaded', () => {
      const system = window.matchMedia('(prefers-color-scheme: dark)')
      const update = () => {
        const appearance = document.documentElement.dataset.appearance
        ipcRenderer.send('desktop:window-appearance', appearance === 'dark' || (appearance !== 'light' && system.matches))
      }
      new MutationObserver(update).observe(document.documentElement, {attributes:true, attributeFilter:['data-appearance']})
      system.addEventListener('change', update)
      update()
    }, {once:true})
  }
  contextBridge.exposeInMainWorld('syncaDesktop', {
    version:process.argv.find(value=>value.startsWith('--synca-version='))?.slice('--synca-version='.length) ?? '',
    build:process.argv.find(value=>value.startsWith('--synca-build='))?.slice('--synca-build='.length) ?? '', emailAuth:!masPreflight, preview, localPreview, platform:process.platform === 'darwin' ? 'macOS' : 'Windows',
    ...(!preview ? {updateState:()=>ipcRenderer.invoke('desktop:update-state'), updateAction:action=>ipcRenderer.invoke('desktop:update-action',action)} : {}),
    recordMenu:options=>ipcRenderer.invoke('desktop:record-menu',options),
    copyRecord:options=>ipcRenderer.invoke('desktop:copy-record',options),
    preferences:()=>ipcRenderer.invoke('desktop:preferences'),
    change:(key,value)=>ipcRenderer.invoke('desktop:change',key,value),
    directory:()=>ipcRenderer.invoke('desktop:directory'),
    count:n=>ipcRenderer.send('desktop:count',n),
    clearCompletedAvailable:available=>ipcRenderer.send('desktop:clear-available',available),
    session:token=>ipcRenderer.send('desktop:session',token),
    subscribe:(name,fn)=>{
      if (!['settings','refresh','sync','clear-completed','update'].includes(name)) throw Error('Unknown desktop event')
      const listener=()=>fn()
      ipcRenderer.on('desktop:'+name,listener)
      return ()=>ipcRenderer.removeListener('desktop:'+name,listener)
    }
  })
}
