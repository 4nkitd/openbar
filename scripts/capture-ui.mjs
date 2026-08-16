import { spawn } from 'node:child_process'
import { mkdir, mkdtemp, writeFile, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'

const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const userDataDir = await mkdtemp(join(tmpdir(), 'codexbar-capture-'))
const port = 9339
const pageUrl = `file://${resolve('docs/index.html')}`
const outputDir = process.argv[2] || tmpdir()
const viewportWidth = Number(process.env.CAPTURE_WIDTH || 1440)
const viewportHeight = Number(process.env.CAPTURE_HEIGHT || 1100)
await mkdir(outputDir, { recursive: true })
const chrome = spawn(chromePath, [
  '--headless=new',
  '--disable-gpu',
  '--disable-extensions',
  '--hide-scrollbars',
  '--allow-file-access-from-files',
  `--remote-debugging-port=${port}`,
  `--user-data-dir=${userDataDir}`,
  'about:blank'
], { stdio: 'ignore' })

const delay = ms => new Promise(resolveDelay => setTimeout(resolveDelay, ms))
let socket
let nextId = 1
const pending = new Map()

async function endpoint() {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/json/list`)
      const pages = await response.json()
      const page = pages.find(item => item.type === 'page')
      if (page?.webSocketDebuggerUrl) return page.webSocketDebuggerUrl
    } catch {}
    await delay(100)
  }
  throw new Error('Chrome DevTools endpoint did not start')
}

function send(method, params = {}) {
  return new Promise((resolveSend, rejectSend) => {
    const id = nextId++
    pending.set(id, { resolve: resolveSend, reject: rejectSend })
    socket.send(JSON.stringify({ id, method, params }))
  })
}

async function evaluate(expression) {
  const result = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
  if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails))
  return result.result.value
}

async function capture(selector, filename) {
  const box = await evaluate(`(() => { const r = document.querySelector(${JSON.stringify(selector)}).getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; })()`)
  const result = await send('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: true,
    clip: { ...box, scale: 1 }
  })
  await writeFile(join(outputDir, filename), Buffer.from(result.data, 'base64'))
}

try {
  const wsUrl = await endpoint()
  socket = new WebSocket(wsUrl)
  await new Promise((resolveOpen, rejectOpen) => {
    socket.addEventListener('open', resolveOpen, { once: true })
    socket.addEventListener('error', rejectOpen, { once: true })
  })
  socket.addEventListener('message', event => {
    const message = JSON.parse(event.data)
    if (!message.id || !pending.has(message.id)) return
    const item = pending.get(message.id)
    pending.delete(message.id)
    if (message.error) item.reject(new Error(message.error.message))
    else item.resolve(message.result)
  })
  await send('Page.enable')
  await send('Runtime.enable')
  await send('Emulation.setDeviceMetricsOverride', { width: viewportWidth, height: viewportHeight, deviceScaleFactor: 1, mobile: viewportWidth <= 640 })
  await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] })
  await send('Page.navigate', { url: pageUrl })
  await delay(3500)
  if (process.env.CAPTURE_PAGE) {
    const result = await send('Page.captureScreenshot', { format: 'png' })
    await writeFile(join(outputDir, 'page.png'), Buffer.from(result.data, 'base64'))
  }
  await capture('.demo-menubar', 'menubar.png')
  await capture('.demo-menuitem', 'status-item.png')
  await capture('.demo-dropdown', 'popover.png')
  await evaluate("document.getElementById('demo-overflow').click(); document.getElementById('demo-preferences').click();")
  await delay(100)
  await capture('.win-settings', 'settings.png')
} finally {
  if (socket) socket.close()
  chrome.kill('SIGTERM')
  await delay(500)
  await rm(userDataDir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 })
}
