// =============================================================================
// create-teacher — scalable teacher onboarding.
//
// A school administrator creates a teacher (name, email, phone, staff id). This
// function:
//   1. verifies the caller is an administrator of the given school,
//   2. if an account already exists for that email, adds the TEACHER membership
//      and reports no password was generated,
//   3. otherwise creates the auth user with a generated password (email
//      pre-confirmed, so no verification link is needed) and adds the TEACHER
//      membership,
//   4. returns the generated password exactly once so the admin can share it
//      (WhatsApp / email / SMS) — the teacher can also use the in-app
//      "Forgot password" flow to reset it.
//
// Requires the SUPABASE_SERVICE_ROLE_KEY secret:
//   supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<service_role key>
//   supabase functions deploy create-teacher
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
    const { school_id, full_name, email, phone, staff_id } = body
    if (!school_id || !email || !full_name) {
      throw new Error('school_id, full_name and email are required')
    }
    const cleanEmail = String(email).trim().toLowerCase()
    const cleanName = String(full_name).trim()

    // ---- caller must be an administrator of the school ----
    const { data: membership, error: memErr } = await supabase
      .from('school_memberships')
      .select('id, role')
      .eq('profile_id', user.id)
      .eq('school_id', school_id)
      .eq('is_active', true)
      .maybeSingle()
    if (memErr) throw new Error('Could not verify permissions')
    if (!membership || !['SUPER_ADMIN', 'ADMIN', 'PRINCIPAL'].includes(membership.role)) {
      throw new Error('Only administrators can create teachers')
    }

    // ---- existing account? ----
    const { data: existing } = await supabase
      .from('profiles')
      .select('id')
      .ilike('email', cleanEmail)
      .maybeSingle()

    if (existing) {
      const { data: already } = await supabase
        .from('school_memberships')
        .select('id')
        .eq('profile_id', existing.id)
        .eq('school_id', school_id)
        .maybeSingle()
      if (already) {
        return json({ created: false, alreadyMember: true, email: cleanEmail })
      }
      const { data: ins, error: insErr } = await supabase
        .from('school_memberships')
        .insert({ school_id, profile_id: existing.id, role: 'TEACHER', staff_id: staff_id ?? null })
        .select('id')
        .single()
      if (insErr) throw new Error('Could not add the teacher to this school')
      return json({
        created: false,
        alreadyMember: false,
        teacher_membership_id: ins.id,
        email: cleanEmail,
      })
    }

    // ---- create the account with a generated password ----
    const password = generatePassword()
    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: cleanEmail,
      password,
      email_confirm: true,
      user_metadata: { full_name: cleanName },
    })
    if (createErr) throw new Error(createErr.message)

    // The on_auth_user_created trigger creates the profile row.
    const { data: ins, error: insErr } = await supabase
      .from('school_memberships')
      .insert({ school_id, profile_id: created.user.id, role: 'TEACHER', staff_id: staff_id ?? null })
      .select('id')
      .single()
    if (insErr) throw new Error('Could not create the teacher membership')

    if (phone) {
      await supabase.from('profiles').update({ phone: String(phone).trim() }).eq('id', created.user.id)
    }

    return json({
      created: true,
      teacher_membership_id: ins.id,
      email: cleanEmail,
      full_name: cleanName,
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