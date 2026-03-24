#include "vino_desktop/Controller.hpp"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <thread>

#if defined(_WIN32)
#include <winsock2.h>
#include <ws2tcpip.h>
using socket_handle = SOCKET;
constexpr socket_handle invalid_socket_handle = INVALID_SOCKET;
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
using socket_handle = int;
constexpr socket_handle invalid_socket_handle = -1;
#endif

namespace vino::desktop {

namespace {

std::string iso_timestamp_now() {
    const auto now = std::chrono::system_clock::now();
    const auto seconds = std::chrono::system_clock::to_time_t(now);
    std::tm time_info {};
#if defined(_WIN32)
    gmtime_s(&time_info, &seconds);
#else
    gmtime_r(&seconds, &time_info);
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

#if !defined(_WIN32)
        const int flags = fcntl(handle, F_GETFL, 0);
        fcntl(handle, F_SETFL, flags | O_NONBLOCK);
#endif

        const int status = ::connect(handle, pointer->ai_addr, static_cast<socklen_t>(pointer->ai_addrlen));
        if (status == 0) {
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

        const int ready = select(handle + 1, nullptr, &write_set, nullptr, &timeout);
        if (ready > 0 && FD_ISSET(handle, &write_set)) {
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
        const auto sent = ::send(
            handle,
            payload.data() + offset,
            static_cast<int>(payload.size() - offset),
            0
        );

        if (sent <= 0) {
            return false;
        }

        offset += static_cast<std::size_t>(sent);
    }
    return true;
}

std::string base64_encode(std::string_view input) {
    static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    std::string output;
    output.reserve(((input.size() + 2) / 3) * 4);

    std::size_t index = 0;
    while (index + 3 <= input.size()) {
        const unsigned value =
            (static_cast<unsigned char>(input[index]) << 16) |
            (static_cast<unsigned char>(input[index + 1]) << 8) |
            static_cast<unsigned char>(input[index + 2]);

        output.push_back(table[(value >> 18) & 0x3F]);
        output.push_back(table[(value >> 12) & 0x3F]);
        output.push_back(table[(value >> 6) & 0x3F]);
        output.push_back(table[value & 0x3F]);
        index += 3;
    }

    const std::size_t remaining = input.size() - index;
    if (remaining == 1) {
        const unsigned value = static_cast<unsigned char>(input[index]) << 16;
        output.push_back(table[(value >> 18) & 0x3F]);
        output.push_back(table[(value >> 12) & 0x3F]);
        output.push_back('=');
        output.push_back('=');
    } else if (remaining == 2) {
        const unsigned value =
            (static_cast<unsigned char>(input[index]) << 16) |
            (static_cast<unsigned char>(input[index + 1]) << 8);
        output.push_back(table[(value >> 18) & 0x3F]);
        output.push_back(table[(value >> 12) & 0x3F]);
        output.push_back(table[(value >> 6) & 0x3F]);
        output.push_back('=');
    }

    return output;
}

std::string base64_decode(const std::string& input) {
    static constexpr unsigned char decoding_table[256] = {
        64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64,64,64,64,62,64,64,64,63,52,53,54,55,56,57,58,59,60,61,64,64,64,65,64,64,
        64, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,64,64,64,64,64,
        64,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,64,64,64,64,64,
        64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,
        64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64,64
    };

    std::string output;
    int value = 0;
    int bits = -8;

    for (const unsigned char character : input) {
        if (character == '=') {
            break;
        }

        const unsigned char decoded = decoding_table[character];
        if (decoded >= 64) {
            continue;
        }

        value = (value << 6) + decoded;
        bits += 6;

        if (bits >= 0) {
            output.push_back(static_cast<char>((value >> bits) & 0xFF));
            bits -= 8;
        }
    }

    return output;
}

json::Value::Object make_object(std::initializer_list<std::pair<const std::string, json::Value>> items) {
    return json::Value::Object(items);
}

} // namespace

struct DesktopController::Session {
    std::string host {};
    int port {0};
    socket_handle socket {invalid_socket_handle};
    std::atomic<bool> running {true};
    std::thread reader_thread {};
    mutable std::mutex write_mutex {};
    std::string device_id {};
    std::string buffer {};
};

struct DesktopController::FileAssembly {
    std::ofstream stream {};
    std::filesystem::path path {};
    std::string category {};
};

struct DesktopController::PendingReply {
    std::string transfer_id {};
    std::string device_id {};
    std::string stage {};
    std::string action {};
};

DesktopController::DesktopController(LogFn log_fn)
    : log_fn_(std::move(log_fn)) {}

DesktopController::~DesktopController() {
    stop();
}

bool DesktopController::connect_to_device(const std::string& host, int port) {
    {
        std::scoped_lock lock(sessions_mutex_);
        const auto key = host + ":" + std::to_string(port);
        if (const auto iterator = sessions_by_host_.find(key); iterator != sessions_by_host_.end()) {
            if (iterator->second && iterator->second->running) {
                log("INFO", "already connected to " + key);
                return true;
            }
        }
    }

    const auto socket = connect_with_timeout(host, port, 250);
    if (socket == invalid_socket_handle) {
        return false;
    }

    auto session = std::make_shared<Session>();
    session->host = host;
    session->port = port;
    session->socket = socket;

    register_session(session);
    registry_.upsert_connected_host(host, port);

    session->reader_thread = std::thread([this, session] {
        reader_loop(session);
    });

    log("INFO", "connected to " + host + ":" + std::to_string(port));
    return true;
}

int DesktopController::scan_prefix(const std::string& prefix, int start, int end, int port) {
    int found = 0;
    for (int value = start; value <= end; ++value) {
        const auto host = prefix + "." + std::to_string(value);
        if (connect_to_device(host, port)) {
            ++found;
        }
    }
    return found;
}

json::Value DesktopController::dispatch(const OutboundOperation& operation) {
    json::Value::Array results;

    for (const auto& device_id : operation.target_device_ids) {
        auto session = session_for_device_id(device_id);
        if (!session) {
            results.push_back(make_object({
                {"deviceId", device_id},
                {"status", "offline"},
                {"action", operation.action},
            }));
            continue;
        }

        OutboundOperation single_target = operation;
        single_target.target_device_ids = {device_id};
        const bool sent = send_envelope(session, single_target);
        results.push_back(make_object({
            {"deviceId", device_id},
            {"status", sent ? "queued" : "send_failed"},
            {"action", operation.action},
        }));
    }

    return make_object({{"results", results}});
}

json::Value DesktopController::install_model(
    const std::vector<std::string>& target_device_ids,
    const std::string& file_path,
    const std::string& model_id,
    const std::string& model_name,
    const std::string& version,
    bool activate_after_install
) {
    std::ifstream stream(file_path, std::ios::binary);
    if (!stream) {
        return make_object({
            {"status", "file_open_failed"},
            {"filePath", file_path}
        });
    }

    stream.seekg(0, std::ios::end);
    const auto byte_count = static_cast<std::size_t>(stream.tellg());
    stream.seekg(0, std::ios::beg);

    std::vector<char> file_data(byte_count);
    if (byte_count > 0) {
        stream.read(file_data.data(), static_cast<std::streamsize>(byte_count));
    }

    json::Value::Array results;
    constexpr std::size_t chunk_size = 256 * 1024;
    const int total_chunks = static_cast<int>((byte_count + chunk_size - 1) / chunk_size);

    for (const auto& device_id : target_device_ids) {
        auto session = session_for_device_id(device_id);
        if (!session) {
            results.push_back(make_object({
                {"deviceId", device_id},
                {"status", "offline"},
                {"action", "inference.model.install"}
            }));
            continue;
        }

        const std::string transfer_id = "model-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
        {
            std::scoped_lock lock(transfers_mutex_);
            model_transfers_[transfer_id] = ModelTransferSnapshot{
                .transfer_id = transfer_id,
                .device_id = device_id,
                .model_id = model_id,
                .model_name = model_name,
                .version = version,
                .file_path = file_path,
                .stage = "begin",
                .local_status = "queued",
                .remote_status = "pending",
                .remote_message = "waiting for device reply",
                .updated_at = DesktopController::timestamp_now(),
                .byte_count = byte_count,
                .bytes_sent = 0,
                .chunk_count = total_chunks,
                .chunks_sent = 0,
                .chunks_acked = 0,
                .finished = false
            };
        }

        bool success = true;
        std::string message_id;

        OutboundOperation begin_operation;
        begin_operation.target_device_ids = {device_id};
        begin_operation.action = "inference.model.install.begin";
        begin_operation.payload = make_object({
            {"transferId", transfer_id},
            {"modelId", model_id},
            {"modelName", model_name},
            {"version", version},
            {"fileName", std::filesystem::path(file_path).filename().string()}
        });

        update_transfer_local_progress(transfer_id, "begin", "sending", 0, 0);
        success = send_envelope(session, begin_operation, &message_id);
        if (success) {
            register_pending_reply(message_id, PendingReply{
                .transfer_id = transfer_id,
                .device_id = device_id,
                .stage = "begin",
                .action = begin_operation.action
            });
            update_transfer_local_progress(transfer_id, "begin", "awaiting_reply", 0, 0);
        }

        if (success) {
            std::size_t offset = 0;
            int chunks_sent = 0;
            while (offset < file_data.size() && success) {
                const std::size_t chunk_end = std::min(offset + chunk_size, file_data.size());
                const std::string_view chunk(file_data.data() + offset, chunk_end - offset);

                OutboundOperation chunk_operation;
                chunk_operation.target_device_ids = {device_id};
                chunk_operation.action = "inference.model.install.chunk";
                chunk_operation.payload = make_object({
                    {"transferId", transfer_id},
                    {"chunkBase64", base64_encode(chunk)}
                });

                message_id.clear();
                success = send_envelope(session, chunk_operation, &message_id);
                if (success) {
                    ++chunks_sent;
                    register_pending_reply(message_id, PendingReply{
                        .transfer_id = transfer_id,
                        .device_id = device_id,
                        .stage = "chunk",
                        .action = chunk_operation.action
                    });
                    update_transfer_local_progress(transfer_id, "streaming", "sending", chunk_end, chunks_sent);
                }
                offset = chunk_end;
            }
        }

        if (success) {
            OutboundOperation commit_operation;
            commit_operation.target_device_ids = {device_id};
            commit_operation.action = "inference.model.install.commit";
            commit_operation.payload = make_object({
                {"transferId", transfer_id},
                {"activateAfterInstall", activate_after_install}
            });
            message_id.clear();
            update_transfer_local_progress(transfer_id, "commit", "sending", byte_count, total_chunks);
            success = send_envelope(session, commit_operation, &message_id);
            if (success) {
                register_pending_reply(message_id, PendingReply{
                    .transfer_id = transfer_id,
                    .device_id = device_id,
                    .stage = "commit",
                    .action = commit_operation.action
                });
                update_transfer_local_progress(transfer_id, "commit", "awaiting_reply", byte_count, total_chunks);
            }
        }

        if (!success) {
            finalize_transfer(
                transfer_id,
                "failed",
                "send_failed",
                "send_failed",
                "desktop failed while streaming model payload",
                true
            );
        }

        results.push_back(make_object({
            {"deviceId", device_id},
            {"status", success ? "queued" : "send_failed"},
            {"action", "inference.model.install"},
            {"transferId", transfer_id},
            {"byteCount", static_cast<int>(byte_count)}
        }));
    }

    return make_object({
        {"results", results},
        {"filePath", file_path},
        {"modelId", model_id},
        {"modelName", model_name},
        {"version", version}
    });
}

std::vector<DeviceSnapshot> DesktopController::list_devices() const {
    return registry_.list();
}

std::vector<ModelTransferSnapshot> DesktopController::list_model_transfers() const {
    std::scoped_lock lock(transfers_mutex_);
    std::vector<ModelTransferSnapshot> transfers;
    transfers.reserve(model_transfers_.size());
    for (const auto& [_, snapshot] : model_transfers_) {
        transfers.push_back(snapshot);
    }
    std::sort(transfers.begin(), transfers.end(), [](const ModelTransferSnapshot& lhs, const ModelTransferSnapshot& rhs) {
        return lhs.updated_at > rhs.updated_at;
    });
    return transfers;
}

json::Value DesktopController::list_devices_json() const {
    return registry_.to_json();
}

bool DesktopController::set_alias(const std::string& device_id, const std::string& alias) {
    return registry_.set_alias(device_id, alias);
}

void DesktopController::load_aliases(const std::map<std::string, std::string>& aliases) {
    registry_.load_aliases(aliases);
}

std::map<std::string, std::string> DesktopController::aliases() const {
    return registry_.aliases();
}

void DesktopController::stop() {
    std::vector<std::shared_ptr<Session>> sessions;
    {
        std::scoped_lock lock(sessions_mutex_);
        for (const auto& [_, session] : sessions_by_host_) {
            sessions.push_back(session);
        }
        sessions_by_host_.clear();
        sessions_by_device_id_.clear();
    }

    for (const auto& session : sessions) {
        session->running = false;
        close_socket(session->socket);
        if (session->reader_thread.joinable()) {
            session->reader_thread.join();
        }
    }
}

void DesktopController::log(const std::string& level, const std::string& message) const {
    if (log_fn_) {
        log_fn_(level, message);
    }
}

void DesktopController::register_session(const std::shared_ptr<Session>& session) {
    std::scoped_lock lock(sessions_mutex_);
    sessions_by_host_[session->host + ":" + std::to_string(session->port)] = session;
}

void DesktopController::unregister_session(const std::shared_ptr<Session>& session) {
    std::scoped_lock lock(sessions_mutex_);
    sessions_by_host_.erase(session->host + ":" + std::to_string(session->port));
    if (!session->device_id.empty()) {
        sessions_by_device_id_.erase(session->device_id);
    }
}

void DesktopController::reader_loop(const std::shared_ptr<Session>& session) {
    char read_buffer[4096];

    while (session->running) {
        const auto bytes_read = recv(session->socket, read_buffer, sizeof(read_buffer), 0);
        if (bytes_read <= 0) {
            break;
        }

        session->buffer.append(read_buffer, read_buffer + bytes_read);

        while (true) {
            const auto newline = session->buffer.find('\n');
            if (newline == std::string::npos) {
                break;
            }

            std::string line = session->buffer.substr(0, newline);
            session->buffer.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            if (!line.empty()) {
                handle_line(session, line);
            }
        }
    }

    registry_.mark_disconnected_host(session->host, session->port);
    unregister_session(session);
    close_socket(session->socket);
    log("WARN", "disconnected from " + session->host + ":" + std::to_string(session->port));
}

void DesktopController::handle_line(const std::shared_ptr<Session>& session, const std::string& line) {
    try {
        const auto root = json::parse(line);
        const auto& object = root.as_object();

        const auto timestamp = object.contains("timestamp") ? object.at("timestamp").as_string() : DesktopController::timestamp_now();
        std::string action = object.contains("action") ? object.at("action").as_string() : "";
        std::string device_id = session->device_id;
        const std::string kind = object.contains("kind") ? object.at("kind").as_string() : "";

        if (const auto source = root.find("source"); source != nullptr && source->is_object()) {
            if (const auto source_device = source->find("deviceId"); source_device != nullptr && source_device->is_string()) {
                device_id = source_device->as_string();
            }
        }

        if (!device_id.empty()) {
            session->device_id = device_id;
            std::scoped_lock lock(sessions_mutex_);
            sessions_by_device_id_[device_id] = session;
        }

        const json::Value payload = root.contains("payload") ? root.at("payload") : json::Value(nullptr);

        if (kind == "reply") {
            const std::string correlation_id = object.contains("correlationId") && object.at("correlationId").is_string()
                ? object.at("correlationId").as_string()
                : "";
            const std::string status = payload.is_object() && payload.contains("status") ? payload.at("status").as_string() : "unknown";
            const std::string message = payload.is_object() && payload.contains("message") ? payload.at("message").as_string() : "";

            bool matched_transfer = false;
            PendingReply pending_reply;
            if (!correlation_id.empty()) {
                std::scoped_lock lock(transfers_mutex_);
                if (const auto iterator = pending_replies_.find(correlation_id); iterator != pending_replies_.end()) {
                    pending_reply = iterator->second;
                    pending_replies_.erase(iterator);
                    matched_transfer = true;
                }
            }

            if (matched_transfer) {
                if (status == "accepted") {
                    if (pending_reply.stage == "chunk") {
                        std::scoped_lock lock(transfers_mutex_);
                        if (const auto iterator = model_transfers_.find(pending_reply.transfer_id); iterator != model_transfers_.end()) {
                            iterator->second.chunks_acked = std::min(iterator->second.chunk_count, iterator->second.chunks_acked + 1);
                            iterator->second.remote_status = status;
                            iterator->second.remote_message = message;
                            iterator->second.updated_at = timestamp;
                        }
                    } else if (pending_reply.stage == "commit") {
                        finalize_transfer(pending_reply.transfer_id, "completed", "completed", status, message, true);
                    } else {
                        update_transfer_local_progress(
                            pending_reply.transfer_id,
                            pending_reply.stage == "begin" ? "streaming" : pending_reply.stage,
                            "sending",
                            0,
                            0,
                            message
                        );
                        std::scoped_lock lock(transfers_mutex_);
                        if (const auto iterator = model_transfers_.find(pending_reply.transfer_id); iterator != model_transfers_.end()) {
                            iterator->second.remote_status = status;
                            iterator->second.remote_message = message;
                            iterator->second.updated_at = timestamp;
                        }
                    }
                } else {
                    finalize_transfer(pending_reply.transfer_id, "failed", "rejected", status, message, true);
                }
            }

            registry_.mark_seen(device_id, timestamp, action.empty() ? "reply" : action);
            log(status == "accepted" ? "INFO" : "WARN", (device_id.empty() ? session->host : device_id) + " reply " + action + " " + status + (message.empty() ? "" : (" · " + message)));
            return;
        }

        if (action == "device.hello") {
            std::string name;
            if (const auto source = root.find("source"); source != nullptr && source->is_object()) {
                if (const auto name_value = source->find("name"); name_value != nullptr && name_value->is_string()) {
                    name = name_value->as_string();
                }
            }
            registry_.apply_hello(session->host, session->port, device_id, name, timestamp, payload);
            log("INFO", device_id + " hello from " + session->host);
            return;
        }

        if (action == "device.status.push") {
            registry_.apply_status(device_id, timestamp, payload, action);
            log("INFO", device_id + " status updated");
            return;
        }

        if (action == "camera.capabilities.report") {
            registry_.apply_capabilities(device_id, payload);
            log("INFO", device_id + " capabilities updated");
            return;
        }

        if (action == "inference.result.push") {
            registry_.apply_inference(device_id, timestamp, payload);
            int detections = 0;
            if (const auto* detections_value = payload.find("detections"); detections_value != nullptr && detections_value->is_array()) {
                detections = static_cast<int>(detections_value->as_array().size());
            }
            log("INFO", device_id + " inference result push detections=" + std::to_string(detections));
            return;
        }

        if (action == "preview.frame.push") {
            if (payload.is_object()) {
                registry_.apply_preview(
                    device_id,
                    timestamp,
                    payload.contains("jpegBase64") ? payload.at("jpegBase64").as_string() : "",
                    payload.contains("imageWidth") ? payload.at("imageWidth").as_int() : 0,
                    payload.contains("imageHeight") ? payload.at("imageHeight").as_int() : 0,
                    payload.contains("frameIndex") ? payload.at("frameIndex").as_int() : 0
                );
            }
            log("INFO", device_id + " preview frame updated");
            return;
        }

        if (action == "media.push.begin" || action == "media.push.chunk" || action == "media.push.commit") {
            handle_media_message(action, payload, device_id, timestamp);
            registry_.mark_seen(device_id, timestamp, action);
            return;
        }

        registry_.mark_seen(device_id, timestamp, action.empty() ? "message" : action);
        log("INFO", (device_id.empty() ? session->host : device_id) + " -> " + (action.empty() ? "message" : action));
    } catch (const std::exception& error) {
        log("ERROR", "failed to parse device message: " + std::string(error.what()));
    }
}

void DesktopController::handle_media_message(const std::string& action, const json::Value& payload, const std::string& device_id, const std::string& timestamp) {
    const auto* transfer_id_value = payload.find("transferId");
    if (transfer_id_value == nullptr || !transfer_id_value->is_string()) {
        return;
    }

    const std::string transfer_id = transfer_id_value->as_string();
    const std::filesystem::path runtime_root = std::filesystem::current_path() / "vino_Desktop_runtime" / "media" / device_id;
    std::filesystem::create_directories(runtime_root);

    if (action == "media.push.begin") {
        const auto file_name = payload.contains("fileName") ? payload.at("fileName").as_string() : (transfer_id + ".bin");
        FileAssembly assembly;
        assembly.path = runtime_root / file_name;
        assembly.category = payload.contains("category") ? payload.at("category").as_string() : "";
        assembly.stream.open(assembly.path, std::ios::binary);

        std::scoped_lock lock(files_mutex_);
        file_assemblies_[transfer_id] = std::move(assembly);
        log("INFO", "receiving media " + assembly.path.string());
        return;
    }

    if (action == "media.push.chunk") {
        const auto* chunk_value = payload.find("chunkBase64");
        if (chunk_value == nullptr || !chunk_value->is_string()) {
            return;
        }

        std::scoped_lock lock(files_mutex_);
        const auto iterator = file_assemblies_.find(transfer_id);
        if (iterator == file_assemblies_.end()) {
            return;
        }

        const std::string binary = base64_decode(chunk_value->as_string());
        iterator->second.stream.write(binary.data(), static_cast<std::streamsize>(binary.size()));
        return;
    }

    if (action == "media.push.commit") {
        std::scoped_lock lock(files_mutex_);
        const auto iterator = file_assemblies_.find(transfer_id);
        if (iterator == file_assemblies_.end()) {
            return;
        }
        iterator->second.stream.flush();
        iterator->second.stream.close();
        log("INFO", "saved media " + iterator->second.path.string());
        registry_.apply_media(device_id, timestamp, iterator->second.path.string(), iterator->second.category);
        file_assemblies_.erase(iterator);
    }
}

bool DesktopController::send_envelope(const std::shared_ptr<Session>& session, const OutboundOperation& operation, std::string* out_message_id) {
    json::Value::Array device_ids;
    for (const auto& target_id : operation.target_device_ids) {
        device_ids.push_back(target_id);
    }

    const std::string message_id = next_message_id();

    const json::Value envelope = make_object({
        {"protocol", "vino.control/1"},
        {"messageId", message_id},
        {"correlationId", json::Value(nullptr)},
        {"kind", "command"},
        {"action", operation.action},
        {"timestamp", DesktopController::timestamp_now()},
        {"source", make_object({
            {"role", "desktop"},
            {"deviceId", "desktop-main"},
            {"name", "vino desktop"}
        })},
        {"target", make_object({
            {"deviceIds", device_ids}
        })},
        {"context", make_object({
            {"productUUID", operation.context.product_uuid},
            {"pointIndex", operation.context.point_index},
            {"jobId", operation.context.job_id}
        })},
        {"payload", operation.payload}
    });

    const auto payload = envelope.stringify() + "\n";

    std::scoped_lock lock(session->write_mutex);
    const bool sent = socket_send_all(session->socket, payload);
    if (sent && out_message_id != nullptr) {
        *out_message_id = message_id;
    }
    return sent;
}

std::string DesktopController::next_message_id() {
    return "desktop-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
}

std::string DesktopController::timestamp_now() {
    return iso_timestamp_now();
}

void DesktopController::register_pending_reply(const std::string& message_id, const PendingReply& pending_reply) {
    if (message_id.empty()) {
        return;
    }
    std::scoped_lock lock(transfers_mutex_);
    pending_replies_[message_id] = pending_reply;
}

void DesktopController::update_transfer_local_progress(
    const std::string& transfer_id,
    const std::string& stage,
    const std::string& local_status,
    std::size_t bytes_sent,
    int chunks_sent,
    const std::string& remote_message
) {
    std::scoped_lock lock(transfers_mutex_);
    const auto iterator = model_transfers_.find(transfer_id);
    if (iterator == model_transfers_.end()) {
        return;
    }

    iterator->second.stage = stage;
    iterator->second.local_status = local_status;
    iterator->second.bytes_sent = std::max(iterator->second.bytes_sent, bytes_sent);
    iterator->second.chunks_sent = std::max(iterator->second.chunks_sent, chunks_sent);
    iterator->second.updated_at = DesktopController::timestamp_now();
    if (!remote_message.empty()) {
        iterator->second.remote_message = remote_message;
    }
}

void DesktopController::finalize_transfer(
    const std::string& transfer_id,
    const std::string& stage,
    const std::string& local_status,
    const std::string& remote_status,
    const std::string& remote_message,
    bool finished
) {
    std::scoped_lock lock(transfers_mutex_);
    const auto iterator = model_transfers_.find(transfer_id);
    if (iterator == model_transfers_.end()) {
        return;
    }

    iterator->second.stage = stage;
    iterator->second.local_status = local_status;
    iterator->second.remote_status = remote_status;
    iterator->second.remote_message = remote_message;
    iterator->second.bytes_sent = iterator->second.byte_count;
    iterator->second.chunks_sent = iterator->second.chunk_count;
    iterator->second.finished = finished;
    iterator->second.updated_at = DesktopController::timestamp_now();
}

std::shared_ptr<DesktopController::Session> DesktopController::session_for_device_id(const std::string& device_id) const {
    std::scoped_lock lock(sessions_mutex_);
    const auto iterator = sessions_by_device_id_.find(device_id);
    if (iterator == sessions_by_device_id_.end()) {
        return nullptr;
    }
    return iterator->second;
}

} // namespace vino::desktop
