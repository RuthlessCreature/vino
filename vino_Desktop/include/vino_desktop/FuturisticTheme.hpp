#pragma once

#include <string>
#include <vector>

namespace vino::desktop {

struct ThemeToken {
    std::string name {};
    std::string value {};
};

[[nodiscard]] std::vector<ThemeToken> default_theme_tokens();
[[nodiscard]] std::string render_theme_tokens();

} // namespace vino::desktop

