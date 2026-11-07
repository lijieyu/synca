// Injected only into the staging artifact, never bundled into production.
if (!localStorage.getItem('authToken')) location.replace('/__preview/');
window.addEventListener('DOMContentLoaded', () => {
  const marker=document.createElement('a');
  marker.href='/__preview/'; marker.textContent='预发环境 · 独立测试数据 · 切换账号';
  marker.style.cssText='position:fixed;z-index:10000;left:50%;top:0;transform:translateX(-50%);max-width:90%;white-space:nowrap;font:11px/1.4 system-ui;padding:3px 12px;border-radius:0 0 8px 8px;background:#6d45ca;color:#fff;text-decoration:none';
  document.body.appendChild(marker);
  new MutationObserver(()=>{if(!localStorage.getItem('authToken'))location.replace('/__preview/');}).observe(document.getElementById('root'),{childList:true,subtree:true});
});
