import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const ADMIN_ROLES = ['SUPER_ADMIN', 'ADMIN', 'PRINCIPAL']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  let batchId: string | undefined
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } },
  )

  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '').trim()
    if (!token) throw new Error('Unauthorized')
    const { data: { user }, error: userError } = await supabase.auth.getUser(token)
    if (userError || !user) throw new Error('Unauthorized')

    const body = await req.json()
    batchId = String(body.batch_id ?? '')
    if (!batchId) throw new Error('batch_id is required')

    const { data: batch, error: batchError } = await supabase
      .from('student_import_batches')
      .select('id, school_id, original_filename, storage_path, status')
      .eq('id', batchId)
      .single()
    if (batchError || !batch) throw new Error('Import batch not found')

    const { data: membership } = await supabase
      .from('school_memberships')
      .select('role')
      .eq('school_id', batch.school_id)
      .eq('profile_id', user.id)
      .eq('is_active', true)
      .maybeSingle()
    if (!membership || !ADMIN_ROLES.includes(membership.role)) {
      throw new Error('Only administrators can process student imports')
    }
    if (['PROCESSING', 'COMPLETED'].includes(batch.status)) {
      throw new Error(`This batch is already ${batch.status.toLowerCase()}`)
    }

    const processingMode = Deno.env.get('IMPORT_PROCESSING_MODE') ?? 'manual'
    const providerUrl = Deno.env.get('OCR_PROVIDER_URL')
    const openAiKey = Deno.env.get('OPENAI_API_KEY')

    await supabase.from('student_import_batches').update({
      status: 'PROCESSING', error_message: null, updated_at: new Date().toISOString(),
    }).eq('id', batchId)

    const { data: signed, error: signedError } = await supabase.storage
      .from('student-imports')
      .createSignedUrl(batch.storage_path, 3600)
    if (signedError || !signed?.signedUrl) throw new Error('Could not open the uploaded PDF')

    if (processingMode === 'manual') {
      await supabase.from('student_import_batches').update({
        status: 'NEEDS_REVIEW', page_count: null, row_count: 0,
        error_message: 'Free manual mode: add and approve rows from the review screen.',
        updated_at: new Date().toISOString(),
      }).eq('id', batchId)
      return json({ batch_id: batchId, page_count: 0, row_count: 0, status: 'NEEDS_REVIEW', mode: 'manual' })
    }

    if (processingMode === 'openai' && !openAiKey) throw new Error('OPENAI_API_KEY is not configured')
    if (processingMode === 'custom' && !providerUrl) throw new Error('OCR_PROVIDER_URL is not configured')
    if (!['openai', 'custom', 'manual'].includes(processingMode)) throw new Error(`Unknown import processing mode: ${processingMode}`)

    const extraction = processingMode === 'custom'
      ? await extractWithAdapter(providerUrl, batchId, batch.original_filename, signed.signedUrl)
      : await extractWithOpenAi(openAiKey!, batch.original_filename, signed.signedUrl)
    const pages = Array.isArray(extraction.pages) ? extraction.pages : []
    if (pages.length === 0) throw new Error('OCR provider returned no pages')

    await supabase.from('student_import_pages').delete().eq('batch_id', batchId)
    await supabase.from('student_import_rows').delete().eq('batch_id', batchId)

    let rowNumber = 0
    let rowCount = 0
    for (const page of pages) {
      const pageNumber = Number(page.page_number ?? pages.indexOf(page) + 1)
      const { data: pageRow, error: pageError } = await supabase
        .from('student_import_pages')
        .insert({
          batch_id: batchId,
          page_number: pageNumber,
          status: 'EXTRACTED',
          raw_text: stringOrNull(page.raw_text),
          extraction_payload: page,
        })
        .select('id')
        .single()
      if (pageError || !pageRow) throw new Error(`Could not save page ${pageNumber}`)

      const rows = Array.isArray(page.rows) ? page.rows : []
      for (const candidate of rows) {
        rowNumber += 1
        const raw = asObject(candidate.raw_data ?? candidate)
        const normalized = normalizeFields(asObject(candidate.normalized_data ?? candidate), raw)
        const confidence = asObject(candidate.confidence)
        const { error: rowError } = await supabase.from('student_import_rows').insert({
          batch_id: batchId,
          page_id: pageRow.id,
          row_number: rowNumber,
          raw_data: raw,
          normalized_data: normalized,
          confidence,
          status: isReady(normalized, confidence) ? 'READY' : 'NEEDS_REVIEW',
        })
        if (rowError) throw new Error(`Could not save extracted row ${rowNumber}`)
        rowCount += 1
      }
    }

    await supabase.from('student_import_batches').update({
      status: 'NEEDS_REVIEW', page_count: pages.length, row_count: rowCount,
      reviewed_count: 0, updated_at: new Date().toISOString(),
    }).eq('id', batchId)
    return json({ batch_id: batchId, page_count: pages.length, row_count: rowCount, status: 'NEEDS_REVIEW' })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error'
    if (batchId) await supabase.from('student_import_batches').update({ status: 'FAILED', error_message: message, updated_at: new Date().toISOString() }).eq('id', batchId)
    return json({ error: message }, 400)
  }
})

