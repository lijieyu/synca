import { _electron as electron } from 'playwright-core'
import {mkdtemp} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import path from 'node:path'
const app=await electron.launch({executablePath:process.argv[2] || '/Applications/Synca Electron.app/Contents/MacOS/Synca Electron',args:['--user-data-dir='+await mkdtemp(path.join(tmpdir(),'synca-login-check-'))]})
try {
 const p=await app.firstWindow()
 await p.locator('#appleid-signin').waitFor()
 await p.waitForFunction(()=>Boolean(window.AppleID))
 const popup=app.waitForEvent('window',{timeout:20000})
 await p.locator('#appleid-signin').click()
 const signin=await popup
 await signin.waitForURL(url=>url.hostname==='appleid.apple.com'||url.hostname==='account.apple.com',{timeout:20000,waitUntil:'commit'})
 console.log('Apple authorization window',new URL(signin.url()).origin)
}finally{ await app.close() }
