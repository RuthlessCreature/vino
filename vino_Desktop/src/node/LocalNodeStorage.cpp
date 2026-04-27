#include "vino_desktop/LocalNodeStorage.hpp"
#include "vino_desktop/RuntimePaths.hpp"

#include <chrono>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <sstream>

#include <sqlite3.h>

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

std::string file_time_to_iso8601(std::filesystem::file_time_type value) {
    const auto adjusted = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
        value - std::filesystem::file_time_type::clock::now() + std::chrono::system_clock::now()
    );
    const auto time = std::chrono::system_clock::to_time_t(adjusted);

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

std::string trim_copy(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string normalize_http_base_url(std::string value) {
    value = trim_copy(std::move(value));
    if (value.empty()) {
        return {};
    }
    if (value.rfind("http://", 0) != 0 && value.rfind("https://", 0) != 0) {
        value = "http://" + value;
    }
    while (value.size() > 1 && value.back() == '/') {
        value.pop_back();
    }
    return value;
}

bool parse_bool_string(std::string value) {
    value = trim_copy(std::move(value));
    for (char& character : value) {
        character = static_cast<char>(std::tolower(static_cast<unsigned char>(character)));
    }
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

std::string infer_category(const std::filesystem::path& path) {
    const std::string extension = path.extension().string();
    if (extension == ".jpg" || extension == ".jpeg" || extension == ".png" || extension == ".heic") {
        return "image";
    }
    if (extension == ".mov" || extension == ".mp4" || extension == ".m4v") {
        return "video";
    }
    return "binary";
}

std::string sanitize_segment(std::string value, const std::string& fallback) {
    for (char& character : value) {
        const bool keep = std::isalnum(static_cast<unsigned char>(character)) || character == '.' || character == '_' || character == '-';
        if (!keep) {
            character = '_';
        }
    }
    while (!value.empty() && value.front() == '.') {
        value.erase(value.begin());
    }
    return value.empty() ? fallback : value;
}

std::string sanitize_extension(const std::string& value) {
    std::string output;
    for (const char character : value) {
        if (std::isalnum(static_cast<unsigned char>(character))) {
            output.push_back(character);
        }
    }
    return output.empty() ? std::string() : ("." + output);
}

std::string base64_decode(const std::string& input) {
    static constexpr unsigned char invalid = 0xFFu;
    static constexpr unsigned char table[256] = {
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, 62, invalid, invalid, invalid, 63,
        52, 53, 54, 55, 56, 57, 58, 59,
        60, 61, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, 0, 1, 2, 3, 4, 5, 6,
        7, 8, 9, 10, 11, 12, 13, 14,
        15, 16, 17, 18, 19, 20, 21, 22,
        23, 24, 25, invalid, invalid, invalid, invalid, invalid,
        invalid, 26, 27, 28, 29, 30, 31, 32,
        33, 34, 35, 36, 37, 38, 39, 40,
        41, 42, 43, 44, 45, 46, 47, 48,
        49, 50, 51, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid,
        invalid, invalid, invalid, invalid, invalid, invalid, invalid, invalid
    };

    std::string output;
    output.reserve((input.size() * 3) / 4);

    int val = 0;
    int bits = -8;
    for (const unsigned char character : input) {
        if (std::isspace(character)) {
            continue;
        }
        if (character == '=') {
            break;
        }
        const unsigned char decoded = table[character];
        if (decoded == invalid) {
            throw std::runtime_error("invalid base64 payload");
        }
        val = (val << 6) + decoded;
        bits += 6;
        if (bits >= 0) {
            output.push_back(static_cast<char>((val >> bits) & 0xFF));
            bits -= 8;
        }
    }
    return output;
}

std::string to_hex(std::uint64_t value) {
    std::ostringstream stream;
    stream << std::hex << value;
    return stream.str();
}

std::string make_asset_id(std::string_view input) {
    constexpr std::uint64_t basis = 1469598103934665603ULL;
    constexpr std::uint64_t prime = 1099511628211ULL;

    std::uint64_t hash = basis;
    for (const unsigned char byte : input) {
        hash ^= byte;
        hash *= prime;
    }
    return "asset-" + to_hex(hash);
}

std::string make_prefixed_id(std::string_view prefix, std::string_view input) {
    return std::string(prefix) + "-" + make_asset_id(input).substr(6);
}

std::string column_text(sqlite3_stmt* statement, int index) {
    const unsigned char* text = sqlite3_column_text(statement, index);
    return text == nullptr ? std::string() : std::string(reinterpret_cast<const char*>(text));
}

sqlite3_int64 select_single_int64(sqlite3* database, const char* sql) {
    sqlite3_stmt* statement = nullptr;
    sqlite3_int64 value = 0;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) == SQLITE_OK) {
        if (sqlite3_step(statement) == SQLITE_ROW) {
            value = sqlite3_column_int64(statement, 0);
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return value;
}

std::string select_single_text(sqlite3* database, const char* sql) {
    sqlite3_stmt* statement = nullptr;
    std::string value;
    if (sqlite3_prepare_v2(database, sql, -1, &statement, nullptr) == SQLITE_OK) {
        if (sqlite3_step(statement) == SQLITE_ROW) {
            value = column_text(statement, 0);
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return value;
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

json::Value parse_json_or_string(const std::string& text) {
    if (text.empty()) {
        return json::Value(nullptr);
    }

    try {
        return json::parse(text);
    } catch (...) {
        return json::Value(text);
    }
}

} // namespace

LocalNodeStorage::LocalNodeStorage() = default;

LocalNodeStorage::~LocalNodeStorage() {
    stop();
}

bool LocalNodeStorage::start(std::string* out_error) {
    std::scoped_lock lock(mutex_);
    if (database_ != nullptr) {
        return true;
    }

    if (!open_database(out_error)) {
        return false;
    }

    if (!initialize_schema(out_error)) {
        sqlite3_close(database_);
        database_ = nullptr;
        return false;
    }

    return true;
}

void LocalNodeStorage::stop() {
    std::scoped_lock lock(mutex_);
    if (database_ != nullptr) {
        sqlite3_close(database_);
        database_ = nullptr;
    }
}

bool LocalNodeStorage::sync_archive_index(std::string* out_error) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return false;
    }
    if (!initialize_schema(out_error)) {
        return false;
    }

    const auto root = archive_root();
    std::error_code error_code;
    std::filesystem::create_directories(root, error_code);

    if (!execute_sql("BEGIN IMMEDIATE TRANSACTION;", out_error)) {
        return false;
    }

    bool ok = true;
    for (std::filesystem::recursive_directory_iterator iterator(root, std::filesystem::directory_options::skip_permission_denied, error_code), end;
         iterator != end;
         iterator.increment(error_code)) {
        if (error_code) {
            continue;
        }
        if (!iterator->is_regular_file(error_code) || error_code) {
            continue;
        }

        const auto absolute_path = iterator->path();
        const auto relative_path = std::filesystem::relative(absolute_path, root, error_code);
        if (error_code || relative_path.empty()) {
            continue;
        }

        auto relative_iterator = relative_path.begin();
        if (relative_iterator == relative_path.end()) {
            continue;
        }

        const std::string device_id = (*relative_iterator).string();
        const std::string file_path = absolute_path.string();
        const std::string file_name = absolute_path.filename().string();
        const std::string category = infer_category(absolute_path);
        const auto byte_count = std::filesystem::file_size(absolute_path, error_code);
        if (error_code) {
            continue;
        }
        const std::string captured_at = file_time_to_iso8601(std::filesystem::last_write_time(absolute_path, error_code));
        if (error_code) {
            continue;
        }

        const std::string asset_id = make_asset_id(file_path);
        const std::string updated_at = now_utc_iso8601();
        if (!upsert_asset(
                asset_id,
                device_id,
                category,
                file_path,
                file_name,
                byte_count,
                captured_at,
                updated_at,
                "",
                0,
                "",
                "archive-scan",
                out_error
            )) {
            ok = false;
            break;
        }
    }

    if (ok) {
        ok = execute_sql("COMMIT;", out_error);
    } else {
        (void)execute_sql("ROLLBACK;", nullptr);
    }

    if (ok) {
        last_sync_at_ = now_utc_iso8601();
    }
    return ok;
}

json::Value LocalNodeStorage::ingest_asset_json(
    const std::string& device_id,
    const std::string& file_name,
    const std::string& category,
    const std::string& captured_at,
    const std::string& content_base64,
    const std::string& project_uuid,
    int point_index,
    const std::string& job_id,
    std::string* out_error
) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return json::Value(nullptr);
    }
    if (!initialize_schema(out_error)) {
        return json::Value(nullptr);
    }

    const std::string safe_device_id = sanitize_segment(device_id, "unknown-device");
    const std::filesystem::path device_root = archive_root() / safe_device_id;
    std::error_code error_code;
    std::filesystem::create_directories(device_root, error_code);
    if (error_code) {
        if (out_error != nullptr) {
            *out_error = error_code.message();
        }
        return json::Value(nullptr);
    }

    const std::filesystem::path requested_name = std::filesystem::path(file_name).filename();
    const std::string extension = sanitize_extension(requested_name.extension().string());
    const std::string stem = sanitize_segment(requested_name.stem().string(), "capture");
    const std::string safe_name = stem + extension;
    std::filesystem::path target_path = device_root / safe_name;

    int suffix = 1;
    while (std::filesystem::exists(target_path, error_code)) {
        target_path = device_root / (stem + "-" + std::to_string(suffix) + extension);
        suffix += 1;
    }

    const std::string binary = base64_decode(content_base64);
    {
        std::ofstream stream(target_path, std::ios::binary | std::ios::trunc);
        if (!stream) {
            if (out_error != nullptr) {
                *out_error = "failed to open asset file for writing";
            }
            return json::Value(nullptr);
        }
        stream.write(binary.data(), static_cast<std::streamsize>(binary.size()));
    }

    const std::string normalized_category = category.empty() ? infer_category(target_path) : category;
    const std::string final_captured_at = captured_at.empty() ? now_utc_iso8601() : captured_at;
    const std::string updated_at = now_utc_iso8601();
    const std::string asset_id = make_asset_id(target_path.string());

    if (!upsert_asset(
            asset_id,
            safe_device_id,
            normalized_category,
            target_path.string(),
            target_path.filename().string(),
            binary.size(),
            final_captured_at,
            updated_at,
            project_uuid,
            point_index,
            job_id,
            "api.ingest.asset",
            out_error
        )) {
        return json::Value(nullptr);
    }

    last_sync_at_ = updated_at;
    (void)enqueue_outbox_job(
        make_prefixed_id("outbox", "asset:" + asset_id),
        "asset",
        asset_id,
        "/api/cloud/v1/ingest/asset",
        "pending",
        "",
        updated_at,
        out_error
    );

    return make_object({
        {"assetId", asset_id},
        {"deviceId", safe_device_id},
        {"category", normalized_category},
        {"filePath", target_path.string()},
        {"fileName", target_path.filename().string()},
        {"byteCount", static_cast<double>(binary.size())},
        {"capturedAt", final_captured_at},
        {"updatedAt", updated_at},
        {"productUUID", project_uuid},
        {"pointIndex", point_index},
        {"jobId", job_id},
        {"cloudStatus", "local_only"}
    });
}

