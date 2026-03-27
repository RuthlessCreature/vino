#pragma once

#include <filesystem>
#include <string>

namespace vino::desktop {

std::filesystem::path desktop_runtime_root();
std::filesystem::path media_root_for_device(const std::string& device_id);

} // namespace vino::desktop
