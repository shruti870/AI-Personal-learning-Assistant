import { createClient } from '@supabase/supabase-js'

/**
 * Service-role client: bypasses RLS and column grants. Server code only
 * (route handlers, server components), and only for the answer key, which
 * students cannot read since migration 009. Never import from a 'use client'
 * file: the key would ship to the browser.
 */
export function createAdminClient() {
  if (typeof window !== 'undefined') {
    throw new Error('createAdminClient must not run in the browser.')
  }
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!key) {
    throw new Error(
      'SUPABASE_SERVICE_ROLE_KEY is not set. Add it to web/.env.local (Supabase -> Project Settings -> API).'
    )
  }
  return createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}