json::Value LocalNodeStorage::ingest_log_json(
    const std::string& log_id,
    const std::string& device_id,
    const std::string& level,
    const std::string& category,
    const std::string& message,
    const std::string& payload_json,
    const std::string& captured_at,
    const std::string& source,
    std::string* out_error
) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return json::Value(nullptr);
    }
    if (!initialize_schema(out_error)) {
        return json::Value(nullptr);
    }

    const std::string safe_device_id = sanitize_segment(device_id, "unknown-device");
    const std::string final_log_id = log_id.empty()
        ? make_prefixed_id("log", safe_device_id + ":" + captured_at + ":" + message)
        : sanitize_segment(log_id, "log");
    const std::string final_captured_at = captured_at.empty() ? now_utc_iso8601() : captured_at;
    const std::string updated_at = now_utc_iso8601();

    if (!upsert_log(
            final_log_id,
            safe_device_id,
            level.empty() ? "info" : level,
            category.empty() ? "general" : category,
            message,
            payload_json,
            final_captured_at,
            source,
            out_error
        )) {
        return json::Value(nullptr);
    }

    (void)enqueue_outbox_job(
        make_prefixed_id("outbox", "log:" + final_log_id),
        "log",
        final_log_id,
        "/api/cloud/v1/ingest/log",
        "pending",
        "",
        updated_at,
        out_error
    );

    return make_object({
        {"logId", final_log_id},
        {"deviceId", safe_device_id},
        {"level", level.empty() ? "info" : level},
        {"category", category.empty() ? "general" : category},
        {"capturedAt", final_captured_at},
        {"queued", true}
    });
}

