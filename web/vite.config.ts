import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { execFileSync } from 'node:child_process'

export default defineConfig(({ command }) => {
  let revision = 'local'
  try {
    revision = execFileSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd: process.env.SYNCA_SOURCE_ROOT || process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'],
    }).trim()
  } catch {
    if (command === 'build') throw new Error('A source revision is required for a production Web build')
  }
  const date = new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date()).replaceAll('-', '.')
  return { plugins: [react()], define: { __WEB_RELEASE__: JSON.stringify(`${date} · ${revision}`) } }
})
