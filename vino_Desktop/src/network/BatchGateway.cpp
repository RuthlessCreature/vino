#include "vino_desktop/BatchGateway.hpp"

#include <array>
#include <chrono>
#include <sstream>
#include <thread>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
using socket_handle = SOCKET;
constexpr socket_handle invalid_socket_handle = INVALID_SOCKET;
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
using socket_handle = int;
constexpr socket_handle invalid_socket_handle = -1;
#endif

namespace vino::desktop {

namespace {

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

std::string http_response(const std::string& status, const std::string& body, const std::string& content_type = "application/json") {
    std::ostringstream stream;
    stream
        << "HTTP/1.1 " << status << "\r\n"
        << "Content-Type: " << content_type << "\r\n"
        << "Content-Length: " << body.size() << "\r\n"
        << "Connection: close\r\n\r\n"
        << body;
    return stream.str();
}

json::Value::Object make_object(std::initializer_list<std::pair<const std::string, json::Value>> items) {
    return json::Value::Object(items);
}

} // namespace

BatchGatewayServer::BatchGatewayServer(DesktopController& controller, LogFn log_fn)
    : controller_(controller)
    , log_fn_(std::move(log_fn)) {}

BatchGatewayServer::~BatchGatewayServer() {
    stop();
}

bool BatchGatewayServer::start(int port) {
    if (running_) {
        return true;
    }

    server_socket_ = ::socket(AF_INET, SOCK_STREAM, 0);
    if (server_socket_ == invalid_socket_handle) {
        return false;
    }

    const int reuse_value = 1;
    setsockopt(server_socket_, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse_value), sizeof(reuse_value));

    sockaddr_in address {};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<uint16_t>(port));
    address.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(server_socket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        close_socket(server_socket_);
        server_socket_ = invalid_socket_handle;
        return false;
    }

    if (listen(server_socket_, 16) != 0) {
        close_socket(server_socket_);
        server_socket_ = invalid_socket_handle;
        return false;
    }

    running_ = true;
    accept_thread_ = new std::thread([this] {
        accept_loop();
    });

    log("INFO", "批处理网关监听 0.0.0.0:" + std::to_string(port));
    return true;
}

void BatchGatewayServer::stop() {
    if (!running_) {
        return;
    }

    running_ = false;
    close_socket(server_socket_);
    server_socket_ = invalid_socket_handle;

    if (accept_thread_ != nullptr) {
        if (accept_thread_->joinable()) {
            accept_thread_->join();
        }
        delete accept_thread_;
        accept_thread_ = nullptr;
    }
}

void BatchGatewayServer::accept_loop() {
    while (running_) {
        sockaddr_in client_address {};
        socklen_t address_length = sizeof(client_address);
        const auto client_socket = accept(server_socket_, reinterpret_cast<sockaddr*>(&client_address), &address_length);
        if (client_socket == invalid_socket_handle) {
            continue;
        }

        std::string request;
        std::array<char, 4096> buffer {};

        while (true) {
            const auto bytes_read = recv(client_socket, buffer.data(), static_cast<int>(buffer.size()), 0);
            if (bytes_read <= 0) {
                break;
            }
            request.append(buffer.data(), static_cast<std::size_t>(bytes_read));
            if (request.find("\r\n\r\n") != std::string::npos) {
                const auto header_end = request.find("\r\n\r\n");
                const auto headers = request.substr(0, header_end);
                const auto content_length_marker = headers.find("Content-Length:");
                if (content_length_marker == std::string::npos) {
                    break;
                }
                const auto line_end = headers.find("\r\n", content_length_marker);
                const auto line = headers.substr(content_length_marker, line_end - content_length_marker);
                const auto colon = line.find(':');
                const auto length_string = line.substr(colon + 1);
                const auto content_length = static_cast<std::size_t>(std::stoi(length_string));
                const auto expected_size = header_end + 4 + content_length;
                if (request.size() >= expected_size) {
                    break;
                }
            }
        }

        const auto response = handle_request(request);
        send(client_socket, response.data(), static_cast<int>(response.size()), 0);
        close_socket(client_socket);
    }
}