json::Value LocalNodeStorage::ingest_stat_json(
    const std::string& stat_id,
    const std::string& device_id,
    const std::string& metric,
    const std::string& value_text,
    const std::string& payload_json,
    const std::string& captured_at,
    const std::string& source,
    std::string* out_error
) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return json::Value(nullptr);
    }
    if (!initialize_schema(out_error)) {
        return json::Value(nullptr);
    }

    const std::string safe_device_id = sanitize_segment(device_id, "unknown-device");
    const std::string final_stat_id = stat_id.empty()
        ? make_prefixed_id("stat", safe_device_id + ":" + metric + ":" + captured_at + ":" + value_text)
        : sanitize_segment(stat_id, "stat");
    const std::string final_captured_at = captured_at.empty() ? now_utc_iso8601() : captured_at;
    const std::string updated_at = now_utc_iso8601();

    if (!upsert_stat(
            final_stat_id,
            safe_device_id,
            metric.empty() ? "generic" : metric,
            value_text,
            payload_json,
            final_captured_at,
            source,
            out_error
        )) {
        return json::Value(nullptr);
    }

    (void)enqueue_outbox_job(
        make_prefixed_id("outbox", "stat:" + final_stat_id),
        "stat",
        final_stat_id,
        "/api/cloud/v1/ingest/stat",
        "pending",
        "",
        updated_at,
        out_error
    );

    return make_object({
        {"statId", final_stat_id},
        {"deviceId", safe_device_id},
        {"metric", metric.empty() ? "generic" : metric},
        {"capturedAt", final_captured_at},
        {"queued", true}
    });
}

json::Value LocalNodeStorage::ingest_result_json(
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
) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return json::Value(nullptr);
    }
    if (!initialize_schema(out_error)) {
        return json::Value(nullptr);
    }

    const std::string safe_device_id = sanitize_segment(device_id, "unknown-device");
    const std::string final_result_id = result_id.empty()
        ? make_prefixed_id("result", safe_device_id + ":" + result_type + ":" + captured_at + ":" + job_id)
        : sanitize_segment(result_id, "result");
    const std::string final_captured_at = captured_at.empty() ? now_utc_iso8601() : captured_at;
    const std::string updated_at = now_utc_iso8601();

    if (!upsert_result(
            final_result_id,
            safe_device_id,
            result_type.empty() ? "generic" : result_type,
            payload_json,
            final_captured_at,
            project_uuid,
            point_index,
            job_id,
            source,
            out_error
        )) {
        return json::Value(nullptr);
    }

    (void)enqueue_outbox_job(
        make_prefixed_id("outbox", "result:" + final_result_id),
        "result",
        final_result_id,
        "/api/cloud/v1/ingest/result",
        "pending",
        "",
        updated_at,
        out_error
    );

    return make_object({
        {"resultId", final_result_id},
        {"deviceId", safe_device_id},
        {"resultType", result_type.empty() ? "generic" : result_type},
        {"capturedAt", final_captured_at},
        {"productUUID", project_uuid},
        {"pointIndex", point_index},
        {"jobId", job_id},
        {"queued", true}
    });
}

