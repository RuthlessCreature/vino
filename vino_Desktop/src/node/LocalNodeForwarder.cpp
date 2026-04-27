#include "vino_desktop/LocalNodeForwarder.hpp"

#include <array>
#include <chrono>
#include <sstream>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
using socket_handle = SOCKET;
constexpr socket_handle invalid_socket_handle = INVALID_SOCKET;
#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>
using socket_handle = int;
constexpr socket_handle invalid_socket_handle = -1;
#endif

namespace vino::desktop {

namespace {

json::Value::Object make_object(std::initializer_list<std::pair<const std::string, json::Value>> items) {
    return json::Value::Object(items);
}

std::string now_utc_iso8601() {
    const auto now = std::chrono::system_clock::now();
    const auto time = std::chrono::system_clock::to_time_t(now);

    std::tm time_info {};
#if defined(_WIN32)
    gmtime_s(&time_info, &time);
#else
    gmtime_r(&time, &time_info);
#endif

    char buffer[32];
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &time_info);
    return buffer;
}

void close_socket(socket_handle handle) {
    if (handle == invalid_socket_handle) {
        return;
    }
#if defined(_WIN32)
    closesocket(handle);
#else
    close(handle);
#endif
}

#if defined(_WIN32)
bool set_socket_blocking_mode(socket_handle handle, bool blocking) {
    u_long mode = blocking ? 0UL : 1UL;
    return ioctlsocket(handle, FIONBIO, &mode) == 0;
}
#else
bool set_socket_blocking_mode(socket_handle handle, bool blocking) {
    const int flags = fcntl(handle, F_GETFL, 0);
    if (flags < 0) {
        return false;
    }
    const int updated = blocking ? (flags & ~O_NONBLOCK) : (flags | O_NONBLOCK);
    return fcntl(handle, F_SETFL, updated) == 0;
}
#endif

bool socket_connect_succeeded(socket_handle handle) {
    int error = 0;
    socklen_t error_size = static_cast<socklen_t>(sizeof(error));
    if (getsockopt(handle, SOL_SOCKET, SO_ERROR, reinterpret_cast<char*>(&error), &error_size) != 0) {
        return false;
    }
    return error == 0;
}

void configure_connected_socket(socket_handle handle) {
    (void)set_socket_blocking_mode(handle, true);
#if defined(SO_NOSIGPIPE)
    const int value = 1;
    setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &value, static_cast<socklen_t>(sizeof(value)));
#endif

#if defined(_WIN32)
    const DWORD timeout_ms = 5000;
    setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, reinterpret_cast<const char*>(&timeout_ms), sizeof(timeout_ms));
#else
    timeval timeout {};
    timeout.tv_sec = 5;
    timeout.tv_usec = 0;
    setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, &timeout, static_cast<socklen_t>(sizeof(timeout)));
    setsockopt(handle, SOL_SOCKET, SO_RCVTIMEO, &timeout, static_cast<socklen_t>(sizeof(timeout)));
#endif
}

socket_handle connect_with_timeout(const std::string& host, int port, int timeout_ms) {
    addrinfo hints {};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    addrinfo* result = nullptr;
    const auto port_string = std::to_string(port);
    if (getaddrinfo(host.c_str(), port_string.c_str(), &hints, &result) != 0) {
        return invalid_socket_handle;
    }

    socket_handle connected = invalid_socket_handle;
    for (addrinfo* pointer = result; pointer != nullptr; pointer = pointer->ai_next) {
        socket_handle handle = ::socket(pointer->ai_family, pointer->ai_socktype, pointer->ai_protocol);
        if (handle == invalid_socket_handle) {
            continue;
        }

        if (!set_socket_blocking_mode(handle, false)) {
            close_socket(handle);
            continue;
        }

        const int status = ::connect(handle, pointer->ai_addr, static_cast<socklen_t>(pointer->ai_addrlen));
        if (status == 0) {
            configure_connected_socket(handle);
            connected = handle;
            break;
        }

#if defined(_WIN32)
        const int error_code = WSAGetLastError();
        if (error_code != WSAEWOULDBLOCK && error_code != WSAEINPROGRESS) {
            close_socket(handle);
            continue;
        }
#else
        if (errno != EINPROGRESS) {
            close_socket(handle);
            continue;
        }
#endif

        fd_set write_set;
        FD_ZERO(&write_set);
        FD_SET(handle, &write_set);

        timeval timeout {};
        timeout.tv_sec = timeout_ms / 1000;
        timeout.tv_usec = (timeout_ms % 1000) * 1000;

        const int ready = select(static_cast<int>(handle) + 1, nullptr, &write_set, nullptr, &timeout);
        if (ready > 0 && FD_ISSET(handle, &write_set) && socket_connect_succeeded(handle)) {
            configure_connected_socket(handle);
            connected = handle;
            break;
        }

        close_socket(handle);
    }

    freeaddrinfo(result);
    return connected;
}

