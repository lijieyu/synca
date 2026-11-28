const colors=['#ff453a','#ffd60a','#30d158','#0a84ff','#ffffff','#000000'];
function validateSelection(value,display){
 const validRect=r=>r&&['x','y','width','height'].every(key=>Number.isFinite(r[key]))&&r.x>=0&&r.y>=0&&r.width>=1&&r.height>=1&&r.x+r.width<=display.width+.01&&r.y+r.height<=display.height+.01;
 if(!value||!validRect(value.rect)||!Array.isArray(value.marks)||value.marks.length>500)throw Error('Invalid selection');
 for(const mark of value.marks)if(!validRect(mark)||!colors.includes(mark.color)||![2,3,5,8].includes(mark.stroke))throw Error('Invalid annotation');
 return value;
}
module.exports={validateSelection};
