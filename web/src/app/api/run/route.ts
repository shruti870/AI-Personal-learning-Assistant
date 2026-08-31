import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

/**
 * Remote execution for compiled languages.
 *
 * C++ and Java cannot run in a browser at any sane weight, so they go to a
 * public judge. Python deliberately does NOT come through here: it runs
 * client-side via Pyodide, which keeps the coding section usable when the
 * network is unavailable.
 *
 * The student writes only a `solve` function. main() is generated here from
 * the problem's type signature, so they never hand-write I/O parsing.
 */

const PISTON = 'https://emkc.org/api/v2/piston/execute'

const VERSIONS: Record<string, { language: string; version: string; filename: string }> = {
  cpp: { language: 'c++', version: '10.2.0', filename: 'main.cpp' },
  java: { language: 'java', version: '15.0.2', filename: 'Main.java' },
}

type Sig = { params: string[]; ret: string }

function parseSignature(sig: string): Sig | null {
  const [lhs, ret] = sig.split('->')
  if (!lhs || !ret) return null
  return { params: lhs.split(',').filter(Boolean), ret }
}

/* ---------------- literal builders ---------------- */

function cppLiteral(type: string, v: unknown): string {
  if (type === 'ints') return `{${(v as number[]).join(',')}}`
  if (type === 'str') return JSON.stringify(v)
  if (type === 'bool') return v ? 'true' : 'false'
  return String(v)
}

function javaLiteral(type: string, v: unknown): string {
  if (type === 'ints') return `new int[]{${(v as number[]).join(',')}}`
  if (type === 'str') return JSON.stringify(v)
  if (type === 'bool') return v ? 'true' : 'false'
  return String(v)
}

/* ---------------- harness generation ---------------- */

function buildCpp(userCode: string, sig: Sig, cases: unknown[][]): string {
  const decls: string[] = []
  const calls: string[] = []

  cases.forEach((args, i) => {
    const names: string[] = []
    args.forEach((a, j) => {
      const t = sig.params[j]
      const name = `a${i}_${j}`
      names.push(name)
      const cppType = t === 'ints' ? 'vector<int>' : t === 'str' ? 'string' : t === 'bool' ? 'bool' : 'int'
      decls.push(`    ${cppType} ${name} = ${cppLiteral(t, a)};`)
    })
    calls.push(`    emit(solve(${names.join(', ')}));`)
  })

  return `#include <bits/stdc++.h>
using namespace std;

${userCode}

static void emit(int v){ cout << v << "\\n"; }
static void emit(bool v){ cout << (v ? "true" : "false") << "\\n"; }
static void emit(const string& v){ cout << "\\"" << v << "\\"" << "\\n"; }
static void emit(const vector<int>& v){
    cout << "[";
    for (size_t i = 0; i < v.size(); i++) { if (i) cout << ","; cout << v[i]; }
    cout << "]\\n";
}

int main(){
    ios::sync_with_stdio(false);
${decls.join('\n')}
${calls.join('\n')}
    return 0;
}
`
}

function buildJava(userCode: string, sig: Sig, cases: unknown[][]): string {
  const calls: string[] = []

  cases.forEach((args) => {
    const lits = args.map((a, j) => javaLiteral(sig.params[j], a))
    calls.push(`        emit(solve(${lits.join(', ')}));`)
  })

  return `import java.util.*;

public class Main {
${userCode
  .split('\n')
  .map((l) => (l.trim() ? '    ' + l : l))
  .join('\n')}

    static void emit(int v){ System.out.println(v); }
    static void emit(boolean v){ System.out.println(v ? "true" : "false"); }
    static void emit(String v){ System.out.println("\\"" + v + "\\""); }
    static void emit(int[] v){
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < v.length; i++) { if (i > 0) sb.append(","); sb.append(v[i]); }
        sb.append("]");
        System.out.println(sb.toString());
    }

    public static void main(String[] args){
${calls.join('\n')}
    }
}
`
}

export async function POST(request: Request) {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Not signed in' }, { status: 401 })

  const { problemId, language, code } = await request.json()

  const target = VERSIONS[language]
  if (!target) {
    return NextResponse.json(
      { error: `${language} is not executed on the server.` },
      { status: 400 }
    )
  }

  const { data: problem } = await supabase
    .from('coding_problems')
    .select('signature, coding_tests ( input_json, expect_json, is_hidden, ordinal )')
    .eq('problem_id', problemId)
    .single()

  if (!problem?.signature) {
    return NextResponse.json(
      { error: 'This problem has no type signature. Run migration 006.' },
      { status: 400 }
    )
  }

  const sig = parseSignature(problem.signature)
  if (!sig) return NextResponse.json({ error: 'Malformed signature.' }, { status: 500 })

  const tests = (problem.coding_tests ?? []).sort((a, b) => a.ordinal - b.ordinal)
  const cases = tests.map((t) => JSON.parse(t.input_json) as unknown[])

  const source =
    language === 'cpp' ? buildCpp(code, sig, cases) : buildJava(code, sig, cases)

  let payload: { run?: { stdout?: string; stderr?: string }; compile?: { stderr?: string } }
  try {
    const res = await fetch(PISTON, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        language: target.language,
        version: target.version,
        files: [{ name: target.filename, content: source }],
        compile_timeout: 10000,
        run_timeout: 5000,
      }),
    })
    if (!res.ok) {
      return NextResponse.json(
        { error: `Judge returned ${res.status}. It may be rate limited; wait a moment.` },
        { status: 502 }
      )
    }
    payload = await res.json()
  } catch {
    return NextResponse.json(
      { error: 'Could not reach the execution service. Python still runs offline.' },
      { status: 502 }
    )
  }

  const compileErr = payload.compile?.stderr?.trim()
  if (compileErr) {
    return NextResponse.json({ results: [], error: compileErr.slice(0, 800) })
  }

  const runErr = payload.run?.stderr?.trim()
  const lines = (payload.run?.stdout ?? '').split('\n').filter((l) => l.length > 0)

  if (lines.length === 0 && runErr) {
    return NextResponse.json({ results: [], error: runErr.slice(0, 800) })
  }

  const results = tests.map((t, i) => {
    const got = lines[i] ?? 'no output'
    return {
      ordinal: t.ordinal,
      hidden: t.is_hidden,
      passed: got === t.expect_json,
      got,
      want: t.expect_json,
    }
  })

  return NextResponse.json({ results, error: runErr ? runErr.slice(0, 400) : null })
}