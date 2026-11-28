import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import {fileURLToPath} from 'node:url';
export default defineConfig({
 root:fileURLToPath(new URL('..',import.meta.url)),
 plugins:[react()],
 define:{__WEB_RELEASE__:JSON.stringify('isolated-markdown-acceptance')},
 build:{outDir:'/tmp/synca-markdown-fixture',emptyOutDir:true,rollupOptions:{input:fileURLToPath(new URL('./markdown-fixture.html',import.meta.url))}},
});
