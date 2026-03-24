#include "vino_desktop/Blueprint.hpp"
#include "vino_desktop/Protocol.hpp"

#include <sstream>

namespace vino::desktop {

std::vector<DeviceTile> DesktopBlueprint::sample_fleet() const {
    return {
        {
            .alias = "Line-A Main Cam",
            .device_id = "iphone-001",
            .ip = "192.168.31.25",
            .lens = "Main",
            .mode = "Photo",
            .model = "defect-detector-v4",
            .online = true,
            .inference_enabled = true,
            .persist_media = false,
        },
        {
            .alias = "Line-A Side Cam",
            .device_id = "iphone-002",
            .ip = "192.168.31.26",
            .lens = "Ultra",
            .mode = "Stream",
            .model = "edge-segmenter-v2",
            .online = true,
            .inference_enabled = false,
            .persist_media = true,
        },
        {
            .alias = "Spare Node",
            .device_id = "iphone-003",
            .ip = "192.168.31.31",
            .lens = "Tele",
            .mode = "Standby",
            .model = "none",
            .online = false,
            .inference_enabled = false,
            .persist_media = false,
        }
    };
}

std::vector<TerminalEvent> DesktopBlueprint::sample_terminal() const {
    return {
        {"09:30:00.114", "INFO", "bonjour discovered iphone-001 at 192.168.31.25"},
        {"09:30:01.841", "INFO", "iphone-001 status push mode=photo lens=wide model=defect-detector-v4"},
        {"09:30:03.202", "WARN", "iphone-002 persistMedia enabled but remote POST target missing"},
        {"09:30:05.915", "INFO", "batch request queued capture.photo.trigger -> iphone-001"},
        {"09:30:06.488", "INFO", "iphone-001 reply capture.photo.trigger accepted"}
    };
}

std::string DesktopBlueprint::render_overview() const {
    std::ostringstream stream;
    stream
        << "Desktop role\n"
        << "- fleet discovery via bonjour and direct IP\n"
        << "- single-device workspace mirrors iPhone controls\n"
        << "- model manager handles install/remove/activate/deactivate\n"
        << "- terminal tracks heartbeats, replies, capture jobs, errors\n"
        << "- POST gateway fans external JSON commands into live devices\n";

    return stream.str();
}

std::string DesktopBlueprint::render_window_layout() const {
    const auto fleet = sample_fleet();
    const auto terminal = sample_terminal();

    std::ostringstream stream;
    stream
        << "Planned dock layout\n"
        << "----------------------------------------\n"
        << "[Left] Fleet\n";

    for (const auto& device : fleet) {
        stream
            << "  - " << device.alias
            << " | " << device.device_id
            << " | " << (device.online ? "online" : "offline")
            << " | " << device.ip
            << " | mode=" << device.mode
            << " | lens=" << device.lens
            << " | model=" << device.model
            << '\n';
    }

    stream
        << "[Center] Device Workspace\n"
        << "  - preview panel placeholder\n"
        << "  - camera controls: fps / wb / tint / exposure / iso / ev / zoom / lens position\n"
        << "  - toggles: focus mode / smooth AF / flash / inference / save media\n"
        << "  - transport context: productUUID / pointIndex / jobID / remote post target\n"
        << "[Right] Models + Batch\n"
        << "  - upload / remove / activate / deactivate CoreML packages\n"
        << "  - compose batch commands for selected fleet members\n"
        << "[Bottom] Data Terminal\n";

    for (const auto& event : terminal) {
        stream << "  - [" << event.timestamp << "] " << event.level << " " << event.message << '\n';
    }

    return stream.str();
}

std::string DesktopBlueprint::render_batch_example() const {
    EnvelopeSummary summary;
    summary.kind = "command";
    summary.action = "capture.photo.trigger";
    summary.target = TargetSelector{.device_ids = {"iphone-001", "iphone-002"}, .all = false};
    summary.context = TriggerContext{
        .product_uuid = "P-2026-03-24-0001",
        .point_index = 5,
        .job_id = "job-001"
    };
    summary.payload_json = "{}";

    std::ostringstream stream;
    stream
        << "Internal envelope example\n"
        << summary.render_json() << '\n';

    return stream.str();
}

} // namespace vino::desktop

