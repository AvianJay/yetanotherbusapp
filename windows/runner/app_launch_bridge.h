#ifndef RUNNER_APP_LAUNCH_BRIDGE_H_
#define RUNNER_APP_LAUNCH_BRIDGE_H_

#include <flutter/encodable_value.h>

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include <windows.h>

namespace flutter {
class BinaryMessenger;
template <typename T>
class MethodChannel;
}  // namespace flutter

class AppLaunchBridge {
 public:
  AppLaunchBridge();
  ~AppLaunchBridge();

  AppLaunchBridge(const AppLaunchBridge&) = delete;
  AppLaunchBridge& operator=(const AppLaunchBridge&) = delete;

  void Configure(flutter::BinaryMessenger* messenger);
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

  static std::optional<std::string> ExtractAuthCallbackArgument(
      const std::vector<std::string>& arguments);
  static bool ForwardAuthCallbackToRunningInstances(const std::string& uri);
  static void MarkWindowAsReceiver(HWND hwnd);
  static void UnmarkWindowAsReceiver(HWND hwnd);

 private:
  void DispatchOrQueue(flutter::EncodableMap payload);

  static std::optional<flutter::EncodableMap> PayloadFromUri(
      const std::string& uri);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::optional<flutter::EncodableMap> pending_action_;
  bool launch_listener_ready_ = false;
};

#endif  // RUNNER_APP_LAUNCH_BRIDGE_H_
