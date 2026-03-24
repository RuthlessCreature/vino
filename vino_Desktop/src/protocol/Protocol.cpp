#include "vino_desktop/Protocol.hpp"

#include <sstream>

namespace vino::desktop {

std::string json_escape(std::string_view input) {
    std::string escaped;
    escaped.reserve(input.size() + 8);

    for (const char character : input) {
        switch (character) {
        case '\\':
            escaped += "\\\\";
            break;
        case '"':
            escaped += "\\\"";
            break;
        case '\n':
            escaped += "\\n";
            break;
        case '\r':
            escaped += "\\r";
            break;
        case '\t':
            escaped += "\\t";
            break;
        default:
            escaped += character;
            break;
        }
    }

    return escaped;
}

std::string render_target_json(const TargetSelector& target) {
    if (!target.all && target.device_ids.empty()) {
        return "null";
    }

    std::ostringstream stream;
    stream << "{";

    if (target.all) {
        stream << "\"all\":true";
        if (!target.device_ids.empty()) {
            stream << ",";
        }
    }

    if (!target.device_ids.empty()) {
        stream << "\"deviceIds\":[";
        for (std::size_t index = 0; index < target.device_ids.size(); ++index) {
            if (index > 0) {
                stream << ",";
            }
            stream << "\"" << json_escape(target.device_ids[index]) << "\"";
        }
        stream << "]";
    }

    stream << "}";
    return stream.str();
}

std::string render_context_json(const TriggerContext& context) {
    if (context.product_uuid.empty() && context.job_id.empty() && context.point_index == 0) {
        return "null";
    }

    std::ostringstream stream;
    stream << "{";
    stream << "\"productUUID\":\"" << json_escape(context.product_uuid) << "\",";
    stream << "\"pointIndex\":" << context.point_index;

    if (!context.job_id.empty()) {
        stream << ",\"jobId\":\"" << json_escape(context.job_id) << "\"";
    }

    stream << "}";
    return stream.str();
}

std::string EnvelopeSummary::render_json() const {
    std::ostringstream stream;
    stream
        << "{\n"
        << "  \"protocol\": \"vino.control/1\",\n"
        << "  \"messageId\": \"desktop-blueprint-message\",\n"
        << "  \"correlationId\": null,\n"
        << "  \"kind\": \"" << json_escape(kind) << "\",\n"
        << "  \"action\": \"" << json_escape(action) << "\",\n"
        << "  \"timestamp\": \"2026-03-24T09:30:00Z\",\n"
        << "  \"source\": {\n"
        << "    \"role\": \"" << json_escape(source_role) << "\",\n"
        << "    \"deviceId\": \"" << json_escape(source_device_id) << "\",\n"
        << "    \"name\": \"" << json_escape(source_name) << "\"\n"
        << "  },\n"
        << "  \"target\": " << render_target_json(target) << ",\n"
        << "  \"context\": " << render_context_json(context) << ",\n"
        << "  \"payload\": " << payload_json << "\n"
        << "}";
    return stream.str();
}

} // namespace vino::desktop

