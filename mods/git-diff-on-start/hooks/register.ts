import type { EngineInterface, Register } from 'claude-code'

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    // turns === 0 keeps a hot reload mid-session from opening /diff again
    if (e.isInteractive && (await $.session.repo()) && (await $.session.turns()) === 0) {
      void openDiff($)
      void openEditor($)
    }
    return next(e)
  })
}

// /diff is registered by the built-in diff plugin after session.start settles, so wait for it
const openDiff = async ($: EngineInterface) => {
  for (let i = 0; i < 40; i++) {
    if ((await $.command.list()).some(c => c.name === 'diff')) break
    await $.clock.sleep(250)
  }
  // /diff toggles: if the panel was restored open, the first run hides it, so run again
  const { text } = await $.command.run({ command: 'diff' })
  if (text?.includes('hidden')) await $.command.run({ command: 'diff' })
}

// same as `code . || antigravity-ide .`: antigravity-ide takes over when code is missing or fails
const openEditor = async ($: EngineInterface) => {
  for (const editor of ['code', 'antigravity-ide']) {
    const ok = await $.process.run([editor, '.']).then(r => r.exitCode === 0, () => false)
    if (ok) return
  }
}
