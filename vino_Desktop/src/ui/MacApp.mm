#import <Cocoa/Cocoa.h>

#include <arpa/inet.h>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <ifaddrs.h>
#include <iomanip>
#include <memory>
#include <net/if.h>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "vino_desktop/DesktopRuntime.hpp"
#include "vino_desktop/FuturisticTheme.hpp"
#include "vino_desktop/MiniJson.hpp"
#include "vino_desktop/Protocol.hpp"
#include "vino_desktop/RuntimePaths.hpp"

namespace {

using vino::desktop::DeviceSnapshot;
using vino::desktop::DesktopRuntime;
using vino::desktop::ModelTransferSnapshot;
using vino::desktop::TriggerContext;
using vino::desktop::UiLogEntry;
using vino::desktop::json::Value;

struct PopupOption {
    std::string value {};
    std::string title {};
};

struct HostPortInput {
    std::string host {};
    int port {vino::desktop::PortMap::control};
};

NSString* to_ns_string(const std::string& value) {
    NSString* string = [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    return string == nil ? @"" : string;
}

std::string to_std_string(NSString* value) {
    if (value == nil) {
        return {};
    }

    const char* utf8 = value.UTF8String;
    return utf8 == nullptr ? std::string {} : std::string(utf8);
}

std::string lowercase_copy(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return value;
}

bool contains_case_insensitive(std::string_view haystack, std::string_view needle) {
    if (needle.empty()) {
        return true;
    }

    const std::string haystack_lower = lowercase_copy(std::string(haystack));
    const std::string needle_lower = lowercase_copy(std::string(needle));
    return haystack_lower.find(needle_lower) != std::string::npos;
}

std::string trim_copy(std::string value) {
    const auto is_space = [](unsigned char character) {
        return std::isspace(character) != 0;
    };

    while (!value.empty() && is_space(static_cast<unsigned char>(value.front()))) {
        value.erase(value.begin());
    }
    while (!value.empty() && is_space(static_cast<unsigned char>(value.back()))) {
        value.pop_back();
    }
    return value;
}

std::vector<std::string> split_string(std::string_view value, char separator) {
    std::vector<std::string> parts;
    std::string current;
    for (const char character : value) {
        if (character == separator) {
            parts.push_back(current);
            current.clear();
            continue;
        }
        current.push_back(character);
    }
    parts.push_back(current);
    return parts;
}

std::optional<HostPortInput> parse_host_port_input(const std::string& input) {
    const std::string trimmed = trim_copy(input);
    if (trimmed.empty()) {
        return std::nullopt;
    }

    HostPortInput result;
    result.host = trimmed;

    if (trimmed.front() == '[') {
        const auto closing = trimmed.find(']');
        if (closing == std::string::npos) {
            return std::nullopt;
        }
        result.host = trimmed.substr(1, closing - 1);
        if (closing + 1 < trimmed.size()) {
            if (trimmed[closing + 1] != ':') {
                return std::nullopt;
            }
            try {
                result.port = std::stoi(trimmed.substr(closing + 2));
            } catch (...) {
                return std::nullopt;
            }
        }
        return result;
    }

    const auto first_colon = trimmed.find(':');
    const auto last_colon = trimmed.rfind(':');
    if (first_colon != std::string::npos && first_colon == last_colon) {
        try {
            result.host = trimmed.substr(0, first_colon);
            result.port = std::stoi(trimmed.substr(first_colon + 1));
        } catch (...) {
            return std::nullopt;
        }
    }

    result.host = trim_copy(result.host);
    if (result.host.empty() || result.port <= 0 || result.port > 65535) {
        return std::nullopt;
    }
    return result;
}

std::vector<std::string> local_ipv4_addresses() {
    std::vector<std::string> addresses;
    ifaddrs* interfaces = nullptr;
    if (getifaddrs(&interfaces) != 0 || interfaces == nullptr) {
        return addresses;
    }

    for (ifaddrs* entry = interfaces; entry != nullptr; entry = entry->ifa_next) {
        if (entry->ifa_addr == nullptr || entry->ifa_addr->sa_family != AF_INET) {
            continue;
        }
        if ((entry->ifa_flags & IFF_UP) == 0 || (entry->ifa_flags & IFF_LOOPBACK) != 0) {
            continue;
        }

        char buffer[INET_ADDRSTRLEN] = {};
        const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(entry->ifa_addr);
        if (inet_ntop(AF_INET, &(ipv4->sin_addr), buffer, sizeof(buffer)) == nullptr) {
            continue;
        }

        std::string address = buffer;
        if (address.rfind("127.", 0) == 0 || address.rfind("169.254.", 0) == 0) {
            continue;
        }
        addresses.push_back(address);
    }

    freeifaddrs(interfaces);
    std::sort(addresses.begin(), addresses.end());
    addresses.erase(std::unique(addresses.begin(), addresses.end()), addresses.end());
    return addresses;
}

std::vector<std::string> local_ipv4_prefixes() {
    std::vector<std::string> prefixes;
    for (const auto& address : local_ipv4_addresses()) {
        const auto parts = split_string(address, '.');
        if (parts.size() != 4) {
            continue;
        }
        prefixes.push_back(parts[0] + "." + parts[1] + "." + parts[2]);
    }

    std::sort(prefixes.begin(), prefixes.end());
    prefixes.erase(std::unique(prefixes.begin(), prefixes.end()), prefixes.end());
    return prefixes;
}

std::vector<std::string> scan_prefixes_from_input(const std::string& input) {
    const std::string trimmed = trim_copy(input);
    if (trimmed.empty() || trimmed == "自动" || lowercase_copy(trimmed) == "auto") {
        return local_ipv4_prefixes();
    }

    std::vector<std::string> prefixes;
    std::string normalized = trimmed;
    std::replace(normalized.begin(), normalized.end(), ';', ',');
    const auto groups = split_string(normalized, ',');
    for (const auto& group : groups) {
        const std::string candidate = trim_copy(group);
        if (!candidate.empty()) {
            prefixes.push_back(candidate);
        }
    }

    if (prefixes.empty()) {
        prefixes = local_ipv4_prefixes();
    }
    return prefixes;
}

NSColor* hex_color(unsigned rgb, CGFloat alpha = 1.0) {
    return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xFF) / 255.0
                                     green:((rgb >> 8) & 0xFF) / 255.0
                                      blue:(rgb & 0xFF) / 255.0
                                     alpha:alpha];
}

NSFont* mono_font(CGFloat size, NSFontWeight weight = NSFontWeightRegular) {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

NSColor* log_color_for_level(const std::string& level) {
    const std::string lowered = lowercase_copy(level);
    if (lowered == "error") {
        return hex_color(0xFF6B7A);
    }
    if (lowered == "warn" || lowered == "warning") {
        return hex_color(0xFFC56B);
    }
    if (lowered == "info") {
        return hex_color(0x62F0FF);
    }
    return hex_color(0xF3F6F8);
}

std::string localized_capture_mode(const std::string& value) {
    if (value == "photo") {
        return "拍照";
    }
    if (value == "stream") {
        return "视频流";
    }
    return value.empty() ? "未就绪" : value;
}

std::string localized_focus_mode(const std::string& value) {
    if (value == "continuousAuto") {
        return "自动对焦";
    }
    if (value == "locked") {
        return "定焦";
    }
    return value.empty() ? "未就绪" : value;
}

std::string localized_lens_name(const std::string& value) {
    if (value == "wide") {
        return "主摄";
    }
    if (value == "ultraWide") {
        return "超广角";
    }
    if (value == "telephoto") {
        return "长焦";
    }
    return value.empty() ? "未就绪" : value;
}

std::string localized_profile_name(const std::string& value) {
    if (value == "h264") {
        return "H.264";
    }
    if (value == "hevc") {
        return "HEVC";
    }
    if (value == "proRes") {
        return "Apple ProRes";
    }
    return value.empty() ? "未就绪" : value;
}

std::vector<PopupOption> capture_mode_options() {
    return {
        {"photo", "拍照"},
        {"stream", "视频流"}
    };
}

std::vector<PopupOption> focus_mode_options() {
    return {
        {"continuousAuto", "自动对焦"},
        {"locked", "定焦"}
    };
}

std::vector<PopupOption> lens_options(const std::vector<std::string>& values = {"wide", "ultraWide", "telephoto"}) {
    std::vector<PopupOption> options;
    options.reserve(values.size());
    for (const auto& value : values) {
        options.push_back(PopupOption{value, localized_lens_name(value)});
    }
    return options;
}

std::vector<PopupOption> recording_profile_options(bool supports_prores = true) {
    std::vector<PopupOption> options {
        {"h264", "H.264"},
        {"hevc", "HEVC"}
    };
    if (supports_prores) {
        options.push_back({"proRes", "Apple ProRes"});
    }
    return options;
}

std::vector<PopupOption> terminal_level_options() {
    return {
        {"all", "全部级别"},
        {"info", "信息"},
        {"warn", "警告"},
        {"error", "错误"}
    };
}

std::vector<PopupOption> terminal_scope_options() {
    return {
        {"all", "全部设备"},
        {"current", "当前设备"}
    };
}

std::string localized_log_level_name(const std::string& value) {
    const std::string lowered = lowercase_copy(value);
    if (lowered == "all") {
        return "全部";
    }
    if (lowered == "info") {
        return "信息";
    }
    if (lowered == "warn" || lowered == "warning") {
        return "警告";
    }
    if (lowered == "error") {
        return "错误";
    }
    return value;
}

std::string localized_transfer_stage(const std::string& value) {
    if (value == "begin") {
        return "初始化";
    }
    if (value == "streaming") {
        return "传输中";
    }
    if (value == "commit") {
        return "提交中";
    }
    if (value == "completed") {
        return "完成";
    }
    if (value == "failed") {
        return "失败";
    }
    return value;
}

std::string localized_transfer_status(const std::string& value) {
    if (value == "queued") {
        return "排队中";
    }
    if (value == "pending") {
        return "待回执";
    }
    if (value == "sending") {
        return "发送中";
    }
    if (value == "awaiting_reply") {
        return "等待回执";
    }
    if (value == "accepted") {
        return "已接受";
    }
    if (value == "completed") {
        return "已完成";
    }
    if (value == "rejected") {
        return "已拒绝";
    }
    if (value == "send_failed") {
        return "发送失败";
    }
    return value;
}

NSTextField* make_label(NSString* text, CGFloat size = 12.0, NSFontWeight weight = NSFontWeightRegular, NSColor* color = nil) {
    NSTextField* label = [NSTextField labelWithString:text];
    label.font = mono_font(size, weight);
    label.textColor = color == nil ? hex_color(0xF3F6F8) : color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [label setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

NSTextField* make_input(NSString* placeholder, NSString* value = @"") {
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = placeholder;
    field.stringValue = value;
    field.font = mono_font(11.0);
    field.textColor = hex_color(0xF3F6F8);
    field.backgroundColor = hex_color(0x050608, 0.92);
    field.bordered = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.wantsLayer = YES;
    field.layer.backgroundColor = hex_color(0x050608, 0.92).CGColor;
    field.layer.borderColor = hex_color(0x24303A).CGColor;
    field.layer.borderWidth = 1.0;
    field.layer.cornerRadius = 10.0;
    [field.heightAnchor constraintEqualToConstant:22.0].active = YES;
    return field;
}

void style_popup(NSPopUpButton* popup) {
    if (popup == nil) {
        return;
    }
    popup.translatesAutoresizingMaskIntoConstraints = NO;
    popup.font = mono_font(11.0);
    popup.controlSize = NSControlSizeSmall;
    [popup.heightAnchor constraintEqualToConstant:22.0].active = YES;
}

NSButton* make_button(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = mono_font(11.0, NSFontWeightSemibold);
    button.controlSize = NSControlSizeSmall;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.wantsLayer = YES;
    button.layer.backgroundColor = hex_color(0x0C1014).CGColor;
    button.layer.borderColor = hex_color(0x24303A).CGColor;
    button.layer.borderWidth = 1.0;
    button.layer.cornerRadius = 10.0;
    button.contentTintColor = hex_color(0x62F0FF);
    [button.heightAnchor constraintEqualToConstant:26.0].active = YES;
    return button;
}

NSButton* make_toggle(NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title;
    button.font = mono_font(11.0);
    button.controlSize = NSControlSizeSmall;
    button.buttonType = NSButtonTypeSwitch;
    button.target = target;
    button.action = action;
    button.contentTintColor = hex_color(0x62F0FF);
    return button;
}

NSStackView* make_stack(NSUserInterfaceLayoutOrientation orientation, CGFloat spacing) {
    NSStackView* stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.orientation = orientation;
    stack.spacing = spacing;
    stack.edgeInsets = NSEdgeInsetsZero;
    stack.alignment = orientation == NSUserInterfaceLayoutOrientationVertical
        ? NSLayoutAttributeWidth
        : NSLayoutAttributeCenterY;
    stack.distribution = NSStackViewDistributionFill;
    return stack;
}

void relax_vertical_layout(NSView* view) {
    if (view == nil) {
        return;
    }

    [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];
    [view setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationVertical];

    for (NSView* child in view.subviews) {
        relax_vertical_layout(child);
    }
}

void relax_horizontal_layout(NSView* view) {
    if (view == nil) {
        return;
    }

    [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [view setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    for (NSView* child in view.subviews) {
        relax_horizontal_layout(child);
    }
}

NSView* make_preview_surface(NSImageView* __strong *out_image_view, NSTextField* __strong *out_title, NSTextField* __strong *out_subtitle) {
    NSView* view = [[NSView alloc] initWithFrame:NSZeroRect];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.wantsLayer = YES;
    view.layer.backgroundColor = hex_color(0x050608, 0.72).CGColor;
    view.layer.borderColor = hex_color(0x24303A).CGColor;
    view.layer.borderWidth = 1.0;
    view.layer.cornerRadius = 14.0;

    NSImageView* image_view = [[NSImageView alloc] initWithFrame:NSZeroRect];
    image_view.translatesAutoresizingMaskIntoConstraints = NO;
    image_view.imageScaling = NSImageScaleProportionallyUpOrDown;
    image_view.imageAlignment = NSImageAlignCenter;
    image_view.wantsLayer = YES;
    image_view.layer.backgroundColor = hex_color(0x050608, 0.72).CGColor;

    NSTextField* title = make_label(@"实时预览区待命", 11.0, NSFontWeightBold, hex_color(0xA8B7C2));
    NSTextField* subtitle = make_label(@"当前桌面端聚焦设备控制、状态总览、模型管理、日志终端与批处理调度", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    subtitle.maximumNumberOfLines = 2;

    [view addSubview:image_view];
    [view addSubview:title];
    [view addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [view.heightAnchor constraintEqualToConstant:72.0],
        [image_view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:1.0],
        [image_view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-1.0],
        [image_view.topAnchor constraintEqualToAnchor:view.topAnchor constant:1.0],
        [image_view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-1.0],
        [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10.0],
        [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:10.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:10.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-10.0],
        [subtitle.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-10.0]
    ]];

    if (out_image_view != nullptr) {
        *out_image_view = image_view;
    }
    if (out_title != nullptr) {
        *out_title = title;
    }
    if (out_subtitle != nullptr) {
        *out_subtitle = subtitle;
    }

    return view;
}

NSScrollView* make_text_scroll(NSTextView* __strong *out_text_view) {
    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSNoBorder;
    scroll.wantsLayer = YES;
    scroll.layer.backgroundColor = hex_color(0x050608, 0.92).CGColor;
    scroll.layer.borderColor = hex_color(0x24303A).CGColor;
    scroll.layer.borderWidth = 1.0;
    scroll.layer.cornerRadius = 12.0;

    NSTextView* text_view = [[NSTextView alloc] initWithFrame:NSZeroRect];
    text_view.editable = NO;
    text_view.selectable = YES;
    text_view.richText = NO;
    text_view.usesFontPanel = NO;
    text_view.automaticQuoteSubstitutionEnabled = NO;
    text_view.automaticDashSubstitutionEnabled = NO;
    text_view.drawsBackground = YES;
    text_view.backgroundColor = hex_color(0x050608, 0.92);
    text_view.textColor = hex_color(0xF3F6F8);
    text_view.font = mono_font(12.0);

    scroll.documentView = text_view;
    if (out_text_view != nullptr) {
        *out_text_view = text_view;
    }

    return scroll;
}

NSView* make_panel(NSString* title, NSView* body) {
    NSView* panel = [[NSView alloc] initWithFrame:NSZeroRect];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.wantsLayer = YES;
    panel.layer.backgroundColor = hex_color(0x0C1014, 0.98).CGColor;
    panel.layer.borderColor = hex_color(0x24303A).CGColor;
    panel.layer.borderWidth = 1.0;
    panel.layer.cornerRadius = 16.0;

    NSTextField* title_label = make_label(title, 10.5, NSFontWeightBold, hex_color(0xA8B7C2));
    body.translatesAutoresizingMaskIntoConstraints = NO;

    [panel addSubview:title_label];
    [panel addSubview:body];

    [NSLayoutConstraint activateConstraints:@[
        [title_label.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8.0],
        [title_label.topAnchor constraintEqualToAnchor:panel.topAnchor constant:8.0],
        [body.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:8.0],
        [body.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-8.0],
        [body.topAnchor constraintEqualToAnchor:title_label.bottomAnchor constant:5.0],
        [body.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8.0]
    ]];

    return panel;
}

NSView* make_slider_row(NSString* title, NSSlider* __strong *out_slider, NSTextField* __strong *out_value, id target, SEL action, double min_value, double max_value) {
    NSTextField* label = make_label(title, 11.0, NSFontWeightSemibold);
    label.alignment = NSTextAlignmentLeft;
    [label.widthAnchor constraintEqualToConstant:54.0].active = YES;

    NSTextField* value = make_label(@"0", 11.0, NSFontWeightRegular, hex_color(0x62F0FF));
    value.alignment = NSTextAlignmentRight;
    [value.widthAnchor constraintEqualToConstant:46.0].active = YES;

    NSSlider* slider = [NSSlider sliderWithValue:min_value minValue:min_value maxValue:max_value target:target action:action];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.continuous = YES;

    NSStackView* row = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 6.0);
    [row addArrangedSubview:label];
    [row addArrangedSubview:slider];
    [row addArrangedSubview:value];
    [slider.widthAnchor constraintGreaterThanOrEqualToConstant:60.0].active = YES;

    if (out_slider != nullptr) {
        *out_slider = slider;
    }
    if (out_value != nullptr) {
        *out_value = value;
    }

    return row;
}

const Value* find_in_object(const Value& value, std::string_view key) {
    return value.is_object() ? value.find(key) : nullptr;
}

double number_or(const Value* value, double fallback) {
    return value != nullptr && value->is_number() ? value->as_number() : fallback;
}

bool bool_or(const Value* value, bool fallback) {
    return value != nullptr && value->is_bool() ? value->as_bool() : fallback;
}

std::string string_or(const Value* value, const std::string& fallback = {}) {
    return value != nullptr && value->is_string() ? value->as_string() : fallback;
}

std::string stringify_block(const std::string& title, const Value& value) {
    return title + "\n" + value.stringify(2) + "\n\n";
}

std::string join_strings(const std::vector<std::string>& values, std::string_view separator) {
    std::ostringstream stream;
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index > 0) {
            stream << separator;
        }
        stream << values[index];
    }
    return stream.str();
}

std::vector<std::string> string_array_or_empty(const Value* value) {
    std::vector<std::string> values;
    if (value == nullptr || !value->is_array()) {
        return values;
    }

    for (const auto& item : value->as_array()) {
        if (item.is_string()) {
            values.push_back(item.as_string());
        }
    }
    return values;
}

std::string bool_text(bool value) {
    return value ? "开" : "关";
}

std::string format_number(double value, int precision = 1) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(precision) << value;
    return stream.str();
}

std::string last_active_text(const DeviceSnapshot& snapshot) {
    if (snapshot.last_seen_monotonic == std::chrono::steady_clock::time_point {}) {
        return snapshot.online ? "刚连接" : "未知";
    }

    const auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::steady_clock::now() - snapshot.last_seen_monotonic
    );
    const auto seconds = std::max<long long>(0, elapsed.count());

    if (seconds <= 1) {
        return "刚刚";
    }
    if (seconds < 60) {
        return std::to_string(seconds) + " 秒前";
    }
    if (seconds < 3600) {
        return std::to_string(seconds / 60) + " 分钟前";
    }
    return std::to_string(seconds / 3600) + " 小时前";
}

