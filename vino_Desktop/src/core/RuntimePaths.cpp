#include "vino_desktop/RuntimePaths.hpp"

#include <cstdlib>

namespace vino::desktop {

namespace {

std::filesystem::path fallback_runtime_root() {
    return std::filesystem::current_path() / "vino_Desktop_runtime";
}

} // namespace

std::filesystem::path desktop_runtime_root() {
#if defined(__APPLE__)
    if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
        return std::filesystem::path(home) / "Library" / "Application Support" / "vino";
    }
#endif

    return fallback_runtime_root();
}

std::filesystem::path media_root_for_device(const std::string& device_id) {
    return desktop_runtime_root() / "media" / device_id;
}

} // namespace vino::desktop
