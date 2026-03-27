#include "vino_desktop/DesktopRuntime.hpp"
#include "vino_desktop/RuntimePaths.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <thread>

namespace vino::desktop {

DesktopRuntime::DesktopRuntime()
    : controller_([this](const std::string& level, const std::string& message) {
        append_log(level, message);
    })
    , batch_gateway_(controller_, [this](const std::string& level, const std::string& message) {
        append_log(level, message);
    }) {}

DesktopRuntime::~DesktopRuntime() {
    stop();
}

bool DesktopRuntime::start() {
    load_aliases_from_disk();
    const bool started = batch_gateway_.start();
    append_log(started ? "INFO" : "ERROR", started ? "批处理网关已就绪，监听 :49020" : "批处理网关启动失败，端口 :49020");
    return started;
}

void DesktopRuntime::stop() {
    batch_gateway_.stop();
    controller_.stop();
}

bool DesktopRuntime::connect_host(const std::string& host, int port) {
    const bool connected = controller_.connect_to_device(host, port);
    append_log(connected ? "INFO" : "WARN", connected ? ("手动连接成功 " + host + ":" + std::to_string(port)) : ("手动连接失败 " + host + ":" + std::to_string(port)));
    return connected;
}

int DesktopRuntime::scan_prefix(const std::string& prefix, int start, int end, int port) {
    append_log("INFO", "开始扫描网段 " + prefix + "." + std::to_string(start) + "-" + std::to_string(end));
    const int found = controller_.scan_prefix(prefix, start, end, port);
    append_log("INFO", "扫描完成，发现 " + std::to_string(found) + " 台可连接设备");
    return found;
}

void DesktopRuntime::scan_prefix_async(const std::string& prefix, int start, int end, int port) {
    std::thread([this, prefix, start, end, port] {
        (void)scan_prefix(prefix, start, end, port);
    }).detach();
}

std::vector<DeviceSnapshot> DesktopRuntime::snapshots() const {
    return controller_.list_devices();
}

std::vector<ModelTransferSnapshot> DesktopRuntime::model_transfers() const {
    return controller_.list_model_transfers();
}

std::vector<UiLogEntry> DesktopRuntime::logs() const {
    std::scoped_lock lock(logs_mutex_);
    return logs_;
}

json::Value DesktopRuntime::dispatch_to_device(
    const std::string& device_id,
    const std::string& action,
    const TriggerContext& context,
    const json::Value& payload
) {
    return dispatch_to_devices({device_id}, action, context, payload);
}

json::Value DesktopRuntime::dispatch_to_devices(
    const std::vector<std::string>& device_ids,
    const std::string& action,
    const TriggerContext& context,
    const json::Value& payload
) {
    OutboundOperation operation;
    operation.target_device_ids = device_ids;
    operation.action = action;
    operation.context = context;
    operation.payload = payload;

    append_log("INFO", "下发动作 " + action + "，目标设备 " + std::to_string(device_ids.size()) + " 台");
    return controller_.dispatch(operation);
}

json::Value DesktopRuntime::install_model_to_device(
    const std::string& device_id,
    const std::string& file_path,
    const std::string& model_id,
    const std::string& model_name,
    const std::string& version,
    bool activate_after_install
) {
    return install_model_to_devices({device_id}, file_path, model_id, model_name, version, activate_after_install);
}

json::Value DesktopRuntime::install_model_to_devices(
    const std::vector<std::string>& device_ids,
    const std::string& file_path,
    const std::string& model_id,
    const std::string& model_name,
    const std::string& version,
    bool activate_after_install
) {
    append_log("INFO", "开始分发模型 " + model_id + "，目标设备 " + std::to_string(device_ids.size()) + " 台");
    return controller_.install_model(device_ids, file_path, model_id, model_name, version, activate_after_install);
}

bool DesktopRuntime::set_alias(const std::string& device_id, const std::string& alias) {
    const bool updated = controller_.set_alias(device_id, alias);
    save_aliases_to_disk();
    append_log(updated ? "INFO" : "WARN", updated ? ("设备命名已更新 " + device_id + " -> " + alias) : ("设备命名更新失败 " + device_id));
    return updated;
}

void DesktopRuntime::append_log(const std::string& level, const std::string& message) {
    std::scoped_lock lock(logs_mutex_);
    logs_.push_back(UiLogEntry{
        .timestamp = timestamp_now_local(),
        .level = level,
        .message = message
    });

    constexpr std::size_t max_log_entries = 500;
    if (logs_.size() > max_log_entries) {
        logs_.erase(logs_.begin(), logs_.begin() + static_cast<std::ptrdiff_t>(logs_.size() - max_log_entries));
    }
}

void DesktopRuntime::load_aliases_from_disk() {
    const auto path = alias_file_path();
    if (!std::filesystem::exists(path)) {
        return;
    }

    std::ifstream stream(path);
    if (!stream) {
        append_log("WARN", "无法打开别名配置文件 " + path.string());
        return;
    }

    std::string content((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    if (content.empty()) {
        return;
    }

    try {
        const auto root = json::parse(content);
        std::map<std::string, std::string> aliases;
        if (root.is_object()) {
            for (const auto& [device_id, alias_value] : root.as_object()) {
                if (alias_value.is_string()) {
                    aliases.emplace(device_id, alias_value.as_string());
                }
            }
        }
        controller_.load_aliases(aliases);
        append_log("INFO", "已加载别名配置，共 " + std::to_string(aliases.size()) + " 条");
    } catch (const std::exception& error) {
        append_log("WARN", "别名配置解析失败: " + std::string(error.what()));
    }
}

void DesktopRuntime::save_aliases_to_disk() const {
    const auto path = alias_file_path();
    std::filesystem::create_directories(path.parent_path());

    json::Value::Object object;
    for (const auto& [device_id, alias] : controller_.aliases()) {
        object[device_id] = alias;
    }

    std::ofstream stream(path, std::ios::trunc);
    if (!stream) {
        return;
    }

    stream << json::Value(object).stringify(2);
}

std::filesystem::path DesktopRuntime::runtime_root() {
    return desktop_runtime_root();
}

std::filesystem::path DesktopRuntime::alias_file_path() {
    return runtime_root() / "settings" / "aliases.json";
}

std::string DesktopRuntime::timestamp_now_local() {
    const auto now = std::chrono::system_clock::now();
    const auto seconds = std::chrono::system_clock::to_time_t(now);
    const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()) % 1000;

    std::tm time_info {};
#if defined(_WIN32)
    localtime_s(&time_info, &seconds);
#else
    localtime_r(&seconds, &time_info);
#endif

    char buffer[32];
    std::strftime(buffer, sizeof(buffer), "%H:%M:%S", &time_info);
    return std::string(buffer) + "." + (milliseconds.count() < 100 ? (milliseconds.count() < 10 ? "00" : "0") : "") + std::to_string(milliseconds.count());
}

} // namespace vino::desktop