std::string device_state_digest(const DeviceSnapshot& snapshot) {
    return std::string(snapshot.online ? "在线" : "离线") + " · " + last_active_text(snapshot);
}

std::string control_sync_signature(const DeviceSnapshot& snapshot) {
    return snapshot.device_id
        + "|status:" + snapshot.status_payload.stringify()
        + "|caps:" + snapshot.capabilities_payload.stringify();
}

std::string popup_selected_value(NSPopUpButton* popup);

bool approximately_equal(double lhs, double rhs, double tolerance) {
    return std::fabs(lhs - rhs) <= tolerance;
}

bool controls_match_snapshot(
    const DeviceSnapshot& snapshot,
    NSPopUpButton* mode_popup,
    NSPopUpButton* focus_popup,
    NSPopUpButton* lens_popup,
    NSPopUpButton* profile_popup,
    NSSlider* fps_slider,
    NSSlider* temperature_slider,
    NSSlider* tint_slider,
    NSSlider* exposure_slider,
    NSSlider* iso_slider,
    NSSlider* ev_slider,
    NSSlider* zoom_slider,
    NSSlider* lens_slider,
    NSButton* flash_toggle,
    NSButton* inference_toggle,
    NSButton* persist_toggle,
    NSButton* smooth_af_toggle
) {
    if (!snapshot.status_payload.is_object()) {
        return false;
    }

    const Value& status = snapshot.status_payload;
    if (popup_selected_value(mode_popup) != string_or(find_in_object(status, "captureMode"))) {
        return false;
    }
    if (popup_selected_value(focus_popup) != string_or(find_in_object(status, "focusMode"))) {
        return false;
    }
    if (popup_selected_value(lens_popup) != string_or(find_in_object(status, "selectedLens"))) {
        return false;
    }
    if (popup_selected_value(profile_popup) != string_or(find_in_object(status, "recordingProfile"))) {
        return false;
    }

    if ((flash_toggle.state == NSControlStateValueOn) != bool_or(find_in_object(status, "flashEnabled"), false)) {
        return false;
    }
    if ((inference_toggle.state == NSControlStateValueOn) != bool_or(find_in_object(status, "inferenceEnabled"), false)) {
        return false;
    }
    if ((persist_toggle.state == NSControlStateValueOn) != bool_or(find_in_object(status, "persistMediaEnabled"), false)) {
        return false;
    }
    if ((smooth_af_toggle.state == NSControlStateValueOn) != bool_or(find_in_object(status, "smoothAutoFocusEnabled"), false)) {
        return false;
    }

    const auto* settings = find_in_object(status, "settings");
    if (settings == nullptr || !settings->is_object()) {
        return false;
    }

    return approximately_equal(fps_slider.doubleValue, number_or(find_in_object(*settings, "frameRate"), fps_slider.doubleValue), 0.11)
        && approximately_equal(temperature_slider.doubleValue, number_or(find_in_object(*settings, "whiteBalanceTemperature"), temperature_slider.doubleValue), 1.0)
        && approximately_equal(tint_slider.doubleValue, number_or(find_in_object(*settings, "whiteBalanceTint"), tint_slider.doubleValue), 1.0)
        && approximately_equal(exposure_slider.doubleValue, number_or(find_in_object(*settings, "exposureSeconds"), exposure_slider.doubleValue), 0.0005)
        && approximately_equal(iso_slider.doubleValue, number_or(find_in_object(*settings, "iso"), iso_slider.doubleValue), 1.0)
        && approximately_equal(ev_slider.doubleValue, number_or(find_in_object(*settings, "exposureBias"), ev_slider.doubleValue), 0.02)
        && approximately_equal(zoom_slider.doubleValue, number_or(find_in_object(*settings, "zoomFactor"), zoom_slider.doubleValue), 0.02)
        && approximately_equal(lens_slider.doubleValue, number_or(find_in_object(*settings, "lensPosition"), lens_slider.doubleValue), 0.02);
}

std::string make_model_id_from_path(const std::string& path) {
    std::string file_name = path;
    const auto slash = file_name.find_last_of("/\\");
    if (slash != std::string::npos) {
        file_name = file_name.substr(slash + 1);
    }

    const auto dot = file_name.find('.');
    if (dot != std::string::npos) {
        file_name = file_name.substr(0, dot);
    }

    std::string output;
    output.reserve(file_name.size());

    bool last_dash = false;
    for (const unsigned char character : file_name) {
        if (std::isalnum(character) != 0) {
            output.push_back(static_cast<char>(std::tolower(character)));
            last_dash = false;
        } else if (!last_dash) {
            output.push_back('-');
            last_dash = true;
        }
    }

    while (!output.empty() && output.front() == '-') {
        output.erase(output.begin());
    }
    while (!output.empty() && output.back() == '-') {
        output.pop_back();
    }

    return output.empty() ? "model" : output;
}

void configure_popup_items(NSPopUpButton* popup, const std::vector<PopupOption>& items) {
    [popup removeAllItems];
    for (const auto& item : items) {
        [popup addItemWithTitle:to_ns_string(item.title)];
        popup.lastItem.representedObject = to_ns_string(item.value);
    }
}

std::string popup_selected_value(NSPopUpButton* popup) {
    if (popup == nil || popup.selectedItem == nil) {
        return {};
    }

    if ([popup.selectedItem.representedObject isKindOfClass:[NSString class]]) {
        return to_std_string((NSString*)popup.selectedItem.representedObject);
    }

    return to_std_string(popup.selectedItem.title);
}

void select_popup_value(NSPopUpButton* popup, const std::string& value) {
    if (popup == nil) {
        return;
    }

    NSString* target = to_ns_string(value);
    for (NSMenuItem* item in popup.itemArray) {
        if ([item.representedObject isKindOfClass:[NSString class]] && [(NSString*)item.representedObject isEqualToString:target]) {
            [popup selectItem:item];
            return;
        }
    }

    if (popup.numberOfItems > 0) {
        [popup selectItemAtIndex:0];
    }
}

void set_slider_range_from_capability(const Value* capability, NSSlider* slider) {
    if (capability == nullptr || !capability->is_object() || slider == nil) {
        return;
    }

    const auto* min_value = find_in_object(*capability, "min");
    const auto* max_value = find_in_object(*capability, "max");

    slider.minValue = number_or(min_value, slider.minValue);
    slider.maxValue = number_or(max_value, slider.maxValue);
}

std::string host_from_service(NSNetService* service) {
    if (service == nil) {
        return {};
    }

    if (service.hostName.length > 0) {
        std::string host = to_std_string(service.hostName);
        while (!host.empty() && host.back() == '.') {
            host.pop_back();
        }
        return host;
    }

    for (NSData* address_data in service.addresses) {
        if (address_data.length < sizeof(sockaddr)) {
            continue;
        }

        const sockaddr* address = static_cast<const sockaddr*>(address_data.bytes);
        char buffer[INET6_ADDRSTRLEN] = {};

        if (address->sa_family == AF_INET && address_data.length >= sizeof(sockaddr_in)) {
            const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(address);
            if (inet_ntop(AF_INET, &(ipv4->sin_addr), buffer, sizeof(buffer)) != nullptr) {
                return buffer;
            }
        }

        if (address->sa_family == AF_INET6 && address_data.length >= sizeof(sockaddr_in6)) {
            const auto* ipv6 = reinterpret_cast<const sockaddr_in6*>(address);
            if (inet_ntop(AF_INET6, &(ipv6->sin6_addr), buffer, sizeof(buffer)) != nullptr) {
                return buffer;
            }
        }
    }

    return {};
}

