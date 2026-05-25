#pragma comment(lib, "windowsapp")

#include "include/just_audio_windows/just_audio_windows_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <map>
#include <memory>
#include <sstream>

#include "player.hpp"

#include <queue>
#include <mutex>
#include <tuple>
#include <thread>
#include <chrono>

// Globals used to marshal encoded messages to the platform thread.
static UINT g_just_audio_notify_message = 0;
static HWND g_just_audio_hwnd = nullptr;
static std::mutex g_just_audio_queue_mutex;
static std::queue<std::tuple<const flutter::BinaryMessenger*, std::string, std::unique_ptr<std::vector<uint8_t>>>> g_just_audio_message_queue;

// Posts an already-encoded envelope to be sent on the platform thread.
void JustAudio_PostEncodedEnvelopeToPlatformThread(const flutter::BinaryMessenger* messenger,
                                                   const std::string& channel,
                                                   std::unique_ptr<std::vector<uint8_t>> payload) {
  if (g_just_audio_notify_message == 0 || g_just_audio_hwnd == nullptr) {
    // If we don't have a valid HWND/message registered yet, try to send directly.
    if (messenger && payload) {
      std::cerr << "[just_audio_windows] Sending envelope directly for channel: " << channel << std::endl;
      messenger->Send(channel, payload->data(), payload->size());
    }
    return;
  }

  {
    std::lock_guard<std::mutex> lock(g_just_audio_queue_mutex);
    g_just_audio_message_queue.emplace(messenger, channel, std::move(payload));
    std::cerr << "[just_audio_windows] Enqueued encoded envelope for channel: " << channel << " queue_size=" << g_just_audio_message_queue.size() << std::endl;
  }

  // Notify the platform thread to process the queue. Ignore failure.
  PostMessage(g_just_audio_hwnd, g_just_audio_notify_message, 0, 0);
}

using flutter::EncodableMap;
using flutter::EncodableValue;

namespace {

// static std::unordered_map<std::string, AudioPlayer> players;
std::vector<std::unique_ptr<AudioPlayer>> players_;

class JustAudioWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  JustAudioWindowsPlugin();

  virtual ~JustAudioWindowsPlugin();

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      flutter::BinaryMessenger* messenger);
  // Loops through cameras and returns camera
  // with matching camera_id or nullptr.
  AudioPlayer* GetPlayerByPlayerId(std::string id);

  // Disposes camera by camera id.
  void DisposePlayerByPlayerId(std::string id);
};

// static
void JustAudioWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.ryanheise.just_audio.methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<JustAudioWindowsPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get(), messenger_pointer = registrar->messenger()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result), std::move(messenger_pointer));
      });

  // Register a top-level window proc delegate to process queued messages
  // posted by native threads. We also capture the HWND to PostMessage into.
  // Use a unique registered message so we don't collide with others.
  g_just_audio_notify_message = RegisterWindowMessageW(L"JUST_AUDIO_WINDOWS_NOTIFY_PLATFORM_THREAD");
  if (registrar->GetView()) {
    g_just_audio_hwnd = registrar->GetView()->GetNativeWindow();
  }

  // Register a delegate that processes the queued messages on the platform thread
  registrar->RegisterTopLevelWindowProcDelegate([](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
    // If it's our notify message, flush the queue.
    if (g_just_audio_notify_message != 0 && message == g_just_audio_notify_message) {
      std::queue<std::tuple<const flutter::BinaryMessenger*, std::string, std::unique_ptr<std::vector<uint8_t>>>> local_q;
      {
        std::lock_guard<std::mutex> lock(g_just_audio_queue_mutex);
        std::swap(local_q, g_just_audio_message_queue);
      }

      while (!local_q.empty()) {
        auto& item = local_q.front();
        const flutter::BinaryMessenger* messenger = std::get<0>(item);
        const std::string& channel = std::get<1>(item);
        std::unique_ptr<std::vector<uint8_t>>& payload = std::get<2>(item);
        if (messenger && payload) {
          messenger->Send(channel, payload->data(), payload->size());
        }
        local_q.pop();
      }

      return std::optional<LRESULT>(0);
    }
    return std::optional<LRESULT>();
  });

  registrar->AddPlugin(std::move(plugin));
}