json::Value LocalNodeStorage::summary_json() const {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr) {
        return make_object({
            {"databasePath", database_path().string()},
            {"archiveRoot", archive_root().string()},
            {"assetCount", 0},
            {"logCount", 0},
            {"statCount", 0},
            {"resultCount", 0},
            {"pendingJobs", 0},
            {"totalBytes", 0},
            {"lastSyncAt", last_sync_at_},
            {"cloudSync", make_object({
                {"enabled", false},
                {"baseURL", ""},
                {"lastFlushAt", ""},
                {"lastFlushStatus", "idle"},
                {"lastError", ""}
            })}
        });
    }
    const int count = static_cast<int>(select_single_int64(database_, "SELECT COUNT(*) FROM assets;"));
    const sqlite3_int64 total_bytes = select_single_int64(database_, "SELECT COALESCE(SUM(byte_count), 0) FROM assets;");
    const int log_count = static_cast<int>(select_single_int64(database_, "SELECT COUNT(*) FROM logs;"));
    const int stat_count = static_cast<int>(select_single_int64(database_, "SELECT COUNT(*) FROM stats;"));
    const int result_count = static_cast<int>(select_single_int64(database_, "SELECT COUNT(*) FROM result_bundles;"));
    const int pending_jobs = static_cast<int>(select_single_int64(database_, "SELECT COUNT(*) FROM outbox_jobs WHERE status = 'pending' OR status = 'retry';"));
    const std::string latest_job_at = select_single_text(database_, "SELECT COALESCE(MAX(updated_at), '') FROM outbox_jobs;");
    const LocalNodeCloudSyncConfig cloud_sync = cloud_sync_config_locked();

    return make_object({
        {"databasePath", database_path().string()},
        {"archiveRoot", archive_root().string()},
        {"assetCount", count},
        {"logCount", log_count},
        {"statCount", stat_count},
        {"resultCount", result_count},
        {"pendingJobs", pending_jobs},
        {"totalBytes", static_cast<double>(total_bytes)},
        {"lastSyncAt", last_sync_at_},
        {"lastQueueAt", latest_job_at},
        {"cloudSync", make_object({
            {"enabled", cloud_sync.enabled},
            {"baseURL", cloud_sync.baseURL},
            {"lastFlushAt", cloud_sync.lastFlushAt},
            {"lastFlushStatus", cloud_sync.lastFlushStatus},
            {"lastError", cloud_sync.lastError}
        })}
    });
}

LocalNodeCloudSyncConfig LocalNodeStorage::cloud_sync_config() const {
    std::scoped_lock lock(mutex_);
    return cloud_sync_config_locked();
}

json::Value LocalNodeStorage::cloud_sync_config_json() const {
    std::scoped_lock lock(mutex_);
    const LocalNodeCloudSyncConfig config = cloud_sync_config_locked();
    return make_object({
        {"enabled", config.enabled},
        {"baseURL", config.baseURL},
        {"lastFlushAt", config.lastFlushAt},
        {"lastFlushStatus", config.lastFlushStatus},
        {"lastError", config.lastError}
    });
}

json::Value LocalNodeStorage::list_assets_json(int limit) const {
    std::scoped_lock lock(mutex_);
    json::Value::Array assets;
    if (database_ == nullptr) {
        return assets;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT asset_id, device_id, category, file_path, file_name, byte_count, captured_at, updated_at, cloud_status "
        "FROM assets ORDER BY captured_at DESC LIMIT ?;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            assets.push_back(make_object({
                {"assetId", column_text(statement, 0)},
                {"deviceId", column_text(statement, 1)},
                {"category", column_text(statement, 2)},
                {"filePath", column_text(statement, 3)},
                {"fileName", column_text(statement, 4)},
                {"byteCount", static_cast<double>(sqlite3_column_int64(statement, 5))},
                {"capturedAt", column_text(statement, 6)},
                {"updatedAt", column_text(statement, 7)},
                {"cloudStatus", column_text(statement, 8)}
            }));
        }
    }

    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return assets;
}

json::Value LocalNodeStorage::find_asset_json(const std::string& asset_id) const {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr) {
        return json::Value(nullptr);
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT asset_id, device_id, category, file_path, file_name, byte_count, captured_at, updated_at, cloud_status "
        "FROM assets WHERE asset_id = ? LIMIT 1;";

    json::Value result(nullptr);
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, asset_id.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            result = make_object({
                {"assetId", column_text(statement, 0)},
                {"deviceId", column_text(statement, 1)},
                {"category", column_text(statement, 2)},
                {"filePath", column_text(statement, 3)},
                {"fileName", column_text(statement, 4)},
                {"byteCount", static_cast<double>(sqlite3_column_int64(statement, 5))},
                {"capturedAt", column_text(statement, 6)},
                {"updatedAt", column_text(statement, 7)},
                {"cloudStatus", column_text(statement, 8)}
            });
        }
    }

    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return result;
}

json::Value LocalNodeStorage::list_logs_json(int limit) const {
    std::scoped_lock lock(mutex_);
    json::Value::Array logs;
    if (database_ == nullptr) {
        return logs;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT log_id, device_id, level, category, message, captured_at, created_at "
        "FROM logs ORDER BY captured_at DESC LIMIT ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            logs.push_back(make_object({
                {"logId", column_text(statement, 0)},
                {"deviceId", column_text(statement, 1)},
                {"level", column_text(statement, 2)},
                {"category", column_text(statement, 3)},
                {"message", column_text(statement, 4)},
                {"capturedAt", column_text(statement, 5)},
                {"createdAt", column_text(statement, 6)}
            }));
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return logs;
}

json::Value LocalNodeStorage::list_stats_json(int limit) const {
    std::scoped_lock lock(mutex_);
    json::Value::Array stats;
    if (database_ == nullptr) {
        return stats;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT stat_id, device_id, metric, value_text, captured_at, created_at "
        "FROM stats ORDER BY captured_at DESC LIMIT ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            stats.push_back(make_object({
                {"statId", column_text(statement, 0)},
                {"deviceId", column_text(statement, 1)},
                {"metric", column_text(statement, 2)},
                {"value", column_text(statement, 3)},
                {"capturedAt", column_text(statement, 4)},
                {"createdAt", column_text(statement, 5)}
            }));
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return stats;
}