std::string network_digest(const DeviceSnapshot& snapshot) {
    const std::vector<std::string> ip_addresses = string_array_or_empty(find_in_object(snapshot.status_payload, "ipAddresses"));
    if (!ip_addresses.empty()) {
        return join_strings(ip_addresses, " · ");
    }
    if (!snapshot.host.empty()) {
        return snapshot.host + ":" + std::to_string(snapshot.port);
    }
    return "未就绪";
}

std::string models_digest(const DeviceSnapshot& snapshot) {
    const std::vector<std::string> active_models = string_array_or_empty(find_in_object(snapshot.status_payload, "activeModelIds"));
    std::vector<std::string> installed_models;

    if (const auto* models = find_in_object(snapshot.capabilities_payload, "models"); models != nullptr && models->is_array()) {
        for (const auto& model : models->as_array()) {
            if (!model.is_object()) {
                continue;
            }

            const std::string model_id = string_or(model.find("id"));
            const std::string version = string_or(model.find("version"));
            if (!model_id.empty()) {
                installed_models.push_back(version.empty() ? model_id : (model_id + "@" + version));
            }
        }
    }

    if (!active_models.empty()) {
        return "启用=" + join_strings(active_models, ", ") + (installed_models.empty() ? "" : (" | 已安装=" + std::to_string(installed_models.size())));
    }

    if (!installed_models.empty()) {
        return "已安装=" + join_strings(installed_models, ", ");
    }

    return "未上报模型";
}

std::string capability_digest(const DeviceSnapshot& snapshot) {
    if (!snapshot.capabilities_payload.is_object()) {
        return "能力信息待获取";
    }

    const auto* capabilities = find_in_object(snapshot.capabilities_payload, "capabilities");
    if (capabilities == nullptr || !capabilities->is_object()) {
        return "能力信息待获取";
    }

    std::vector<std::string> items;
    if (const auto supported_lenses = string_array_or_empty(find_in_object(*capabilities, "supportedLenses")); !supported_lenses.empty()) {
        std::vector<std::string> localized_lenses;
        for (const auto& lens : supported_lenses) {
            localized_lenses.push_back(localized_lens_name(lens));
        }
        items.push_back("镜头=" + join_strings(localized_lenses, ", "));
    }

    if (const auto* frame_rate = find_in_object(*capabilities, "frameRate"); frame_rate != nullptr && frame_rate->is_object()) {
        items.push_back(
            "帧率=" + format_number(number_or(find_in_object(*frame_rate, "min"), 0.0), 0)
            + "…"
            + format_number(number_or(find_in_object(*frame_rate, "max"), 0.0), 0)
        );
    }

    items.push_back("闪光灯=" + bool_text(bool_or(find_in_object(*capabilities, "supportsFlash"), false)));
    items.push_back("平滑对焦=" + bool_text(bool_or(find_in_object(*capabilities, "supportsSmoothAutoFocus"), false)));
    items.push_back("ProRes=" + bool_text(bool_or(find_in_object(*capabilities, "supportsProRes"), false)));
    return join_strings(items, " | ");
}

bool is_image_media_path(const std::string& path) {
    if (path.empty()) {
        return false;
    }

    std::string extension = std::filesystem::path(path).extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char character) {
        return static_cast<char>(std::tolower(character));
    });
    return extension == ".jpg" || extension == ".jpeg" || extension == ".png" || extension == ".heic" || extension == ".heif" || extension == ".bmp" || extension == ".tif" || extension == ".tiff";
}

std::string compact_path(const std::string& path) {
    if (path.size() <= 96) {
        return path;
    }
    return path.substr(0, 24) + " … " + path.substr(path.size() - 64);
}

std::vector<std::filesystem::path> recent_media_paths_for_device(const DeviceSnapshot& snapshot, std::size_t limit = 24) {
    std::vector<std::filesystem::path> paths;
    if (snapshot.device_id.empty()) {
        return paths;
    }

    const std::filesystem::path root = vino::desktop::media_root_for_device(snapshot.device_id);
    std::error_code error;
    if (!std::filesystem::exists(root, error)) {
        return paths;
    }

    for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
        if (error) {
            break;
        }
        if (entry.is_regular_file(error)) {
            paths.push_back(entry.path());
        }
    }

    std::sort(paths.begin(), paths.end(), [](const std::filesystem::path& lhs, const std::filesystem::path& rhs) {
        std::error_code lhs_error;
        std::error_code rhs_error;
        const auto lhs_time = std::filesystem::last_write_time(lhs, lhs_error);
        const auto rhs_time = std::filesystem::last_write_time(rhs, rhs_error);

        if (lhs_error || rhs_error) {
            return lhs.filename().string() > rhs.filename().string();
        }

        return lhs_time > rhs_time;
    });

    if (paths.size() > limit) {
        paths.resize(limit);
    }

    return paths;
}

std::string log_entry_text(const UiLogEntry& entry) {
    return "[" + entry.timestamp + "] " + entry.level + " " + entry.message;
}

std::string inference_digest(const DeviceSnapshot& snapshot) {
    if (!snapshot.inference_payload.is_object()) {
        return "推理待命";
    }

    const auto* detections_value = find_in_object(snapshot.inference_payload, "detections");
    const auto* latency_value = find_in_object(snapshot.inference_payload, "latencyMS");
    const auto* frame_value = find_in_object(snapshot.inference_payload, "frameIndex");

    const int detection_count = detections_value != nullptr && detections_value->is_array()
        ? static_cast<int>(detections_value->as_array().size())
        : 0;

    std::ostringstream stream;
    stream << "目标=" << detection_count;
    if (latency_value != nullptr && latency_value->is_number()) {
        stream << " | 延迟=" << format_number(latency_value->as_number(), 2) << " ms";
    }
    if (frame_value != nullptr && frame_value->is_number()) {
        stream << " | 帧=" << static_cast<int>(frame_value->as_number());
    }

    if (detections_value != nullptr && detections_value->is_array() && !detections_value->as_array().empty()) {
        std::vector<std::string> labels;
        for (const auto& detection : detections_value->as_array()) {
            if (!detection.is_object()) {
                continue;
            }
            const std::string label = string_or(detection.find("label"));
            const auto* confidence_value = detection.find("confidence");
            if (!label.empty()) {
                labels.push_back(
                    confidence_value != nullptr && confidence_value->is_number()
                        ? (label + "@" + format_number(confidence_value->as_number(), 2))
                        : label
                );
            }
            if (labels.size() >= 3) {
                break;
            }
        }
        if (!labels.empty()) {
            stream << " | " << join_strings(labels, ", ");
        }
    }

    return stream.str();
}

std::string transfer_digest(const ModelTransferSnapshot& transfer) {
    const double progress = transfer.byte_count == 0
        ? (transfer.finished ? 100.0 : 0.0)
        : (100.0 * static_cast<double>(transfer.bytes_sent) / static_cast<double>(transfer.byte_count));

    std::ostringstream stream;
    stream
        << transfer.device_id
        << " | " << transfer.model_id
        << " | " << format_number(progress, 1) << "%"
        << " | " << localized_transfer_stage(transfer.stage)
        << " | 本地=" << localized_transfer_status(transfer.local_status)
        << " | 设备=" << localized_transfer_status(transfer.remote_status.empty() ? "pending" : transfer.remote_status)
        << " | 分块 " << transfer.chunks_sent << "/" << transfer.chunk_count
        << " | 已确认 " << transfer.chunks_acked;

    if (!transfer.remote_message.empty()) {
        stream << "\n  " << transfer.remote_message;
    }
    return stream.str();
}

std::string upload_result_summary(const Value& result, std::size_t device_count) {
    const auto* results_value = find_in_object(result, "results");
    if (results_value == nullptr || !results_value->is_array()) {
        return "模型上传任务已提交";
    }

    int queued = 0;
    int busy = 0;
    int failed = 0;
    std::vector<std::string> details;

    for (const auto& item : results_value->as_array()) {
        if (!item.is_object()) {
            continue;
        }
        const std::string status = string_or(item.find("status"));
        const std::string device_id = string_or(item.find("deviceId"));
        const std::string message = string_or(item.find("message"));

        if (status == "queued") {
            ++queued;
        } else if (status == "busy") {
            ++busy;
        } else {
            ++failed;
        }

        if (!message.empty()) {
            details.push_back(device_id.empty() ? message : (device_id + " · " + message));
        }
    }

    std::ostringstream stream;
    stream << "模型上传：已提交 " << queued << " 台";
    if (busy > 0) {
        stream << "，忙碌 " << busy << " 台";
    }
    if (failed > 0) {
        stream << "，失败 " << failed << " 台";
    }
    if (queued == 0 && busy == 0 && failed == 0) {
        stream << "，目标 " << device_count << " 台";
    }
    if (!details.empty()) {
        stream << " ｜ " << details.front();
    }
    return stream.str();
}

const ModelTransferSnapshot* latest_active_transfer_for_device(
    const std::vector<ModelTransferSnapshot>& transfers,
    const std::string& device_id
) {
    const ModelTransferSnapshot* match = nullptr;
    for (const auto& transfer : transfers) {
        if (transfer.finished || transfer.device_id != device_id) {
            continue;
        }
        if (match == nullptr || transfer.updated_at > match->updated_at) {
            match = &transfer;
        }
    }
    return match;
}

bool has_active_transfer_for_any_device(
    const std::vector<ModelTransferSnapshot>& transfers,
    const std::vector<std::string>& device_ids
) {
    for (const auto& device_id : device_ids) {
        if (latest_active_transfer_for_device(transfers, device_id) != nullptr) {
            return true;
        }
    }
    return false;
}

std::string active_transfer_summary(const ModelTransferSnapshot& transfer) {
    const double progress = transfer.byte_count == 0
        ? (transfer.finished ? 100.0 : 0.0)
        : (100.0 * static_cast<double>(transfer.bytes_sent) / static_cast<double>(transfer.byte_count));

    std::ostringstream stream;
    stream
        << "传输中 " << format_number(progress, 1) << "%"
        << " | 阶段=" << localized_transfer_stage(transfer.stage)
        << " | 分块确认 " << transfer.chunks_acked << "/" << transfer.chunk_count;
    return stream.str();
}

std::string snapshot_dump(const DeviceSnapshot& snapshot) {
    std::ostringstream stream;
    stream
        << "设备快照\n"
        << "设备ID=" << snapshot.device_id << "\n"
        << "别名=" << snapshot.alias << "\n"
        << "主机=" << snapshot.host << ":" << snapshot.port << "\n"
        << "在线=" << (snapshot.online ? "是" : "否") << "\n"
        << "最后活跃=" << last_active_text(snapshot) << "\n"
        << "最后时间=" << snapshot.last_seen << "\n"
        << "最后消息=" << snapshot.last_message << "\n\n"
        << "最近媒体路径=" << snapshot.last_media_path << "\n"
        << "最近媒体类别=" << snapshot.last_media_category << "\n"
        << "最近媒体时间=" << snapshot.last_media_seen << "\n\n"
        << "预览帧序号=" << snapshot.preview_frame_index << "\n"
        << "预览尺寸=" << snapshot.preview_image_width << "x" << snapshot.preview_image_height << "\n"
        << "预览时间=" << snapshot.preview_seen << "\n\n"
        << stringify_block("握手", snapshot.hello_payload)
        << stringify_block("状态", snapshot.status_payload)
        << stringify_block("能力", snapshot.capabilities_payload)
        << stringify_block("推理", snapshot.inference_payload);

    return stream.str();
}

} // namespace

@interface VinoDesktopAppController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@end

