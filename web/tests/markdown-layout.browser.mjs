// Run against tests/markdown-fixture.html. Uses real record/scratch components and CSS.
export default async function markdownLayout(page){
 await page.locator('header select').selectOption('list-whitespace');
 const expand=page.locator('.fixture-record .message-expand');if(await expand.count())await expand.click();
 await page.locator('.scratch-modes button').nth(1).click();
 await page.locator('.fixture-scratch .message-list-text').first().waitFor();
 const whitespace=await page.locator('.message-list-text').evaluateAll(nodes=>nodes.map(node=>({text:node.textContent,whiteSpace:getComputedStyle(node).whiteSpace})));
 if(!whitespace.length||whitespace.some(node=>node.whiteSpace!=='pre-wrap'))throw Error('List whitespace collapsed');
 const headers=Array.from({length:40},(_,i)=>`Column ${i+1}`);
 const wide=`| ${headers.join(' | ')} |\n| ${headers.map(()=>'---').join(' | ')} |\n| ${headers.map(()=>'readable value').join(' | ')} |`;
 await page.locator('.scratch-modes button').first().click();
 await page.locator('.scratchpad textarea').fill(wide);
 await page.locator('.scratch-modes button').nth(1).click();
 const table=page.locator('.fixture-scratch .message-table-scroll');
 await table.waitFor();
 const dimensions=await table.evaluate(node=>({width:node.clientWidth,scroll:node.scrollWidth,cells:[...node.querySelectorAll('th')].map(cell=>({width:cell.getBoundingClientRect().width,font:parseFloat(getComputedStyle(cell).fontSize)}))}));
 if(dimensions.scroll<=dimensions.width)throw Error('Wide table must scroll horizontally');
 if(dimensions.cells.some(cell=>cell.width<6*cell.font))throw Error('Table columns compressed below readable width');
 await table.evaluate(node=>{node.scrollLeft=200;});
 if(await table.evaluate(node=>node.scrollLeft)<=0)throw Error('Table scroll position did not change');
 await page.locator('.scratch-modes button').first().click();
 await page.locator('.scratchpad textarea').fill('| Long cell |\n| --- |\n| '+('longtoken'.repeat(100))+' |');
 await page.locator('.scratch-modes button').nth(1).click();
 const longCell=await page.locator('.fixture-scratch td .message-table-cell').evaluate(node=>({width:node.getBoundingClientRect().width,height:node.getBoundingClientRect().height,font:parseFloat(getComputedStyle(node).fontSize)}));
 if(longCell.width>28*longCell.font+1||longCell.height<2*longCell.font)throw Error('Long cell did not wrap within its width limit');
 return {whitespace,dimensions,longCell};
}
