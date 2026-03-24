#pragma once

#include <string>
#include <vector>

namespace vino::desktop {

struct DeviceTile {
    std::string alias {};
    std::string device_id {};
    std::string ip {};
    std::string lens {};
    std::string mode {};
    std::string model {};
    bool online {true};
    bool inference_enabled {false};
    bool persist_media {false};
};

struct TerminalEvent {
    std::string timestamp {};
    std::string level {};
    std::string message {};
};

class DesktopBlueprint {
public:
    [[nodiscard]] std::vector<DeviceTile> sample_fleet() const;
    [[nodiscard]] std::vector<TerminalEvent> sample_terminal() const;
    [[nodiscard]] std::string render_overview() const;
    [[nodiscard]] std::string render_window_layout() const;
    [[nodiscard]] std::string render_batch_example() const;
};

} // namespace vino::desktop