@implementation VinoDesktopAppController {
    std::unique_ptr<DesktopRuntime> _runtime;
    std::vector<DeviceSnapshot> _devices;
    std::vector<ModelTransferSnapshot> _modelTransfers;
    std::string _selectedDeviceId;
    std::string _lastControlSyncSignature;
    std::string _pendingControlDeviceId;
    std::string _latestTransferDigest;
    NSUInteger _lastLogCount;
    bool _controlDraftDirty;
    bool _controlApplyPending;
    std::chrono::steady_clock::time_point _controlApplyStartedAt;

    NSWindow* _window;
    NSTableView* _tableView;
    NSTextView* _terminalView;
    NSTextView* _rawView;
    NSTextView* _transferView;
    NSImageView* _previewImageView;
    NSTextField* _previewTitleLabel;
    NSTextField* _previewSubtitleLabel;

    NSTextField* _hostField;
    NSTextField* _scanPrefixField;
    NSTextField* _scanStartField;
    NSTextField* _scanEndField;
    NSTextField* _bonjourLabel;
    NSTextField* _fleetStatusLabel;
    NSPopUpButton* _bonjourPopup;

    NSTextField* _summaryLabel;
    NSTextField* _controlStatusLabel;
    NSTextField* _networkLabel;
    NSTextField* _capabilityLabel;
    NSTextField* _modelsLabel;
    NSTextField* _aliasField;
    NSTextField* _modelField;
    NSTextField* _modelVersionField;
    NSTextField* _modelPathField;
    NSTextField* _productField;
    NSTextField* _pointField;
    NSTextField* _jobField;
    NSTextField* _archiveLabel;
    NSTextField* _terminalSearchField;
    NSTextField* _terminalStatsLabel;

    NSPopUpButton* _modePopup;
    NSPopUpButton* _focusPopup;
    NSPopUpButton* _lensPopup;
    NSPopUpButton* _profilePopup;
    NSPopUpButton* _archivePopup;
    NSPopUpButton* _terminalLevelPopup;
    NSPopUpButton* _terminalScopePopup;

    NSSlider* _fpsSlider;
    NSTextField* _fpsValue;
    NSSlider* _temperatureSlider;
    NSTextField* _temperatureValue;
    NSSlider* _tintSlider;
    NSTextField* _tintValue;
    NSSlider* _exposureSlider;
    NSTextField* _exposureValue;
    NSSlider* _isoSlider;
    NSTextField* _isoValue;
    NSSlider* _evSlider;
    NSTextField* _evValue;
    NSSlider* _zoomSlider;
    NSTextField* _zoomValue;
    NSSlider* _lensSlider;
    NSTextField* _lensValue;

    NSButton* _flashToggle;
    NSButton* _inferenceToggle;
    NSButton* _persistToggle;
    NSButton* _smoothAFToggle;
    NSButton* _activateAfterInstallToggle;
    NSButton* _browseModelButton;
    NSButton* _uploadButton;
    NSButton* _uploadAllButton;

    NSTimer* _refreshTimer;
    NSNetServiceBrowser* _serviceBrowser;
    NSMutableDictionary<NSString*, NSNetService*>* _bonjourServices;
    std::vector<std::string> _archivePaths;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    _runtime = std::make_unique<DesktopRuntime>();
    _runtime->start();
    _bonjourServices = [[NSMutableDictionary alloc] init];
    _controlDraftDirty = false;
    _controlApplyPending = false;
    _controlApplyStartedAt = std::chrono::steady_clock::time_point {};

    [self buildWindow];
    [self startBonjourDiscovery];
    [self refreshUI:nil];

    _refreshTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                     target:self
                                                   selector:@selector(refreshUI:)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [_refreshTimer invalidate];
    _refreshTimer = nil;
    [_serviceBrowser stop];
    _serviceBrowser = nil;
    if (_runtime) {
        _runtime->stop();
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (void)buildWindow {
    const CGFloat default_width = 1366.0;
    const CGFloat default_height = 560.0;
    NSScreen* main_screen = NSScreen.mainScreen;
    NSRect visible_frame = main_screen != nil ? main_screen.visibleFrame : NSMakeRect(0.0, 0.0, default_width, default_height);
    const CGFloat content_width = std::min(default_width, std::max<CGFloat>(1080.0, visible_frame.size.width - 18.0));
    const CGFloat content_height = std::min(default_height, std::max<CGFloat>(540.0, visible_frame.size.height - 44.0));
    const NSRect content_rect = NSMakeRect(
        std::round(NSMidX(visible_frame) - content_width * 0.5),
        std::round(NSMidY(visible_frame) - content_height * 0.5),
        content_width,
        content_height
    );

    _window = [[NSWindow alloc] initWithContentRect:content_rect
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskMiniaturizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"vino 工业控制台 · 紧凑布局 B12";
    _window.backgroundColor = hex_color(0x050608);

    NSView* content = _window.contentView;
    content.wantsLayer = YES;
    content.layer.backgroundColor = hex_color(0x050608).CGColor;

    NSSplitView* rootSplit = [[NSSplitView alloc] initWithFrame:content.bounds];
    rootSplit.translatesAutoresizingMaskIntoConstraints = NO;
    rootSplit.vertical = NO;
    rootSplit.dividerStyle = NSSplitViewDividerStyleThin;
    rootSplit.wantsLayer = YES;
    [content addSubview:rootSplit];

    [NSLayoutConstraint activateConstraints:@[
        [rootSplit.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:8.0],
        [rootSplit.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-8.0],
        [rootSplit.topAnchor constraintEqualToAnchor:content.topAnchor constant:8.0],
        [rootSplit.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-8.0]
    ]];

    NSSplitView* topSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1090.0, 466.0)];
    topSplit.vertical = YES;
    topSplit.dividerStyle = NSSplitViewDividerStyleThin;

    NSView* leftPanel = [self buildFleetPanel];
    NSView* centerPanel = [self buildWorkspacePanel];
    NSView* rightPanel = [self buildSidePanel];
    NSView* terminalPanel = [self buildTerminalPanel];

    [leftPanel.widthAnchor constraintEqualToConstant:220.0].active = YES;
    [centerPanel.widthAnchor constraintGreaterThanOrEqualToConstant:720.0].active = YES;
    [rightPanel.widthAnchor constraintGreaterThanOrEqualToConstant:352.0].active = YES;

    [topSplit addSubview:leftPanel];
    [topSplit addSubview:centerPanel];
    [topSplit addSubview:rightPanel];
    [rootSplit addSubview:topSplit];
    [rootSplit addSubview:terminalPanel];

    for (NSView* view in @[leftPanel, centerPanel, rightPanel, terminalPanel, topSplit, rootSplit]) {
        relax_vertical_layout(view);
        relax_horizontal_layout(view);
    }

    [rootSplit setPosition:462.0 ofDividerAtIndex:0];
    [topSplit setPosition:220.0 ofDividerAtIndex:0];
    [topSplit setPosition:980.0 ofDividerAtIndex:1];

    const NSRect frame_rect = [_window frameRectForContentRect:content_rect];
    _window.minSize = frame_rect.size;
    _window.maxSize = frame_rect.size;
    _window.contentMinSize = NSMakeSize(content_width, content_height);
    _window.contentMaxSize = NSMakeSize(content_width, content_height);
    [_window setFrame:frame_rect display:NO];
    [_window setContentSize:NSMakeSize(content_width, content_height)];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_window setFrame:frame_rect display:YES];
        [_window setContentSize:NSMakeSize(content_width, content_height)];
    });
}

- (void)updateFleetStatusMessage:(const std::string&)message {
    if (_fleetStatusLabel != nil) {
        _fleetStatusLabel.stringValue = to_ns_string(message);
    }
}

- (std::vector<std::string>)resolvedScanPrefixes {
    return scan_prefixes_from_input(to_std_string(_scanPrefixField.stringValue));
}

- (NSView*)buildFleetPanel {
    const std::vector<std::string> local_prefixes = local_ipv4_prefixes();
    const std::string prefix_hint = local_prefixes.empty() ? std::string {"自动"} : ("自动 · " + join_strings(local_prefixes, " / "));

    _hostField = make_input(@"输入 IP 或 IP:端口");
    _hostField.stringValue = @"";

    _scanPrefixField = make_input(to_ns_string(prefix_hint));
    _scanPrefixField.stringValue = @"自动";
    _scanStartField = make_input(@"1");
    _scanStartField.stringValue = @"1";
    _scanEndField = make_input(@"254");
    _scanEndField.stringValue = @"254";
    _bonjourPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_bonjourPopup);
    [_bonjourPopup addItemWithTitle:@"Bonjour 扫描中…"];
    _bonjourPopup.enabled = NO;
    _bonjourLabel = make_label(@"Bonjour 待命", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _bonjourLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _fleetStatusLabel = make_label(
        to_ns_string(local_prefixes.empty()
            ? "连接：请输入 iPhone 的 IP。扫描：留空或输入“自动”时会尝试本机可用 IPv4 网段。"
            : ("连接：请输入 iPhone 的 IP 或 IP:端口。扫描候选：" + join_strings(local_prefixes, " · ") + ".*")),
        11.0,
        NSFontWeightRegular,
        hex_color(0xA8B7C2)
    );
    _fleetStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _fleetStatusLabel.maximumNumberOfLines = 2;

    NSButton* connectButton = make_button(@"连接", self, @selector(connectPressed:));
    NSButton* scanButton = make_button(@"扫描", self, @selector(scanPressed:));
    NSButton* bonjourButton = make_button(@"连接 Bonjour", self, @selector(connectBonjourPressed:));
    NSButton* bonjourRefreshButton = make_button(@"刷新", self, @selector(refreshBonjourPressed:));

    NSStackView* connectRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [connectRow addArrangedSubview:_hostField];
    [connectRow addArrangedSubview:connectButton];
    [connectRow addArrangedSubview:scanButton];
    [connectButton.widthAnchor constraintEqualToConstant:78.0].active = YES;
    [scanButton.widthAnchor constraintEqualToConstant:68.0].active = YES;

    NSStackView* scanRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [scanRow addArrangedSubview:_scanPrefixField];
    [scanRow addArrangedSubview:_scanStartField];
    [scanRow addArrangedSubview:_scanEndField];
    [_scanStartField.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [_scanEndField.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [_scanPrefixField.widthAnchor constraintGreaterThanOrEqualToConstant:92.0].active = YES;

    NSStackView* bonjourRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [bonjourRow addArrangedSubview:_bonjourPopup];
    [bonjourRow addArrangedSubview:bonjourButton];
    [bonjourRow addArrangedSubview:bonjourRefreshButton];
    [bonjourButton.widthAnchor constraintEqualToConstant:90.0].active = YES;
    [bonjourRefreshButton.widthAnchor constraintEqualToConstant:58.0].active = YES;

    NSScrollView* tableScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    tableScroll.translatesAutoresizingMaskIntoConstraints = NO;
    tableScroll.hasVerticalScroller = YES;
    tableScroll.borderType = NSNoBorder;
    tableScroll.wantsLayer = YES;
    tableScroll.layer.backgroundColor = hex_color(0x050608, 0.9).CGColor;
    tableScroll.layer.borderColor = hex_color(0x24303A).CGColor;
    tableScroll.layer.borderWidth = 1.0;
    tableScroll.layer.cornerRadius = 12.0;

    _tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _tableView.headerView = nil;
    _tableView.rowHeight = 22.0;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = hex_color(0x050608, 0.9);
    _tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _tableView.intercellSpacing = NSMakeSize(0.0, 1.0);
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

    NSTableColumn* aliasColumn = [[NSTableColumn alloc] initWithIdentifier:@"alias"];
    aliasColumn.width = 90.0;
    NSTableColumn* stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
    stateColumn.width = 78.0;
    NSTableColumn* endpointColumn = [[NSTableColumn alloc] initWithIdentifier:@"endpoint"];
    endpointColumn.width = 104.0;

    [_tableView addTableColumn:aliasColumn];
    [_tableView addTableColumn:stateColumn];
    [_tableView addTableColumn:endpointColumn];

    tableScroll.documentView = _tableView;
    [tableScroll.heightAnchor constraintGreaterThanOrEqualToConstant:132.0].active = YES;

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [body addArrangedSubview:connectRow];
    [body addArrangedSubview:scanRow];
    [body addArrangedSubview:_fleetStatusLabel];
    [body addArrangedSubview:bonjourRow];
    [body addArrangedSubview:_bonjourLabel];
    [body addArrangedSubview:tableScroll];

    return make_panel(@"设备墙", body);
}

- (NSView*)buildWorkspacePanel {
    _summaryLabel = make_label(@"未选择设备", 12.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _summaryLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _summaryLabel.maximumNumberOfLines = 2;
    _controlStatusLabel = make_label(@"参数状态：未选择设备", 12.0, NSFontWeightSemibold, hex_color(0xA8B7C2));
    _controlStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _controlStatusLabel.maximumNumberOfLines = 1;

    _productField = make_input(@"产品 UUID");
    _pointField = make_input(@"点位号", @"0");
    _jobField = make_input(@"任务 ID");
    _archiveLabel = make_label(@"归档：未选择设备", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _archiveLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _archivePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_archivePopup);
    [_archivePopup addItemWithTitle:@"暂无媒体"];
    _archivePopup.enabled = NO;

    _modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_modePopup);
    configure_popup_items(_modePopup, capture_mode_options());
    _modePopup.target = self;
    _modePopup.action = @selector(controlChanged:);
    select_popup_value(_modePopup, "photo");

    _focusPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_focusPopup);
    configure_popup_items(_focusPopup, focus_mode_options());
    _focusPopup.target = self;
    _focusPopup.action = @selector(controlChanged:);
    select_popup_value(_focusPopup, "continuousAuto");

    _lensPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_lensPopup);
    configure_popup_items(_lensPopup, lens_options());
    _lensPopup.target = self;
    _lensPopup.action = @selector(controlChanged:);
    select_popup_value(_lensPopup, "wide");

    _profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_profilePopup);
    configure_popup_items(_profilePopup, recording_profile_options());
    _profilePopup.target = self;
    _profilePopup.action = @selector(controlChanged:);
    select_popup_value(_profilePopup, "hevc");

    _flashToggle = make_toggle(@"闪光灯", self, @selector(togglePressed:));
    _inferenceToggle = make_toggle(@"推理", self, @selector(togglePressed:));
    _persistToggle = make_toggle(@"保存媒体", self, @selector(togglePressed:));
    _smoothAFToggle = make_toggle(@"平滑对焦", self, @selector(togglePressed:));

    NSButton* applyButton = make_button(@"应用参数", self, @selector(applyPatchPressed:));
    NSButton* photoButton = make_button(@"执行拍照", self, @selector(photoPressed:));
    NSButton* startRecordButton = make_button(@"开始录像", self, @selector(startRecordPressed:));
    NSButton* stopRecordButton = make_button(@"停止录像", self, @selector(stopRecordPressed:));
    NSButton* capsButton = make_button(@"读取能力", self, @selector(fetchCapabilitiesPressed:));
    NSButton* openArchiveButton = make_button(@"打开媒体", self, @selector(openArchivePressed:));
    NSButton* revealArchiveButton = make_button(@"定位文件", self, @selector(revealArchivePressed:));

    NSView* preview = make_preview_surface(&_previewImageView, &_previewTitleLabel, &_previewSubtitleLabel);

    NSStackView* contextRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [contextRow addArrangedSubview:_productField];
    [contextRow addArrangedSubview:_pointField];
    [contextRow addArrangedSubview:_jobField];
    [_pointField.widthAnchor constraintEqualToConstant:72.0].active = YES;
    [_jobField.widthAnchor constraintEqualToConstant:104.0].active = YES;

    NSStackView* archiveRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [archiveRow addArrangedSubview:_archivePopup];
    [archiveRow addArrangedSubview:openArchiveButton];
    [archiveRow addArrangedSubview:revealArchiveButton];
    [openArchiveButton.widthAnchor constraintEqualToConstant:78.0].active = YES;
    [revealArchiveButton.widthAnchor constraintEqualToConstant:68.0].active = YES;

    NSStackView* modeRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modeRow addArrangedSubview:make_label(@"模式", 11.0, NSFontWeightSemibold)];
    [modeRow addArrangedSubview:_modePopup];
    [modeRow addArrangedSubview:make_label(@"对焦", 11.0, NSFontWeightSemibold)];
    [modeRow addArrangedSubview:_focusPopup];
    [_modePopup.widthAnchor constraintEqualToConstant:100.0].active = YES;
    [_focusPopup.widthAnchor constraintEqualToConstant:110.0].active = YES;

    NSStackView* opticsRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [opticsRow addArrangedSubview:make_label(@"镜头", 11.0, NSFontWeightSemibold)];
    [opticsRow addArrangedSubview:_lensPopup];
    [opticsRow addArrangedSubview:make_label(@"编码", 11.0, NSFontWeightSemibold)];
    [opticsRow addArrangedSubview:_profilePopup];
    [_lensPopup.widthAnchor constraintEqualToConstant:110.0].active = YES;
    [_profilePopup.widthAnchor constraintEqualToConstant:100.0].active = YES;

    NSStackView* togglesTopRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    togglesTopRow.distribution = NSStackViewDistributionFillEqually;
    [togglesTopRow addArrangedSubview:_flashToggle];
    [togglesTopRow addArrangedSubview:_smoothAFToggle];

    NSStackView* togglesBottomRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    togglesBottomRow.distribution = NSStackViewDistributionFillEqually;
    [togglesBottomRow addArrangedSubview:_inferenceToggle];
    [togglesBottomRow addArrangedSubview:_persistToggle];

    NSStackView* actionRowTop = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    actionRowTop.distribution = NSStackViewDistributionFillEqually;
    [actionRowTop addArrangedSubview:applyButton];
    [actionRowTop addArrangedSubview:capsButton];
    [actionRowTop addArrangedSubview:photoButton];

    NSStackView* actionRowBottom = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    actionRowBottom.distribution = NSStackViewDistributionFillEqually;
    [actionRowBottom addArrangedSubview:startRecordButton];
    [actionRowBottom addArrangedSubview:stopRecordButton];

    NSView* fpsRow = make_slider_row(@"帧率", &_fpsSlider, &_fpsValue, self, @selector(sliderChanged:), 1.0, 60.0);
    NSView* temperatureRow = make_slider_row(@"色温", &_temperatureSlider, &_temperatureValue, self, @selector(sliderChanged:), 2800.0, 8000.0);
    NSView* tintRow = make_slider_row(@"色调", &_tintSlider, &_tintValue, self, @selector(sliderChanged:), -150.0, 150.0);
    NSView* exposureRow = make_slider_row(@"曝光时间", &_exposureSlider, &_exposureValue, self, @selector(sliderChanged:), 0.0001, 0.5);
    NSView* isoRow = make_slider_row(@"ISO", &_isoSlider, &_isoValue, self, @selector(sliderChanged:), 20.0, 1600.0);
    NSView* evRow = make_slider_row(@"EV", &_evSlider, &_evValue, self, @selector(sliderChanged:), -8.0, 8.0);
    NSView* zoomRow = make_slider_row(@"变焦", &_zoomSlider, &_zoomValue, self, @selector(sliderChanged:), 1.0, 15.0);
    NSView* lensRow = make_slider_row(@"焦距位置", &_lensSlider, &_lensValue, self, @selector(sliderChanged:), 0.0, 1.0);

    NSStackView* imagingRowTop = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    imagingRowTop.distribution = NSStackViewDistributionFillEqually;
    [imagingRowTop addArrangedSubview:fpsRow];
    [imagingRowTop addArrangedSubview:temperatureRow];

    NSStackView* imagingRowBottom = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    imagingRowBottom.distribution = NSStackViewDistributionFillEqually;
    [imagingRowBottom addArrangedSubview:tintRow];
    [imagingRowBottom addArrangedSubview:exposureRow];

    NSStackView* imagingCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 5.0);
    [imagingCardBody addArrangedSubview:imagingRowTop];
    [imagingCardBody addArrangedSubview:imagingRowBottom];

    NSStackView* lensRowTop = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    lensRowTop.distribution = NSStackViewDistributionFillEqually;
    [lensRowTop addArrangedSubview:isoRow];
    [lensRowTop addArrangedSubview:evRow];

    NSStackView* lensRowBottom = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    lensRowBottom.distribution = NSStackViewDistributionFillEqually;
    [lensRowBottom addArrangedSubview:zoomRow];
    [lensRowBottom addArrangedSubview:lensRow];

    NSStackView* lensCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 5.0);
    [lensCardBody addArrangedSubview:lensRowTop];
    [lensCardBody addArrangedSubview:lensRowBottom];

    NSStackView* leftCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [leftCardBody addArrangedSubview:preview];
    [leftCardBody addArrangedSubview:_summaryLabel];
    [leftCardBody addArrangedSubview:contextRow];
    [leftCardBody addArrangedSubview:archiveRow];
    [leftCardBody addArrangedSubview:_archiveLabel];
    NSView* leftCard = make_panel(@"预览 / 任务", leftCardBody);
    [leftCard.widthAnchor constraintEqualToConstant:290.0].active = YES;

    NSStackView* sliderGrid = make_stack(NSUserInterfaceLayoutOrientationVertical, 5.0);
    [sliderGrid addArrangedSubview:imagingRowTop];
    [sliderGrid addArrangedSubview:imagingRowBottom];
    [sliderGrid addArrangedSubview:lensRowTop];
    [sliderGrid addArrangedSubview:lensRowBottom];

    NSStackView* rightCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 5.0);
    [rightCardBody addArrangedSubview:_controlStatusLabel];
    [rightCardBody addArrangedSubview:modeRow];
    [rightCardBody addArrangedSubview:opticsRow];
    [rightCardBody addArrangedSubview:togglesTopRow];
    [rightCardBody addArrangedSubview:togglesBottomRow];
    [rightCardBody addArrangedSubview:actionRowTop];
    [rightCardBody addArrangedSubview:actionRowBottom];
    [rightCardBody addArrangedSubview:sliderGrid];
    NSView* rightCard = make_panel(@"采集 / 参数", rightCardBody);
    [rightCard.widthAnchor constraintGreaterThanOrEqualToConstant:430.0].active = YES;

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    body.distribution = NSStackViewDistributionFill;
    body.alignment = NSLayoutAttributeTop;
    [body addArrangedSubview:leftCard];
    [body addArrangedSubview:rightCard];

    return make_panel(@"设备工作区", body);
}

