#include "vino_desktop/LocalNodeApi.hpp"
#include "vino_desktop/LocalNodeConsoleAssets.hpp"

#include <array>
#include <cctype>
#include <fstream>
#include <sstream>

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

std::string strip_query(const std::string& path) {
    const auto marker = path.find('?');
    return marker == std::string::npos ? path : path.substr(0, marker);
}

bool has_suffix(const std::string& value, const std::string& suffix) {
    return value.size() >= suffix.size() && value.compare(value.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::string to_lower_ascii(std::string value) {
    for (char& character : value) {
        character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    }
    return value;
}

std::string url_decode(const std::string& value) {
    auto decode_hex = [](char character) -> int {
        if (character >= '0' && character <= '9') {
            return character - '0';
        }
        if (character >= 'a' && character <= 'f') {
            return 10 + (character - 'a');
        }
        if (character >= 'A' && character <= 'F') {
            return 10 + (character - 'A');
        }
        return -1;
    };

    std::string decoded;
    decoded.reserve(value.size());

    for (std::size_t index = 0; index < value.size(); ++index) {
        const char character = value[index];
        if (character == '%' && index + 2 < value.size()) {
            const int high = decode_hex(value[index + 1]);
            const int low = decode_hex(value[index + 2]);
            if (high >= 0 && low >= 0) {
                decoded.push_back(static_cast<char>((high << 4) | low));
                index += 2;
                continue;
            }
        }
        decoded.push_back(character == '+' ? ' ' : character);
    }

    return decoded;
}

bool read_binary_file(const std::string& path, std::string* out_bytes) {
    if (out_bytes == nullptr) {
        return false;
    }

    std::ifstream stream(path, std::ios::binary);
    if (!stream) {
        return false;
    }

    stream.seekg(0, std::ios::end);
    const std::streamoff size = stream.tellg();
    if (size < 0) {
        return false;
    }

    out_bytes->assign(static_cast<std::size_t>(size), '\0');
    stream.seekg(0, std::ios::beg);
    if (size > 0) {
        stream.read(out_bytes->data(), size);
    }
    return stream.good() || stream.eof();
}

std::string guess_content_type(const std::string& file_name, const std::string& category) {
    const auto marker = file_name.find_last_of('.');
    const std::string extension = marker == std::string::npos ? "" : to_lower_ascii(file_name.substr(marker + 1));
    const std::string normalized_category = to_lower_ascii(category);

    if (extension == "jpg" || extension == "jpeg") return "image/jpeg";
    if (extension == "png") return "image/png";
    if (extension == "webp") return "image/webp";
    if (extension == "gif") return "image/gif";
    if (extension == "bmp") return "image/bmp";
    if (extension == "tif" || extension == "tiff") return "image/tiff";
    if (extension == "svg") return "image/svg+xml";
    if (extension == "mp4" || extension == "m4v") return "video/mp4";
    if (extension == "mov") return "video/quicktime";
    if (extension == "webm") return "video/webm";
    if (extension == "ogv") return "video/ogg";
    if (extension == "avi") return "video/x-msvideo";
    if (extension == "pdf") return "application/pdf";
    if (extension == "json") return "application/json";
    if (extension == "txt" || extension == "log") return "text/plain; charset=utf-8";
    if (normalized_category == "image") return "image/jpeg";
    if (normalized_category == "video") return "video/mp4";
    return "application/octet-stream";
}

int read_limit_from_query(const std::string& path, int fallback) {
    const auto marker = path.find('?');
    if (marker == std::string::npos) {
        return fallback;
    }

    const std::string query = path.substr(marker + 1);
    const std::string prefix = "limit=";
    const auto position = query.find(prefix);
    if (position == std::string::npos) {
        return fallback;
    }

    try {
        return std::max(1, std::stoi(query.substr(position + prefix.size())));
    } catch (...) {
        return fallback;
    }
}

std::string optional_string(const json::Value::Object& object, const std::string& key, const std::string& fallback = "") {
    const auto iterator = object.find(key);
    if (iterator == object.end() || iterator->second.is_null()) {
        return fallback;
    }
    if (iterator->second.is_string()) {
        return iterator->second.as_string();
    }
    if (iterator->second.is_number()) {
        return std::to_string(iterator->second.as_int());
    }
    if (iterator->second.is_bool()) {
        return iterator->second.as_bool() ? "true" : "false";
    }
    return iterator->second.stringify();
}

int optional_int(const json::Value::Object& object, const std::string& key, int fallback = 0) {
    const auto iterator = object.find(key);
    if (iterator == object.end() || iterator->second.is_null()) {
        return fallback;
    }
    if (iterator->second.is_number()) {
        return iterator->second.as_int();
    }
    if (iterator->second.is_string()) {
        try {
            return std::stoi(iterator->second.as_string());
        } catch (...) {
            return fallback;
        }
    }
    return fallback;
}

std::string stringify_or_empty(const json::Value::Object& object, const std::string& key) {
    const auto iterator = object.find(key);
    if (iterator == object.end() || iterator->second.is_null()) {
        return "{}";
    }
    return iterator->second.stringify();
}

} // namespace

LocalNodeApiServer::LocalNodeApiServer(DesktopController& controller, LocalNodeStorage& storage, LocalNodeForwarder& forwarder, LogFn log_fn)
    : controller_(controller)
    , storage_(storage)
    , forwarder_(forwarder)
    , log_fn_(std::move(log_fn)) {}

LocalNodeApiServer::~LocalNodeApiServer() {
    stop();
}

bool LocalNodeApiServer::start(int port) {
    if (running_) {
        return true;
    }

    port_ = port;
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

    if (listen(server_socket_, 32) != 0) {
        close_socket(server_socket_);
        server_socket_ = invalid_socket_handle;
        return false;
    }

    running_ = true;
    accept_thread_ = new std::thread([this] {
        accept_loop();
    });

    log("INFO", "本地节点 API 已监听 0.0.0.0:" + std::to_string(port_));
    return true;
}

void LocalNodeApiServer::stop() {
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

LocalNodeApiServer::Request LocalNodeApiServer::parse_request(const std::string& raw_request) {
    Request request;
    const auto line_end = raw_request.find("\r\n");
    if (line_end == std::string::npos) {
        return request;
    }

    std::istringstream line_stream(raw_request.substr(0, line_end));
    std::string version;
    line_stream >> request.method >> request.path >> version;

    const auto body_separator = raw_request.find("\r\n\r\n");
    request.body = body_separator == std::string::npos ? "" : raw_request.substr(body_separator + 4);
    return request;
}

void LocalNodeApiServer::accept_loop() {
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
                const auto line_break = headers.find("\r\n", content_length_marker);
                const auto line = headers.substr(content_length_marker, line_break - content_length_marker);
                const auto colon = line.find(':');
                const auto content_length = static_cast<std::size_t>(std::stoi(line.substr(colon + 1)));
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

std::string LocalNodeApiServer::handle_request(const std::string& raw_request) {
    const Request request = parse_request(raw_request);
    const std::string path = strip_query(request.path);

    if (request.method == "GET" && path == "/api/local/v1/health") {
        return handle_health_get();
    }
    if (request.method == "GET" && (path == "/" || path == "/console")) {
        return handle_console_get();
    }
    if (request.method == "GET" && path == "/app.css") {
        return handle_console_css_get();
    }
    if (request.method == "GET" && path == "/app.js") {
        return handle_console_js_get();
    }
    if (request.method == "GET" && path == "/api/local/v1/devices") {
        return handle_devices_get();
    }
    if (request.method == "GET" && path == "/api/local/v1/storage/summary") {
        return handle_summary_get();
    }
    if (request.method == "GET" && path == "/api/local/v1/assets") {
        return handle_assets_get(request.path);
    }
    if (request.method == "GET" && path == "/api/local/v1/logs") {
        return handle_logs_get(request.path);
    }
    if (request.method == "GET" && path == "/api/local/v1/stats") {
        return handle_stats_get(request.path);
    }
    if (request.method == "GET" && path == "/api/local/v1/results") {
        return handle_results_get(request.path);
    }
    if (request.method == "GET" && path == "/api/local/v1/outbox") {
        return handle_outbox_get(request.path);
    }
    if (request.method == "GET" && path.rfind("/api/local/v1/assets/", 0) == 0 && has_suffix(path, "/content")) {
        return handle_asset_content_get(path);
    }
    if (request.method == "GET" && path.rfind("/api/local/v1/assets/", 0) == 0) {
        return handle_asset_detail_get(path);
    }
    if (request.method == "POST" && path == "/api/local/v1/connect") {
        return handle_connect_post(request.body);
    }
    if (request.method == "POST" && path == "/api/local/v1/scan") {
        return handle_scan_post(request.body);
    }
    if (request.method == "POST" && path == "/api/local/v1/cloud/config") {
        return handle_cloud_config_post(request.body);
    }
    if (request.method == "POST" && path == "/api/local/v1/ingest/asset") {
        return handle_ingest_asset_post(request.body);
    }
    if (request.method == "POST" && path == "/api/local/v1/ingest/log") {
        return handle_ingest_log_post(request.body, "api.ingest.log");
    }
    if (request.method == "POST" && path == "/api/local/v1/ingest/stat") {
        return handle_ingest_stat_post(request.body, "api.ingest.stat");
    }
    if (request.method == "POST" && path == "/api/local/v1/ingest/result") {
        return handle_ingest_result_post(request.body, "api.ingest.result");
    }
    if (request.method == "POST" && path == "/api/local/v1/index/rebuild") {
        return handle_index_post();
    }
    if (request.method == "POST" && path == "/api/local/v1/outbox/flush") {
        return handle_outbox_flush_post();
    }
    if (request.method == "POST" && path == "/uploadLog") {
        return handle_ingest_log_post(request.body, "compat.uploadLog");
    }
    if (request.method == "POST" && path == "/uploadStat") {
        return handle_ingest_stat_post(request.body, "compat.uploadStat");
    }
    if (request.method == "POST" && path == "/uploadData") {
        return handle_ingest_result_post(request.body, "compat.uploadData");
    }

    return http_response("404 Not Found", "{\"error\":\"route not found\"}");
}

std::string LocalNodeApiServer::handle_health_get() const {
    const json::Value payload(make_object({
        {"service", "vino_local_node"},
        {"status", "ok"},
        {"apiPort", port_},
        {"storage", storage_.summary_json()}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_console_get() const {
    return http_response("200 OK", local_node_console_html(), "text/html; charset=utf-8");
}

std::string LocalNodeApiServer::handle_console_css_get() const {
    return http_response("200 OK", local_node_console_css(), "text/css; charset=utf-8");
}

std::string LocalNodeApiServer::handle_console_js_get() const {
    return http_response("200 OK", local_node_console_js(), "application/javascript; charset=utf-8");
}

std::string LocalNodeApiServer::handle_devices_get() const {
    const json::Value payload(make_object({
        {"devices", controller_.list_devices_json()}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_summary_get() const {
    const json::Value payload = storage_.summary_json();
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_assets_get(const std::string& path) const {
    const int limit = read_limit_from_query(path, 100);
    const json::Value payload(make_object({
        {"assets", storage_.list_assets_json(limit)},
        {"limit", limit}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_asset_detail_get(const std::string& path) const {
    const std::string prefix = "/api/local/v1/assets/";
    const std::string asset_id = url_decode(path.substr(prefix.size()));
    const json::Value payload = storage_.find_asset_json(asset_id);
    if (payload.is_null()) {
        return http_response("404 Not Found", "{\"error\":\"asset not found\"}");
    }
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_asset_content_get(const std::string& path) const {
    const std::string prefix = "/api/local/v1/assets/";
    const std::string suffix = "/content";

    if (!has_suffix(path, suffix) || path.size() <= prefix.size() + suffix.size()) {
        return http_response("400 Bad Request", "{\"error\":\"invalid asset content path\"}");
    }

    const std::string encoded_asset_id = path.substr(prefix.size(), path.size() - prefix.size() - suffix.size());
    const std::string asset_id = url_decode(encoded_asset_id);
    const json::Value asset = storage_.find_asset_json(asset_id);
    if (!asset.is_object()) {
        return http_response("404 Not Found", "{\"error\":\"asset not found\"}");
    }

    const auto& object = asset.as_object();
    const std::string file_path = optional_string(object, "filePath");
    const std::string file_name = optional_string(object, "fileName");
    const std::string category = optional_string(object, "category");
    if (file_path.empty()) {
        return http_response("404 Not Found", "{\"error\":\"asset file path missing\"}");
    }

    std::string bytes;
    if (!read_binary_file(file_path, &bytes)) {
        return http_response("404 Not Found", "{\"error\":\"asset file missing\"}");
    }

    return http_response("200 OK", bytes, guess_content_type(file_name, category));
}

std::string LocalNodeApiServer::handle_logs_get(const std::string& path) const {
    const int limit = read_limit_from_query(path, 100);
    const json::Value payload(make_object({
        {"logs", storage_.list_logs_json(limit)},
        {"limit", limit}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_stats_get(const std::string& path) const {
    const int limit = read_limit_from_query(path, 100);
    const json::Value payload(make_object({
        {"stats", storage_.list_stats_json(limit)},
        {"limit", limit}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_results_get(const std::string& path) const {
    const int limit = read_limit_from_query(path, 100);
    const json::Value payload(make_object({
        {"results", storage_.list_results_json(limit)},
        {"limit", limit}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_outbox_get(const std::string& path) const {
    const int limit = read_limit_from_query(path, 100);
    const json::Value payload(make_object({
        {"jobs", storage_.list_outbox_json(limit)},
        {"limit", limit}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_cloud_config_post(const std::string& body) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string base_url = optional_string(object, "baseURL", optional_string(object, "baseUrl"));
        const std::string enabled_text = optional_string(object, "enabled", "false");
        const bool enabled = enabled_text == "true" || enabled_text == "1";

        std::string error_message;
        const bool updated = storage_.update_cloud_sync_config(base_url, enabled, &error_message);
        const json::Value payload(make_object({
            {"updated", updated},
            {"error", error_message},
            {"cloudSync", storage_.cloud_sync_config_json()}
        }));
        return http_response(updated ? "200 OK" : "500 Internal Server Error", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_outbox_flush_post() {
    const LocalNodeForwarder::FlushReport report = forwarder_.flush_once();
    const json::Value payload(make_object({
        {"flushed", true},
        {"report", report.to_json()},
        {"cloudSync", storage_.cloud_sync_config_json()},
        {"storage", storage_.summary_json()}
    }));
    return http_response("200 OK", payload.stringify(2));
}

std::string LocalNodeApiServer::handle_connect_post(const std::string& body) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string host = object.at("host").as_string();
        const int port = object.contains("port") ? object.at("port").as_int() : PortMap::control;
        const bool connected = controller_.connect_to_device(host, port);

        const json::Value payload(make_object({
            {"host", host},
            {"port", port},
            {"connected", connected}
        }));
        return http_response(connected ? "200 OK" : "502 Bad Gateway", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_scan_post(const std::string& body) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string prefix = object.at("prefix").as_string();
        const int start = object.at("start").as_int();
        const int end = object.at("end").as_int();
        const int port = object.contains("port") ? object.at("port").as_int() : PortMap::control;
        const int found = controller_.scan_prefix(prefix, start, end, port);

        const json::Value payload(make_object({
            {"prefix", prefix},
            {"start", start},
            {"end", end},
            {"port", port},
            {"found", found}
        }));
        return http_response("200 OK", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_ingest_asset_post(const std::string& body) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();

        const std::string device_id = object.at("deviceId").as_string();
        const std::string file_name = object.at("fileName").as_string();
        const std::string content_base64 = object.at("contentBase64").as_string();
        const std::string category = object.contains("category") ? object.at("category").as_string() : "";
        const std::string captured_at = object.contains("capturedAt") ? object.at("capturedAt").as_string() : "";
        const std::string project_uuid = object.contains("productUUID") ? object.at("productUUID").as_string() : "";
        const int point_index = object.contains("pointIndex") ? object.at("pointIndex").as_int() : 0;
        const std::string job_id = object.contains("jobId") ? object.at("jobId").as_string() : "";

        std::string error_message;
        const json::Value payload = storage_.ingest_asset_json(
            device_id,
            file_name,
            category,
            captured_at,
            content_base64,
            project_uuid,
            point_index,
            job_id,
            &error_message
        );

        if (!error_message.empty()) {
            return http_response("500 Internal Server Error", std::string("{\"error\":\"") + json::escape(error_message) + "\"}");
        }

        return http_response("200 OK", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_ingest_log_post(const std::string& body, const std::string& source) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string device_id = optional_string(object, "deviceId", optional_string(object, "deviceID", "unknown-device"));
        const std::string log_id = optional_string(object, "idempotencyKey", optional_string(object, "logId"));
        const std::string level = optional_string(object, "level", optional_string(object, "status", "info"));
        const std::string category = optional_string(object, "category", "general");
        const std::string message = optional_string(object, "message", optional_string(object, "msg", "log"));
        const std::string captured_at = optional_string(object, "capturedAt", optional_string(object, "timestamp"));
        const std::string payload_json = body;

        std::string error_message;
        const json::Value payload = storage_.ingest_log_json(
            log_id,
            device_id,
            level,
            category,
            message,
            payload_json,
            captured_at,
            source,
            &error_message
        );

        if (!error_message.empty()) {
            return http_response("500 Internal Server Error", std::string("{\"error\":\"") + json::escape(error_message) + "\"}");
        }
        return http_response("200 OK", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_ingest_stat_post(const std::string& body, const std::string& source) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string device_id = optional_string(object, "deviceId", optional_string(object, "deviceID", "unknown-device"));
        const std::string stat_id = optional_string(object, "idempotencyKey", optional_string(object, "statId"));
        const std::string metric = optional_string(object, "metric", optional_string(object, "name", "generic"));
        const std::string value_text = optional_string(object, "value", optional_string(object, "statValue"));
        const std::string captured_at = optional_string(object, "capturedAt", optional_string(object, "timestamp"));
        const std::string payload_json = body;

        std::string error_message;
        const json::Value payload = storage_.ingest_stat_json(
            stat_id,
            device_id,
            metric,
            value_text,
            payload_json,
            captured_at,
            source,
            &error_message
        );

        if (!error_message.empty()) {
            return http_response("500 Internal Server Error", std::string("{\"error\":\"") + json::escape(error_message) + "\"}");
        }
        return http_response("200 OK", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_ingest_result_post(const std::string& body, const std::string& source) {
    try {
        const auto root = json::parse(body);
        const auto& object = root.as_object();
        const std::string device_id = optional_string(object, "deviceId", optional_string(object, "deviceID", "unknown-device"));
        const std::string result_id = optional_string(object, "idempotencyKey", optional_string(object, "resultId"));
        const std::string result_type = optional_string(object, "resultType", "generic");
        const std::string captured_at = optional_string(object, "capturedAt", optional_string(object, "timestamp"));
        const std::string project_uuid = optional_string(object, "productUUID", optional_string(object, "productUuid"));
        const int point_index = optional_int(object, "pointIndex", 0);
        const std::string job_id = optional_string(object, "jobId");
        const std::string payload_json = stringify_or_empty(object, "payload") == "{}" ? body : stringify_or_empty(object, "payload");

        std::string error_message;
        const json::Value payload = storage_.ingest_result_json(
            result_id,
            device_id,
            result_type,
            payload_json,
            captured_at,
            project_uuid,
            point_index,
            job_id,
            source,
            &error_message
        );

        if (!error_message.empty()) {
            return http_response("500 Internal Server Error", std::string("{\"error\":\"") + json::escape(error_message) + "\"}");
        }
        return http_response("200 OK", payload.stringify(2));
    } catch (const std::exception& error) {
        return http_response("400 Bad Request", std::string("{\"error\":\"") + json::escape(error.what()) + "\"}");
    }
}

std::string LocalNodeApiServer::handle_index_post() {
    std::string error_message;
    const bool indexed = storage_.sync_archive_index(&error_message);
    const json::Value payload(make_object({
        {"indexed", indexed},
        {"error", error_message},
        {"storage", storage_.summary_json()}
    }));
    return http_response(indexed ? "200 OK" : "500 Internal Server Error", payload.stringify(2));
}

void LocalNodeApiServer::log(const std::string& level, const std::string& message) const {
    if (log_fn_) {
        log_fn_(level, message);
    }
}

} // namespace vino::desktop
