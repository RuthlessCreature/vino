#include "vino_desktop/BatchGateway.hpp"
#include "vino_desktop/Blueprint.hpp"
#include "vino_desktop/Controller.hpp"
#include "vino_desktop/FuturisticTheme.hpp"
#include "vino_desktop/PostGateway.hpp"
#include "vino_desktop/Protocol.hpp"

#include <atomic>
#include <chrono>
#include <csignal>
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
        << "  vino_desktop_blueprint --demo\n"
        << "  vino_desktop_blueprint --daemon [--connect IP[:PORT]]... [--scan PREFIX START END]\n";
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

void run_demo() {
    const vino::desktop::DesktopBlueprint blueprint {};
    const vino::desktop::PostGatewayBlueprint gateway {};

    std::cout << "vino_Desktop blueprint prototype\n";
    std::cout << "control port: " << vino::desktop::PortMap::control << '\n';
    std::cout << "batch gateway port: " << vino::desktop::PortMap::batch_gateway << "\n\n";
    std::cout << blueprint.render_overview() << '\n';
    std::cout << vino::desktop::render_theme_tokens() << '\n';
    std::cout << blueprint.render_window_layout() << '\n';
    std::cout << gateway.render_documentation() << '\n';
    std::cout << "Batch request example\n";
    std::cout << gateway.render_example_request() << '\n';
    std::cout << blueprint.render_batch_example() << '\n';
}

} // namespace

int main(int argc, char** argv) {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    bool daemon_mode = false;
    std::vector<std::pair<std::string, int>> direct_targets;
    std::optional<ScanRequest> scan_request;

    for (int index = 1; index < argc; ++index) {
        const std::string argument = argv[index];
        if (argument == "--demo") {
            daemon_mode = false;
            continue;
        }
        if (argument == "--daemon") {
            daemon_mode = true;
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
    }

    if (!daemon_mode) {
        print_usage();
        run_demo();
        return 0;
    }

    vino::desktop::DesktopController controller([](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });
    vino::desktop::BatchGatewayServer batch_gateway(controller, [](const std::string& level, const std::string& message) {
        std::cout << "[" << level << "] " << message << '\n';
    });

    std::cout << "vino_Desktop daemon\n";
    std::cout << "control port target: " << vino::desktop::PortMap::control << '\n';
    std::cout << "batch gateway port: " << vino::desktop::PortMap::batch_gateway << '\n';

    if (!batch_gateway.start()) {
        std::cerr << "failed to start batch gateway\n";
        return 1;
    }

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

    std::cout << "[INFO] daemon ready, press Ctrl+C to stop\n";

    while (g_should_run) {
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }

    batch_gateway.stop();
    controller.stop();
    return 0;
}
