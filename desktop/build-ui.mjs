import path from 'node:path'
import os from 'node:os'
import fs from 'node:fs/promises'
import {execFileSync} from 'node:child_process'
const root=path.resolve(process.env.SYNCA_WEB||'../web')
const modules=path.resolve(process.env.SYNCA_WEB_MODULES||path.join(root,'node_modules'))
const stage=await fs.mkdtemp(path.join(os.tmpdir(),'synca-renderer-'))
try{
  for(const name of ['src','public','package.json','index.html','vite.config.ts','tsconfig.json','tsconfig.app.json','tsconfig.node.json']){
    await fs.cp(path.join(root,name),path.join(stage,name),{recursive:true})
  }
  await fs.symlink(modules,path.join(stage,'node_modules'),'dir')
  execFileSync('git',['apply','--no-index',path.resolve('frontend.patch')],{cwd:stage,stdio:'inherit'})
  await fs.cp('ui',path.join(stage,'src/desktop'),{recursive:true})
  execFileSync(path.join(modules,'.bin/tsc'),['-b'],{cwd:stage,stdio:'inherit'})
  execFileSync(path.join(modules,'.bin/vite'),['build','--outDir',path.resolve('app/renderer'),'--emptyOutDir'],{cwd:stage,stdio:'inherit',env:{...process.env,SYNCA_SOURCE_ROOT:root}})
}finally{await fs.rm(stage,{recursive:true,force:true})}