- (NSView*)buildSidePanel {
    _networkLabel = make_label(@"网络：未选择设备", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _networkLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _networkLabel.maximumNumberOfLines = 1;
    _capabilityLabel = make_label(@"能力：未选择设备", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _capabilityLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _capabilityLabel.maximumNumberOfLines = 1;
    _modelsLabel = make_label(@"模型：未选择设备", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _modelsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _modelsLabel.maximumNumberOfLines = 2;

    _aliasField = make_input(@"设备名称");
    _modelField = make_input(@"模型 ID");
    _modelVersionField = make_input(@"版本", @"1.0.0");
    _modelPathField = make_input(@"模型文件路径");
    _activateAfterInstallToggle = make_toggle(@"上传后启用", self, @selector(togglePressed:));

    NSButton* aliasButton = make_button(@"应用名称", self, @selector(aliasPressed:));
    NSButton* activateButton = make_button(@"启用", self, @selector(activateModelPressed:));
    NSButton* deactivateButton = make_button(@"停用", self, @selector(deactivateModelPressed:));
    NSButton* removeButton = make_button(@"删除", self, @selector(removeModelPressed:));
    _browseModelButton = make_button(@"选择文件", self, @selector(openModelPressed:));
    _uploadButton = make_button(@"上传本机", self, @selector(uploadModelPressed:));
    _uploadAllButton = make_button(@"上传全机", self, @selector(uploadModelAllPressed:));
    NSButton* photoAllButton = make_button(@"全机拍照", self, @selector(photoAllPressed:));
    NSButton* aiOnButton = make_button(@"全机推理", self, @selector(aiOnAllPressed:));
    NSButton* aiOffButton = make_button(@"全机停推", self, @selector(aiOffAllPressed:));

    NSStackView* aliasRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [aliasRow addArrangedSubview:_aliasField];
    [aliasRow addArrangedSubview:aliasButton];
    [aliasButton.widthAnchor constraintEqualToConstant:82.0].active = YES;

    NSStackView* statusCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [statusCardBody addArrangedSubview:_networkLabel];
    [statusCardBody addArrangedSubview:_capabilityLabel];
    [statusCardBody addArrangedSubview:_modelsLabel];
    [statusCardBody addArrangedSubview:aliasRow];

    NSStackView* modelRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modelRow addArrangedSubview:_modelField];
    [modelRow addArrangedSubview:_modelVersionField];
    [modelRow addArrangedSubview:_activateAfterInstallToggle];
    [_modelVersionField.widthAnchor constraintEqualToConstant:64.0].active = YES;

    NSStackView* modelPathRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modelPathRow addArrangedSubview:_modelPathField];

    NSStackView* modelActionRowTop = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    modelActionRowTop.distribution = NSStackViewDistributionFillEqually;
    [modelActionRowTop addArrangedSubview:activateButton];
    [modelActionRowTop addArrangedSubview:deactivateButton];
    [modelActionRowTop addArrangedSubview:removeButton];

    NSStackView* modelActionRowBottom = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    modelActionRowBottom.distribution = NSStackViewDistributionFillEqually;
    [modelActionRowBottom addArrangedSubview:_browseModelButton];
    [modelActionRowBottom addArrangedSubview:_uploadButton];
    [modelActionRowBottom addArrangedSubview:_uploadAllButton];

    NSStackView* batchRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    batchRow.distribution = NSStackViewDistributionFillEqually;
    [batchRow addArrangedSubview:photoAllButton];
    [batchRow addArrangedSubview:aiOnButton];
    [batchRow addArrangedSubview:aiOffButton];

    NSTextField* gatewayLabel = make_label(@"网关：/api/v1/batch ｜ /api/v1/devices ｜ 49020", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    gatewayLabel.lineBreakMode = NSLineBreakByWordWrapping;
    gatewayLabel.maximumNumberOfLines = 2;

    [statusCardBody addArrangedSubview:batchRow];
    [statusCardBody addArrangedSubview:gatewayLabel];
    NSView* statusCard = make_panel(@"设备 / 批处理", statusCardBody);

    NSStackView* modelCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [modelCardBody addArrangedSubview:modelRow];
    [modelCardBody addArrangedSubview:modelPathRow];
    [modelCardBody addArrangedSubview:modelActionRowTop];
    [modelCardBody addArrangedSubview:modelActionRowBottom];
    NSView* modelCard = make_panel(@"模型管理", modelCardBody);

    NSScrollView* rawScroll = make_text_scroll(&_rawView);
    [rawScroll.heightAnchor constraintGreaterThanOrEqualToConstant:54.0].active = YES;

    NSStackView* diagnosticsCardBody = make_stack(NSUserInterfaceLayoutOrientationVertical, 4.0);
    [diagnosticsCardBody addArrangedSubview:rawScroll];
    NSView* diagnosticsCard = make_panel(@"诊断", diagnosticsCardBody);

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [body addArrangedSubview:statusCard];
    [body addArrangedSubview:modelCard];
    [body addArrangedSubview:diagnosticsCard];

    return make_panel(@"控制矩阵", body);
}

- (NSView*)buildTerminalPanel {
    NSScrollView* terminalScroll = make_text_scroll(&_terminalView);
    [terminalScroll.heightAnchor constraintGreaterThanOrEqualToConstant:36.0].active = YES;

    _terminalSearchField = make_input(@"搜索日志");
    _terminalLevelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_terminalLevelPopup);
    configure_popup_items(_terminalLevelPopup, terminal_level_options());
    _terminalLevelPopup.target = self;
    _terminalLevelPopup.action = @selector(terminalFilterChanged:);
    select_popup_value(_terminalLevelPopup, "all");

    _terminalScopePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    style_popup(_terminalScopePopup);
    configure_popup_items(_terminalScopePopup, terminal_scope_options());
    _terminalScopePopup.target = self;
    _terminalScopePopup.action = @selector(terminalFilterChanged:);
    select_popup_value(_terminalScopePopup, "all");

    NSButton* exportButton = make_button(@"导出日志", self, @selector(exportTerminalPressed:));

    NSStackView* filterRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [filterRow addArrangedSubview:_terminalSearchField];
    [filterRow addArrangedSubview:_terminalLevelPopup];
    [filterRow addArrangedSubview:_terminalScopePopup];
    [filterRow addArrangedSubview:exportButton];
    [_terminalLevelPopup.widthAnchor constraintEqualToConstant:104.0].active = YES;
    [_terminalScopePopup.widthAnchor constraintEqualToConstant:110.0].active = YES;
    [exportButton.widthAnchor constraintEqualToConstant:84.0].active = YES;

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 6.0);
    [body addArrangedSubview:filterRow];
    [body addArrangedSubview:terminalScroll];

    return make_panel(@"数据终端", body);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_devices.size());
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;

    if (row < 0 || row >= static_cast<NSInteger>(_devices.size())) {
        return nil;
    }

    NSString* identifier = tableColumn.identifier;
    NSTableCellView* cell = [tableView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;

        NSTextField* text = make_label(@"", 12.0, NSFontWeightRegular);
        text.frame = NSMakeRect(6.0, 4.0, tableColumn.width - 12.0, 20.0);
        text.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:text];
        cell.textField = text;
    }

    const DeviceSnapshot& snapshot = _devices[static_cast<std::size_t>(row)];

    std::string value;
    if ([identifier isEqualToString:@"alias"]) {
        value = snapshot.alias.empty() ? snapshot.device_id : snapshot.alias;
    } else if ([identifier isEqualToString:@"state"]) {
        value = device_state_digest(snapshot);
    } else {
        value = snapshot.host.empty() ? snapshot.device_id : (snapshot.host + ":" + std::to_string(snapshot.port));
    }

    cell.textField.stringValue = to_ns_string(value);
    cell.textField.textColor = snapshot.online ? hex_color(0xF3F6F8) : hex_color(0xA8B7C2, 0.65);
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification;
    const NSInteger row = _tableView.selectedRow;
    if (row < 0 || row >= static_cast<NSInteger>(_devices.size())) {
        _selectedDeviceId.clear();
        _lastControlSyncSignature.clear();
        _pendingControlDeviceId.clear();
        _controlDraftDirty = false;
        _controlApplyPending = false;
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
        [self refreshPresentation];
        return;
    }

    const std::string next_device_id = _devices[static_cast<std::size_t>(row)].device_id;
    const bool selection_changed = next_device_id != _selectedDeviceId;
    _selectedDeviceId = next_device_id;

    if (selection_changed) {
        _lastControlSyncSignature.clear();
        _pendingControlDeviceId.clear();
        _controlDraftDirty = false;
        _controlApplyPending = false;
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
        [self loadControlsFromCurrentSelection];
    }
    [self refreshPresentation];
}

