import {parseMarkdown,toggleMarkdownTask} from './parse';
export const parseJSON=(source:string):string=>JSON.stringify(parseMarkdown(source));
export const toggleTask=toggleMarkdownTask;
