#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <vector>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  
  // 1. Native Single-Instance Mutex Check.
  // Performs a zero-latency check BEFORE creating any window or spinning up the Dart VM.
  // This terminates duplicate processes instantly with 100% reliable zero window-flashing or "flashbangs".
  const wchar_t* mutexName = L"SnapDns_SingleInstance_Mutex_v2";
  HANDLE existingMutex = ::OpenMutexW(SYNCHRONIZE, FALSE, mutexName);

  if (existingMutex != nullptr) {
    ::CloseHandle(existingMutex); // Release temporary handle

    // Find the original window (checking both title variants)
    const wchar_t* windowName1 = L"SnapDNS";
    const wchar_t* windowName2 = L"SnapDNS ";

    HWND hwnd = ::FindWindowW(nullptr, windowName1);
    if (hwnd == nullptr) hwnd = ::FindWindowW(nullptr, windowName2);

    if (hwnd != nullptr) {
      // FIX: Call both SW_SHOW (5) to unhide the window from the tray,
      // and SW_RESTORE (9) to restore its original size if it was minimized to the taskbar!
      ::ShowWindow(hwnd, SW_SHOW);    // 5 = Unhides from Tray (Makes visible)
      ::ShowWindow(hwnd, SW_RESTORE); // 9 = Restores size if minimized
      ::SetForegroundWindow(hwnd);
    }

    return EXIT_SUCCESS; // Terminate this duplicate process immediately
  }

  // Create the Mutex for the primary instance (held until process exits)
  HANDLE mutex = ::CreateMutexW(nullptr, FALSE, mutexName);

  // Initialize COM, so that it is available for use in the library and/or plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"SnapDNS", origin, size)) {
    if (mutex != nullptr) ::CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (mutex != nullptr) ::CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}