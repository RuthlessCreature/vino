#pragma once

#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

#include "vino_desktop/MiniJson.hpp"

struct sqlite3;

namespace vino::desktop {

struct LocalNodeOutboxJob {
    std::string jobID {};
    std::string jobType {};
    std::string refID {};
    std::string cloudEndpoint {};
    std::string status {};
    int retryCount {0};
    std::string lastError {};
    std::string updatedAt {};
};

struct LocalNodeCloudSyncConfig {
    bool enabled {false};
    std::string baseURL {};
    std::string lastFlushAt {};
    std::string lastFlushStatus {"idle"};
    std::string lastError {};
};

class LocalNodeStorage {
public:
    LocalNodeStorage();
    ~LocalNodeStorage();

    bool start(std::string* out_error = nullptr);
    void stop();

    bool sync_archive_index(std::string* out_error = nullptr);
    json::Value ingest_asset_json(
        const std::string& device_id,
        const std::string& file_name,
        const std::string& category,
        const std::string& captured_at,
        const std::string& content_base64,
        const std::string& project_uuid,
        int point_index,
        const std::string& job_id,
        std::string* out_error = nullptr
    );
    json::Value ingest_log_json(
        const std::string& log_id,
        const std::string& device_id,
        const std::string& level,
        const std::string& category,
        const std::string& message,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& source,
        std::string* out_error = nullptr
    );
    json::Value ingest_stat_json(
        const std::string& stat_id,
        const std::string& device_id,
        const std::string& metric,
        const std::string& value_text,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& source,
        std::string* out_error = nullptr
    );
    json::Value ingest_result_json(
        const std::string& result_id,
        const std::string& device_id,
        const std::string& result_type,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& project_uuid,
        int point_index,
        const std::string& job_id,
        const std::string& source,
        std::string* out_error = nullptr
    );

    [[nodiscard]] json::Value summary_json() const;
    [[nodiscard]] LocalNodeCloudSyncConfig cloud_sync_config() const;
    [[nodiscard]] json::Value cloud_sync_config_json() const;
    [[nodiscard]] json::Value list_assets_json(int limit = 100) const;
    [[nodiscard]] json::Value find_asset_json(const std::string& asset_id) const;
    [[nodiscard]] json::Value list_logs_json(int limit = 100) const;
    [[nodiscard]] json::Value list_stats_json(int limit = 100) const;
    [[nodiscard]] json::Value list_results_json(int limit = 100) const;
    [[nodiscard]] json::Value list_outbox_json(int limit = 100) const;
    [[nodiscard]] std::vector<LocalNodeOutboxJob> pending_outbox_jobs(int limit = 100) const;

    bool update_cloud_sync_config(const std::string& base_url, bool enabled, std::string* out_error = nullptr);
    bool record_cloud_sync_result(
        const std::string& flush_status,
        const std::string& last_error,
        const std::string& flushed_at,
        std::string* out_error = nullptr
    );
    bool build_cloud_request_body(const LocalNodeOutboxJob& job, std::string* out_body, std::string* out_error = nullptr) const;
    bool mark_outbox_job_success(const LocalNodeOutboxJob& job, const std::string& updated_at, std::string* out_error = nullptr);
    bool mark_outbox_job_failure(const LocalNodeOutboxJob& job, const std::string& error_message, const std::string& updated_at, std::string* out_error = nullptr);

private:
    static std::filesystem::path database_path();
    static std::filesystem::path archive_root();

    bool open_database(std::string* out_error);
    bool initialize_schema(std::string* out_error);
    bool execute_sql(const std::string& sql, std::string* out_error);
    bool upsert_asset(
        const std::string& asset_id,
        const std::string& device_id,
        const std::string& category,
        const std::string& file_path,
        const std::string& file_name,
        std::uintmax_t byte_count,
        const std::string& captured_at,
        const std::string& updated_at,
        const std::string& project_uuid,
        int point_index,
        const std::string& job_id,
        const std::string& source,
        std::string* out_error
    );
    bool upsert_log(
        const std::string& log_id,
        const std::string& device_id,
        const std::string& level,
        const std::string& category,
        const std::string& message,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& source,
        std::string* out_error
    );
    bool upsert_stat(
        const std::string& stat_id,
        const std::string& device_id,
        const std::string& metric,
        const std::string& value_text,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& source,
        std::string* out_error
    );
    bool upsert_result(
        const std::string& result_id,
        const std::string& device_id,
        const std::string& result_type,
        const std::string& payload_json,
        const std::string& captured_at,
        const std::string& project_uuid,
        int point_index,
        const std::string& job_id,
        const std::string& source,
        std::string* out_error
    );
    bool enqueue_outbox_job(
        const std::string& job_id,
        const std::string& job_type,
        const std::string& ref_id,
        const std::string& cloud_endpoint,
        const std::string& status,
        const std::string& last_error,
        const std::string& updated_at,
        std::string* out_error
    );
    [[nodiscard]] std::string setting_value_locked(const std::string& key, const std::string& fallback = "") const;
    bool upsert_setting_locked(const std::string& key, const std::string& value, const std::string& updated_at, std::string* out_error);
    [[nodiscard]] LocalNodeCloudSyncConfig cloud_sync_config_locked() const;
    bool update_asset_cloud_status_locked(const std::string& asset_id, const std::string& cloud_status, std::string* out_error);

    mutable std::mutex mutex_;
    sqlite3* database_ {nullptr};
    std::string last_sync_at_ {};
};

} // namespace vino::desktop