std::string BatchGatewayServer::handle_request(const std::string& raw_request) {
    const auto first_line_end = raw_request.find("\r\n");
    if (first_line_end == std::string::npos) {
        return http_response("400 Bad Request", "{\"error\":\"invalid http request\"}");
    }

    const auto request_line = raw_request.substr(0, first_line_end);
    std::istringstream line_stream(request_line);
    std::string method;
    std::string path;
    std::string version;
    line_stream >> method >> path >> version;

    const auto body_separator = raw_request.find("\r\n\r\n");
    const std::string body = body_separator == std::string::npos ? "" : raw_request.substr(body_separator + 4);

    if (method == "POST" && path == "/api/v1/batch") {
        return handle_batch_post(body);
    }
    if (method == "GET" && path == "/api/v1/devices") {
        return handle_devices_get();
    }
    if (method == "GET" && path.rfind("/api/v1/jobs/", 0) == 0) {
        return handle_job_get(path);
    }

    return http_response("404 Not Found", "{\"error\":\"route not found\"}");
}

std::string BatchGatewayServer::handle_batch_post(const std::string& body) {
    try {
        const auto root = json::parse(body);
        const auto request_id = root.contains("requestId") ? root.at("requestId").as_string() : "batch-unknown";
        const auto& operations = root.at("operations").as_array();

        json::Value::Array result_array;
        int accepted = 0;
        int rejected = 0;

        for (const auto& operation_value : operations) {
            const auto& operation = operation_value.as_object();
            OutboundOperation outbound;
            outbound.action = operation.at("action").as_string();

            if (const auto* context = operation_value.find("context"); context != nullptr && context->is_object()) {
                outbound.context.product_uuid = context->contains("productUUID") ? context->at("productUUID").as_string() : "";
                outbound.context.point_index = context->contains("pointIndex") ? context->at("pointIndex").as_int() : 0;
                outbound.context.job_id = context->contains("jobId") ? context->at("jobId").as_string() : "";
            }

            if (const auto* target = operation_value.find("target"); target != nullptr && target->is_object()) {
                if (const auto* device_ids = target->find("deviceIds"); device_ids != nullptr && device_ids->is_array()) {
                    for (const auto& entry : device_ids->as_array()) {
                        outbound.target_device_ids.push_back(entry.as_string());
                    }
                }
            }

            outbound.payload = operation.contains("payload") ? operation.at("payload") : json::Value::Object {};

            if (outbound.target_device_ids.empty()) {
                ++rejected;
                result_array.push_back(make_object({
                    {"action", outbound.action},
                    {"status", "rejected"},
                    {"reason", "empty target set"}
                }));
                continue;
            }

            const auto result = controller_.dispatch(outbound);
            ++accepted;
            result_array.push_back(make_object({
                {"action", outbound.action},
                {"status", "queued"},
                {"dispatch", result}
            }));
        }

        const auto response = json::Value(make_object({
            {"requestId", request_id},
            {"accepted", accepted},
            {"rejected", rejected},
            {"results", result_array}
        }));

        {
            std::scoped_lock lock(jobs_mutex_);
            jobs_[request_id] = JobSummary{.request_id = request_id, .result = response};
        }

        return http_response("200 OK", response.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string BatchGatewayServer::handle_devices_get() const {
    const auto payload = json::Value(make_object({
        {"devices", controller_.list_devices_json()}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string BatchGatewayServer::handle_job_get(const std::string& path) const {
    const auto request_id = path.substr(std::string("/api/v1/jobs/").size());
    std::scoped_lock lock(jobs_mutex_);
    const auto iterator = jobs_.find(request_id);
    if (iterator == jobs_.end()) {
        return http_response("404 Not Found", "{\"error\":\"job not found\"}");
    }
    return http_response("200 OK", iterator->second.result.stringify(2));
}

void BatchGatewayServer::log(const std::string& level, const std::string& message) const {
    if (log_fn_) {
        log_fn_(level, message);
    }
}

} // namespace vino::desktop
