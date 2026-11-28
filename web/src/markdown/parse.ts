import {fromMarkdown} from 'mdast-util-from-markdown';
import {gfmFromMarkdown} from 'mdast-util-gfm';
import {gfm} from 'micromark-extension-gfm';
import type {Root,RootContent,PhrasingContent,Definition} from 'mdast';

export interface MarkdownNode {
 type:string;
 children?:MarkdownNode[];
 value?:string;
 depth?:number;
 ordered?:boolean;
 start?:number;
 checked?:boolean;
 taskOffset?:number;
 align?:('left'|'right'|'center'|null)[];
 url?:string;
 title?:string;
 alt?:string;
 lang?:string;
 source?:string;
 position?:{start:{offset:number};end:{offset:number}};
}
export interface MarkdownDocument {version:1;type:'root';plain:boolean;children:MarkdownNode[]}
const options={extensions:[gfm()],mdastExtensions:[gfmFromMarkdown()]};
const safeLink=(url:string)=>/^(?:https?:\/\/|mailto:|tel:)/i.test(url);
type InputNode=Root|RootContent|PhrasingContent;

/** Pure CommonMark/GFM parser shared by React and the bundled JavaScriptCore runtime. */
export function parseMarkdown(source:string):MarkdownDocument {
 try{return parseDocument(source);}catch{
  // Malformed/deep documents must never take down a feed row or discard editable source.
  return {version:1,type:'root',plain:true,children:[{type:'paragraph',children:[{type:'text',value:source}]}]};
 }
}
function parseDocument(source:string):MarkdownDocument {
 const tree=fromMarkdown(source,options);
 const definitions=new Map<string,Definition>();
 function collect(node:InputNode,depth=0){
  if(depth>128)throw new RangeError('Markdown nesting limit');
  if(node.type==='definition'&&!definitions.has(node.identifier.toUpperCase()))definitions.set(node.identifier.toUpperCase(),node);
  if('children' in node)node.children.forEach(child=>collect(child,depth+1));
 }
 collect(tree);
 function normalize(node:InputNode):MarkdownNode[] {
  if(node.type==='definition')return [];
  const start=node.position?.start.offset,end=node.position?.end.offset;
  const result:MarkdownNode={type:node.type};
  if(start!==undefined&&end!==undefined)result.position={start:{offset:start},end:{offset:end}};
  if('value'in node)result.value=node.value;
  if('children'in node)result.children=underlines(node.children.flatMap(normalize));
  if(node.type==='heading')result.depth=node.depth;
  if(node.type==='list'){result.ordered=node.ordered??false;if(node.start!=null)result.start=node.start;}
  if(node.type==='listItem'&&typeof node.checked==='boolean'){
   result.checked=node.checked;
   if(start!==undefined&&end!==undefined){
    const offset=source.indexOf('[',start)+1;
    if(offset>start&&offset<end&&/^[ xX]\]/.test(source.slice(offset,offset+2)))result.taskOffset=offset;
   }
  }
  if(node.type==='table')result.align=node.align??[];
  if(node.type==='code'&&node.lang)result.lang=node.lang;
  if(node.type==='image'||node.type==='imageReference'){
   result.type='image';result.alt=node.alt??'';result.source=source.slice(start,end);
   const definition=node.type==='imageReference'?definitions.get(node.identifier.toUpperCase()):node;
   if(definition){result.url=definition.url;if(definition.title)result.title=definition.title;}
  }
  if(node.type==='link'||node.type==='linkReference'){
   const definition=node.type==='linkReference'?definitions.get(node.identifier.toUpperCase()):node;
   if(!definition||!safeLink(definition.url))return result.children??[];
   result.type='link';result.url=definition.url;if(definition.title)result.title=definition.title;
  }
  return [result];
 }
 function underlines(children:MarkdownNode[]):MarkdownNode[]{
  let opening=-1;
  for(let i=0;i<children.length;i++){
   const child=children[i];
   if(child.type!=='html')continue;
   if(child.value==='<u>'){opening=i;continue;}
   if(child.value==='</u>'&&opening>=0){
    const first=children[opening];const start=first.position?.start.offset,end=child.position?.end.offset;
    if(start!==undefined&&end!==undefined&&!/[\r\n]/.test(source.slice(start,end))){
     children.splice(opening,i-opening+1,{type:'underline',children:children.slice(opening+1,i),position:{start:{offset:start},end:{offset:end}}});i=opening;
    }
   }
   opening=-1;
  }
  return children;
 }
 const children=tree.children.flatMap(normalize);
 const plain=children.every(node=>node.type==='paragraph'&&node.children?.every(child=>child.type==='text'));
 return {version:1,type:'root',plain,children};
}

/** Validate against the current parsed source, never against a stale or code-like bracket. */
export function toggleMarkdownTask(source:string,offset:number):string|null {
 if(!Number.isInteger(offset)||offset<0)return null;
 const contains=(nodes:MarkdownNode[]):boolean=>nodes.some(node=>node.taskOffset===offset||(node.children!==undefined&&contains(node.children)));
 if(!contains(parseMarkdown(source).children))return null;
 return source.slice(0,offset)+(source[offset]===' '?'x':' ')+source.slice(offset+1);
}
