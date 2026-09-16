// =============================================================================
// reset-teacher-password — generate a new password for a teacher.
//
// Used when a teacher loses their password or it may be compromised. An
// administrator calls this with the teacher's membership id; the function
// verifies the caller is an admin, generates a fresh password, updates the
// auth user, and returns the password exactly once for the admin to share.
//
//   supabase functions deploy reset-teacher-password
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '').trim()
    if (!token) throw new Error('Unauthorized')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    )

    const {
      data: { user },
      error: userErr,
    } = await supabase.auth.getUser(token)
    if (userErr || !user) throw new Error('Unauthorized')

    const body = await req.json()
    const { school_id, membership_id } = body
    if (!school_id || !membership_id) {
      throw new Error('school_id and membership_id are required')
    }

    // ---- caller must be an administrator of the school ----
    const { data: admin, error: adminErr } = await supabase
      .from('school_memberships')
      .select('id, role')
      .eq('profile_id', user.id)
      .eq('school_id', school_id)
      .eq('is_active', true)
      .maybeSingle()
    if (adminErr) throw new Error('Could not verify permissions')
    if (!admin || !['SUPER_ADMIN', 'ADMIN', 'PRINCIPAL'].includes(admin.role)) {
      throw new Error('Only administrators can reset teacher passwords')
    }

    // ---- the target membership must be a TEACHER in this school ----
    const { data: target, error: targetErr } = await supabase
      .from('school_memberships')
      .select('id, profile_id, role')
      .eq('id', membership_id)
      .eq('school_id', school_id)
      .maybeSingle()
    if (targetErr || !target) throw new Error('Teacher membership not found')
    if (target.role !== 'TEACHER') throw new Error('Only TEACHER memberships can be reset')

    const { data: profile, error: profileErr } = await supabase
      .from('profiles')
      .select('email, full_name')
      .eq('id', target.profile_id)
      .maybeSingle()
    if (profileErr || !profile) throw new Error('Teacher profile not found')

    const password = generatePassword()
    const { error: updateErr } = await supabase.auth.admin.updateUserById(
      target.profile_id,
      { password },
    )
    if (updateErr) throw new Error(updateErr.message)

    return json({
      email: profile.email ?? '',
      full_name: profile.full_name ?? '',
      password,
    })
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Unexpected error'
    return json({ error: message }, 400)
  }
})

function generatePassword(len = 12): string {
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  const lower = 'abcdefghijkmnpqrstuvwxyz'
  const digits = '23456789'
  const symbols = '@#$%&*!?'
  const all = upper + lower + digits + symbols
  const rand = (n: number) =>
    Math.floor((crypto.getRandomValues(new Uint32Array(1))[0] / 4294967296) * n)
  const arr = [
    upper[rand(upper.length)],
    lower[rand(lower.length)],
    digits[rand(digits.length)],
    symbols[rand(symbols.length)],
  ]
  for (let i = 4; i < len; i++) arr.push(all[rand(all.length)])
  for (let i = arr.length - 1; i > 0; i--) {
    const j = rand(i + 1)
    ;[arr[i], arr[j]] = [arr[j], arr[i]]
  }
  return arr.join('')
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}