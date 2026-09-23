#include "local_student_ocr.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Data.Pdf.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Globalization.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <algorithm>
#include <stdexcept>

using flutter::EncodableValue;
using flutter::EncodableMap;
using flutter::EncodableList;
using namespace winrt::Windows;

LocalStudentOcr::LocalStudentOcr(flutter::BinaryMessenger* messenger, HWND window)
    : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "reportwise/local_student_ocr", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "extractPdf") { result->NotImplemented(); return; }
    if (result_) { result->Error("OCR_BUSY", "Another PDF is being scanned."); return; }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    if (!args) { result->Error("INVALID_PDF", "Choose a PDF first."); return; }
    auto entry = args->find(EncodableValue("path"));
    if (entry == args->end() || !std::holds_alternative<std::string>(entry->second)) {
      result->Error("INVALID_PDF", "Choose a PDF first."); return;
    }
    if (worker_.joinable()) worker_.join();
    result_ = std::move(result);
    const auto path = std::get<std::string>(entry->second);
    worker_ = std::thread([this, path]() { Extract(path); });
  });
}

LocalStudentOcr::~LocalStudentOcr() {
  stopping_ = true;
  if (worker_.joinable()) worker_.join();
  channel_->SetMethodCallHandler(nullptr);
}

void LocalStudentOcr::Push(Event event) {
  if (stopping_) return;
  { std::lock_guard<std::mutex> lock(mutex_); events_.push_back(std::move(event)); }
  PostMessage(window_, kMessage, 0, 0);
}

void LocalStudentOcr::Deliver() {
  std::deque<Event> events;
  { std::lock_guard<std::mutex> lock(mutex_); events.swap(events_); }
  for (auto& event : events) {
    if (event.page > 0) {
      channel_->InvokeMethod("progress", std::make_unique<EncodableValue>(EncodableMap{
          {EncodableValue("page"), EncodableValue(event.page)},
          {EncodableValue("total"), EncodableValue(event.total)}}));
    } else if (result_) {
      if (event.error.empty()) result_->Success(EncodableValue(std::move(event.pages)));
      else result_->Error("OCR_FAILED", event.error);
      result_.reset();
    }
  }
}

void LocalStudentOcr::Extract(const std::string& path) {
  bool apartment_initialized = false;
  Event complete;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    apartment_initialized = true;
    // Prefer the school's Windows language, restricted to English/French.
    auto engine = Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
    if (engine) {
      const auto tag = winrt::to_string(engine.RecognizerLanguage().LanguageTag());
      if (tag.rfind("en", 0) != 0 && tag.rfind("fr", 0) != 0) engine = nullptr;
    }
    if (!engine) engine = Media::Ocr::OcrEngine::TryCreateFromLanguage(Globalization::Language(L"en-US"));
    if (!engine) engine = Media::Ocr::OcrEngine::TryCreateFromLanguage(Globalization::Language(L"fr-FR"));
    if (!engine) throw std::runtime_error(
        "Install English or French OCR in Windows Settings > Time & language > Language options, then retry.");
    const auto file = Storage::StorageFile::GetFileFromPathAsync(winrt::to_hstring(path)).get();
    const auto document = Data::Pdf::PdfDocument::LoadFromFileAsync(file).get();
    const auto count = document.PageCount();
    if (count == 0 || count > 50) throw std::runtime_error("Please split the register into PDFs of 1-50 pages.");
    for (uint32_t i = 0; i < count && !stopping_; ++i) {
      Event progress;
      progress.page = static_cast<int>(i + 1); progress.total = static_cast<int>(count);
      Push(std::move(progress));
      auto page = document.GetPage(i);
      const auto size = page.Size();
      if (size.Width <= 0 || size.Height <= 0) throw std::runtime_error("The PDF contains a page with invalid dimensions.");
      const auto limit = std::min(3200.0, static_cast<double>(Media::Ocr::OcrEngine::MaxImageDimension()));
      const auto scale = std::min(3.5, limit / std::max(size.Width, size.Height));
      Data::Pdf::PdfPageRenderOptions options;
      options.DestinationWidth(std::max(1u, static_cast<uint32_t>(size.Width * scale)));
      options.DestinationHeight(std::max(1u, static_cast<uint32_t>(size.Height * scale)));
      Storage::Streams::InMemoryRandomAccessStream stream;
      page.RenderToStreamAsync(stream, options).get();
      stream.Seek(0);
      const auto decoder = Graphics::Imaging::BitmapDecoder::CreateAsync(stream).get();
      auto bitmap = decoder.GetSoftwareBitmapAsync(Graphics::Imaging::BitmapPixelFormat::Bgra8,
          Graphics::Imaging::BitmapAlphaMode::Premultiplied).get();
      const auto recognized = engine.RecognizeAsync(bitmap).get();
      EncodableList words;
      for (const auto& line : recognized.Lines()) {
        for (const auto& word : line.Words()) {
          const auto box = word.BoundingRect();
          words.emplace_back(EncodableMap{
              {EncodableValue("text"), EncodableValue(winrt::to_string(word.Text()))},
              {EncodableValue("x"), EncodableValue(static_cast<double>(box.X) / bitmap.PixelWidth())},
              {EncodableValue("y"), EncodableValue(static_cast<double>(box.Y) / bitmap.PixelHeight())},
              {EncodableValue("width"), EncodableValue(static_cast<double>(box.Width) / bitmap.PixelWidth())},
              {EncodableValue("height"), EncodableValue(static_cast<double>(box.Height) / bitmap.PixelHeight())}
              // Windows OCR supplies no confidence score; do not invent one.
          });
        }
      }
      complete.pages.emplace_back(EncodableMap{
          {EncodableValue("page_number"), EncodableValue(static_cast<int>(i + 1))},
          {EncodableValue("raw_text"), EncodableValue(winrt::to_string(recognized.Text()))},
          {EncodableValue("words"), EncodableValue(std::move(words))}});
      bitmap.Close(); stream.Close(); page.Close();
    }
  } catch (const winrt::hresult_error& error) {
    complete.error = "Windows could not scan this PDF: " + winrt::to_string(error.message());
  } catch (const std::exception& error) {
    complete.error = error.what();
  } catch (...) {
    complete.error = "Windows could not scan this PDF. Try an unlocked, upright PDF.";
  }
  if (apartment_initialized) winrt::uninit_apartment();
  Push(std::move(complete));
}