json::Value LocalNodeStorage::list_results_json(int limit) const {
    std::scoped_lock lock(mutex_);
    json::Value::Array results;
    if (database_ == nullptr) {
        return results;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT result_id, device_id, result_type, captured_at, project_uuid, point_index, job_id "
        "FROM result_bundles ORDER BY captured_at DESC LIMIT ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            results.push_back(make_object({
                {"resultId", column_text(statement, 0)},
                {"deviceId", column_text(statement, 1)},
                {"resultType", column_text(statement, 2)},
                {"capturedAt", column_text(statement, 3)},
                {"productUUID", column_text(statement, 4)},
                {"pointIndex", sqlite3_column_int(statement, 5)},
                {"jobId", column_text(statement, 6)}
            }));
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return results;
}

json::Value LocalNodeStorage::list_outbox_json(int limit) const {
    std::scoped_lock lock(mutex_);
    json::Value::Array jobs;
    if (database_ == nullptr) {
        return jobs;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT job_id, job_type, ref_id, cloud_endpoint, status, retry_count, last_error, updated_at "
        "FROM outbox_jobs ORDER BY updated_at DESC LIMIT ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            jobs.push_back(make_object({
                {"jobId", column_text(statement, 0)},
                {"jobType", column_text(statement, 1)},
                {"refId", column_text(statement, 2)},
                {"cloudEndpoint", column_text(statement, 3)},
                {"status", column_text(statement, 4)},
                {"retryCount", sqlite3_column_int(statement, 5)},
                {"lastError", column_text(statement, 6)},
                {"updatedAt", column_text(statement, 7)}
            }));
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return jobs;
}

std::vector<LocalNodeOutboxJob> LocalNodeStorage::pending_outbox_jobs(int limit) const {
    std::scoped_lock lock(mutex_);
    std::vector<LocalNodeOutboxJob> jobs;
    if (database_ == nullptr) {
        return jobs;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "SELECT job_id, job_type, ref_id, cloud_endpoint, status, retry_count, last_error, updated_at "
        "FROM outbox_jobs "
        "WHERE status = 'pending' OR status = 'retry' "
        "ORDER BY retry_count ASC, updated_at ASC LIMIT ?;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_int(statement, 1, limit);
        while (sqlite3_step(statement) == SQLITE_ROW) {
            jobs.push_back(LocalNodeOutboxJob{
                .jobID = column_text(statement, 0),
                .jobType = column_text(statement, 1),
                .refID = column_text(statement, 2),
                .cloudEndpoint = column_text(statement, 3),
                .status = column_text(statement, 4),
                .retryCount = sqlite3_column_int(statement, 5),
                .lastError = column_text(statement, 6),
                .updatedAt = column_text(statement, 7),
            });
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return jobs;
}

bool LocalNodeStorage::update_cloud_sync_config(const std::string& base_url, bool enabled, std::string* out_error) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return false;
    }
    if (!initialize_schema(out_error)) {
        return false;
    }

    const std::string updated_at = now_utc_iso8601();
    const std::string normalized = normalize_http_base_url(base_url);
    return upsert_setting_locked("cloud_sync_enabled", enabled ? "1" : "0", updated_at, out_error) &&
        upsert_setting_locked("cloud_base_url", normalized, updated_at, out_error);
}

bool LocalNodeStorage::record_cloud_sync_result(
    const std::string& flush_status,
    const std::string& last_error,
    const std::string& flushed_at,
    std::string* out_error
) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr && !open_database(out_error)) {
        return false;
    }
    if (!initialize_schema(out_error)) {
        return false;
    }

    const std::string updated_at = flushed_at.empty() ? now_utc_iso8601() : flushed_at;
    return upsert_setting_locked("cloud_last_flush_status", flush_status, updated_at, out_error) &&
        upsert_setting_locked("cloud_last_error", last_error, updated_at, out_error) &&
        upsert_setting_locked("cloud_last_flush_at", updated_at, updated_at, out_error);
}