bool socket_send_all(socket_handle handle, const std::string& payload) {
    std::size_t offset = 0;
    while (offset < payload.size()) {
        const auto sent = ::send(handle, payload.data() + offset, static_cast<int>(payload.size() - offset), 0);
        if (sent <= 0) {
            return false;
        }
        offset += static_cast<std::size_t>(sent);
    }
    return true;
}

std::string socket_receive_all(socket_handle handle) {
    std::string response;
    std::array<char, 4096> buffer {};
    while (true) {
        const auto bytes_read = recv(handle, buffer.data(), static_cast<int>(buffer.size()), 0);
        if (bytes_read <= 0) {
            break;
        }
        response.append(buffer.data(), static_cast<std::size_t>(bytes_read));
    }
    return response;
}

struct ParsedHttpUrl {
    std::string host {};
    int port {80};
    std::string basePath {};
};

bool parse_http_url(const std::string& raw_url, ParsedHttpUrl* out_url, std::string* out_error) {
    std::string value = raw_url;
    if (value.rfind("http://", 0) == 0) {
        value = value.substr(7);
    } else if (value.rfind("https://", 0) == 0) {
        if (out_error != nullptr) {
            *out_error = "https is not supported by local node mvp forwarder";
        }
        return false;
    }

    const auto slash = value.find('/');
    const std::string authority = slash == std::string::npos ? value : value.substr(0, slash);
    const std::string base_path = slash == std::string::npos ? std::string() : value.substr(slash);
    if (authority.empty()) {
        if (out_error != nullptr) {
            *out_error = "cloud base url host is empty";
        }
        return false;
    }

    ParsedHttpUrl parsed;
    parsed.basePath = base_path;

    const auto colon = authority.rfind(':');
    if (colon != std::string::npos && authority.find(':') == colon) {
        parsed.host = authority.substr(0, colon);
        try {
            parsed.port = std::stoi(authority.substr(colon + 1));
        } catch (...) {
            if (out_error != nullptr) {
                *out_error = "cloud base url port is invalid";
            }
            return false;
        }
    } else {
        parsed.host = authority;
    }

    if (parsed.host.empty()) {
        if (out_error != nullptr) {
            *out_error = "cloud base url host is empty";
        }
        return false;
    }

    *out_url = parsed;
    return true;
}

std::string join_path(const std::string& base_path, const std::string& endpoint) {
    const bool base_empty = base_path.empty() || base_path == "/";
    const bool endpoint_has_slash = !endpoint.empty() && endpoint.front() == '/';
    if (base_empty) {
        return endpoint_has_slash ? endpoint : ("/" + endpoint);
    }

    if (endpoint_has_slash) {
        return base_path + endpoint;
    }
    return base_path + "/" + endpoint;
}

bool http_post_json(const std::string& base_url, const std::string& endpoint, const std::string& body, std::string* out_error) {
    ParsedHttpUrl url;
    if (!parse_http_url(base_url, &url, out_error)) {
        return false;
    }

    const socket_handle handle = connect_with_timeout(url.host, url.port, 5000);
    if (handle == invalid_socket_handle) {
        if (out_error != nullptr) {
            *out_error = "failed to connect to cloud endpoint";
        }
        return false;
    }

    const std::string target = join_path(url.basePath, endpoint);
    std::ostringstream request;
    request
        << "POST " << target << " HTTP/1.1\r\n"
        << "Host: " << url.host << ":" << url.port << "\r\n"
        << "Content-Type: application/json\r\n"
        << "Content-Length: " << body.size() << "\r\n"
        << "Connection: close\r\n\r\n"
        << body;

    if (!socket_send_all(handle, request.str())) {
        close_socket(handle);
        if (out_error != nullptr) {
            *out_error = "failed to send cloud request";
        }
        return false;
    }

    const std::string response = socket_receive_all(handle);
    close_socket(handle);

    const auto line_end = response.find("\r\n");
    if (line_end == std::string::npos) {
        if (out_error != nullptr) {
            *out_error = "cloud response is invalid";
        }
        return false;
    }

    std::istringstream line_stream(response.substr(0, line_end));
    std::string http_version;
    int status_code = 0;
    line_stream >> http_version >> status_code;
    if (status_code >= 200 && status_code < 300) {
        return true;
    }

    std::string response_error = "cloud http status " + std::to_string(status_code);
    const auto body_offset = response.find("\r\n\r\n");
    if (body_offset != std::string::npos) {
        const std::string response_body = response.substr(body_offset + 4);
        try {
            const json::Value parsed = json::parse(response_body);
            if (parsed.is_object()) {
                const auto* error_value = parsed.find("error");
                if (error_value != nullptr && error_value->is_string()) {
                    response_error = error_value->as_string();
                }
            }
        } catch (...) {
        }
    }

    if (out_error != nullptr) {
        *out_error = response_error;
    }
    return false;
}

} // namespace

