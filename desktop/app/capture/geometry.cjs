(function(root){
 const clamp=(v,min,max)=>Math.min(max,Math.max(min,v));
 function rect(a,b,bounds){const x=clamp(Math.min(a.x,b.x),0,bounds.width),y=clamp(Math.min(a.y,b.y),0,bounds.height);return{x,y,width:clamp(Math.max(a.x,b.x),0,bounds.width)-x,height:clamp(Math.max(a.y,b.y),0,bounds.height)-y};}
 function intersection(a,b){const x=Math.max(a.x,b.x),y=Math.max(a.y,b.y);return{x,y,width:Math.max(0,Math.min(a.x+a.width,b.x+b.width)-x),height:Math.max(0,Math.min(a.y+a.height,b.y+b.height)-y)};}
 function windowAt(point,windows,display){const window=windows.find(r=>point.x>=r.x&&point.y>=r.y&&point.x<r.x+r.width&&point.y<r.y+r.height);if(!window)return null;const r=intersection(window,display);return r.width>0&&r.height>0?{...r,x:r.x-display.x,y:r.y-display.y}:null;}
 function pixels(rect,size,display){const sx=size.width/display.width,sy=size.height/display.height;const x=clamp(Math.floor(rect.x*sx),0,size.width-1),y=clamp(Math.floor(rect.y*sy),0,size.height-1);return{x,y,width:clamp(Math.ceil((rect.x+rect.width)*sx)-x,1,size.width-x),height:clamp(Math.ceil((rect.y+rect.height)*sy)-y,1,size.height-y)};}
 const api={rect,intersection,windowAt,pixels};if(typeof module!=='undefined')module.exports=api;else root.captureGeometry=api;
})(globalThis);
