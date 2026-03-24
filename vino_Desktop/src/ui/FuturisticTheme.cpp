#include "vino_desktop/FuturisticTheme.hpp"

#include <sstream>

namespace vino::desktop {

std::vector<ThemeToken> default_theme_tokens() {
    return {
        {"background", "#050608"},
        {"panel", "#0C1014"},
        {"stroke", "#24303A"},
        {"accent", "#62F0FF"},
        {"success", "#55E39E"},
        {"warning", "#FFB347"},
        {"danger", "#FF5A6B"},
        {"textPrimary", "#F3F6F8"},
        {"textSecondary", "#A8B7C2"},
    };
}

std::string render_theme_tokens() {
    std::ostringstream stream;
    stream << "Theme tokens\n";

    for (const auto& token : default_theme_tokens()) {
        stream << "- " << token.name << " = " << token.value << '\n';
    }

    return stream.str();
}

} // namespace vino::desktop