- (void)refreshUI:(id)sender {
    (void)sender;

    _devices = _runtime->snapshots();
    [_tableView reloadData];

    if (_selectedDeviceId.empty() && !_devices.empty() && _tableView.selectedRow < 0) {
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }

    if (!_selectedDeviceId.empty()) {
        const std::string selected_device_id = _selectedDeviceId;
        const auto iterator = std::find_if(_devices.begin(), _devices.end(), [&selected_device_id](const DeviceSnapshot& snapshot) {
            return snapshot.device_id == selected_device_id;
        });
        if (iterator != _devices.end()) {
            const NSInteger row = static_cast<NSInteger>(std::distance(_devices.begin(), iterator));
            if (_tableView.selectedRow != row) {
                [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            }
        } else if (_tableView.selectedRow >= 0 && _tableView.selectedRow < static_cast<NSInteger>(_devices.size())) {
            _selectedDeviceId = _devices[static_cast<std::size_t>(_tableView.selectedRow)].device_id;
            _lastControlSyncSignature.clear();
            _pendingControlDeviceId.clear();
            _controlDraftDirty = false;
            _controlApplyPending = false;
        } else if (!_devices.empty()) {
            _selectedDeviceId = _devices.front().device_id;
            _lastControlSyncSignature.clear();
            _pendingControlDeviceId.clear();
            _controlDraftDirty = false;
            _controlApplyPending = false;
            [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        }
    }

    const std::vector<UiLogEntry> logs = _runtime->logs();
    [self refreshTerminalPresentationWithLogs:logs];
    _lastLogCount = logs.size();

    const std::vector<ModelTransferSnapshot> transfers = _runtime->model_transfers();
    _modelTransfers = transfers;
    std::ostringstream transfer_stream;
    if (transfers.empty()) {
        transfer_stream << "暂无模型传输记录";
    } else {
        for (std::size_t index = 0; index < transfers.size(); ++index) {
            if (index > 0) {
                transfer_stream << "\n\n";
            }
            transfer_stream << transfer_digest(transfers[index]);
        }
    }
    _latestTransferDigest = transfer_stream.str();
    _transferView.string = to_ns_string(transfer_stream.str());

    if (const DeviceSnapshot* snapshot = [self currentSnapshot]; snapshot != nullptr) {
        const std::string signature = control_sync_signature(*snapshot);
        const bool controls_aligned = controls_match_snapshot(
            *snapshot,
            _modePopup,
            _focusPopup,
            _lensPopup,
            _profilePopup,
            _fpsSlider,
            _temperatureSlider,
            _tintSlider,
            _exposureSlider,
            _isoSlider,
            _evSlider,
            _zoomSlider,
            _lensSlider,
            _flashToggle,
            _inferenceToggle,
            _persistToggle,
            _smoothAFToggle
        );
        const bool apply_timed_out = _controlApplyPending
            && (_pendingControlDeviceId != snapshot->device_id
                || std::chrono::steady_clock::now() - _controlApplyStartedAt > std::chrono::seconds(2));

        if (_controlApplyPending && controls_aligned) {
            _controlApplyPending = false;
            _pendingControlDeviceId.clear();
            _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
            _lastControlSyncSignature = signature;
        } else if (_controlApplyPending && apply_timed_out) {
            _controlApplyPending = false;
            _pendingControlDeviceId.clear();
            _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
            _lastControlSyncSignature.clear();
        }

        if (!_controlDraftDirty && !_controlApplyPending && signature != _lastControlSyncSignature) {
            _lastControlSyncSignature = signature;
            [self loadControlsFromCurrentSelection];
        }
    } else {
        _pendingControlDeviceId.clear();
        _controlDraftDirty = false;
        _controlApplyPending = false;
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
    }

    [self refreshPresentation];
    [self refreshSliderLabels];
    [self refreshControlAvailability];
}

- (void)refreshTerminalPresentationWithLogs:(const std::vector<UiLogEntry>&)logs {
    if (_terminalView == nil) {
        return;
    }

    const std::string search = to_std_string(_terminalSearchField.stringValue);
    const std::string selected_level = _terminalLevelPopup.selectedItem == nil ? "all" : popup_selected_value(_terminalLevelPopup);
    const bool current_device_scope = popup_selected_value(_terminalScopePopup) == "current";
    const DeviceSnapshot* current_snapshot = [self currentSnapshot];

    NSMutableAttributedString* output = [[NSMutableAttributedString alloc] init];
    std::size_t matched_count = 0;

    for (const auto& entry : logs) {
        const std::string level = lowercase_copy(entry.level);
        const bool level_matches = selected_level == "all" || level == selected_level;

        bool scope_matches = true;
        if (current_device_scope) {
            scope_matches = current_snapshot != nullptr
                && (
                    contains_case_insensitive(entry.message, current_snapshot->device_id)
                    || contains_case_insensitive(entry.message, current_snapshot->alias)
                    || contains_case_insensitive(entry.message, current_snapshot->host)
                );
        }

        const std::string line = log_entry_text(entry);
        const bool search_matches = contains_case_insensitive(line, search);

        if (!level_matches || !scope_matches || !search_matches) {
            continue;
        }

        ++matched_count;
        NSDictionary* attributes = @{
            NSForegroundColorAttributeName: log_color_for_level(entry.level),
            NSFontAttributeName: mono_font(12.0)
        };
        [output appendAttributedString:[[NSAttributedString alloc] initWithString:to_ns_string(line + "\n") attributes:attributes]];
    }

    if (matched_count == 0) {
        NSDictionary* empty_attributes = @{
            NSForegroundColorAttributeName: hex_color(0xA8B7C2),
            NSFontAttributeName: mono_font(12.0)
        };
        [output appendAttributedString:[[NSAttributedString alloc] initWithString:@"当前筛选条件下没有匹配日志\n" attributes:empty_attributes]];
    }

    [_terminalView.textStorage setAttributedString:output];
    [_terminalView scrollRangeToVisible:NSMakeRange(_terminalView.string.length, 0)];

    if (_terminalStatsLabel != nil) {
        std::ostringstream stream;
        stream
            << "日志：" << matched_count << "/" << logs.size()
            << " | 级别=" << localized_log_level_name(selected_level)
            << " | 范围=" << (current_device_scope ? (current_snapshot == nullptr ? "未选设备" : "当前设备") : "全部设备");
        _terminalStatsLabel.stringValue = to_ns_string(stream.str());
    }
}

- (void)refreshPresentation {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        _summaryLabel.stringValue = @"未选择设备";
        _networkLabel.stringValue = @"网络：未选择设备";
        _capabilityLabel.stringValue = @"能力：未选择设备";
        _modelsLabel.stringValue = @"模型：未选择设备";
        _rawView.string = @"";
        [self refreshArchivePresentation];
        [self refreshPreviewForSnapshot:nullptr];
        [self refreshModelTransferPresentation];
        return;
    }

    const Value* status = snapshot->status_payload.is_object() ? &snapshot->status_payload : nullptr;
    const std::string capture_mode = status == nullptr ? "" : string_or(find_in_object(*status, "captureMode"));
    const std::string focus_mode = status == nullptr ? "" : string_or(find_in_object(*status, "focusMode"));
    const std::string selected_lens = status == nullptr ? "" : string_or(find_in_object(*status, "selectedLens"));
    const std::string profile = status == nullptr ? "" : string_or(find_in_object(*status, "recordingProfile"));

    std::ostringstream summary;
    summary
        << snapshot->device_id
        << " | " << (snapshot->alias.empty() ? snapshot->device_id : snapshot->alias)
        << " | " << (snapshot->online ? "在线" : "离线")
        << " | " << snapshot->host << ":" << snapshot->port
        << " | 活跃=" << last_active_text(*snapshot)
        << " | 最近时间=" << snapshot->last_seen
        << " | 最近消息=" << snapshot->last_message << "\n"
        << "模式=" << localized_capture_mode(capture_mode)
        << " | 对焦=" << localized_focus_mode(focus_mode)
        << " | 镜头=" << localized_lens_name(selected_lens)
        << " | 编码=" << localized_profile_name(profile)
        << " | 录像=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "isRecording"), false))
        << " | 推理=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "inferenceEnabled"), false))
        << " | 保存=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "persistMediaEnabled"), false))
        << " | 闪光灯=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "flashEnabled"), false))
        << " | 平滑对焦=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "smoothAutoFocusEnabled"), false))
        << " | 预览帧=" << snapshot->preview_frame_index << "\n"
        << "IP=" << network_digest(*snapshot) << " | 最后活跃=" << last_active_text(*snapshot) << "\n"
        << "模型=" << models_digest(*snapshot);
    _summaryLabel.stringValue = to_ns_string(summary.str());
    _networkLabel.stringValue = to_ns_string("网络：" + network_digest(*snapshot) + " | 最后活跃=" + last_active_text(*snapshot));
    _capabilityLabel.stringValue = to_ns_string("能力：" + capability_digest(*snapshot));
    _modelsLabel.stringValue = to_ns_string("模型：" + models_digest(*snapshot));
    std::string diagnostic_text;
    if (!_latestTransferDigest.empty()) {
        diagnostic_text += "模型传输\n";
        diagnostic_text += _latestTransferDigest;
        diagnostic_text += "\n\n";
    }
    diagnostic_text += snapshot_dump(*snapshot);
    _rawView.string = to_ns_string(diagnostic_text);
    [self refreshArchivePresentation];
    [self refreshPreviewForSnapshot:snapshot];
    [self refreshModelTransferPresentation];
}

- (void)refreshArchivePresentation {
    if (_archivePopup == nil || _archiveLabel == nil) {
        return;
    }

    [_archivePopup removeAllItems];
    _archivePaths.clear();

    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        [_archivePopup addItemWithTitle:@"未选择设备"];
        _archivePopup.enabled = NO;
        _archiveLabel.stringValue = @"归档：未选择设备";
        return;
    }

    const auto archive_paths = recent_media_paths_for_device(*snapshot);
    if (archive_paths.empty()) {
        [_archivePopup addItemWithTitle:@"暂无归档媒体"];
        _archivePopup.enabled = NO;
        _archiveLabel.stringValue = to_ns_string(
            "归档：等待远程拍照/录像推送到 "
            + compact_path(vino::desktop::media_root_for_device(snapshot->device_id).string())
        );
        return;
    }

    _archivePopup.enabled = YES;
    for (const auto& path : archive_paths) {
        const std::string path_string = path.string();
        _archivePaths.push_back(path_string);
        [_archivePopup addItemWithTitle:to_ns_string(path.filename().string())];
        _archivePopup.lastItem.representedObject = to_ns_string(path_string);
    }

    _archiveLabel.stringValue = to_ns_string(
        "归档：" + std::to_string(_archivePaths.size()) + " 个文件 · "
        + compact_path(vino::desktop::media_root_for_device(snapshot->device_id).string())
    );
}

- (void)loadControlsFromCurrentSelection {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        _controlDraftDirty = false;
        _controlApplyPending = false;
        _pendingControlDeviceId.clear();
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
        [self refreshControlAvailability];
        return;
    }

    _aliasField.stringValue = to_ns_string(snapshot->alias);
    if (!snapshot->status_payload.is_object()) {
        _controlDraftDirty = false;
        _controlApplyPending = false;
        _pendingControlDeviceId.clear();
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
        [self refreshControlAvailability];
        return;
    }

    const Value& status = snapshot->status_payload;

    const auto* captureMode = find_in_object(status, "captureMode");
    if (captureMode != nullptr && captureMode->is_string()) {
        select_popup_value(_modePopup, captureMode->as_string());
    }

    const auto* focusMode = find_in_object(status, "focusMode");
    if (focusMode != nullptr && focusMode->is_string()) {
        select_popup_value(_focusPopup, focusMode->as_string());
    }

    const auto* selectedLens = find_in_object(status, "selectedLens");
    if (selectedLens != nullptr && selectedLens->is_string()) {
        select_popup_value(_lensPopup, selectedLens->as_string());
    }

    const auto* recordingProfile = find_in_object(status, "recordingProfile");
    if (recordingProfile != nullptr && recordingProfile->is_string()) {
        select_popup_value(_profilePopup, recordingProfile->as_string());
    }

    const auto* selectedModelId = find_in_object(status, "selectedModelId");
    if (selectedModelId != nullptr && selectedModelId->is_string()) {
        _modelField.stringValue = to_ns_string(selectedModelId->as_string());
    } else if (const auto activeModelIds = string_array_or_empty(find_in_object(status, "activeModelIds")); !activeModelIds.empty()) {
        _modelField.stringValue = to_ns_string(activeModelIds.front());
    }

    _flashToggle.state = bool_or(find_in_object(status, "flashEnabled"), false) ? NSControlStateValueOn : NSControlStateValueOff;
    _smoothAFToggle.state = bool_or(find_in_object(status, "smoothAutoFocusEnabled"), false) ? NSControlStateValueOn : NSControlStateValueOff;
    _inferenceToggle.state = bool_or(find_in_object(status, "inferenceEnabled"), false) ? NSControlStateValueOn : NSControlStateValueOff;
    _persistToggle.state = bool_or(find_in_object(status, "persistMediaEnabled"), false) ? NSControlStateValueOn : NSControlStateValueOff;

    if (const auto* settings = find_in_object(status, "settings"); settings != nullptr && settings->is_object()) {
        _fpsSlider.doubleValue = number_or(find_in_object(*settings, "frameRate"), _fpsSlider.doubleValue);
        _temperatureSlider.doubleValue = number_or(find_in_object(*settings, "whiteBalanceTemperature"), _temperatureSlider.doubleValue);
        _tintSlider.doubleValue = number_or(find_in_object(*settings, "whiteBalanceTint"), _tintSlider.doubleValue);
        _exposureSlider.doubleValue = number_or(find_in_object(*settings, "exposureSeconds"), _exposureSlider.doubleValue);
        _isoSlider.doubleValue = number_or(find_in_object(*settings, "iso"), _isoSlider.doubleValue);
        _evSlider.doubleValue = number_or(find_in_object(*settings, "exposureBias"), _evSlider.doubleValue);
        _zoomSlider.doubleValue = number_or(find_in_object(*settings, "zoomFactor"), _zoomSlider.doubleValue);
        _lensSlider.doubleValue = number_or(find_in_object(*settings, "lensPosition"), _lensSlider.doubleValue);
    }

    if (snapshot->capabilities_payload.is_object()) {
        const Value& capabilities_payload = snapshot->capabilities_payload;
        if (const auto* capabilities = find_in_object(capabilities_payload, "capabilities"); capabilities != nullptr && capabilities->is_object()) {
            set_slider_range_from_capability(find_in_object(*capabilities, "frameRate"), _fpsSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "whiteBalanceTemperature"), _temperatureSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "whiteBalanceTint"), _tintSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "exposureSeconds"), _exposureSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "iso"), _isoSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "exposureBias"), _evSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "zoomFactor"), _zoomSlider);
            set_slider_range_from_capability(find_in_object(*capabilities, "lensPosition"), _lensSlider);

            if (const auto* supportedLenses = find_in_object(*capabilities, "supportedLenses"); supportedLenses != nullptr && supportedLenses->is_array()) {
                std::vector<std::string> items;
                for (const auto& value : supportedLenses->as_array()) {
                    if (value.is_string()) {
                        items.push_back(value.as_string());
                    }
                }
                if (!items.empty()) {
                    configure_popup_items(_lensPopup, lens_options(items));
                    select_popup_value(_lensPopup, string_or(selectedLens, items.front()));
                }
            }

            if (const auto* supportsProRes = find_in_object(*capabilities, "supportsProRes"); supportsProRes != nullptr) {
                configure_popup_items(_profilePopup, recording_profile_options(bool_or(supportsProRes, false)));
                select_popup_value(_profilePopup, string_or(recordingProfile, "hevc"));
            }
        }
    }

    _controlDraftDirty = false;
    _controlApplyPending = false;
    _pendingControlDeviceId.clear();
    _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
    [self refreshSliderLabels];
    [self refreshControlAvailability];
}

