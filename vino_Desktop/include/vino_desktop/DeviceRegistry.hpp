#pragma once

#include <chrono>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "vino_desktop/MiniJson.hpp"

namespace vino::desktop {

struct DeviceSnapshot {
    std::string device_id {};
    std::string alias {};
    std::string host {};
    int port {0};
    bool online {false};
    std::string last_seen {};
    std::string last_message {};
    std::chrono::steady_clock::time_point last_seen_monotonic {};
    std::chrono::steady_clock::time_point last_control_seen_monotonic {};
    json::Value hello_payload {};
    json::Value status_payload {};
    json::Value capabilities_payload {};
    json::Value inference_payload {};
    std::string last_media_path {};
    std::string last_media_category {};
    std::string last_media_seen {};
    std::string preview_jpeg_base64 {};
    int preview_image_width {0};
    int preview_image_height {0};
    int preview_frame_index {0};
    std::string preview_seen {};
};

class DeviceRegistry {
public:
    void upsert_connected_host(const std::string& host, int port);
    void apply_hello(
        const std::string& host,
        int port,
        const std::string& device_id,
        const std::string& name,
        const std::string& timestamp,
        const json::Value& payload
    );
    void apply_status(
        const std::string& device_id,
        const std::string& timestamp,
        const json::Value& payload,
        const std::string& message
    );
    void apply_capabilities(
        const std::string& device_id,
        const json::Value& payload
    );
    void apply_inference(
        const std::string& device_id,
        const std::string& timestamp,
        const json::Value& payload
    );
    void apply_media(
        const std::string& device_id,
        const std::string& timestamp,
        const std::string& path,
        const std::string& category
    );
    void apply_preview(
        const std::string& device_id,
        const std::string& timestamp,
        const std::string& jpeg_base64,
        int image_width,
        int image_height,
        int frame_index
    );
    void mark_seen(
        const std::string& device_id,
        const std::string& timestamp,
        const std::string& message
    );
    void mark_disconnected_host(const std::string& host, int port);
    bool set_alias(const std::string& device_id, const std::string& alias);
    void load_aliases(const std::map<std::string, std::string>& aliases);
    std::map<std::string, std::string> aliases() const;
    std::optional<DeviceSnapshot> find_by_device_id(const std::string& device_id) const;
    std::optional<DeviceSnapshot> find_by_host(const std::string& host, int port) const;
    std::vector<DeviceSnapshot> list() const;
    json::Value to_json() const;

private:
    static std::string host_key(const std::string& host, int port);
    void apply_alias_override(DeviceSnapshot& snapshot, const std::string& fallback_alias);

    mutable std::mutex mutex_;
    std::map<std::string, DeviceSnapshot> devices_;
    std::map<std::string, std::string> host_to_device_id_;
    std::map<std::string, std::string> alias_overrides_;
};

} // namespace vino::desktop
