#include "flutter_window.h"

#include <windows.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Bidirectional power MethodChannel:
  //  - native -> Dart: InvokeMethod("suspend"/"resume") on WM_POWERBROADCAST.
  //  - Dart -> native: setSleepPrevention(bool) via SetThreadExecutionState.
  power_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "hyb_farm/power",
      &flutter::StandardMethodCodec::GetInstance());
  power_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setSleepPrevention") {
          result->NotImplemented();
          return;
        }
        const auto* args = std::get_if<bool>(call.arguments());
        const bool enabled = args != nullptr && *args;
        const EXECUTION_STATE flags = enabled
            ? static_cast<EXECUTION_STATE>(ES_CONTINUOUS | ES_SYSTEM_REQUIRED)
            : ES_CONTINUOUS;
        // Block idle sleep only, not screen off (avoid ES_DISPLAY_REQUIRED).
        const EXECUTION_STATE previous = SetThreadExecutionState(flags);
        if (previous == 0) {
          const DWORD error = GetLastError();
          result->Error("set_sleep_prevention_failed",
                        "SetThreadExecutionState failed",
                        flutter::EncodableValue(static_cast<int>(error)));
          return;
        }
        result->Success(flutter::EncodableValue(true));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_POWERBROADCAST:
      // System power event: suspend is best-effort logging only (may not reach
      // Dart before suspending); resume triggers the Dart-side recovery flow.
      if (power_channel_) {
        if (wparam == PBT_APMSUSPEND) {
          power_channel_->InvokeMethod(
              "suspend", std::make_unique<flutter::EncodableValue>());
          return TRUE;
        }
        if (wparam == PBT_APMRESUMEAUTOMATIC) {
          power_channel_->InvokeMethod(
              "resume",
              std::make_unique<flutter::EncodableValue>(
                  std::string("automatic")));
          return TRUE;
        }
        if (wparam == PBT_APMRESUMESUSPEND) {
          power_channel_->InvokeMethod(
              "resume",
              std::make_unique<flutter::EncodableValue>(std::string("suspend")));
          return TRUE;
        }
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
