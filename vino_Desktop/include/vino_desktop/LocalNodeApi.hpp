#pragma once

#include <functional>
#include <map>
#include <string>
#include <thread>

#include "vino_desktop/Controller.hpp"
#include "vino_desktop/LocalNodeForwarder.hpp"
#include "vino_desktop/LocalNodeStorage.hpp"

namespace vino::desktop {

class LocalNodeApiServer {
public:
    using LogFn = std::function<void(const std::string&, const std::string&)>;

    LocalNodeApiServer(DesktopController& controller, LocalNodeStorage& storage, LocalNodeForwarder& forwarder, LogFn log_fn = {});
    ~LocalNodeApiServer();

    bool start(int port = PortMap::local_node_api);
    void stop();

private:
    struct Request {
        std::string method {};
        std::string path {};
        std::string body {};
    };

    static Request parse_request(const std::string& raw_request);
    void accept_loop();
    std::string handle_request(const std::string& raw_request);
    std::string handle_health_get() const;
    std::string handle_console_get() const;
    std::string handle_console_css_get() const;
    std::string handle_console_js_get() const;
    std::string handle_devices_get() const;
    std::string handle_summary_get() const;
    std::string handle_assets_get(const std::string& path) const;
    std::string handle_asset_content_get(const std::string& path) const;
    std::string handle_asset_detail_get(const std::string& path) const;
    std::string handle_logs_get(const std::string& path) const;
    std::string handle_stats_get(const std::string& path) const;
    std::string handle_results_get(const std::string& path) const;
    std::string handle_outbox_get(const std::string& path) const;
    std::string handle_cloud_config_post(const std::string& body);
    std::string handle_outbox_flush_post();
    std::string handle_connect_post(const std::string& body);
    std::string handle_scan_post(const std::string& body);
    std::string handle_ingest_asset_post(const std::string& body);
    std::string handle_ingest_log_post(const std::string& body, const std::string& source);
    std::string handle_ingest_stat_post(const std::string& body, const std::string& source);
    std::string handle_ingest_result_post(const std::string& body, const std::string& source);
    std::string handle_index_post();
    void log(const std::string& level, const std::string& message) const;

    DesktopController& controller_;
    LocalNodeStorage& storage_;
    LocalNodeForwarder& forwarder_;
    LogFn log_fn_;
    int server_socket_ {-1};
    bool running_ {false};
    int port_ {PortMap::local_node_api};
    std::thread* accept_thread_ {nullptr};
};

} // namespace vino::desktop
