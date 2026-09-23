# Student import OCR adapter

`process-student-import` is the server-side boundary between ReportWise and an OCR/document-understanding provider.

The Windows/macOS desktop **Scan PDF** flow now uses local OCR and saves extracted rows directly into the admin-protected review tables. It does **not** invoke this function or require an API key. See `app/docs/free-student-ocr.md` for prerequisites and testing.

For callers that explicitly invoke this server function, its default remains manual mode. Paid/custom processing is opt-in; changing this function's secrets does not change the local desktop scanner.

To explicitly use the built-in OpenAI adapter, configure:

```bash
supabase secrets set IMPORT_PROCESSING_MODE=openai
supabase secrets set OPENAI_API_KEY=your-openai-api-key
supabase secrets set OPENAI_OCR_MODEL=gpt-5.6-luna
supabase functions deploy process-student-import
```

The function sends the PDF to the OpenAI Responses API as an `input_file` with high visual detail and requests strict structured JSON output. Keep the API key only in Supabase secrets; never put it in the Flutter app.

Alternatively, configure a custom adapter endpoint:

```bash
supabase secrets set IMPORT_PROCESSING_MODE=custom
supabase secrets set OCR_PROVIDER_URL=https://your-ocr-adapter.example/process
supabase secrets set OCR_PROVIDER_TOKEN=your-provider-token
supabase functions deploy process-student-import
```

The function sends the provider a temporary signed PDF URL:

```json
{
  "batch_id": "uuid",
  "filename": "register.pdf",
  "document_url": "https://...signed-url..."
}
```

The provider must return:

```json
{
  "pages": [
    {
      "page_number": 1,
      "raw_text": "...",
      "rows": [
        {
          "raw_data": {"student_id": "A-001", "name": "..."},
          "normalized_data": {"full_name": "...", "class_id": "uuid"},
          "confidence": {"full_name": 0.98, "class_id": 0.94}
        }
      ]
    }
  ]
}
```

The worker maps common aliases such as `student_id`, `admission_no`, `matricule`, `first_name`, `last_name`, `sex`, `grade`, and `form`. Rows are marked `READY` only when they have a name, a class, and an average confidence of at least 90%; all other rows go to `NEEDS_REVIEW`.