- (const DeviceSnapshot*)currentSnapshot {
    if (_selectedDeviceId.empty()) {
        return nullptr;
    }

    const std::string selected_device_id = _selectedDeviceId;
    const auto iterator = std::find_if(_devices.begin(), _devices.end(), [&selected_device_id](const DeviceSnapshot& snapshot) {
        return snapshot.device_id == selected_device_id;
    });

    if (iterator == _devices.end()) {
        return nullptr;
    }

    return &(*iterator);
}

- (void)refreshPreviewForSnapshot:(const DeviceSnapshot*)snapshot {
    if (_previewImageView == nil || _previewTitleLabel == nil || _previewSubtitleLabel == nil) {
        return;
    }

    if (snapshot == nullptr) {
        _previewImageView.image = nil;
        _previewTitleLabel.stringValue = @"实时预览待命";
        _previewSubtitleLabel.stringValue = @"请选择设备，以查看实时镜像、最新媒体、推理摘要和运行状态";
        return;
    }

    const std::string inference_summary = inference_digest(*snapshot);
    if (!snapshot->preview_jpeg_base64.empty() && snapshot->preview_frame_index > 0) {
        NSData* image_data = [[NSData alloc] initWithBase64EncodedString:to_ns_string(snapshot->preview_jpeg_base64) options:0];
        NSImage* image = image_data == nil ? nil : [[NSImage alloc] initWithData:image_data];
        _previewImageView.image = image;
        _previewTitleLabel.stringValue = @"实时镜像";
        _previewSubtitleLabel.stringValue = to_ns_string(
            "帧=" + std::to_string(snapshot->preview_frame_index)
            + " | 尺寸=" + std::to_string(snapshot->preview_image_width) + "x" + std::to_string(snapshot->preview_image_height)
            + " | 接收时间=" + snapshot->preview_seen + "\n"
            + "最新推理：" + inference_summary
        );
        return;
    }

    if (!snapshot->last_media_path.empty()) {
        const bool is_image = is_image_media_path(snapshot->last_media_path);
        const std::string category = snapshot->last_media_category.empty() ? "媒体" : snapshot->last_media_category;
        const std::string file_name = std::filesystem::path(snapshot->last_media_path).filename().string();

        if (is_image) {
            NSImage* image = [[NSImage alloc] initWithContentsOfFile:to_ns_string(snapshot->last_media_path)];
            _previewImageView.image = image;
        } else {
            _previewImageView.image = nil;
        }

        _previewTitleLabel.stringValue = to_ns_string(std::string(is_image ? "最新图像" : "最新文件") + " · " + category);
        _previewSubtitleLabel.stringValue = to_ns_string(
            file_name + "\n"
            + compact_path(snapshot->last_media_path) + "\n"
            + "接收时间=" + (snapshot->last_media_seen.empty() ? snapshot->last_seen : snapshot->last_media_seen)
            + " | " + inference_summary
        );
        return;
    }

    _previewImageView.image = nil;
    _previewTitleLabel.stringValue = @"尚未收到媒体";
    _previewSubtitleLabel.stringValue = to_ns_string(
        "最新推理：" + inference_summary + "\n"
        + "远程拍照或录像完成后，媒体文件会出现在此处"
    );
}

- (void)refreshSliderLabels {
    _fpsValue.stringValue = [NSString stringWithFormat:@"%.1f", _fpsSlider.doubleValue];
    _temperatureValue.stringValue = [NSString stringWithFormat:@"%.0f", _temperatureSlider.doubleValue];
    _tintValue.stringValue = [NSString stringWithFormat:@"%.0f", _tintSlider.doubleValue];
    _exposureValue.stringValue = [NSString stringWithFormat:@"%.4f", _exposureSlider.doubleValue];
    _isoValue.stringValue = [NSString stringWithFormat:@"%.0f", _isoSlider.doubleValue];
    _evValue.stringValue = [NSString stringWithFormat:@"%.2f", _evSlider.doubleValue];
    _zoomValue.stringValue = [NSString stringWithFormat:@"%.2f", _zoomSlider.doubleValue];
    _lensValue.stringValue = [NSString stringWithFormat:@"%.2f", _lensSlider.doubleValue];
}

- (void)refreshControlAvailability {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    const bool hasSelection = snapshot != nullptr;
    const bool isOnline = hasSelection && snapshot->online;

    bool supportsSmoothAF = true;
    bool supportsFlash = true;

    if (snapshot != nullptr && snapshot->capabilities_payload.is_object()) {
        if (const auto* capabilities = find_in_object(snapshot->capabilities_payload, "capabilities"); capabilities != nullptr && capabilities->is_object()) {
            supportsSmoothAF = bool_or(find_in_object(*capabilities, "supportsSmoothAutoFocus"), true);
            supportsFlash = bool_or(find_in_object(*capabilities, "supportsFlash"), true);
        }
    }

    const bool lockedFocus = popup_selected_value(_focusPopup) == "locked";

    _productField.enabled = hasSelection;
    _pointField.enabled = hasSelection;
    _jobField.enabled = hasSelection;
    _aliasField.enabled = hasSelection;
    _modelField.enabled = hasSelection;
    _modelVersionField.enabled = hasSelection;
    _activateAfterInstallToggle.enabled = hasSelection;

    _modePopup.enabled = isOnline;
    _focusPopup.enabled = isOnline;
    _lensPopup.enabled = isOnline;
    _profilePopup.enabled = isOnline;

    _fpsSlider.enabled = isOnline;
    _temperatureSlider.enabled = isOnline;
    _tintSlider.enabled = isOnline;
    _exposureSlider.enabled = isOnline;
    _isoSlider.enabled = isOnline;
    _evSlider.enabled = isOnline;
    _zoomSlider.enabled = isOnline;
    _lensSlider.enabled = isOnline && lockedFocus;

    _flashToggle.enabled = isOnline && supportsFlash;
    _smoothAFToggle.enabled = isOnline && supportsSmoothAF && !lockedFocus;
    _inferenceToggle.enabled = isOnline;
    _persistToggle.enabled = isOnline;
    [self refreshControlStatusPresentation];
    [self refreshModelTransferPresentation];
}

- (void)refreshControlStatusPresentation {
    if (_controlStatusLabel == nil) {
        return;
    }

    const DeviceSnapshot* snapshot = [self currentSnapshot];
    NSString* text = @"参数状态：未选择设备";
    NSColor* color = hex_color(0xA8B7C2);

    if (snapshot != nullptr) {
        if (!snapshot->online) {
            text = @"参数状态：设备离线";
            color = hex_color(0xA8B7C2);
        } else if (_controlApplyPending) {
            text = @"参数状态：下发中，等待设备确认";
            color = hex_color(0xFFC56B);
        } else if (_controlDraftDirty) {
            text = @"参数状态：有未应用改动";
            color = hex_color(0xFFC56B);
        } else {
            text = @"参数状态：已同步到设备";
            color = hex_color(0x62F0FF);
        }
    }

    _controlStatusLabel.stringValue = text;
    _controlStatusLabel.textColor = color;
}

- (void)refreshModelTransferPresentation {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    const std::vector<std::string> online_device_ids = [self onlineDeviceIds];
    const ModelTransferSnapshot* selected_transfer = snapshot == nullptr
        ? nullptr
        : latest_active_transfer_for_device(_modelTransfers, snapshot->device_id);
    const bool selected_upload_busy = snapshot != nullptr && selected_transfer != nullptr;
    const bool any_upload_busy = has_active_transfer_for_any_device(_modelTransfers, online_device_ids);

    if (_browseModelButton != nil) {
        _browseModelButton.enabled = YES;
    }
    if (_uploadButton != nil) {
        _uploadButton.enabled = snapshot != nullptr && snapshot->online && !selected_upload_busy;
        _uploadButton.title = selected_upload_busy ? @"上传中" : @"上传本机";
    }
    if (_uploadAllButton != nil) {
        _uploadAllButton.enabled = !online_device_ids.empty() && !any_upload_busy;
        _uploadAllButton.title = any_upload_busy ? @"全机上传中" : @"上传全机";
    }

    if (_modelsLabel == nil || snapshot == nullptr) {
        return;
    }

    std::string text = "模型：" + models_digest(*snapshot);
    if (selected_transfer != nullptr) {
        text += " | " + active_transfer_summary(*selected_transfer);
    }
    _modelsLabel.stringValue = to_ns_string(text);
    _modelsLabel.textColor = selected_transfer != nullptr ? hex_color(0xFFC56B) : hex_color(0xA8B7C2);
}

- (TriggerContext)currentContext {
    TriggerContext context;
    context.product_uuid = to_std_string(_productField.stringValue);
    context.point_index = std::max(0, _pointField.intValue);
    context.job_id = to_std_string(_jobField.stringValue);
    return context;
}

- (void)dispatchToSelectedAction:(const std::string&)action payload:(const Value&)payload {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        return;
    }

    _runtime->dispatch_to_device(snapshot->device_id, action, [self currentContext], payload);
}

- (std::vector<std::string>)onlineDeviceIds {
    std::vector<std::string> device_ids;
    for (const auto& snapshot : _devices) {
        if (snapshot.online) {
            device_ids.push_back(snapshot.device_id);
        }
    }
    return device_ids;
}

- (void)connectPressed:(id)sender {
    (void)sender;
    const auto endpoint = parse_host_port_input(to_std_string(_hostField.stringValue));
    if (!endpoint.has_value()) {
        [self updateFleetStatusMessage:"请输入有效的 iPhone 地址，格式为 IP 或 IP:端口"];
        return;
    }

    _hostField.stringValue = to_ns_string(
        endpoint->port == vino::desktop::PortMap::control
            ? endpoint->host
            : (endpoint->host + ":" + std::to_string(endpoint->port))
    );
    [self updateFleetStatusMessage:"正在连接 " + endpoint->host + ":" + std::to_string(endpoint->port) + " …"];

    const HostPortInput connection_target = *endpoint;
    __weak VinoDesktopAppController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VinoDesktopAppController* strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_runtime == nullptr) {
            return;
        }

        const bool connected = strongSelf->_runtime->connect_host(connection_target.host, connection_target.port);
        dispatch_async(dispatch_get_main_queue(), ^{
            VinoDesktopAppController* uiSelf = weakSelf;
            if (uiSelf == nil) {
                return;
            }

            [uiSelf updateFleetStatusMessage:
                connected
                    ? ("连接成功：" + connection_target.host + ":" + std::to_string(connection_target.port))
                    : ("连接失败：" + connection_target.host + ":" + std::to_string(connection_target.port) + "，请确认 iPhone IP、端口 48920 和本地网络权限")
            ];
            [uiSelf refreshUI:nil];
        });
    });
}

- (void)scanPressed:(id)sender {
    (void)sender;
    int start = std::max(0, _scanStartField.intValue);
    int end = std::max(0, _scanEndField.intValue);
    if (end < start) {
        std::swap(start, end);
        _scanStartField.intValue = start;
        _scanEndField.intValue = end;
    }

    const std::vector<std::string> prefixes = [self resolvedScanPrefixes];
    if (prefixes.empty()) {
        [self updateFleetStatusMessage:"没有可用的本机 IPv4 网段，请手动输入例如 192.168.31"];
        return;
    }

    const std::string prefix_summary = join_strings(prefixes, " · ");
    [self updateFleetStatusMessage:
        "正在扫描 " + prefix_summary + ".* ，范围 " + std::to_string(start) + "-" + std::to_string(end) + " …"
    ];

    __weak VinoDesktopAppController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VinoDesktopAppController* strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_runtime == nullptr) {
            return;
        }

        int found_total = 0;
        for (const auto& prefix : prefixes) {
            found_total += strongSelf->_runtime->scan_prefix(prefix, start, end);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            VinoDesktopAppController* uiSelf = weakSelf;
            if (uiSelf == nil) {
                return;
            }

            [uiSelf updateFleetStatusMessage:
                "扫描完成：" + prefix_summary + ".* ，发现 " + std::to_string(found_total) + " 台设备"
            ];
            [uiSelf refreshUI:nil];
        });
    });
}

