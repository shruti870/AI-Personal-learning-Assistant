'use client'

export type TestCase = {
  test_id: number
  input_json: string
  expect_json: string
  is_hidden: boolean
  ordinal: number
}

export type TestResult = {
  ordinal: number
  hidden: boolean
  passed: boolean
  got: string
  want: string
}

export type RunOutcome = { results: TestResult[]; error: string | null }

/**
 * Remote runner for compiled languages.
 *
 * C++ and Java have no practical browser runtime, so they are compiled and
 * executed server-side. main() is generated from the problem's type
 * signature, so the student writes only `solve`.
 */
export async function runRemote(
  problemId: string,
  language: string,
  code: string
): Promise<RunOutcome> {
  try {
    const res = await fetch('/api/run', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ problemId, language, code }),
    })
    const data = await res.json()
    if (!res.ok) return { results: [], error: data.error ?? `Request failed (${res.status})` }
    return { results: data.results ?? [], error: data.error ?? null }
  } catch {
    return {
      results: [],
      error: 'Could not reach the execution service. Python still runs offline.',
    }
  }
}

/* ------------------------------------------------------------------ */
/* Python via Pyodide                                                  */
/* ------------------------------------------------------------------ */

const PYODIDE_VERSION = 'v0.26.2'
const PYODIDE_URL = `https://cdn.jsdelivr.net/pyodide/${PYODIDE_VERSION}/full/`

type Pyodide = { runPython: (code: string) => unknown }

declare global {
  interface Window {
    loadPyodide?: (opts: { indexURL: string }) => Promise<Pyodide>
  }
}

let pyodidePromise: Promise<Pyodide> | null = null

/** Loads Pyodide once, on first use. Roughly 10 MB, so never eagerly. */
export function loadPyodide(): Promise<Pyodide> {
  if (pyodidePromise) return pyodidePromise

  pyodidePromise = new Promise<Pyodide>((resolve, reject) => {
    if (window.loadPyodide) {
      window.loadPyodide({ indexURL: PYODIDE_URL }).then(resolve).catch(reject)
      return
    }
    const script = document.createElement('script')
    script.src = `${PYODIDE_URL}pyodide.js`
    script.onload = () => {
      if (!window.loadPyodide) {
        reject(new Error('Pyodide loaded but the entry point is missing.'))
        return
      }
      window.loadPyodide({ indexURL: PYODIDE_URL }).then(resolve).catch(reject)
    }
    script.onerror = () =>
      reject(new Error('Could not reach the Pyodide CDN. Check your connection.'))
    document.head.appendChild(script)
  })

  return pyodidePromise
}

/**
 * Runs the student's Python and compares against the same JSON expectations
 * the JavaScript runner uses. separators=(',', ':') matters: json.dumps
 * inserts spaces by default and every comparison would fail.
 */
export async function runPython(code: string, tests: TestCase[]): Promise<RunOutcome> {
  let py: Pyodide
  try {
    py = await loadPyodide()
  } catch (e) {
    return { results: [], error: e instanceof Error ? e.message : String(e) }
  }

  const ordered = [...tests].sort((a, b) => a.ordinal - b.ordinal)
  const inputs = JSON.stringify(ordered.map((t) => t.input_json))

  const harness = `
import json, traceback

_user_globals = {}
_outputs = []
_fatal = None

try:
    exec(${JSON.stringify(code)}, _user_globals)
    _solve = _user_globals.get('solve')
    if not callable(_solve):
        _fatal = 'No function named solve was defined.'
except Exception:
    _fatal = traceback.format_exc(limit=1).strip().splitlines()[-1]

if _fatal is None:
    for _raw in json.loads(${JSON.stringify(inputs)}):
        try:
            _args = json.loads(_raw)
            _r = _solve(*_args)
            _outputs.append(json.dumps(_r, separators=(',', ':')))
        except Exception as _e:
            _outputs.append('threw: ' + type(_e).__name__ + ': ' + str(_e))

json.dumps({'fatal': _fatal, 'outputs': _outputs})
`

  let payload: { fatal: string | null; outputs: string[] }
  try {
    payload = JSON.parse(String(py.runPython(harness)))
  } catch (e) {
    return { results: [], error: e instanceof Error ? e.message : String(e) }
  }

  if (payload.fatal) return { results: [], error: payload.fatal }

  const results: TestResult[] = ordered.map((t, i) => {
    const got = payload.outputs[i] ?? 'no output'
    return {
      ordinal: t.ordinal,
      hidden: t.is_hidden,
      passed: got === t.expect_json,
      got,
      want: t.expect_json,
    }
  })

  return { results, error: null }
}