bool LocalNodeStorage::build_cloud_request_body(const LocalNodeOutboxJob& job, std::string* out_body, std::string* out_error) const {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr) {
        if (out_error != nullptr) {
            *out_error = "local node database not ready";
        }
        return false;
    }

    auto fail = [&](const std::string& message) {
        if (out_error != nullptr) {
            *out_error = message;
        }
        return false;
    };

    if (job.jobType == "asset") {
        sqlite3_stmt* statement = nullptr;
        const char* sql =
            "SELECT asset_id, device_id, category, file_path, file_name, captured_at, project_uuid, point_index, job_id "
            "FROM assets WHERE asset_id = ? LIMIT 1;";
        if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
            return fail(sqlite3_errmsg(database_));
        }

        sqlite3_bind_text(statement, 1, job.refID.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) != SQLITE_ROW) {
            sqlite3_finalize(statement);
            return fail("asset record not found");
        }

        const std::string asset_id = column_text(statement, 0);
        const std::string device_id = column_text(statement, 1);
        const std::string category = column_text(statement, 2);
        const std::string file_path = column_text(statement, 3);
        const std::string file_name = column_text(statement, 4);
        const std::string captured_at = column_text(statement, 5);
        const std::string project_uuid = column_text(statement, 6);
        const int point_index = sqlite3_column_int(statement, 7);
        const std::string job_id = column_text(statement, 8);
        sqlite3_finalize(statement);

        std::ifstream stream(file_path, std::ios::binary);
        if (!stream) {
            return fail("failed to open asset file");
        }
        const std::string binary((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());

        const json::Value body(make_object({
            {"idempotencyKey", asset_id},
            {"deviceId", device_id},
            {"fileName", file_name},
            {"category", category},
            {"capturedAt", captured_at},
            {"productUUID", project_uuid},
            {"pointIndex", point_index},
            {"jobId", job_id},
            {"contentBase64", base64_encode(binary)}
        }));
        *out_body = body.stringify();
        return true;
    }

    if (job.jobType == "result") {
        sqlite3_stmt* statement = nullptr;
        const char* sql =
            "SELECT result_id, device_id, result_type, payload_json, captured_at, project_uuid, point_index, job_id "
            "FROM result_bundles WHERE result_id = ? LIMIT 1;";
        if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
            return fail(sqlite3_errmsg(database_));
        }

        sqlite3_bind_text(statement, 1, job.refID.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) != SQLITE_ROW) {
            sqlite3_finalize(statement);
            return fail("result record not found");
        }

        const json::Value body(make_object({
            {"idempotencyKey", column_text(statement, 0)},
            {"resultId", column_text(statement, 0)},
            {"deviceId", column_text(statement, 1)},
            {"resultType", column_text(statement, 2)},
            {"payload", parse_json_or_string(column_text(statement, 3))},
            {"capturedAt", column_text(statement, 4)},
            {"productUUID", column_text(statement, 5)},
            {"pointIndex", sqlite3_column_int(statement, 6)},
            {"jobId", column_text(statement, 7)}
        }));
        sqlite3_finalize(statement);
        *out_body = body.stringify();
        return true;
    }

    if (job.jobType == "log") {
        sqlite3_stmt* statement = nullptr;
        const char* sql =
            "SELECT log_id, device_id, level, category, message, payload_json, captured_at "
            "FROM logs WHERE log_id = ? LIMIT 1;";
        if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
            return fail(sqlite3_errmsg(database_));
        }

        sqlite3_bind_text(statement, 1, job.refID.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) != SQLITE_ROW) {
            sqlite3_finalize(statement);
            return fail("log record not found");
        }

        const json::Value body(make_object({
            {"idempotencyKey", column_text(statement, 0)},
            {"logId", column_text(statement, 0)},
            {"deviceId", column_text(statement, 1)},
            {"level", column_text(statement, 2)},
            {"category", column_text(statement, 3)},
            {"message", column_text(statement, 4)},
            {"payload", parse_json_or_string(column_text(statement, 5))},
            {"capturedAt", column_text(statement, 6)}
        }));
        sqlite3_finalize(statement);
        *out_body = body.stringify();
        return true;
    }

    if (job.jobType == "stat") {
        sqlite3_stmt* statement = nullptr;
        const char* sql =
            "SELECT stat_id, device_id, metric, value_text, payload_json, captured_at "
            "FROM stats WHERE stat_id = ? LIMIT 1;";
        if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
            return fail(sqlite3_errmsg(database_));
        }

        sqlite3_bind_text(statement, 1, job.refID.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) != SQLITE_ROW) {
            sqlite3_finalize(statement);
            return fail("stat record not found");
        }

        const json::Value body(make_object({
            {"idempotencyKey", column_text(statement, 0)},
            {"statId", column_text(statement, 0)},
            {"deviceId", column_text(statement, 1)},
            {"metric", column_text(statement, 2)},
            {"value", column_text(statement, 3)},
            {"payload", parse_json_or_string(column_text(statement, 4))},
            {"capturedAt", column_text(statement, 5)}
        }));
        sqlite3_finalize(statement);
        *out_body = body.stringify();
        return true;
    }

    return fail("unsupported outbox job type");
}

bool LocalNodeStorage::mark_outbox_job_success(const LocalNodeOutboxJob& job, const std::string& updated_at, std::string* out_error) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr) {
        if (out_error != nullptr) {
            *out_error = "local node database not ready";
        }
        return false;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "UPDATE outbox_jobs SET status = 'synced', last_error = '', updated_at = ? WHERE job_id = ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, job.jobID.c_str(), -1, SQLITE_TRANSIENT);
    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    if (job.jobType == "asset") {
        return update_asset_cloud_status_locked(job.refID, "synced", out_error);
    }
    return true;
}

bool LocalNodeStorage::mark_outbox_job_failure(const LocalNodeOutboxJob& job, const std::string& error_message, const std::string& updated_at, std::string* out_error) {
    std::scoped_lock lock(mutex_);
    if (database_ == nullptr) {
        if (out_error != nullptr) {
            *out_error = "local node database not ready";
        }
        return false;
    }

    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "UPDATE outbox_jobs "
        "SET status = 'retry', retry_count = retry_count + 1, last_error = ?, updated_at = ? "
        "WHERE job_id = ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, error_message.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, job.jobID.c_str(), -1, SQLITE_TRANSIENT);
    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    if (job.jobType == "asset") {
        return update_asset_cloud_status_locked(job.refID, "sync_error", out_error);
    }
    return true;
}

std::filesystem::path LocalNodeStorage::database_path() {
    return desktop_runtime_root() / "local_node" / "local_node.db";
}

std::filesystem::path LocalNodeStorage::archive_root() {
    return desktop_runtime_root() / "media";
}

