import { expect, test } from 'claude-code/testing'

declare const setTimeout: (fn: (value?: unknown) => void, ms: number) => unknown

const opened_ref: { current: string[] } = { current: [] }

const start = async (
  $: any,
  on: any,
  { repo, turns, isInteractive, hiddenFirst = false, editors = ['code'] }: { repo: boolean; turns: number; isInteractive: boolean; hiddenFirst?: boolean; editors?: string[] },
) => {
  const ran: string[] = []
  const opened: string[] = []
  opened_ref.current = opened
  on('session.repo', () => ({ value: repo ? { internal: false } : null }))
  on('session.turns', () => ({ value: turns }))
  on('clock.sleep', () => ({ value: undefined }))
  let listed = 0
  // /diff shows up in the list only on the third look, as in the real session
  on('command.list', () => ({ value: ++listed < 3 ? [] : [{ name: 'diff' }] }))
  on('command.run', (_: unknown, e: { command: string }) => {
    ran.push(e.command)
    return { text: ran.length === 1 && hiddenFirst ? 'Diff panel hidden' : 'Diff panel shown' }
  })
  // editors lists the executables that exist; anything else fails to start
  on('process.run', (_: unknown, e: { argv: string[] }) => {
    opened.push(e.argv[0])
    if (!editors.includes(e.argv[0])) throw new Error('spawn ENOENT')
    return { value: { exitCode: 0, stdout: '', stderr: '' } }
  })
  on('session.start', (_: unknown, e: { cwd: string }) => ({ cwd: e.cwd }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive })
  await new Promise(r => setTimeout(r, 1200))
  return ran
}

test('opens /diff on an interactive start inside a repo', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: true })).toEqual(['diff'])
})

test('does nothing outside a repo', async ($, on) => {
  expect(await start($, on, { repo: false, turns: 0, isInteractive: true })).toEqual([])
})

test('does nothing when headless', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: false })).toEqual([])
})

test('does nothing after a mid-session reload', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 3, isInteractive: true })).toEqual([])
})

test('runs /diff again when the first run hid a restored panel', async ($, on) => {
  expect(await start($, on, { repo: true, turns: 0, isInteractive: true, hiddenFirst: true })).toEqual(['diff', 'diff'])
})

test('opens the project in code', async ($, on) => {
  await start($, on, { repo: true, turns: 0, isInteractive: true })
  expect(opened_ref.current).toEqual(['code'])
})

test('falls back to antigravity-ide when code is missing', async ($, on) => {
  await start($, on, { repo: true, turns: 0, isInteractive: true, editors: ['antigravity-ide'] })
  expect(opened_ref.current).toEqual(['code', 'antigravity-ide'])
})

test('opens no editor outside a repo', async ($, on) => {
  await start($, on, { repo: false, turns: 0, isInteractive: true })
  expect(opened_ref.current).toEqual([])
})
