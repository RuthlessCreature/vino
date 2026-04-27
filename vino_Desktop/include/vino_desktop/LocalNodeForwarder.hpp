#pragma once

#include <atomic>
#include <functional>
#include <mutex>
#include <string>
#include <thread>

#include "vino_desktop/LocalNodeStorage.hpp"
#include "vino_desktop/MiniJson.hpp"

namespace vino::desktop {

class LocalNodeForwarder {
public:
    using LogFn = std::function<void(const std::string&, const std::string&)>;

    struct FlushReport {
        bool enabled {false};
        std::string baseURL {};
        int attempted {0};
        int succeeded {0};
        int failed {0};
        std::string finishedAt {};
        std::string status {"idle"};
        std::string lastError {};

        [[nodiscard]] json::Value to_json() const;
    };

    explicit LocalNodeForwarder(LocalNodeStorage& storage, LogFn log_fn = {});
    ~LocalNodeForwarder();

    void start();
    void stop();
    [[nodiscard]] FlushReport flush_once(int limit = 16);

private:
    void run_loop();
    void log(const std::string& level, const std::string& message) const;

    LocalNodeStorage& storage_;
    LogFn log_fn_;
    std::atomic<bool> running_ {false};
    std::thread* worker_ {nullptr};
    std::mutex flush_mutex_;
};

} // namespace vino::desktop
