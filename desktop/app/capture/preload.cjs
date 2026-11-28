const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('capture',{
 load:()=>ipcRenderer.invoke('capture:load'),
 finish:value=>ipcRenderer.invoke('capture:finish',value),
 cancel:()=>ipcRenderer.send('capture:cancel'),
});
