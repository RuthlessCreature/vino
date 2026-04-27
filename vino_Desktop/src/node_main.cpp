#include "vino_desktop/BatchGateway.hpp"
#include "vino_desktop/Controller.hpp"
#include "vino_desktop/LocalNodeApi.hpp"
#include "vino_desktop/LocalNodeForwarder.hpp"
#include "vino_desktop/LocalNodeStorage.hpp"
#include "vino_desktop/Protocol.hpp"

#include <atomic>
#include <chrono>
#include <csignal>
#include <cstdlib>
#include <iostream>
#include <optional>
#include <string>
#include <thread>
#include <vector>

namespace {

std::atomic<bool> g_should_run {true};

struct ScanRequest {
    std::string prefix {};
    int start {0};
    int end {0};
};

void handle_signal(int) {
    g_should_run = false;
}

void print_usage() {
    std::cout
        << "usage:\n"
        << "  vino_local_node [--api-port PORT] [--batch-port PORT]\n"
        << "                  [--connect IP[:PORT]]... [--scan PREFIX START END]\n"
        << "                  [--cloud-base-url URL] [--cloud-sync on|off]\n";
}

std::pair<std::string, int> parse_host_port(const std::string& value) {
    const auto separator = value.find(':');
    if (separator == std::string::npos) {
        return {value, vino::desktop::PortMap::control};
    }

    return {
        value.substr(0, separator),
        std::stoi(value.substr(separator + 1))
    };
}

} // namespace

int main(int argc, char** argv) {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    int api_port = vino::desktop::PortMap::local_node_api;
    int batch_port = vino::desktop::PortMap::batch_gateway;
    std::vector<std::pair<std::string, int>> direct_targets;
    std::optional<ScanRequest> scan_request;
    std::optional<std::string> cloud_base_url;
    std::optional<bool> cloud_sync_enabled;

    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "--help" || argument == "-h") {
            print_usage();
            return 0;
        }
        if (argument == "--api-port" && index + 1 < argc) {
            api_port = std::stoi(argv[++index]);
            continue;
        }
        if (argument == "--batch-port" && index + 1 < argc) {
            batch_port = std::stoi(argv[++index]);
            continue;
        }
        if (argument == "--connect" && index + 1 < argc) {
            direct_targets.push_back(parse_host_port(argv[++index]));
            continue;
        }
        if (argument == "--scan" && index + 3 < argc) {
            scan_request = ScanRequest{
                .prefix = argv[++index],
                .start = std::stoi(argv[++index]),
                .end = std::stoi(argv[++index])
            };
            continue;
        }
        if (argument == "--cloud-base-url" && index + 1 < argc) {
            cloud_base_url = argv[++index];
            continue;
        }
        if (argument == "--cloud-sync" && index + 1 < argc) {
            const std::string value = argv[++index];
            cloud_sync_enabled = (value == "1" || value == "true" || value == "on" || value == "yes");
            continue;
        }
    }

    vino::desktop::DesktopController controller([](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });
    vino::desktop::BatchGatewayServer batch_gateway(controller, [](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });
    vino::desktop::LocalNodeStorage storage;
    vino::desktop::LocalNodeForwarder forwarder(storage, [](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });
    vino::desktop::LocalNodeApiServer api_server(controller, storage, forwarder, [](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });

    std::string storage_error;
    if (!storage.start(&storage_error)) {
        std::cerr << "failed to open local node storage: " << storage_error << '\n';
        return 1;
    }

    if (!storage.sync_archive_index(&storage_error)) {
        std::cerr << "[WARN] initial archive index failed: " << storage_error << '\n';
    }

    if (!cloud_base_url.has_value()) {
        if (const char* env_value = std::getenv("VINO_CLOUD_BASE_URL"); env_value != nullptr) {
            cloud_base_url = std::string(env_value);
        }
    }
    if (!cloud_sync_enabled.has_value()) {
        if (const char* env_value = std::getenv("VINO_CLOUD_SYNC_ENABLED"); env_value != nullptr) {
            const std::string raw_value = env_value;
            cloud_sync_enabled = (raw_value == "1" || raw_value == "true" || raw_value == "on" || raw_value == "yes");
        }
    }
    if (cloud_base_url.has_value() || cloud_sync_enabled.has_value()) {
        const vino::desktop::LocalNodeCloudSyncConfig existing = storage.cloud_sync_config();
        const std::string effective_base_url = cloud_base_url.value_or(existing.baseURL);
        const bool effective_enabled = cloud_sync_enabled.value_or(existing.enabled);
        if (!storage.update_cloud_sync_config(effective_base_url, effective_enabled, &storage_error)) {
            std::cerr << "[WARN] failed to apply cloud sync config: " << storage_error << '\n';
        }
    }

    if (!batch_gateway.start(batch_port)) {
        std::cerr << "failed to start batch gateway on :" << batch_port << '\n';
        return 1;
    }

    if (!api_server.start(api_port)) {
        std::cerr << "failed to start local node api on :" << api_port << '\n';
        batch_gateway.stop();
        return 1;
    }

    forwarder.start();

    std::cout << "vino_LocalNode service\n";
    std::cout << "control target port: " << vino::desktop::PortMap::control << '\n';
    std::cout << "batch gateway port: " << batch_port << '\n';
    std::cout << "local api port: " << api_port << '\n';

    for (const auto& [host, port] : direct_targets) {
        const bool connected = controller.connect_to_device(host, port);
        std::cout << (connected ? "[INFO] " : "[WARN] ") << "connect " << host << ":" << port << '\n';
    }

    if (scan_request.has_value()) {
        const auto found = controller.scan_prefix(
            scan_request->prefix,
            scan_request->start,
            scan_request->end,
            vino::desktop::PortMap::control
        );
        std::cout << "[INFO] scan found " << found << " reachable control port(s)\n";
    }

    std::thread index_thread([&storage] {
        while (g_should_run) {
            std::this_thread::sleep_for(std::chrono::seconds(3));
            std::string error_message;
            (void)storage.sync_archive_index(&error_message);
        }
    });

    std::cout << "[INFO] local node ready, press Ctrl+C to stop\n";

    while (g_should_run) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    if (index_thread.joinable()) {
        index_thread.join();
    }

    api_server.stop();
    forwarder.stop();
    batch_gateway.stop();
    controller.stop();
    storage.stop();
    return 0;
}
