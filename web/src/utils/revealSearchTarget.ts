/** Keep the original row visible through attachment layout changes, until user intent. */
export function revealSearchTarget(container: HTMLElement, id: string, onMissing: () => void, matchedText?: string) {
  let stopped=false, frame=0, focused=false, expansionRequested=false;
  const find=()=>Array.from(container.querySelectorAll<HTMLElement>('[data-message-id]')).find(row=>row.dataset.messageId===id);
  let highlightTimer=0;
  const matchRect=(row: HTMLElement) => {
    const content=row.querySelector('.message-content');
    if (!content || !matchedText) return null;
    const walker=document.createTreeWalker(content,NodeFilter.SHOW_TEXT);
    const nodes: Text[]=[]; let node: Node | null; let text='';
    while ((node=walker.nextNode())) { nodes.push(node as Text); text+=node.textContent; }
    // Preview whitespace is collapsed; map it back into rendered Markdown text nodes.
    const offsets: number[]=[]; let normalized='';
    for(let i=0;i<text.length;i++) {
      if(/\s/.test(text[i])) {if(normalized.endsWith(' ')) continue;normalized+=' ';}
      else normalized+=text[i];
      offsets.push(i);
    }
    const needle=matchedText.replace(/\s+/g,' '), index=normalized.indexOf(needle);
    if(index<0) return null;
    const start=offsets[index], finish=offsets[index+needle.length-1]+1;
    let offset=0; const range=document.createRange(); let found=false;
    for(const node of nodes) {
      const end=offset+node.length;
      if(!found && start<end) {range.setStart(node,start-offset);found=true;}
      if(found && finish<=end) {range.setEnd(node,finish-offset);return range.getBoundingClientRect();}
      offset=end;
    }
    return null;
  };
  const position=()=>{
    frame=0; if(stopped) return;
    const row=find(); if(!row) {stop();onMissing();return;}
    const content=row.querySelector<HTMLElement>('.message-content');
    const hit=matchRect(row);
    if(!expansionRequested && matchedText && content?.classList.contains('message-content-collapsed') && (!hit || hit.bottom>content.getBoundingClientRect().bottom+1)) {
      expansionRequested=true;
      row.querySelector<HTMLButtonElement>('.message-expand[aria-expanded="false"]')?.click();
      schedule(); return;
    }
    const bounds=container.getBoundingClientRect(), rowRect=row.getBoundingClientRect();
    const rect=hit && rowRect.height>container.clientHeight-24 ? hit : rowRect;
    const inset=12, visibleHeight=container.clientHeight-inset*2;
    if(rect.height>visibleHeight || rect.top<bounds.top+inset || rect.bottom>bounds.top+container.clientHeight-inset) {
      container.scrollTop+=rect.top-bounds.top-inset;
    }
    if(!focused) {focused=true;row.classList.remove('search-target');void row.offsetWidth;row.classList.add('search-target');highlightTimer=window.setTimeout(()=>find()?.classList.remove('search-target'),1300);row.focus({preventScroll:true});}
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
