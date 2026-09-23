#ifndef RUNNER_LOCAL_STUDENT_OCR_H_
#define RUNNER_LOCAL_STUDENT_OCR_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <thread>

// All Flutter replies are delivered on the window thread; WinRT runs in an MTA.
class LocalStudentOcr {
 public:
  static constexpr UINT kMessage = WM_APP + 173;
  LocalStudentOcr(flutter::BinaryMessenger* messenger, HWND window);
  ~LocalStudentOcr();
  void Deliver();

 private:
  struct Event {
    int page = 0;
    int total = 0;
    flutter::EncodableList pages;
    std::string error;
  };
  void Push(Event event);
  void Extract(const std::string& path);
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result_;
  std::thread worker_;
  std::atomic<bool> stopping_{false};
  std::mutex mutex_;
  std::deque<Event> events_;
};
#endif
