/**
 * Without generated database types, supabase-js types a to-one embed
 * (e.g. `concepts:concept_id ( name )`) as an array, although PostgREST
 * returns a single object at runtime. Accept either shape.
 */
export type Embed<T> = T | T[] | null | undefined

export function one<T>(v: Embed<T>): T | null {
  return Array.isArray(v) ? (v[0] ?? null) : (v ?? null)
}
