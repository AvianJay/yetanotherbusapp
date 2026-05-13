#include "app_launch_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cctype>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr wchar_t kAppLaunchReceiverProperty[] =
    L"YABus.AppLaunchReceiverWindow";
constexpr ULONG_PTR kAppLaunchCopyDataId = 0x5941425553;

std::string AsciiLower(std::string_view value) {
  std::string lowered(value);
  std::transform(
      lowered.begin(), lowered.end(), lowered.begin(),
      [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
      });
  return lowered;
}

int HexValue(char character) {
  if (character >= '0' && character <= '9') {
    return character - '0';
  }
  if (character >= 'a' && character <= 'f') {
    return character - 'a' + 10;
  }
  if (character >= 'A' && character <= 'F') {
    return character - 'A' + 10;
  }
  return -1;
}

std::string PercentDecode(std::string_view value) {
  std::string decoded;
  decoded.reserve(value.size());
  for (size_t index = 0; index < value.size(); ++index) {
    const char character = value[index];
    if (character == '%' && index + 2 < value.size()) {
      const int high = HexValue(value[index + 1]);
      const int low = HexValue(value[index + 2]);
      if (high >= 0 && low >= 0) {
        decoded.push_back(static_cast<char>((high << 4) | low));
        index += 2;
        continue;
      }
    }
    if (character == '+') {
      decoded.push_back(' ');
      continue;
    }
    decoded.push_back(character);
  }
  return decoded;
}

void AddParametersFromComponent(flutter::EncodableMap& payload,
                                std::string_view component) {
  size_t start = 0;
  while (start <= component.size()) {
    const size_t separator = component.find('&', start);
    const size_t end =
        separator == std::string_view::npos ? component.size() : separator;
    const std::string_view pair = component.substr(start, end - start);
    if (!pair.empty()) {
      const size_t equals = pair.find('=');
      const std::string key = PercentDecode(
          equals == std::string_view::npos ? pair : pair.substr(0, equals));
      if (!key.empty()) {
        const std::string value = equals == std::string_view::npos
            ? std::string()
            : PercentDecode(pair.substr(equals + 1));
        payload[flutter::EncodableValue(key)] =
            flutter::EncodableValue(value);
      }
    }
    if (separator == std::string_view::npos) {
      break;
    }
    start = separator + 1;
  }
}

struct WindowCollector {
  std::vector<HWND> windows;
};

BOOL CALLBACK CollectReceiverWindows(HWND hwnd, LPARAM lparam) {
  if (GetPropW(hwnd, kAppLaunchReceiverProperty) == nullptr) {
    return TRUE;
  }
  auto* collector = reinterpret_cast<WindowCollector*>(lparam);
  collector->windows.push_back(hwnd);
  return TRUE;
}

void ActivateReceiverWindow(HWND hwnd) {
  if (!::IsWindow(hwnd)) {
    return;
  }
  if (::IsIconic(hwnd)) {
    ::ShowWindowAsync(hwnd, SW_RESTORE);
  } else {
    ::ShowWindowAsync(hwnd, SW_SHOWNORMAL);
  }
  ::BringWindowToTop(hwnd);
  ::SetForegroundWindow(hwnd);
}

}  // namespace

AppLaunchBridge::AppLaunchBridge() = default;

AppLaunchBridge::~AppLaunchBridge() = default;

void AppLaunchBridge::Configure(flutter::BinaryMessenger* messenger) {
  if (channel_ || messenger == nullptr) {
    return;
  }

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "tw.avianjay.taiwanbus.flutter/app_launch",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](
          const flutter::MethodCall<flutter::EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
              result) {
        if (call.method_name() == "setLaunchListenerReady") {
          launch_listener_ready_ = true;
          result->Success();
          return;
        }

        if (call.method_name() == "takeInitialLaunchAction") {
          if (pending_action_.has_value()) {
            result->Success(flutter::EncodableValue(*pending_action_));
            pending_action_.reset();
          } else {
            result->Success();
          }
          return;
        }

        result->NotImplemented();
      });
}

