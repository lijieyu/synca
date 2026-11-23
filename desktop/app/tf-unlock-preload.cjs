const {contextBridge,ipcRenderer}=require('electron')
if(process.isMainFrame)contextBridge.exposeInMainWorld('unlockPreview',{
  submit:(username,password)=>ipcRenderer.invoke('synca-tf:unlock',username,password),
})