- (void)startBonjourDiscovery {
    if (_serviceBrowser != nil) {
        return;
    }

    _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    _serviceBrowser.delegate = self;
    _bonjourLabel.stringValue = @"Bonjour 正在搜索 _vino-control._tcp";
    [_serviceBrowser searchForServicesOfType:@"_vino-control._tcp." inDomain:@""];
}

- (void)rebuildBonjourPopup {
    [_bonjourPopup removeAllItems];

    NSArray<NSNetService*>* services = [[_bonjourServices allValues] sortedArrayUsingComparator:^NSComparisonResult(NSNetService* lhs, NSNetService* rhs) {
        return [lhs.name compare:rhs.name options:NSCaseInsensitiveSearch];
    }];

    if (services.count == 0) {
        [_bonjourPopup addItemWithTitle:@"未发现 Bonjour 设备"];
        _bonjourPopup.enabled = NO;
        return;
    }

    _bonjourPopup.enabled = YES;
    for (NSNetService* service in services) {
        const std::string host = host_from_service(service);
        NSString* title = host.empty()
            ? [NSString stringWithFormat:@"%@ · 解析中", service.name]
            : [NSString stringWithFormat:@"%@ · %@:%ld", service.name, to_ns_string(host), static_cast<long>(service.port > 0 ? service.port : 48920)];
        [_bonjourPopup addItemWithTitle:title];
        _bonjourPopup.lastItem.representedObject = service;
    }

    _bonjourLabel.stringValue = [NSString stringWithFormat:@"Bonjour 已发现 %lu 台设备", static_cast<unsigned long>(services.count)];
}

- (void)refreshBonjourPressed:(id)sender {
    (void)sender;
    [_serviceBrowser stop];
    _serviceBrowser = nil;
    [_bonjourServices removeAllObjects];
    [self rebuildBonjourPopup];
    [self startBonjourDiscovery];
}

- (void)connectBonjourPressed:(id)sender {
    (void)sender;
    NSNetService* service = (NSNetService*)_bonjourPopup.selectedItem.representedObject;
    if (service == nil) {
        return;
    }

    const std::string host = host_from_service(service);
    if (host.empty()) {
        service.delegate = self;
        [service resolveWithTimeout:3.0];
        _bonjourLabel.stringValue = [NSString stringWithFormat:@"正在解析 %@", service.name];
        return;
    }

    _hostField.stringValue = to_ns_string(host);
    _runtime->connect_host(host, service.port > 0 ? static_cast<int>(service.port) : 48920);
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser*)browser {
    (void)browser;
    _bonjourLabel.stringValue = @"Bonjour 正在搜索 _vino-control._tcp";
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didNotSearch:(NSDictionary<NSString*, NSNumber*>*)errorDict {
    (void)browser;
    _bonjourLabel.stringValue = [NSString stringWithFormat:@"Bonjour 搜索失败 %@", errorDict.description];
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didFindService:(NSNetService*)service moreComing:(BOOL)moreComing {
    (void)browser;
    NSString* key = [NSString stringWithFormat:@"%@|%@", service.name, service.domain];
    _bonjourServices[key] = service;
    service.delegate = self;
    [service resolveWithTimeout:3.0];
    if (!moreComing) {
        [self rebuildBonjourPopup];
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didRemoveService:(NSNetService*)service moreComing:(BOOL)moreComing {
    (void)browser;
    NSString* key = [NSString stringWithFormat:@"%@|%@", service.name, service.domain];
    [_bonjourServices removeObjectForKey:key];
    if (!moreComing) {
        [self rebuildBonjourPopup];
    }
}

- (void)netServiceDidResolveAddress:(NSNetService*)sender {
    (void)sender;
    [self rebuildBonjourPopup];
}

- (void)netService:(NSNetService*)sender didNotResolve:(NSDictionary<NSString*, NSNumber*>*)errorDict {
    (void)sender;
    (void)errorDict;
    [self rebuildBonjourPopup];
}

- (void)sliderChanged:(id)sender {
    (void)sender;
    _controlDraftDirty = true;
    _controlApplyPending = false;
    _pendingControlDeviceId.clear();
    _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
    [self refreshSliderLabels];
}

- (void)controlChanged:(id)sender {
    (void)sender;
    _controlDraftDirty = true;
    _controlApplyPending = false;
    _pendingControlDeviceId.clear();
    _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
    [self refreshControlAvailability];
}

- (void)togglePressed:(id)sender {
    if (sender != _activateAfterInstallToggle) {
        _controlDraftDirty = true;
        _controlApplyPending = false;
        _pendingControlDeviceId.clear();
        _controlApplyStartedAt = std::chrono::steady_clock::time_point {};
    }
    [self refreshControlAvailability];
}

- (void)terminalFilterChanged:(id)sender {
    (void)sender;
    [self refreshUI:nil];
}

- (void)exportTerminalPressed:(id)sender {
    (void)sender;

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"vino-数据终端.log";

    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSError* error = nil;
    BOOL success = [_terminalView.string writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if (!success && error != nil) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"导出失败";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    }
}

- (void)openArchivePressed:(id)sender {
    (void)sender;
    NSString* path = (NSString*)_archivePopup.selectedItem.representedObject;
    if (path.length == 0) {
        return;
    }

    NSURL* url = [NSURL fileURLWithPath:path];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void)revealArchivePressed:(id)sender {
    (void)sender;
    NSString* path = (NSString*)_archivePopup.selectedItem.representedObject;
    if (path.length == 0) {
        return;
    }

    NSURL* url = [NSURL fileURLWithPath:path];
    if (url != nil) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[url]];
    }
}

- (void)applyPatchPressed:(id)sender {
    (void)sender;
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        return;
    }

    Value::Object settings;
    settings["frameRate"] = _fpsSlider.doubleValue;
    settings["whiteBalanceTemperature"] = _temperatureSlider.doubleValue;
    settings["whiteBalanceTint"] = _tintSlider.doubleValue;
    settings["exposureSeconds"] = _exposureSlider.doubleValue;
    settings["iso"] = _isoSlider.doubleValue;
    settings["exposureBias"] = _evSlider.doubleValue;
    settings["zoomFactor"] = _zoomSlider.doubleValue;
    settings["lensPosition"] = _lensSlider.doubleValue;

    Value::Object payload;
    payload["captureMode"] = popup_selected_value(_modePopup);
    payload["focusMode"] = popup_selected_value(_focusPopup);
    payload["selectedLens"] = popup_selected_value(_lensPopup);
    payload["recordingProfile"] = popup_selected_value(_profilePopup);
    payload["smoothAutoFocusEnabled"] = (_smoothAFToggle.state == NSControlStateValueOn);
    payload["flashEnabled"] = (_flashToggle.state == NSControlStateValueOn);
    payload["inferenceEnabled"] = (_inferenceToggle.state == NSControlStateValueOn);
    payload["persistMediaEnabled"] = (_persistToggle.state == NSControlStateValueOn);
    payload["settings"] = settings;

    _controlDraftDirty = false;
    _controlApplyPending = true;
    _pendingControlDeviceId = snapshot->device_id;
    _controlApplyStartedAt = std::chrono::steady_clock::now();
    [self dispatchToSelectedAction:"camera.config.patch" payload:Value(payload)];
}

- (void)photoPressed:(id)sender {
    (void)sender;
    [self dispatchToSelectedAction:"capture.photo.trigger" payload:Value::Object {}];
}

- (void)startRecordPressed:(id)sender {
    (void)sender;
    Value::Object payload;
    payload["enabled"] = true;
    [self dispatchToSelectedAction:"capture.recording.set" payload:Value(payload)];
}

- (void)stopRecordPressed:(id)sender {
    (void)sender;
    Value::Object payload;
    payload["enabled"] = false;
    [self dispatchToSelectedAction:"capture.recording.set" payload:Value(payload)];
}

- (void)fetchCapabilitiesPressed:(id)sender {
    (void)sender;
    [self dispatchToSelectedAction:"camera.capabilities.get" payload:Value::Object {}];
}

- (void)aliasPressed:(id)sender {
    (void)sender;
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        return;
    }

    const std::string alias = to_std_string(_aliasField.stringValue);
    if (alias.empty()) {
        return;
    }

    _runtime->set_alias(snapshot->device_id, alias);
    Value::Object payload;
    payload["name"] = alias;
    _runtime->dispatch_to_device(snapshot->device_id, "device.alias.set", [self currentContext], Value(payload));
}

- (void)activateModelPressed:(id)sender {
    (void)sender;
    const std::string model_id = to_std_string(_modelField.stringValue);
    if (model_id.empty()) {
        return;
    }

    Value::Object payload;
    payload["modelId"] = model_id;
    [self dispatchToSelectedAction:"inference.model.activate" payload:Value(payload)];
}

- (void)deactivateModelPressed:(id)sender {
    (void)sender;
    const std::string model_id = to_std_string(_modelField.stringValue);
    if (model_id.empty()) {
        return;
    }

    Value::Object payload;
    payload["modelId"] = model_id;
    [self dispatchToSelectedAction:"inference.model.deactivate" payload:Value(payload)];
}

- (void)removeModelPressed:(id)sender {
    (void)sender;
    const std::string model_id = to_std_string(_modelField.stringValue);
    if (model_id.empty()) {
        return;
    }

    Value::Object payload;
    payload["modelId"] = model_id;
    [self dispatchToSelectedAction:"inference.model.remove" payload:Value(payload)];
}

- (void)openModelPressed:(id)sender {
    (void)sender;

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.allowedFileTypes = @[@"mlmodel", @"mlpackage", @"mlmodelc"];

    if ([panel runModal] == NSModalResponseOK) {
        NSURL* url = panel.URL;
        if (url != nil) {
            const std::string path = to_std_string(url.path);
            _modelPathField.stringValue = url.path;
            if (_modelField.stringValue.length == 0) {
                _modelField.stringValue = to_ns_string(make_model_id_from_path(path));
            }
        }
    }
}

- (void)uploadModelPressed:(id)sender {
    (void)sender;

    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        return;
    }

    const std::string path = to_std_string(_modelPathField.stringValue);
    const std::string model_id = to_std_string(_modelField.stringValue);
    if (path.empty() || model_id.empty()) {
        return;
    }

    NSString* version_string = _modelVersionField.stringValue.length == 0 ? @"1.0.0" : _modelVersionField.stringValue;
    const std::string version = to_std_string(version_string);
    const std::string device_id = snapshot->device_id;
    const bool activate_after_install = _activateAfterInstallToggle.state == NSControlStateValueOn;
    [self updateFleetStatusMessage:"正在后台上传模型 " + model_id + " 到 1 台设备…"];

    __weak VinoDesktopAppController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VinoDesktopAppController* strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_runtime == nullptr) {
            return;
        }

        const Value result = strongSelf->_runtime->install_model_to_device(
            device_id,
            path,
            model_id,
            model_id,
            version,
            activate_after_install
        );

        dispatch_async(dispatch_get_main_queue(), ^{
            VinoDesktopAppController* uiSelf = weakSelf;
            if (uiSelf == nil) {
                return;
            }

            [uiSelf updateFleetStatusMessage:upload_result_summary(result, 1)];
            [uiSelf refreshUI:nil];
        });
    });
}

- (void)uploadModelAllPressed:(id)sender {
    (void)sender;

    const std::string path = to_std_string(_modelPathField.stringValue);
    const std::string model_id = to_std_string(_modelField.stringValue);
    const std::vector<std::string> device_ids = [self onlineDeviceIds];
    if (path.empty() || model_id.empty() || device_ids.empty()) {
        return;
    }

    NSString* version_string = _modelVersionField.stringValue.length == 0 ? @"1.0.0" : _modelVersionField.stringValue;
    const std::string version = to_std_string(version_string);
    const bool activate_after_install = _activateAfterInstallToggle.state == NSControlStateValueOn;
    [self updateFleetStatusMessage:"正在后台上传模型 " + model_id + " 到 " + std::to_string(device_ids.size()) + " 台设备…"];

    __weak VinoDesktopAppController* weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        VinoDesktopAppController* strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_runtime == nullptr) {
            return;
        }

        const Value result = strongSelf->_runtime->install_model_to_devices(
            device_ids,
            path,
            model_id,
            model_id,
            version,
            activate_after_install
        );

        dispatch_async(dispatch_get_main_queue(), ^{
            VinoDesktopAppController* uiSelf = weakSelf;
            if (uiSelf == nil) {
                return;
            }

            [uiSelf updateFleetStatusMessage:upload_result_summary(result, device_ids.size())];
            [uiSelf refreshUI:nil];
        });
    });
}

- (void)photoAllPressed:(id)sender {
    (void)sender;
    const std::vector<std::string> device_ids = [self onlineDeviceIds];
    if (!device_ids.empty()) {
        _runtime->dispatch_to_devices(device_ids, "capture.photo.trigger", [self currentContext], Value::Object {});
    }
}

- (void)aiOnAllPressed:(id)sender {
    (void)sender;
    const std::vector<std::string> device_ids = [self onlineDeviceIds];
    if (!device_ids.empty()) {
        Value::Object payload;
        payload["enabled"] = true;
        _runtime->dispatch_to_devices(device_ids, "inference.runtime.set", [self currentContext], Value(payload));
    }
}

- (void)aiOffAllPressed:(id)sender {
    (void)sender;
    const std::vector<std::string> device_ids = [self onlineDeviceIds];
    if (!device_ids.empty()) {
        Value::Object payload;
        payload["enabled"] = false;
        _runtime->dispatch_to_devices(device_ids, "inference.runtime.set", [self currentContext], Value(payload));
    }
}

@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication* application = [NSApplication sharedApplication];
        VinoDesktopAppController* controller = [[VinoDesktopAppController alloc] init];
        application.delegate = controller;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        [application run];
    }

    return 0;
}