json::Value LocalNodeForwarder::FlushReport::to_json() const {
    return make_object({
        {"enabled", enabled},
        {"baseURL", baseURL},
        {"attempted", attempted},
        {"succeeded", succeeded},
        {"failed", failed},
        {"finishedAt", finishedAt},
        {"status", status},
        {"lastError", lastError}
    });
}

LocalNodeForwarder::LocalNodeForwarder(LocalNodeStorage& storage, LogFn log_fn)
    : storage_(storage)
    , log_fn_(std::move(log_fn)) {}

LocalNodeForwarder::~LocalNodeForwarder() {
    stop();
}

void LocalNodeForwarder::start() {
    if (running_) {
        return;
    }
    running_ = true;
    worker_ = new std::thread([this] { run_loop(); });
}

void LocalNodeForwarder::stop() {
    if (!running_) {
        return;
    }
    running_ = false;
    if (worker_ != nullptr) {
        if (worker_->joinable()) {
            worker_->join();
        }
        delete worker_;
        worker_ = nullptr;
    }
}

LocalNodeForwarder::FlushReport LocalNodeForwarder::flush_once(int limit) {
    std::scoped_lock flush_lock(flush_mutex_);

    FlushReport report;
    const LocalNodeCloudSyncConfig config = storage_.cloud_sync_config();
    report.enabled = config.enabled;
    report.baseURL = config.baseURL;
    report.finishedAt = now_utc_iso8601();

    if (!config.enabled || config.baseURL.empty()) {
        report.status = config.enabled ? "idle" : "disabled";
        report.lastError = config.enabled ? "cloud base url is empty" : "";
        if (config.enabled) {
            std::string ignored;
            (void)storage_.record_cloud_sync_result(report.status, report.lastError, report.finishedAt, &ignored);
        }
        return report;
    }

    const auto jobs = storage_.pending_outbox_jobs(limit);
    if (jobs.empty()) {
        report.status = "idle";
        std::string ignored;
        (void)storage_.record_cloud_sync_result(report.status, "", report.finishedAt, &ignored);
        return report;
    }

    for (const auto& job : jobs) {
        report.attempted += 1;
        std::string body;
        std::string error_message;
        if (!storage_.build_cloud_request_body(job, &body, &error_message)) {
            report.failed += 1;
            report.lastError = error_message;
            std::string ignored;
            (void)storage_.mark_outbox_job_failure(job, error_message, report.finishedAt, &ignored);
            continue;
        }

        if (http_post_json(config.baseURL, job.cloudEndpoint, body, &error_message)) {
            report.succeeded += 1;
            std::string ignored;
            (void)storage_.mark_outbox_job_success(job, report.finishedAt, &ignored);
        } else {
            report.failed += 1;
            report.lastError = error_message;
            std::string ignored;
            (void)storage_.mark_outbox_job_failure(job, error_message, report.finishedAt, &ignored);
        }
    }

    if (report.failed == 0) {
        report.status = "success";
    } else if (report.succeeded > 0) {
        report.status = "partial";
    } else {
        report.status = "error";
    }

    std::string ignored;
    (void)storage_.record_cloud_sync_result(report.status, report.lastError, report.finishedAt, &ignored);

    if (report.attempted > 0) {
        log(report.failed == 0 ? "INFO" : "WARN",
            "outbox flush attempted=" + std::to_string(report.attempted) +
            " ok=" + std::to_string(report.succeeded) +
            " fail=" + std::to_string(report.failed));
    }
    return report;
}

void LocalNodeForwarder::run_loop() {
    while (running_) {
        std::this_thread::sleep_for(std::chrono::seconds(3));
        if (!running_) {
            break;
        }
        (void)flush_once();
    }
}

void LocalNodeForwarder::log(const std::string& level, const std::string& message) const {
    if (log_fn_) {
        log_fn_(level, message);
    }
}

} // namespace vino::desktop
