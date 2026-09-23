# Free automatic student register scanning

The desktop **Students → Scan PDF → Scan and review** flow performs OCR on the school's computer. There is no OCR API subscription, service key, local server, or Python/Tesseract installation. The original PDF and extracted suggestions are then saved to the existing Supabase import tables. Saving/importing still requires a connection to Supabase and uses its normal storage/database quota.

## Platforms

- **Windows 10/11:** uses Windows.Media.Ocr and Windows.Data.Pdf through a native Flutter channel. An English or French OCR language pack must be installed. The school's Windows preferred language is used where available; English/French are fallback choices. Missing packs produce an actionable error. See Windows Settings → Time & language → Language options; an administrator may need to install the language's OCR capability on managed PCs. A one-time language download may require internet.
- **macOS 11+:** uses Vision and Core Graphics, built into the OS. This supports testing on the developer's Mac.
- Browser, Android, iOS and Linux local scanning are not implemented. The UI says so instead of claiming that empty results are manual mode.

A full rebuild/restart is necessary after native changes; hot reload cannot register a native channel. Windows releases must be built on Windows with the Flutter desktop toolchain and Windows SDK (C++/WinRT headers). The existing Windows build workflow compiles this path; no new package dependency is needed.

## Behavior and limits

1. Select an unlocked PDF, up to 50 MB and 50 pages. Split larger registers.
2. Render and recognize each page in a background native worker. Page progress stays visible.
3. Use word positions to map table columns with English/French aliases: full name, first/last names, matricule, student ID/admission number, date of birth, class/level, sex/gender. Each page can use a different layout; repeated headings are supported. Wrapped identifiers are joined. One-character OCR errors in longer headings can be tolerated.
4. Save every candidate as `NEEDS_REVIEW`. Unknown headings/empty pages produce visible warnings, not invented students. Raw recognized text remains accessible. The parser does not yet handle arbitrary prose layouts, complex merged cells, multi-line heading bands, or continuation pages without headings.
5. Review, correct or exclude rows. Use **View original PDF** to compare against the scan. Exact, unique class-name matches preselect existing classes; unmatched classes require selection. Ambiguous dates remain visible in the editor and block approval until corrected or explicitly cleared. **Approve** and **Approve All** accept structurally valid rows; they do not guarantee OCR accuracy. Invalid rows remain for review. No names, identifiers or dates are guessed. Existing school IDs are suggested as matricules; missing IDs remain null for the existing generation trigger at import.
6. Only explicitly approved rows are committed through the existing import RPC.

Windows OCR does not expose confidence scores, so the UI reports `unknown` rather than fabricating a percentage. Mac scores describe text recognition, not proof that the table mapping is correct. Handwritten, faint, skewed or densely ruled registers may need substantial correction. This is an initial table-register parser, not a guarantee for every handwritten register or layout.

The previously added migrations 0028–0030, private `student-imports` bucket, admin policies and commit RPC must already be applied. Migration 0031 adds serialized, retry-safe batch commits. Migration 0032 adds the recovery journal. Neither migration has been deployed automatically by this task. No Edge Function deployment is needed for local OCR.

## Verification

From `app/`:

```sh
flutter test --no-pub test/student_register_parser_test.dart test/local_student_ocr_test.dart
flutter build macos --debug --no-pub --dart-define-from-file=.env
# On Windows:
flutter build windows --release --dart-define-from-file=.env
```

On a Mac, independently exercise the actual OCR engine with the synthetic three-page register (from the repository root):

```sh
swiftc app/macos/Runner/LocalStudentOCR.swift app/tool/ocr_smoke/main.swift -o /tmp/reportwise-ocr-smoke
/tmp/reportwise-ocr-smoke output/pdf/sample_school_student_register_scanned.pdf /tmp/reportwise-ocr-sample.json
dart app/tool/verify_student_ocr.dart /tmp/reportwise-ocr-sample.json
```

The smoke check expects 30 candidate students and checks their expected names. The development sample produced 10 candidates on each page with all 30 names correct, but two matricules were misrecognized (one incomplete, one with similar-looking non-Latin letters). Inspect values as well as counts: OCR can misread identifiers even when every row is found. This is a Mac test result, not a Windows accuracy measurement.

Before distributing a Windows build, run the same PDF in the Windows app, check page progress and 30 rows, verify missing IDs remain blank, verify English/French headers, reject a row, and confirm only approved rows are imported in a test school. Also test an empty/password-protected PDF and a Windows machine without an OCR language pack. Native Windows runtime behavior cannot be verified on a Mac.

References: [Microsoft OCR](https://learn.microsoft.com/en-us/uwp/api/windows.media.ocr.ocrengine), [Microsoft PDF rendering](https://learn.microsoft.com/en-us/uwp/api/windows.data.pdf.pdfpage.rendertostreamasync), [Apple text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest).
