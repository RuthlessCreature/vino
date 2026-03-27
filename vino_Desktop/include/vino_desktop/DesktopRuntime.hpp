#pragma once

#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

#include "vino_desktop/BatchGateway.hpp"
#include "vino_desktop/Controller.hpp"
#include "vino_desktop/DeviceRegistry.hpp"

namespace vino::desktop {

struct UiLogEntry {
    std::string timestamp {};
    std::string level {};
    std::string message {};
};

class DesktopRuntime {
public:
    DesktopRuntime();
    ~DesktopRuntime();

    bool start();
    void stop();

    bool connect_host(const std::string& host, int port = PortMap::control);
    int scan_prefix(const std::string& prefix, int start, int end, int port = PortMap::control);
    void scan_prefix_async(const std::string& prefix, int start, int end, int port = PortMap::control);

    std::vector<DeviceSnapshot> snapshots() const;
    std::vector<ModelTransferSnapshot> model_transfers() const;
    std::vector<UiLogEntry> logs() const;

    json::Value dispatch_to_device(
        const std::string& device_id,
        const std::string& action,
        const TriggerContext& context,
        const json::Value& payload
    );

    json::Value dispatch_to_devices(
        const std::vector<std::string>& device_ids,
        const std::string& action,
        const TriggerContext& context,
        const json::Value& payload
    );
    json::Value install_model_to_device(
        const std::string& device_id,
        const std::string& file_path,
        const std::string& model_id,
        const std::string& model_name,
        const std::string& version,
        bool activate_after_install
    );
    json::Value install_model_to_devices(
        const std::vector<std::string>& device_ids,
        const std::string& file_path,
        const std::string& model_id,
        const std::string& model_name,
        const std::string& version,
        bool activate_after_install
    );

    bool set_alias(const std::string& device_id, const std::string& alias);

private:
    void append_log(const std::string& level, const std::string& message);
    void load_aliases_from_disk();
    void save_aliases_to_disk() const;
    static std::filesystem::path runtime_root();
    static std::filesystem::path alias_file_path();
    static std::string timestamp_now_local();

    DesktopController controller_;
    BatchGatewayServer batch_gateway_;

    mutable std::mutex logs_mutex_;
    std::vector<UiLogEntry> logs_;
};

} // namespace vino::desktop
