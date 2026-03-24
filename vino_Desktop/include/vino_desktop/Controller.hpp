#pragma once

#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "vino_desktop/DeviceRegistry.hpp"
#include "vino_desktop/Protocol.hpp"

namespace vino::desktop {

struct OutboundOperation {
    std::vector<std::string> target_device_ids {};
    std::string action {};
    TriggerContext context {};
    json::Value payload {};
};

struct ModelTransferSnapshot {
    std::string transfer_id {};
    std::string device_id {};
    std::string model_id {};
    std::string model_name {};
    std::string version {};
    std::string file_path {};
    std::string stage {};
    std::string local_status {};
    std::string remote_status {};
    std::string remote_message {};
    std::string updated_at {};
    std::size_t byte_count {0};
    std::size_t bytes_sent {0};
    int chunk_count {0};
    int chunks_sent {0};
    int chunks_acked {0};
    bool finished {false};
};

class DesktopController {
public:
    using LogFn = std::function<void(const std::string&, const std::string&)>;

    explicit DesktopController(LogFn log_fn = {});
    ~DesktopController();

    bool connect_to_device(const std::string& host, int port = PortMap::control);
    int scan_prefix(const std::string& prefix, int start, int end, int port = PortMap::control);
    json::Value dispatch(const OutboundOperation& operation);
    json::Value install_model(
        const std::vector<std::string>& target_device_ids,
        const std::string& file_path,
        const std::string& model_id,
        const std::string& model_name,
        const std::string& version,
        bool activate_after_install
    );
    std::vector<DeviceSnapshot> list_devices() const;
    std::vector<ModelTransferSnapshot> list_model_transfers() const;
    json::Value list_devices_json() const;
    bool set_alias(const std::string& device_id, const std::string& alias);
    void load_aliases(const std::map<std::string, std::string>& aliases);
    std::map<std::string, std::string> aliases() const;
    void stop();

private:
    struct Session;
    struct FileAssembly;
    struct PendingReply;

    void log(const std::string& level, const std::string& message) const;
    void register_session(const std::shared_ptr<Session>& session);
    void unregister_session(const std::shared_ptr<Session>& session);
    void reader_loop(const std::shared_ptr<Session>& session);
    void handle_line(const std::shared_ptr<Session>& session, const std::string& line);
    void handle_media_message(const std::string& action, const json::Value& payload, const std::string& device_id, const std::string& timestamp);
    bool send_envelope(const std::shared_ptr<Session>& session, const OutboundOperation& operation, std::string* out_message_id = nullptr);
    std::shared_ptr<Session> session_for_device_id(const std::string& device_id) const;
    static std::string next_message_id();
    static std::string timestamp_now();
    void register_pending_reply(const std::string& message_id, const PendingReply& pending_reply);
    void update_transfer_local_progress(
        const std::string& transfer_id,
        const std::string& stage,
        const std::string& local_status,
        std::size_t bytes_sent,
        int chunks_sent,
        const std::string& remote_message = {}
    );
    void finalize_transfer(
        const std::string& transfer_id,
        const std::string& stage,
        const std::string& local_status,
        const std::string& remote_status,
        const std::string& remote_message,
        bool finished
    );

    DeviceRegistry registry_;
    LogFn log_fn_;

    mutable std::mutex sessions_mutex_;
    std::map<std::string, std::shared_ptr<Session>> sessions_by_host_;
    std::map<std::string, std::shared_ptr<Session>> sessions_by_device_id_;

    mutable std::mutex files_mutex_;
    std::map<std::string, FileAssembly> file_assemblies_;

    mutable std::mutex transfers_mutex_;
    std::map<std::string, ModelTransferSnapshot> model_transfers_;
    std::map<std::string, PendingReply> pending_replies_;
};

} // namespace vino::desktop