bool LocalNodeStorage::open_database(std::string* out_error) {
    std::error_code error_code;
    std::filesystem::create_directories(database_path().parent_path(), error_code);

    if (sqlite3_open(database_path().string().c_str(), &database_) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    return execute_sql(
        "PRAGMA journal_mode=WAL;"
        "PRAGMA synchronous=NORMAL;"
        "PRAGMA busy_timeout=5000;",
        out_error
    );
}

bool LocalNodeStorage::initialize_schema(std::string* out_error) {
    return execute_sql(
        "CREATE TABLE IF NOT EXISTS assets ("
        " asset_id TEXT PRIMARY KEY,"
        " device_id TEXT NOT NULL,"
        " category TEXT NOT NULL,"
        " file_path TEXT NOT NULL UNIQUE,"
        " file_name TEXT NOT NULL,"
        " byte_count INTEGER NOT NULL,"
        " captured_at TEXT NOT NULL,"
        " created_at TEXT NOT NULL,"
        " updated_at TEXT NOT NULL,"
        " project_uuid TEXT NOT NULL DEFAULT '',"
        " point_index INTEGER NOT NULL DEFAULT 0,"
        " job_id TEXT NOT NULL DEFAULT '',"
        " source TEXT NOT NULL DEFAULT 'archive-scan',"
        " sha256 TEXT NOT NULL DEFAULT '',"
        " cloud_status TEXT NOT NULL DEFAULT 'local_only'"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_assets_device_id ON assets(device_id);"
        "CREATE INDEX IF NOT EXISTS idx_assets_captured_at ON assets(captured_at DESC);"
        "CREATE TABLE IF NOT EXISTS logs ("
        " log_id TEXT PRIMARY KEY,"
        " device_id TEXT NOT NULL,"
        " level TEXT NOT NULL,"
        " category TEXT NOT NULL,"
        " message TEXT NOT NULL,"
        " payload_json TEXT NOT NULL DEFAULT '{}',"
        " captured_at TEXT NOT NULL,"
        " created_at TEXT NOT NULL,"
        " source TEXT NOT NULL DEFAULT 'api.ingest.log'"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_logs_captured_at ON logs(captured_at DESC);"
        "CREATE TABLE IF NOT EXISTS stats ("
        " stat_id TEXT PRIMARY KEY,"
        " device_id TEXT NOT NULL,"
        " metric TEXT NOT NULL,"
        " value_text TEXT NOT NULL,"
        " payload_json TEXT NOT NULL DEFAULT '{}',"
        " captured_at TEXT NOT NULL,"
        " created_at TEXT NOT NULL,"
        " source TEXT NOT NULL DEFAULT 'api.ingest.stat'"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_stats_captured_at ON stats(captured_at DESC);"
        "CREATE TABLE IF NOT EXISTS result_bundles ("
        " result_id TEXT PRIMARY KEY,"
        " device_id TEXT NOT NULL,"
        " result_type TEXT NOT NULL,"
        " payload_json TEXT NOT NULL DEFAULT '{}',"
        " captured_at TEXT NOT NULL,"
        " created_at TEXT NOT NULL,"
        " project_uuid TEXT NOT NULL DEFAULT '',"
        " point_index INTEGER NOT NULL DEFAULT 0,"
        " job_id TEXT NOT NULL DEFAULT '',"
        " source TEXT NOT NULL DEFAULT 'api.ingest.result'"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_results_captured_at ON result_bundles(captured_at DESC);"
        "CREATE TABLE IF NOT EXISTS outbox_jobs ("
        " job_id TEXT PRIMARY KEY,"
        " job_type TEXT NOT NULL,"
        " ref_id TEXT NOT NULL,"
        " cloud_endpoint TEXT NOT NULL,"
        " status TEXT NOT NULL DEFAULT 'pending',"
        " retry_count INTEGER NOT NULL DEFAULT 0,"
        " last_error TEXT NOT NULL DEFAULT '',"
        " created_at TEXT NOT NULL,"
        " updated_at TEXT NOT NULL"
        ");"
        "CREATE TABLE IF NOT EXISTS runtime_settings ("
        " setting_key TEXT PRIMARY KEY,"
        " setting_value TEXT NOT NULL DEFAULT '',"
        " updated_at TEXT NOT NULL"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_outbox_updated_at ON outbox_jobs(updated_at DESC);",
        out_error
    );
}

std::string LocalNodeStorage::setting_value_locked(const std::string& key, const std::string& fallback) const {
    if (database_ == nullptr) {
        return fallback;
    }

    sqlite3_stmt* statement = nullptr;
    std::string value = fallback;
    const char* sql = "SELECT setting_value FROM runtime_settings WHERE setting_key = ? LIMIT 1;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) == SQLITE_OK) {
        sqlite3_bind_text(statement, 1, key.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            value = column_text(statement, 0);
        }
    }
    if (statement != nullptr) {
        sqlite3_finalize(statement);
    }
    return value;
}

bool LocalNodeStorage::upsert_setting_locked(const std::string& key, const std::string& value, const std::string& updated_at, std::string* out_error) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO runtime_settings (setting_key, setting_value, updated_at) VALUES (?, ?, ?)"
        " ON CONFLICT(setting_key) DO UPDATE SET"
        " setting_value = excluded.setting_value,"
        " updated_at = excluded.updated_at;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, key.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, value.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, updated_at.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

LocalNodeCloudSyncConfig LocalNodeStorage::cloud_sync_config_locked() const {
    LocalNodeCloudSyncConfig config;
    if (database_ == nullptr) {
        return config;
    }

    config.enabled = parse_bool_string(setting_value_locked("cloud_sync_enabled", "0"));
    config.baseURL = normalize_http_base_url(setting_value_locked("cloud_base_url", ""));
    config.lastFlushAt = setting_value_locked("cloud_last_flush_at", "");
    config.lastFlushStatus = setting_value_locked("cloud_last_flush_status", "idle");
    config.lastError = setting_value_locked("cloud_last_error", "");
    return config;
}

