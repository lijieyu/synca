'use strict';
const $=id=>document.getElementById(id),canvas=$('screen'),ctx=canvas.getContext('2d'),geometry=globalThis.captureGeometry;
let data,image,selection,hover,drag,marks=[],previewMark,mode='select',busy=false;
const text={en:{hint:'Hover to select a window · Drag for a region · Esc to cancel',select:'Select',annotate:'Rectangle',undo:'Undo',save:'Save',cancel:'Cancel',copy:'Copy',color:'Color',width:'Width',error:'Could not finish. Try again.',colors:['Red','Yellow','Green','Blue','White','Black']},zh:{hint:'悬停选窗口 · 拖动选区域 · Esc 取消',select:'选区',annotate:'矩形标注',undo:'撤销',save:'保存',cancel:'取消',copy:'复制',color:'颜色',width:'线宽',error:'操作未完成，请重试。',colors:['红','黄','绿','蓝','白','黑']},'zh-Hant':{hint:'懸停選視窗 · 拖動選區域 · Esc 取消',select:'選區',annotate:'矩形標註',undo:'復原',save:'儲存',cancel:'取消',copy:'複製',color:'顏色',width:'線寬',error:'操作未完成，請重試。',colors:['紅','黃','綠','藍','白','黑']}};
let labels=text.en;
function point(e){return{x:Math.max(0,Math.min(innerWidth,e.clientX)),y:Math.max(0,Math.min(innerHeight,e.clientY))};}
function handles(r){return[[r.x,r.y],[r.x+r.width/2,r.y],[r.x+r.width,r.y],[r.x+r.width,r.y+r.height/2],[r.x+r.width,r.y+r.height],[r.x+r.width/2,r.y+r.height],[r.x,r.y+r.height],[r.x,r.y+r.height/2]];}
function drawMark(c,m){c.strokeStyle=m.color;c.lineWidth=m.stroke;c.strokeRect(m.x+m.stroke/2,m.y+m.stroke/2,Math.max(0,m.width-m.stroke),Math.max(0,m.height-m.stroke));}
function draw(){
 if(!image)return;const scale=devicePixelRatio;canvas.width=Math.round(innerWidth*scale);canvas.height=Math.round(innerHeight*scale);canvas.style.width=innerWidth+'px';canvas.style.height=innerHeight+'px';ctx.setTransform(scale,0,0,scale,0,0);ctx.drawImage(image,0,0,innerWidth,innerHeight);
 ctx.fillStyle='#0007';ctx.fillRect(0,0,innerWidth,innerHeight);const r=selection||hover;
 if(r){ctx.save();ctx.beginPath();ctx.rect(r.x,r.y,r.width,r.height);ctx.clip();ctx.drawImage(image,0,0,innerWidth,innerHeight);for(const m of marks)drawMark(ctx,m);if(previewMark)drawMark(ctx,previewMark);ctx.restore();ctx.strokeStyle='#55b7ff';ctx.lineWidth=1;ctx.strokeRect(r.x+.5,r.y+.5,r.width,r.height);
  if(selection&&mode==='select'){ctx.fillStyle='#fff';for(const [x,y]of handles(r))ctx.fillRect(x-3,y-3,6,6);}
  const pixel=geometry.pixels(r,{width:image.naturalWidth,height:image.naturalHeight},data.display);$('size').textContent=`${pixel.width} × ${pixel.height}`;$('size').style.left=Math.min(innerWidth-90,r.x)+'px';$('size').style.top=Math.max(0,r.y-24)+'px';
 }else $('size').textContent='';
 $('toolbar').hidden=!selection;$('hint').hidden=!!selection;$('undo').disabled=marks.length===0||busy;
 if(selection){const bar=$('toolbar'),width=bar.offsetWidth,height=bar.offsetHeight;bar.style.left=Math.max(8,Math.min(innerWidth-width-8,selection.x+selection.width-width))+'px';bar.style.top=Math.max(8,Math.min(innerHeight-height-8,selection.y+selection.height+10))+'px';}
}
canvas.addEventListener('pointermove',e=>{
 if(!data||!image||busy)return;
 const p=point(e);
 if(!drag){if(!selection)hover=geometry.windowAt({x:p.x+data.display.x,y:p.y+data.display.y},data.windows,data.display);draw();return;}
 if(drag.type==='region')selection=geometry.rect(drag.start,p,data.display);
 else if(drag.type==='annotation')previewMark={...geometry.rect(drag.start,p,data.display),color:$('color').value,stroke:Number($('width').value)};
 else if(drag.type==='resize'){
  const old=drag.original,index=drag.handle;let left=old.x,right=old.x+old.width,top=old.y,bottom=old.y+old.height;
  if([0,6,7].includes(index))left=p.x;if([2,3,4].includes(index))right=p.x;if([0,1,2].includes(index))top=p.y;if([4,5,6].includes(index))bottom=p.y;
  selection=geometry.rect({x:left,y:top},{x:right,y:bottom},data.display);
 }else if(drag.type==='move'){
  const old=drag.original;selection={...old,x:Math.max(0,Math.min(innerWidth-old.width,old.x+p.x-drag.start.x)),y:Math.max(0,Math.min(innerHeight-old.height,old.y+p.y-drag.start.y))};
 }
 draw();
});
canvas.addEventListener('pointerdown',e=>{
 if(!data||!image||busy||e.button!==0)return;const p=point(e);canvas.setPointerCapture(e.pointerId);
 if(selection&&mode==='annotate'){drag={type:'annotation',start:p};return;}
 const handle=selection?handles(selection).findIndex(([x,y])=>Math.abs(x-p.x)<9&&Math.abs(y-p.y)<9):-1;
 if(handle>=0)drag={type:'resize',handle,original:{...selection},start:p};
 else if(selection&&p.x>=selection.x&&p.x<=selection.x+selection.width&&p.y>=selection.y&&p.y<=selection.y+selection.height)drag={type:'move',original:{...selection},start:p};
 else {drag={type:'region',start:p,hover};selection=null;marks=[];}
});
canvas.addEventListener('pointerup',e=>{
 if(!drag)return;const p=point(e);
 if(drag.type==='region'&&Math.hypot(p.x-drag.start.x,p.y-drag.start.y)<4)selection=drag.hover||null;
 if(previewMark&&previewMark.width>=2&&previewMark.height>=2&&marks.length<500)marks.push(previewMark);
 previewMark=null;drag=null;if(selection&&(selection.width<2||selection.height<2))selection=null;draw();
});
canvas.addEventListener('pointercancel',()=>{drag=null;previewMark=null;draw();});
function setMode(next){mode=next;$('select').setAttribute('aria-pressed',String(next==='select'));$('annotate').setAttribute('aria-pressed',String(next==='annotate'));draw();}
$('select').onclick=()=>setMode('select');$('annotate').onclick=()=>setMode('annotate');$('undo').onclick=()=>{marks.pop();draw();};$('cancel').onclick=()=>window.capture.cancel();
async function finish(action){
 if(!selection||busy)return;busy=true;for(const b of document.querySelectorAll('#toolbar button'))b.disabled=true;
 try{const crop=geometry.pixels(selection,{width:image.naturalWidth,height:image.naturalHeight},data.display);const output=document.createElement('canvas');output.width=crop.width;output.height=crop.height;const c=output.getContext('2d');c.drawImage(image,crop.x,crop.y,crop.width,crop.height,0,0,crop.width,crop.height);
  c.scale(image.naturalWidth/data.display.width,image.naturalHeight/data.display.height);c.translate(-selection.x,-selection.y);for(const m of marks)drawMark(c,m);
  const result=await window.capture.finish({action,rect:selection,marks,png:output.toDataURL('image/png')});
  if(result?.error){$('hint').hidden=false;$('hint').textContent=labels.error;}
 }catch{$('hint').hidden=false;$('hint').textContent=labels.error;}
 finally{busy=false;for(const b of document.querySelectorAll('#toolbar button'))b.disabled=false;}
}
$('save').onclick=()=>void finish('save');$('copy').onclick=()=>void finish('copy');
document.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();window.capture.cancel();}else if(e.key==='Enter'&&!['SELECT','BUTTON'].includes(document.activeElement.tagName)){e.preventDefault();void finish('copy');}else if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='z'){e.preventDefault();marks.pop();draw();}});
window.addEventListener('resize',draw);
window.capture.load().then(async payload=>{data=payload;labels=text[payload.language]||text.en;document.documentElement.lang=payload.language;
 for(const id of ['select','annotate','undo','save','cancel','copy'])$(id).textContent=labels[id];$('color').setAttribute('aria-label',labels.color);$('width').setAttribute('aria-label',labels.width);[...$('color').options].forEach((option,index)=>option.text=labels.colors[index]);$('hint').textContent=labels.hint;canvas.setAttribute('aria-label',labels.hint);
 image=new Image();image.src=payload.png;await image.decode();hover=geometry.windowAt(payload.cursor,payload.windows,payload.display);draw();document.body.dataset.ready='true';
}).catch(()=>window.capture.cancel());
