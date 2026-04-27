#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace vino::desktop {

struct PortMap {
    static constexpr int control = 48920;
    static constexpr int preview = 48921;
    static constexpr int batch_gateway = 49020;
    static constexpr int local_node_api = 49030;
};

struct TargetSelector {
    std::vector<std::string> device_ids {};
    bool all {false};
};

struct TriggerContext {
    std::string product_uuid {};
    int point_index {0};
    std::string job_id {};
};

struct EnvelopeSummary {
    std::string kind {"command"};
    std::string action {"device.status.push"};
    std::string source_role {"desktop"};
    std::string source_device_id {"desktop-main"};
    std::string source_name {"vino console"};
    TargetSelector target {};
    TriggerContext context {};
    std::string payload_json {"{}"};

    [[nodiscard]] std::string render_json() const;
};

[[nodiscard]] std::string json_escape(std::string_view input);
[[nodiscard]] std::string render_target_json(const TargetSelector& target);
[[nodiscard]] std::string render_context_json(const TriggerContext& context);

} // namespace vino::desktop
