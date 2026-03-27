#include "vino_desktop/DeviceRegistry.hpp"

#include <chrono>
#include <filesystem>

namespace vino::desktop {

namespace {

constexpr auto offline_timeout = std::chrono::seconds(5);

std::chrono::steady_clock::time_point monotonic_now() {
    return std::chrono::steady_clock::now();
}

void refresh_online_state(DeviceSnapshot& snapshot) {
    if (!snapshot.online) {
        return;
    }

    if (snapshot.last_control_seen_monotonic == std::chrono::steady_clock::time_point {}) {
        return;
    }

    if (monotonic_now() - snapshot.last_control_seen_monotonic > offline_timeout) {
        snapshot.online = false;
        snapshot.last_message = "心跳超时";
    }
}

json::Value snapshot_to_json(const DeviceSnapshot& snapshot) {
    return json::Value::Object{
        {"deviceId", snapshot.device_id},
        {"alias", snapshot.alias},
        {"host", snapshot.host},
        {"port", snapshot.port},
        {"online", snapshot.online},
        {"lastSeen", snapshot.last_seen},
        {"lastMessage", snapshot.last_message},
        {"hello", snapshot.hello_payload},
        {"status", snapshot.status_payload},
        {"capabilities", snapshot.capabilities_payload},
        {"inference", snapshot.inference_payload},
        {"lastMediaPath", snapshot.last_media_path},
        {"lastMediaCategory", snapshot.last_media_category},
        {"lastMediaSeen", snapshot.last_media_seen},
        {"previewImageWidth", snapshot.preview_image_width},
        {"previewImageHeight", snapshot.preview_image_height},
        {"previewFrameIndex", snapshot.preview_frame_index},
        {"previewSeen", snapshot.preview_seen},
    };
}

} // namespace

std::string DeviceRegistry::host_key(const std::string& host, int port) {
    return host + ":" + std::to_string(port);
}

void DeviceRegistry::apply_alias_override(DeviceSnapshot& snapshot, const std::string& fallback_alias) {
    if (const auto iterator = alias_overrides_.find(snapshot.device_id); iterator != alias_overrides_.end()) {
        snapshot.alias = iterator->second;
        return;
    }

    if (snapshot.alias.empty()) {
        snapshot.alias = fallback_alias;
    }
}

void DeviceRegistry::upsert_connected_host(const std::string& host, int port) {
    std::scoped_lock lock(mutex_);
    const std::string temporary_id = host_key(host, port);
    auto& snapshot = devices_[temporary_id];
    snapshot.device_id = temporary_id;
    snapshot.host = host;
    snapshot.port = port;
    snapshot.online = true;
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
    apply_alias_override(snapshot, host);
    host_to_device_id_[temporary_id] = temporary_id;
}

void DeviceRegistry::apply_hello(
    const std::string& host,
    int port,
    const std::string& device_id,
    const std::string& name,
    const std::string& timestamp,
    const json::Value& payload
) {
    std::scoped_lock lock(mutex_);

    const std::string key = host_key(host, port);
    DeviceSnapshot merged;

    if (const auto existing_by_id = devices_.find(device_id); existing_by_id != devices_.end()) {
        merged = existing_by_id->second;
        devices_.erase(existing_by_id);
    } else if (const auto existing_by_host = devices_.find(key); existing_by_host != devices_.end()) {
        merged = existing_by_host->second;
        devices_.erase(existing_by_host);
    }

    merged.device_id = device_id;
    merged.host = host;
    merged.port = port;
    merged.online = true;
    merged.last_seen = timestamp;
    merged.last_message = "device.hello";
    merged.last_seen_monotonic = monotonic_now();
    merged.last_control_seen_monotonic = merged.last_seen_monotonic;
    merged.hello_payload = payload;
    apply_alias_override(merged, name.empty() ? device_id : name);

    devices_[device_id] = merged;
    host_to_device_id_[key] = device_id;
}

void DeviceRegistry::apply_status(
    const std::string& device_id,
    const std::string& timestamp,
    const json::Value& payload,
    const std::string& message
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.online = true;
    snapshot.last_seen = timestamp;
    snapshot.last_message = message;
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
    snapshot.status_payload = payload;
}

void DeviceRegistry::apply_capabilities(
    const std::string& device_id,
    const json::Value& payload
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.online = true;
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
    snapshot.capabilities_payload = payload;
}

void DeviceRegistry::apply_inference(
    const std::string& device_id,
    const std::string& timestamp,
    const json::Value& payload
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.online = true;
    snapshot.last_seen = timestamp;
    snapshot.last_message = "inference.result.push";
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
    snapshot.inference_payload = payload;
}

void DeviceRegistry::apply_media(
    const std::string& device_id,
    const std::string& timestamp,
    const std::string& path,
    const std::string& category
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.online = true;
    snapshot.last_seen = timestamp;
    snapshot.last_message = "media.push.commit";
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
    snapshot.last_media_path = path;
    snapshot.last_media_category = category;
    snapshot.last_media_seen = timestamp;
}

void DeviceRegistry::apply_preview(
    const std::string& device_id,
    const std::string& timestamp,
    const std::string& jpeg_base64,
    int image_width,
    int image_height,
    int frame_index
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.preview_jpeg_base64 = jpeg_base64;
    snapshot.preview_image_width = image_width;
    snapshot.preview_image_height = image_height;
    snapshot.preview_frame_index = frame_index;
    snapshot.preview_seen = timestamp;
}

void DeviceRegistry::mark_seen(
    const std::string& device_id,
    const std::string& timestamp,
    const std::string& message
) {
    std::scoped_lock lock(mutex_);
    auto& snapshot = devices_[device_id];
    snapshot.device_id = device_id;
    apply_alias_override(snapshot, device_id);
    snapshot.online = true;
    snapshot.last_seen = timestamp;
    snapshot.last_message = message;
    snapshot.last_seen_monotonic = monotonic_now();
    snapshot.last_control_seen_monotonic = snapshot.last_seen_monotonic;
}

void DeviceRegistry::mark_disconnected_host(const std::string& host, int port) {
    std::scoped_lock lock(mutex_);
    const auto key = host_key(host, port);
    if (const auto mapped = host_to_device_id_.find(key); mapped != host_to_device_id_.end()) {
        if (const auto iterator = devices_.find(mapped->second); iterator != devices_.end()) {
            iterator->second.online = false;
            iterator->second.last_message = "socket disconnected";
            iterator->second.last_seen_monotonic = std::chrono::steady_clock::time_point {};
            iterator->second.last_control_seen_monotonic = std::chrono::steady_clock::time_point {};
        }
        return;
    }

    if (const auto iterator = devices_.find(key); iterator != devices_.end()) {
        iterator->second.online = false;
        iterator->second.last_message = "socket disconnected";
        iterator->second.last_seen_monotonic = std::chrono::steady_clock::time_point {};
        iterator->second.last_control_seen_monotonic = std::chrono::steady_clock::time_point {};
    }
}

bool DeviceRegistry::set_alias(const std::string& device_id, const std::string& alias) {
    std::scoped_lock lock(mutex_);
    alias_overrides_[device_id] = alias;

    if (const auto iterator = devices_.find(device_id); iterator != devices_.end()) {
        iterator->second.alias = alias;
    }
    return true;
}

void DeviceRegistry::load_aliases(const std::map<std::string, std::string>& aliases) {
    std::scoped_lock lock(mutex_);
    alias_overrides_ = aliases;
    for (auto& [device_id, snapshot] : devices_) {
        apply_alias_override(snapshot, snapshot.alias.empty() ? device_id : snapshot.alias);
    }
}

std::map<std::string, std::string> DeviceRegistry::aliases() const {
    std::scoped_lock lock(mutex_);
    return alias_overrides_;
}

std::optional<DeviceSnapshot> DeviceRegistry::find_by_device_id(const std::string& device_id) const {
    std::scoped_lock lock(mutex_);
    const auto iterator = devices_.find(device_id);
    if (iterator == devices_.end()) {
        return std::nullopt;
    }
    DeviceSnapshot snapshot = iterator->second;
    refresh_online_state(snapshot);
    return snapshot;
}

std::optional<DeviceSnapshot> DeviceRegistry::find_by_host(const std::string& host, int port) const {
    std::scoped_lock lock(mutex_);
    const auto key = host_key(host, port);
    const auto mapped = host_to_device_id_.find(key);
    if (mapped != host_to_device_id_.end()) {
        if (const auto iterator = devices_.find(mapped->second); iterator != devices_.end()) {
            DeviceSnapshot snapshot = iterator->second;
            refresh_online_state(snapshot);
            return snapshot;
        }
    }
    if (const auto iterator = devices_.find(key); iterator != devices_.end()) {
        DeviceSnapshot snapshot = iterator->second;
        refresh_online_state(snapshot);
        return snapshot;
    }
    return std::nullopt;
}

std::vector<DeviceSnapshot> DeviceRegistry::list() const {
    std::scoped_lock lock(mutex_);
    std::vector<DeviceSnapshot> devices;
    devices.reserve(devices_.size());
    for (const auto& [_, snapshot] : devices_) {
        DeviceSnapshot copy = snapshot;
        refresh_online_state(copy);
        devices.push_back(std::move(copy));
    }
    return devices;
}

json::Value DeviceRegistry::to_json() const {
    json::Value::Array array;
    for (const auto& snapshot : list()) {
        array.push_back(snapshot_to_json(snapshot));
    }
    return array;
}

} // namespace vino::desktop