JustAudioWindowsPlugin::JustAudioWindowsPlugin() {}

JustAudioWindowsPlugin::~JustAudioWindowsPlugin() {}

void JustAudioWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
    flutter::BinaryMessenger* messenger) {
  const auto* args =std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (args) {
    if (method_call.method_name().compare("init") == 0) {
      const auto* id = std::get_if<std::string>(ValueOrNull(*args, "id"));
      if (!id) {
        return result->Error("argument_error", "id argument missing");
      }
      // Log with timestamp
      auto now = std::chrono::system_clock::now();
      auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
      std::cerr << "[just_audio_windows] init player id=" << *id << " ts=" << ms << std::endl;
      auto player = std::make_unique<AudioPlayer>(*id, messenger);
      players_.push_back(std::move(player));
      // Dump current registered player ids for diagnostics
      std::stringstream ss;
      ss << "[just_audio_windows] registered players after init (ts=" << ms << "): ";
      for (auto &p : players_) {
        ss << p->id << " ";
      }
      std::cerr << ss.str() << std::endl;
      result->Success();
    } else if (method_call.method_name().compare("disposePlayer") == 0) {
      const auto* id = std::get_if<std::string>(ValueOrNull(*args, "id"));
      if (!id) {
        return result->Error("argument_error", "id argument missing");
      }
      auto now = std::chrono::system_clock::now();
      auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
      std::cerr << "[just_audio_windows] disposePlayer id=" << *id << " ts=" << ms << std::endl;
      // Dump players before dispose
      {
        std::stringstream ss;
        ss << "[just_audio_windows] registered players before dispose (ts=" << ms << "): ";
        for (auto &p : players_) {
          ss << p->id << " ";
        }
        std::cerr << ss.str() << std::endl;
      }
      DisposePlayerByPlayerId(*id);
      // Dump players after dispose
      {
        std::stringstream ss;
        ss << "[just_audio_windows] registered players after dispose (ts=" << ms << "): ";
        for (auto &p : players_) {
          ss << p->id << " ";
        }
        std::cerr << ss.str() << std::endl;
      }
      result->Success(flutter::EncodableMap());
    } else if (method_call.method_name().compare("disposeAllPlayers") == 0) {
      auto now = std::chrono::system_clock::now();
      auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
      std::cerr << "[just_audio_windows] disposeAllPlayers() ts=" << ms << std::endl;
      std::cerr << "[just_audio_windows] registered players before clear: ";
      for (auto &p : players_) { std::cerr << p->id << " "; }
      std::cerr << std::endl;
      players_.clear();
      std::cerr << "[just_audio_windows] registered players after clear: (" << players_.size() << ")" << std::endl;
      result->Success(flutter::EncodableMap());
    } else {
      result->NotImplemented();
    }
  } else {
    result->NotImplemented();
  }
}

AudioPlayer* JustAudioWindowsPlugin::GetPlayerByPlayerId(std::string id) {
  for (auto it = begin(players_); it != end(players_); ++it) {
    if ((*it)->HasPlayerId(id)) {
      return it->get();
    }
  }
  return nullptr;
}

void JustAudioWindowsPlugin::DisposePlayerByPlayerId(std::string id) {
  for (auto it = begin(players_); it != end(players_); ++it) {
    if ((*it)->HasPlayerId(id)) {
      (*it)->disposing = true;
      // Start a thread to delay the actual erase
      std::thread([id]() {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        // Now erase
        for (auto jt = players_.begin(); jt != players_.end(); ++jt) {
          if ((*jt)->id == id) {
            players_.erase(jt);
            break;
          }
        }
      }).detach();
      return;
    }
  }
}

}  // namespace

void JustAudioWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  JustAudioWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