bool AppLaunchBridge::HandleWindowMessage(UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam) {
  if (message != WM_COPYDATA) {
    return false;
  }

  const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (copy_data == nullptr || copy_data->dwData != kAppLaunchCopyDataId ||
      copy_data->lpData == nullptr || copy_data->cbData == 0) {
    return false;
  }

  const auto* raw_uri = static_cast<const char*>(copy_data->lpData);
  const size_t uri_length =
      copy_data->cbData > 0 ? copy_data->cbData - 1 : copy_data->cbData;
  const std::string uri(raw_uri, raw_uri + uri_length);

  const auto payload = PayloadFromUri(uri);
  if (!payload.has_value()) {
    return false;
  }

  DispatchOrQueue(*payload);
  return true;
}

std::optional<std::string> AppLaunchBridge::ExtractAuthCallbackArgument(
    const std::vector<std::string>& arguments) {
  for (const auto& argument : arguments) {
    if (PayloadFromUri(argument).has_value()) {
      return argument;
    }
  }
  return std::nullopt;
}

bool AppLaunchBridge::ForwardAuthCallbackToRunningInstances(
    const std::string& uri) {
  if (!PayloadFromUri(uri).has_value()) {
    return false;
  }

  WindowCollector collector;
  ::EnumWindows(CollectReceiverWindows, reinterpret_cast<LPARAM>(&collector));
  if (collector.windows.empty()) {
    return false;
  }

  COPYDATASTRUCT copy_data{};
  copy_data.dwData = kAppLaunchCopyDataId;
  copy_data.cbData = static_cast<DWORD>(uri.size() + 1);
  copy_data.lpData = const_cast<char*>(uri.c_str());

  HWND activated_window = nullptr;
  bool delivered = false;
  for (const auto hwnd : collector.windows) {
    DWORD_PTR send_result = 0;
    const auto sent = ::SendMessageTimeoutW(
        hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&copy_data),
        SMTO_ABORTIFHUNG, 3000, &send_result);
    if (sent != 0) {
      delivered = true;
      if (activated_window == nullptr) {
        activated_window = hwnd;
      }
    }
  }

  if (activated_window != nullptr) {
    ActivateReceiverWindow(activated_window);
  }

  return delivered;
}

void AppLaunchBridge::MarkWindowAsReceiver(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  ::SetPropW(hwnd, kAppLaunchReceiverProperty, reinterpret_cast<HANDLE>(1));
}

void AppLaunchBridge::UnmarkWindowAsReceiver(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  ::RemovePropW(hwnd, kAppLaunchReceiverProperty);
}

void AppLaunchBridge::DispatchOrQueue(flutter::EncodableMap payload) {
  if (launch_listener_ready_ && channel_) {
    channel_->InvokeMethod(
        "onLaunchAction",
        std::make_unique<flutter::EncodableValue>(payload));
    return;
  }
  pending_action_ = std::move(payload);
}

std::optional<flutter::EncodableMap> AppLaunchBridge::PayloadFromUri(
    const std::string& uri) {
  const size_t scheme_separator = uri.find("://");
  if (scheme_separator == std::string::npos) {
    return std::nullopt;
  }

  if (AsciiLower(std::string_view(uri).substr(0, scheme_separator)) !=
      "yabus") {
    return std::nullopt;
  }

  const size_t authority_start = scheme_separator + 3;
  size_t host_end = uri.find_first_of("/?#", authority_start);
  if (host_end == std::string::npos) {
    host_end = uri.size();
  }

  if (AsciiLower(std::string_view(uri).substr(
          authority_start, host_end - authority_start)) != "auth-callback") {
    return std::nullopt;
  }

  flutter::EncodableMap payload;
  payload[flutter::EncodableValue("target")] =
      flutter::EncodableValue("auth_callback");

  const size_t query_start = uri.find('?', authority_start);
  const size_t fragment_start = uri.find('#', authority_start);
  if (query_start != std::string::npos) {
    const size_t query_end =
        fragment_start == std::string::npos ? uri.size() : fragment_start;
    AddParametersFromComponent(
        payload, std::string_view(uri).substr(query_start + 1,
                                              query_end - query_start - 1));
  }

  if (fragment_start != std::string::npos && fragment_start + 1 < uri.size()) {
    AddParametersFromComponent(
        payload, std::string_view(uri).substr(fragment_start + 1));
  }

  const auto has_token =
      payload.find(flutter::EncodableValue("token")) != payload.end();
  const auto has_error =
      payload.find(flutter::EncodableValue("error")) != payload.end();
  if (!has_token && !has_error) {
    return std::nullopt;
  }

  return payload;
}
