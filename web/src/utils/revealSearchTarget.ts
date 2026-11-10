/** Keep the original row visible through attachment layout changes, until user intent. */
export function revealSearchTarget(container: HTMLElement, id: string, onMissing: () => void) {
  let stopped=false, frame=0, focused=false;
  const find=()=>Array.from(container.querySelectorAll<HTMLElement>('[data-message-id]')).find(row=>row.dataset.messageId===id);
  const highlightTimer=window.setTimeout(()=>find()?.classList.remove('search-target'),1300);
  const position=()=>{
    frame=0; if(stopped) return;
    const row=find(); if(!row) {stop();onMissing();return;}
    const bounds=container.getBoundingClientRect(), rect=row.getBoundingClientRect();
    const inset=12, visibleHeight=container.clientHeight-inset*2;
    if(rect.height>visibleHeight || rect.top<bounds.top+inset || rect.bottom>bounds.top+container.clientHeight-inset) {
      container.scrollTop+=rect.top-bounds.top-inset;
    }
    if(!focused) {focused=true;row.classList.remove('search-target');void row.offsetWidth;row.classList.add('search-target');row.focus({preventScroll:true});}
  };
  const schedule=()=>{if(!frame&&!stopped) frame=requestAnimationFrame(position);};
  const resize=new ResizeObserver(schedule);
  const observe=()=>{resize.disconnect();resize.observe(container);container.querySelectorAll('[data-message-id]').forEach(row=>resize.observe(row));schedule();};
  const mutations=new MutationObserver(observe);
  const key=(event:KeyboardEvent)=>{if(['ArrowUp','ArrowDown','PageUp','PageDown','Home','End',' '].includes(event.key)) stop();};
  function stop() {stopped=true;cancelAnimationFrame(frame);resize.disconnect();mutations.disconnect();container.removeEventListener('wheel',stop);container.removeEventListener('touchstart',stop);container.removeEventListener('pointerdown',stop);window.removeEventListener('keydown',key);}
  container.addEventListener('wheel',stop,{passive:true});container.addEventListener('touchstart',stop,{passive:true});container.addEventListener('pointerdown',stop,{passive:true});window.addEventListener('keydown',key);
  mutations.observe(container,{childList:true,subtree:true});observe();
  return ()=>{stop();clearTimeout(highlightTimer);find()?.classList.remove('search-target');};
}