bool LocalNodeStorage::update_asset_cloud_status_locked(const std::string& asset_id, const std::string& cloud_status, std::string* out_error) {
    sqlite3_stmt* statement = nullptr;
    const char* sql = "UPDATE assets SET cloud_status = ?, updated_at = ? WHERE asset_id = ?;";
    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    const std::string updated_at = now_utc_iso8601();
    sqlite3_bind_text(statement, 1, cloud_status.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, asset_id.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::execute_sql(const std::string& sql, std::string* out_error) {
    char* error_message = nullptr;
    const int rc = sqlite3_exec(database_, sql.c_str(), nullptr, nullptr, &error_message);
    if (rc != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = error_message == nullptr ? "sqlite error" : error_message;
        }
        if (error_message != nullptr) {
            sqlite3_free(error_message);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::upsert_asset(
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
) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO assets ("
        " asset_id, device_id, category, file_path, file_name, byte_count, captured_at, created_at, updated_at,"
        " project_uuid, point_index, job_id, source"
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(file_path) DO UPDATE SET"
        " asset_id = excluded.asset_id,"
        " device_id = excluded.device_id,"
        " category = excluded.category,"
        " file_name = excluded.file_name,"
        " byte_count = excluded.byte_count,"
        " captured_at = excluded.captured_at,"
        " updated_at = excluded.updated_at,"
        " project_uuid = excluded.project_uuid,"
        " point_index = excluded.point_index,"
        " job_id = excluded.job_id,"
        " source = excluded.source;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, asset_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, device_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, category.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 4, file_path.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 5, file_name.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(statement, 6, static_cast<sqlite3_int64>(byte_count));
    sqlite3_bind_text(statement, 7, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 8, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 9, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 10, project_uuid.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(statement, 11, point_index);
    sqlite3_bind_text(statement, 12, job_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 13, source.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::upsert_log(
    const std::string& log_id,
    const std::string& device_id,
    const std::string& level,
    const std::string& category,
    const std::string& message,
    const std::string& payload_json,
    const std::string& captured_at,
    const std::string& source,
    std::string* out_error
) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO logs (log_id, device_id, level, category, message, payload_json, captured_at, created_at, source)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(log_id) DO UPDATE SET"
        " device_id = excluded.device_id,"
        " level = excluded.level,"
        " category = excluded.category,"
        " message = excluded.message,"
        " payload_json = excluded.payload_json,"
        " captured_at = excluded.captured_at,"
        " created_at = excluded.created_at,"
        " source = excluded.source;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, log_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, device_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, level.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 4, category.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 5, message.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 6, payload_json.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 7, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 8, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 9, source.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::upsert_stat(
    const std::string& stat_id,
    const std::string& device_id,
    const std::string& metric,
    const std::string& value_text,
    const std::string& payload_json,
    const std::string& captured_at,
    const std::string& source,
    std::string* out_error
) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO stats (stat_id, device_id, metric, value_text, payload_json, captured_at, created_at, source)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(stat_id) DO UPDATE SET"
        " device_id = excluded.device_id,"
        " metric = excluded.metric,"
        " value_text = excluded.value_text,"
        " payload_json = excluded.payload_json,"
        " captured_at = excluded.captured_at,"
        " created_at = excluded.created_at,"
        " source = excluded.source;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, stat_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, device_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, metric.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 4, value_text.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 5, payload_json.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 6, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 7, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 8, source.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::upsert_result(
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
) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO result_bundles ("
        " result_id, device_id, result_type, payload_json, captured_at, created_at, project_uuid, point_index, job_id, source"
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        " ON CONFLICT(result_id) DO UPDATE SET"
        " device_id = excluded.device_id,"
        " result_type = excluded.result_type,"
        " payload_json = excluded.payload_json,"
        " captured_at = excluded.captured_at,"
        " created_at = excluded.created_at,"
        " project_uuid = excluded.project_uuid,"
        " point_index = excluded.point_index,"
        " job_id = excluded.job_id,"
        " source = excluded.source;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, result_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, device_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, result_type.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 4, payload_json.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 5, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 6, captured_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 7, project_uuid.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int(statement, 8, point_index);
    sqlite3_bind_text(statement, 9, job_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 10, source.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

bool LocalNodeStorage::enqueue_outbox_job(
    const std::string& job_id,
    const std::string& job_type,
    const std::string& ref_id,
    const std::string& cloud_endpoint,
    const std::string& status,
    const std::string& last_error,
    const std::string& updated_at,
    std::string* out_error
) {
    sqlite3_stmt* statement = nullptr;
    const char* sql =
        "INSERT INTO outbox_jobs (job_id, job_type, ref_id, cloud_endpoint, status, retry_count, last_error, created_at, updated_at)"
        " VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?)"
        " ON CONFLICT(job_id) DO UPDATE SET"
        " job_type = excluded.job_type,"
        " ref_id = excluded.ref_id,"
        " cloud_endpoint = excluded.cloud_endpoint,"
        " status = excluded.status,"
        " last_error = excluded.last_error,"
        " updated_at = excluded.updated_at;";

    if (sqlite3_prepare_v2(database_, sql, -1, &statement, nullptr) != SQLITE_OK) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }

    sqlite3_bind_text(statement, 1, job_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 2, job_type.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 3, ref_id.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 4, cloud_endpoint.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 5, status.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 6, last_error.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 7, updated_at.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(statement, 8, updated_at.c_str(), -1, SQLITE_TRANSIENT);

    const int rc = sqlite3_step(statement);
    sqlite3_finalize(statement);
    if (rc != SQLITE_DONE) {
        if (out_error != nullptr) {
            *out_error = sqlite3_errmsg(database_);
        }
        return false;
    }
    return true;
}

} // namespace vino::desktop
