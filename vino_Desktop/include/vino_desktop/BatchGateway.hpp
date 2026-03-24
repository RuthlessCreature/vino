#pragma once

#include <functional>
#include <map>
#include <string>
#include <thread>

#include "vino_desktop/Controller.hpp"

namespace vino::desktop {

class BatchGatewayServer {
public:
    using LogFn = std::function<void(const std::string&, const std::string&)>;

    BatchGatewayServer(DesktopController& controller, LogFn log_fn = {});
    ~BatchGatewayServer();

    bool start(int port = PortMap::batch_gateway);
    void stop();

private:
    struct JobSummary {
        std::string request_id {};
        json::Value result {};
    };

    void accept_loop();
    std::string handle_request(const std::string& raw_request);
    std::string handle_batch_post(const std::string& body);
    std::string handle_devices_get() const;
    std::string handle_job_get(const std::string& path) const;
    void log(const std::string& level, const std::string& message) const;

    DesktopController& controller_;
    LogFn log_fn_;
    int server_socket_ {-1};
    bool running_ {false};
    std::thread* accept_thread_ {nullptr};
    mutable std::mutex jobs_mutex_;
    std::map<std::string, JobSummary> jobs_;
};

} // namespace vino::desktop