function providerHeaders(): Record<string, string> {
  const token = Deno.env.get('OCR_PROVIDER_TOKEN')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

async function extractWithAdapter(url: string, batchId: string, filename: string, documentUrl: string) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...providerHeaders() },
    body: JSON.stringify({ batch_id: batchId, filename, document_url: documentUrl }),
  })
  if (!response.ok) throw new Error(`OCR provider returned HTTP ${response.status}`)
  return await response.json()
}

async function extractWithOpenAi(apiKey: string, filename: string, documentUrl: string) {
  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: Deno.env.get('OPENAI_OCR_MODEL') ?? 'gpt-5.6-luna',
      store: false,
      input: [{
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: `Extract every student row from ${filename}. This may be a scanned register with varied columns, a printed table, or multiple sections. Preserve the page boundaries. Do not invent values. Return empty strings for missing fields. A school identifier and a matricule are separate: put admission numbers, student IDs, registration numbers, or similar values in school_identifier; use matricule only when the document explicitly labels it matricule. Dates must be YYYY-MM-DD when unambiguous. Gender must be M or F when clear. Confidence values must be between 0 and 1.`,
          },
          { type: 'input_file', file_url: documentUrl, detail: 'high' },
        ],
      }],
      text: {
        format: {
          type: 'json_schema',
          name: 'student_register_extraction',
          strict: true,
          schema: extractionSchema(),
        },
      },
    }),
  })
  if (!response.ok) throw new Error(`OpenAI OCR returned HTTP ${response.status}: ${await response.text()}`)
  const payload = await response.json()
  const outputText = payload.output_text ?? payload.output
    ?.flatMap((item: any) => item.content ?? [])
    ?.filter((item: any) => item.type === 'output_text')
    ?.map((item: any) => item.text)
    ?.join('')
  if (!outputText) throw new Error('OpenAI OCR returned no structured output')
  try {
    return JSON.parse(outputText)
  } catch {
    throw new Error('OpenAI OCR returned invalid structured output')
  }
}

function extractionSchema() {
  return {
    type: 'object',
    additionalProperties: false,
    required: ['pages'],
    properties: {
      pages: {
        type: 'array',
        items: {
          type: 'object',
          additionalProperties: false,
          required: ['page_number', 'raw_text', 'rows'],
          properties: {
            page_number: { type: 'integer' },
            raw_text: { type: 'string' },
            rows: {
              type: 'array',
              items: {
                type: 'object',
                additionalProperties: false,
                required: ['full_name', 'school_identifier', 'matricule', 'date_of_birth', 'gender', 'class_name', 'confidence'],
                properties: {
                  full_name: { type: 'string' },
                  school_identifier: { type: 'string' },
                  matricule: { type: 'string' },
                  date_of_birth: { type: 'string' },
                  gender: { type: 'string' },
                  class_name: { type: 'string' },
                  confidence: {
                    type: 'object',
                    additionalProperties: false,
                    required: ['full_name', 'school_identifier', 'matricule', 'date_of_birth', 'gender', 'class_name'],
                    properties: {
                      full_name: { type: 'number' },
                      school_identifier: { type: 'number' },
                      matricule: { type: 'number' },
                      date_of_birth: { type: 'number' },
                      gender: { type: 'number' },
                      class_name: { type: 'number' },
                    },
                  },
                },
              },
            },
          },
        },
      },
    },
  }
}

function asObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {}
}

function stringOrNull(value: unknown): string | null {
  const text = value == null ? '' : String(value).trim()
  return text || null
}

function normalizeFields(candidate: Record<string, unknown>, raw: Record<string, unknown>): Record<string, unknown> {
  const source = { ...raw, ...candidate }
  const pick = (...names: string[]) => names.map((name) => source[name]).find((value) => stringOrNull(value) != null)
  const fullName = pick('full_name', 'name', 'student_name') ?? [pick('first_name', 'firstname'), pick('last_name', 'lastname')].filter((value) => stringOrNull(value) != null).join(' ')
  return {
    ...candidate,
    full_name: stringOrNull(fullName),
    matricule: stringOrNull(pick('matricule', 'matricule_no')),
    external_student_id: stringOrNull(pick('external_student_id', 'school_identifier', 'student_id', 'admission_no', 'registration_no')),
    date_of_birth: stringOrNull(pick('date_of_birth', 'birth_date', 'dob')),
    gender: stringOrNull(pick('gender', 'sex')),
    class_name: stringOrNull(pick('class_name', 'class', 'grade', 'level', 'form')),
    class_id: stringOrNull(source.class_id),
  }
}

function isReady(data: Record<string, unknown>, confidence: Record<string, unknown>): boolean {
  const name = stringOrNull(data.full_name)
  const values = Object.values(confidence).filter((value): value is number => typeof value === 'number')
  const average = values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0
  return Boolean(name && data.class_id && average >= 0.9)
}

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}
