import {createElement,Fragment,useMemo,type ReactNode} from 'react';
import {parseMarkdown,type MarkdownNode} from '../markdown/parse';

interface MarkdownControls {
 onTaskToggle?:(offset:number)=>void;
 taskPending?:boolean;
 taskLabel?:string;
 /** The host must resolve this UUID against assets owned by the current account. */
 renderOwnedImage?:(node:MarkdownNode)=>ReactNode;
}
const ownedImage=/^synca-image:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const visibleText=(node:MarkdownNode):string=>node.value??node.alt??node.children?.map(visibleText).join('')??'';

/** Records and scratch previews share this renderer and the native parser contract. */
export function MessageMarkdown({text,onTaskToggle,taskPending,taskLabel,renderOwnedImage}:{text:string}&MarkdownControls){
 const document=useMemo(()=>parseMarkdown(text),[text]);
 if(document.plain)return <span className="message-plain">{text}</span>;
 function renderChildren(node:MarkdownNode):ReactNode{return node.children?.map((child,index)=><Fragment key={index}>{render(child)}</Fragment>);}
 function render(node:MarkdownNode):ReactNode {
  switch(node.type){
   case 'text':case 'html':return node.value;
   case 'paragraph':return <p>{renderChildren(node)}</p>;
   case 'heading':return createElement(`h${node.depth??1}`,null,renderChildren(node));
   case 'strong':return <strong>{renderChildren(node)}</strong>;
   case 'emphasis':return <em>{renderChildren(node)}</em>;
   case 'delete':return <del>{renderChildren(node)}</del>;
   case 'underline':return <u>{renderChildren(node)}</u>;
   case 'inlineCode':return <code>{node.value}</code>;
   case 'code':return <pre tabIndex={0}><code className={node.lang?`language-${node.lang}`:undefined}>{node.value+'\n'}</code></pre>;
   case 'break':return <br/>;
   case 'thematicBreak':return <hr/>;
   case 'blockquote':return <blockquote>{renderChildren(node)}</blockquote>;
   case 'list':return node.ordered?<ol start={node.start}>{renderChildren(node)}</ol>:<ul>{renderChildren(node)}</ul>;
   case 'listItem':{
    const task=typeof node.checked==='boolean';const offset=node.taskOffset;
    const label=node.children?.filter(child=>child.type!=='list').map(visibleText).join(' ').trim();
    return <li className={task?'task-list-item':undefined}>{task&&<><input type="checkbox" checked={node.checked} disabled={!onTaskToggle||offset===undefined}
     aria-label={label||taskLabel} aria-disabled={taskPending||undefined}
     onChange={()=>{if(!taskPending&&offset!==undefined)onTaskToggle?.(offset);}}/>{' '}</>}{node.children?.map((child,index)=><Fragment key={index}>{index===0&&child.type==='paragraph'?<span className="message-list-text" style={{whiteSpace:'pre-wrap'}}>{renderChildren(child)}</span>:render(child)}</Fragment>)}</li>;
   }
   case 'table':return <div className="message-table-scroll" tabIndex={0}><table>{node.children?.map((row,index)=>{
    const cells=<tr>{row.children?.map((cell,column)=>createElement(index===0?'th':'td',{key:column,style:{textAlign:node.align?.[column]??undefined},scope:index===0?'col':undefined},<div className="message-table-cell">{renderChildren(cell)}</div>))}</tr>;
    return index===0?<thead key={index}>{cells}</thead>:<tbody key={index}>{cells}</tbody>;
   })}</table></div>;
   case 'link':return <a href={node.url} title={node.title} className="message-link" target="_blank" rel="noopener noreferrer">{renderChildren(node)}</a>;
   case 'image':return (node.url&&ownedImage.test(node.url)?renderOwnedImage?.(node):undefined)??node.source??node.alt;
   default:return renderChildren(node)??node.value;
  }
 }
 return <div className="message-markdown">{document.children.map((node,index)=><Fragment key={index}>{render(node)}</Fragment>)}</div>;
}
