#import <Cocoa/Cocoa.h>

#include <arpa/inet.h>
#include <algorithm>
#include <cctype>
#include <filesystem>
#include <iomanip>
#include <memory>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

#include "vino_desktop/DesktopRuntime.hpp"
#include "vino_desktop/FuturisticTheme.hpp"
#include "vino_desktop/MiniJson.hpp"
#include "vino_desktop/Protocol.hpp"

namespace {

using vino::desktop::DeviceSnapshot;
using vino::desktop::DesktopRuntime;
using vino::desktop::ModelTransferSnapshot;
using vino::desktop::TriggerContext;
using vino::desktop::UiLogEntry;
using vino::desktop::json::Value;

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

NSColor* hex_color(unsigned rgb, CGFloat alpha = 1.0) {
    return [NSColor colorWithCalibratedRed:((rgb >> 16) & 0xFF) / 255.0
                                     green:((rgb >> 8) & 0xFF) / 255.0
                                      blue:(rgb & 0xFF) / 255.0
                                     alpha:alpha];
}

NSFont* mono_font(CGFloat size, NSFontWeight weight = NSFontWeightRegular) {
    return [NSFont monospacedSystemFontOfSize:size weight:weight];
}

NSTextField* make_label(NSString* text, CGFloat size = 12.0, NSFontWeight weight = NSFontWeightRegular, NSColor* color = nil) {
    NSTextField* label = [NSTextField labelWithString:text];
    label.font = mono_font(size, weight);
    label.textColor = color == nil ? hex_color(0xF3F6F8) : color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

NSTextField* make_input(NSString* placeholder, NSString* value = @"") {
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholderString = placeholder;
    field.stringValue = value;
    field.font = mono_font(12.0);
    field.textColor = hex_color(0xF3F6F8);
    field.backgroundColor = hex_color(0x050608, 0.92);
    field.bordered = NO;
    field.focusRingType = NSFocusRingTypeNone;
    field.wantsLayer = YES;
    field.layer.backgroundColor = hex_color(0x050608, 0.92).CGColor;
    field.layer.borderColor = hex_color(0x24303A).CGColor;
    field.layer.borderWidth = 1.0;
    field.layer.cornerRadius = 10.0;
    return field;
}

NSButton* make_button(NSString* title, id target, SEL action) {
    NSButton* button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.font = mono_font(12.0, NSFontWeightSemibold);
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.wantsLayer = YES;
    button.layer.backgroundColor = hex_color(0x0C1014).CGColor;
    button.layer.borderColor = hex_color(0x24303A).CGColor;
    button.layer.borderWidth = 1.0;
    button.layer.cornerRadius = 10.0;
    button.contentTintColor = hex_color(0x62F0FF);
    return button;
}

NSButton* make_toggle(NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:NSZeroRect];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.title = title;
    button.font = mono_font(12.0);
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
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    return stack;
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

    NSTextField* title = make_label(@"LIVE PREVIEW MIRROR RESERVED", 11.0, NSFontWeightBold, hex_color(0xA8B7C2));
    NSTextField* subtitle = make_label(@"desktop shell currently focuses on control, state, logs, and batch operations", 12.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    subtitle.lineBreakMode = NSLineBreakByWordWrapping;
    subtitle.maximumNumberOfLines = 4;

    [view addSubview:image_view];
    [view addSubview:title];
    [view addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [view.heightAnchor constraintEqualToConstant:160.0],
        [image_view.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:1.0],
        [image_view.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-1.0],
        [image_view.topAnchor constraintEqualToAnchor:view.topAnchor constant:1.0],
        [image_view.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-1.0],
        [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:14.0],
        [title.topAnchor constraintEqualToAnchor:view.topAnchor constant:14.0],
        [subtitle.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:14.0],
        [subtitle.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-14.0],
        [subtitle.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-14.0]
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

    NSTextField* title_label = make_label(title, 11.0, NSFontWeightBold, hex_color(0xA8B7C2));
    body.translatesAutoresizingMaskIntoConstraints = NO;

    [panel addSubview:title_label];
    [panel addSubview:body];

    [NSLayoutConstraint activateConstraints:@[
        [title_label.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14.0],
        [title_label.topAnchor constraintEqualToAnchor:panel.topAnchor constant:14.0],
        [body.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14.0],
        [body.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14.0],
        [body.topAnchor constraintEqualToAnchor:title_label.bottomAnchor constant:10.0],
        [body.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14.0]
    ]];

    return panel;
}

NSView* make_slider_row(NSString* title, NSSlider* __strong *out_slider, NSTextField* __strong *out_value, id target, SEL action, double min_value, double max_value) {
    NSTextField* label = make_label(title, 12.0, NSFontWeightSemibold);
    label.alignment = NSTextAlignmentLeft;

    NSTextField* value = make_label(@"0", 12.0, NSFontWeightRegular, hex_color(0x62F0FF));
    value.alignment = NSTextAlignmentRight;
    [value.widthAnchor constraintEqualToConstant:92.0].active = YES;

    NSSlider* slider = [NSSlider sliderWithValue:min_value minValue:min_value maxValue:max_value target:target action:action];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.continuous = YES;

    NSStackView* row = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 10.0);
    [row addArrangedSubview:label];
    [row addArrangedSubview:slider];
    [row addArrangedSubview:value];
    [slider.widthAnchor constraintGreaterThanOrEqualToConstant:220.0].active = YES;

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
    return value ? "on" : "off";
}

std::string format_number(double value, int precision = 1) {
    std::ostringstream stream;
    stream << std::fixed << std::setprecision(precision) << value;
    return stream.str();
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

void replace_popup_items(NSPopUpButton* popup, const std::vector<std::string>& items) {
    [popup removeAllItems];
    for (const auto& item : items) {
        [popup addItemWithTitle:to_ns_string(item)];
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
    return "n/a";
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
        return "active=" + join_strings(active_models, ", ") + (installed_models.empty() ? "" : (" | installed=" + std::to_string(installed_models.size())));
    }

    if (!installed_models.empty()) {
        return "installed=" + join_strings(installed_models, ", ");
    }

    return "no models reported";
}

std::string capability_digest(const DeviceSnapshot& snapshot) {
    if (!snapshot.capabilities_payload.is_object()) {
        return "capabilities pending";
    }

    const auto* capabilities = find_in_object(snapshot.capabilities_payload, "capabilities");
    if (capabilities == nullptr || !capabilities->is_object()) {
        return "capabilities pending";
    }

    std::vector<std::string> items;
    if (const auto supported_lenses = string_array_or_empty(find_in_object(*capabilities, "supportedLenses")); !supported_lenses.empty()) {
        items.push_back("lenses=" + join_strings(supported_lenses, ", "));
    }

    if (const auto* frame_rate = find_in_object(*capabilities, "frameRate"); frame_rate != nullptr && frame_rate->is_object()) {
        items.push_back(
            "fps=" + format_number(number_or(find_in_object(*frame_rate, "min"), 0.0), 0)
            + "…"
            + format_number(number_or(find_in_object(*frame_rate, "max"), 0.0), 0)
        );
    }

    items.push_back("flash=" + bool_text(bool_or(find_in_object(*capabilities, "supportsFlash"), false)));
    items.push_back("smoothAF=" + bool_text(bool_or(find_in_object(*capabilities, "supportsSmoothAutoFocus"), false)));
    items.push_back("proRes=" + bool_text(bool_or(find_in_object(*capabilities, "supportsProRes"), false)));
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

std::string inference_digest(const DeviceSnapshot& snapshot) {
    if (!snapshot.inference_payload.is_object()) {
        return "inference pending";
    }

    const auto* detections_value = find_in_object(snapshot.inference_payload, "detections");
    const auto* latency_value = find_in_object(snapshot.inference_payload, "latencyMS");
    const auto* frame_value = find_in_object(snapshot.inference_payload, "frameIndex");

    const int detection_count = detections_value != nullptr && detections_value->is_array()
        ? static_cast<int>(detections_value->as_array().size())
        : 0;

    std::ostringstream stream;
    stream << "detections=" << detection_count;
    if (latency_value != nullptr && latency_value->is_number()) {
        stream << " | latency=" << format_number(latency_value->as_number(), 2) << " ms";
    }
    if (frame_value != nullptr && frame_value->is_number()) {
        stream << " | frame=" << static_cast<int>(frame_value->as_number());
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
        << " | " << transfer.stage
        << " | local=" << transfer.local_status
        << " | remote=" << (transfer.remote_status.empty() ? "pending" : transfer.remote_status)
        << " | chunks " << transfer.chunks_sent << "/" << transfer.chunk_count
        << " ack " << transfer.chunks_acked;

    if (!transfer.remote_message.empty()) {
        stream << "\n  " << transfer.remote_message;
    }
    return stream.str();
}

std::string snapshot_dump(const DeviceSnapshot& snapshot) {
    std::ostringstream stream;
    stream
        << "DEVICE\n"
        << "id=" << snapshot.device_id << "\n"
        << "alias=" << snapshot.alias << "\n"
        << "host=" << snapshot.host << ":" << snapshot.port << "\n"
        << "online=" << (snapshot.online ? "true" : "false") << "\n"
        << "lastSeen=" << snapshot.last_seen << "\n"
        << "lastMessage=" << snapshot.last_message << "\n\n"
        << "lastMediaPath=" << snapshot.last_media_path << "\n"
        << "lastMediaCategory=" << snapshot.last_media_category << "\n"
        << "lastMediaSeen=" << snapshot.last_media_seen << "\n\n"
        << "previewFrameIndex=" << snapshot.preview_frame_index << "\n"
        << "previewSize=" << snapshot.preview_image_width << "x" << snapshot.preview_image_height << "\n"
        << "previewSeen=" << snapshot.preview_seen << "\n\n"
        << stringify_block("HELLO", snapshot.hello_payload)
        << stringify_block("STATUS", snapshot.status_payload)
        << stringify_block("CAPABILITIES", snapshot.capabilities_payload)
        << stringify_block("INFERENCE", snapshot.inference_payload);

    return stream.str();
}

} // namespace

@interface VinoDesktopAppController : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@end

@implementation VinoDesktopAppController {
    std::unique_ptr<DesktopRuntime> _runtime;
    std::vector<DeviceSnapshot> _devices;
    std::string _selectedDeviceId;
    NSUInteger _lastLogCount;

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
    NSPopUpButton* _bonjourPopup;

    NSTextField* _summaryLabel;
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
    NSTextField* _remotePostField;

    NSPopUpButton* _modePopup;
    NSPopUpButton* _focusPopup;
    NSPopUpButton* _lensPopup;
    NSPopUpButton* _profilePopup;

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

    NSTimer* _refreshTimer;
    NSNetServiceBrowser* _serviceBrowser;
    NSMutableDictionary<NSString*, NSNetService*>* _bonjourServices;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    _runtime = std::make_unique<DesktopRuntime>();
    _runtime->start();
    _bonjourServices = [[NSMutableDictionary alloc] init];

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
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(120.0, 120.0, 1520.0, 940.0)
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskMiniaturizable |
                                                     NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title = @"vino Desktop";
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
        [rootSplit.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:10.0],
        [rootSplit.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-10.0],
        [rootSplit.topAnchor constraintEqualToAnchor:content.topAnchor constant:10.0],
        [rootSplit.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-10.0]
    ]];

    NSSplitView* topSplit = [[NSSplitView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 1400.0, 660.0)];
    topSplit.vertical = YES;
    topSplit.dividerStyle = NSSplitViewDividerStyleThin;

    NSView* leftPanel = [self buildFleetPanel];
    NSView* centerPanel = [self buildWorkspacePanel];
    NSView* rightPanel = [self buildSidePanel];
    NSView* terminalPanel = [self buildTerminalPanel];

    [topSplit addSubview:leftPanel];
    [topSplit addSubview:centerPanel];
    [topSplit addSubview:rightPanel];
    [rootSplit addSubview:topSplit];
    [rootSplit addSubview:terminalPanel];

    [rootSplit setPosition:660.0 ofDividerAtIndex:0];
    [topSplit setPosition:310.0 ofDividerAtIndex:0];
    [topSplit setPosition:1080.0 ofDividerAtIndex:1];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSView*)buildFleetPanel {
    _hostField = make_input(@"192.168.31.25");
    _hostField.stringValue = @"192.168.31.25";

    _scanPrefixField = make_input(@"192.168.31");
    _scanPrefixField.stringValue = @"192.168.31";
    _scanStartField = make_input(@"1");
    _scanStartField.stringValue = @"20";
    _scanEndField = make_input(@"254");
    _scanEndField.stringValue = @"40";
    _bonjourPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _bonjourPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_bonjourPopup addItemWithTitle:@"Bonjour scanning…"];
    _bonjourPopup.enabled = NO;
    _bonjourLabel = make_label(@"Bonjour idle", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _bonjourLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    NSButton* connectButton = make_button(@"Connect", self, @selector(connectPressed:));
    NSButton* scanButton = make_button(@"Scan", self, @selector(scanPressed:));
    NSButton* bonjourButton = make_button(@"Bonjour", self, @selector(connectBonjourPressed:));
    NSButton* bonjourRefreshButton = make_button(@"Refresh", self, @selector(refreshBonjourPressed:));

    NSStackView* connectRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 10.0);
    [connectRow addArrangedSubview:_hostField];
    [connectRow addArrangedSubview:connectButton];
    [connectButton.widthAnchor constraintEqualToConstant:94.0].active = YES;

    NSStackView* scanRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [scanRow addArrangedSubview:_scanPrefixField];
    [scanRow addArrangedSubview:_scanStartField];
    [scanRow addArrangedSubview:_scanEndField];
    [scanRow addArrangedSubview:scanButton];
    [_scanStartField.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [_scanEndField.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [scanButton.widthAnchor constraintEqualToConstant:80.0].active = YES;

    NSStackView* bonjourRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [bonjourRow addArrangedSubview:_bonjourPopup];
    [bonjourRow addArrangedSubview:bonjourButton];
    [bonjourRow addArrangedSubview:bonjourRefreshButton];
    [bonjourButton.widthAnchor constraintEqualToConstant:88.0].active = YES;
    [bonjourRefreshButton.widthAnchor constraintEqualToConstant:82.0].active = YES;

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
    _tableView.rowHeight = 28.0;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = hex_color(0x050608, 0.9);
    _tableView.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _tableView.intercellSpacing = NSMakeSize(0.0, 1.0);
    _tableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;

    NSTableColumn* aliasColumn = [[NSTableColumn alloc] initWithIdentifier:@"alias"];
    aliasColumn.width = 150.0;
    NSTableColumn* stateColumn = [[NSTableColumn alloc] initWithIdentifier:@"state"];
    stateColumn.width = 54.0;
    NSTableColumn* endpointColumn = [[NSTableColumn alloc] initWithIdentifier:@"endpoint"];
    endpointColumn.width = 120.0;

    [_tableView addTableColumn:aliasColumn];
    [_tableView addTableColumn:stateColumn];
    [_tableView addTableColumn:endpointColumn];

    tableScroll.documentView = _tableView;
    [tableScroll.heightAnchor constraintGreaterThanOrEqualToConstant:300.0].active = YES;

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 10.0);
    [body addArrangedSubview:connectRow];
    [body addArrangedSubview:scanRow];
    [body addArrangedSubview:bonjourRow];
    [body addArrangedSubview:_bonjourLabel];
    [body addArrangedSubview:tableScroll];

    return make_panel(@"FLEET", body);
}

- (NSView*)buildWorkspacePanel {
    _summaryLabel = make_label(@"no device selected", 12.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _summaryLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _summaryLabel.maximumNumberOfLines = 4;

    _productField = make_input(@"Product UUID");
    _pointField = make_input(@"Point Index", @"0");
    _jobField = make_input(@"Job ID");
    _remotePostField = make_input(@"Remote POST URL");

    _modePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _modePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_modePopup addItemsWithTitles:@[@"photo", @"stream"]];
    _modePopup.target = self;
    _modePopup.action = @selector(controlChanged:);

    _focusPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _focusPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_focusPopup addItemsWithTitles:@[@"continuousAuto", @"locked"]];
    _focusPopup.target = self;
    _focusPopup.action = @selector(controlChanged:);

    _lensPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _lensPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_lensPopup addItemsWithTitles:@[@"wide", @"ultraWide", @"telephoto"]];
    _lensPopup.target = self;
    _lensPopup.action = @selector(controlChanged:);

    _profilePopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _profilePopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_profilePopup addItemsWithTitles:@[@"h264", @"hevc", @"proRes"]];
    _profilePopup.target = self;
    _profilePopup.action = @selector(controlChanged:);

    _flashToggle = make_toggle(@"Flash", self, @selector(togglePressed:));
    _inferenceToggle = make_toggle(@"Inference", self, @selector(togglePressed:));
    _persistToggle = make_toggle(@"Store Media", self, @selector(togglePressed:));
    _smoothAFToggle = make_toggle(@"Smooth AF", self, @selector(togglePressed:));

    NSButton* applyButton = make_button(@"Apply Patch", self, @selector(applyPatchPressed:));
    NSButton* photoButton = make_button(@"Trigger Photo", self, @selector(photoPressed:));
    NSButton* startRecordButton = make_button(@"Start Record", self, @selector(startRecordPressed:));
    NSButton* stopRecordButton = make_button(@"Stop Record", self, @selector(stopRecordPressed:));
    NSButton* capsButton = make_button(@"Fetch Caps", self, @selector(fetchCapabilitiesPressed:));

    NSView* preview = make_preview_surface(&_previewImageView, &_previewTitleLabel, &_previewSubtitleLabel);

    NSStackView* contextRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [contextRow addArrangedSubview:_productField];
    [contextRow addArrangedSubview:_pointField];
    [contextRow addArrangedSubview:_jobField];
    [_pointField.widthAnchor constraintEqualToConstant:78.0].active = YES;
    [_jobField.widthAnchor constraintEqualToConstant:126.0].active = YES;

    NSStackView* modeRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modeRow addArrangedSubview:make_label(@"Mode", 12.0, NSFontWeightSemibold)];
    [modeRow addArrangedSubview:_modePopup];
    [modeRow addArrangedSubview:make_label(@"Focus", 12.0, NSFontWeightSemibold)];
    [modeRow addArrangedSubview:_focusPopup];
    [_modePopup.widthAnchor constraintEqualToConstant:120.0].active = YES;
    [_focusPopup.widthAnchor constraintEqualToConstant:140.0].active = YES;

    NSStackView* opticsRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [opticsRow addArrangedSubview:make_label(@"Lens", 12.0, NSFontWeightSemibold)];
    [opticsRow addArrangedSubview:_lensPopup];
    [opticsRow addArrangedSubview:make_label(@"Profile", 12.0, NSFontWeightSemibold)];
    [opticsRow addArrangedSubview:_profilePopup];
    [_lensPopup.widthAnchor constraintEqualToConstant:140.0].active = YES;
    [_profilePopup.widthAnchor constraintEqualToConstant:120.0].active = YES;

    NSStackView* togglesRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 12.0);
    [togglesRow addArrangedSubview:_flashToggle];
    [togglesRow addArrangedSubview:_smoothAFToggle];
    [togglesRow addArrangedSubview:_inferenceToggle];
    [togglesRow addArrangedSubview:_persistToggle];

    NSStackView* buttonsRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [buttonsRow addArrangedSubview:applyButton];
    [buttonsRow addArrangedSubview:photoButton];
    [buttonsRow addArrangedSubview:startRecordButton];
    [buttonsRow addArrangedSubview:stopRecordButton];
    [buttonsRow addArrangedSubview:capsButton];

    NSView* fpsRow = make_slider_row(@"FPS", &_fpsSlider, &_fpsValue, self, @selector(sliderChanged:), 1.0, 60.0);
    NSView* temperatureRow = make_slider_row(@"Temp", &_temperatureSlider, &_temperatureValue, self, @selector(sliderChanged:), 2800.0, 8000.0);
    NSView* tintRow = make_slider_row(@"Tint", &_tintSlider, &_tintValue, self, @selector(sliderChanged:), -150.0, 150.0);
    NSView* exposureRow = make_slider_row(@"Exposure", &_exposureSlider, &_exposureValue, self, @selector(sliderChanged:), 0.0001, 0.5);
    NSView* isoRow = make_slider_row(@"ISO", &_isoSlider, &_isoValue, self, @selector(sliderChanged:), 20.0, 1600.0);
    NSView* evRow = make_slider_row(@"EV", &_evSlider, &_evValue, self, @selector(sliderChanged:), -8.0, 8.0);
    NSView* zoomRow = make_slider_row(@"Zoom", &_zoomSlider, &_zoomValue, self, @selector(sliderChanged:), 1.0, 15.0);
    NSView* lensRow = make_slider_row(@"Lens Position", &_lensSlider, &_lensValue, self, @selector(sliderChanged:), 0.0, 1.0);

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 10.0);
    [body addArrangedSubview:preview];
    [body addArrangedSubview:_summaryLabel];
    [body addArrangedSubview:contextRow];
    [body addArrangedSubview:_remotePostField];
    [body addArrangedSubview:modeRow];
    [body addArrangedSubview:opticsRow];
    [body addArrangedSubview:fpsRow];
    [body addArrangedSubview:temperatureRow];
    [body addArrangedSubview:tintRow];
    [body addArrangedSubview:exposureRow];
    [body addArrangedSubview:isoRow];
    [body addArrangedSubview:evRow];
    [body addArrangedSubview:zoomRow];
    [body addArrangedSubview:lensRow];
    [body addArrangedSubview:togglesRow];
    [body addArrangedSubview:buttonsRow];

    return make_panel(@"DEVICE WORKSPACE", body);
}

- (NSView*)buildSidePanel {
    _networkLabel = make_label(@"network: no device selected", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _networkLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _networkLabel.maximumNumberOfLines = 3;
    _capabilityLabel = make_label(@"capabilities: no device selected", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _capabilityLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _capabilityLabel.maximumNumberOfLines = 4;
    _modelsLabel = make_label(@"models: no device selected", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    _modelsLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _modelsLabel.maximumNumberOfLines = 4;

    _aliasField = make_input(@"Alias");
    _modelField = make_input(@"Model ID");
    _modelVersionField = make_input(@"Version", @"1.0.0");
    _modelPathField = make_input(@"Model file path");
    _activateAfterInstallToggle = make_toggle(@"Activate After Install", self, @selector(togglePressed:));

    NSButton* aliasButton = make_button(@"Apply Alias", self, @selector(aliasPressed:));
    NSButton* activateButton = make_button(@"Activate", self, @selector(activateModelPressed:));
    NSButton* deactivateButton = make_button(@"Deactivate", self, @selector(deactivateModelPressed:));
    NSButton* removeButton = make_button(@"Remove", self, @selector(removeModelPressed:));
    NSButton* browseButton = make_button(@"Browse", self, @selector(openModelPressed:));
    NSButton* uploadButton = make_button(@"Upload", self, @selector(uploadModelPressed:));
    NSButton* uploadAllButton = make_button(@"Upload All", self, @selector(uploadModelAllPressed:));
    NSButton* photoAllButton = make_button(@"Photo All Online", self, @selector(photoAllPressed:));
    NSButton* aiOnButton = make_button(@"AI On All", self, @selector(aiOnAllPressed:));
    NSButton* aiOffButton = make_button(@"AI Off All", self, @selector(aiOffAllPressed:));

    NSStackView* aliasRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [aliasRow addArrangedSubview:_aliasField];
    [aliasRow addArrangedSubview:aliasButton];
    [aliasButton.widthAnchor constraintEqualToConstant:96.0].active = YES;

    NSStackView* modelRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modelRow addArrangedSubview:_modelField];
    [modelRow addArrangedSubview:activateButton];
    [modelRow addArrangedSubview:deactivateButton];
    [modelRow addArrangedSubview:removeButton];
    [activateButton.widthAnchor constraintEqualToConstant:84.0].active = YES;
    [deactivateButton.widthAnchor constraintEqualToConstant:92.0].active = YES;
    [removeButton.widthAnchor constraintEqualToConstant:76.0].active = YES;

    NSStackView* modelMetaRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modelMetaRow addArrangedSubview:_modelVersionField];
    [modelMetaRow addArrangedSubview:_activateAfterInstallToggle];
    [_modelVersionField.widthAnchor constraintEqualToConstant:90.0].active = YES;

    NSStackView* modelPathRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [modelPathRow addArrangedSubview:_modelPathField];
    [modelPathRow addArrangedSubview:browseButton];
    [modelPathRow addArrangedSubview:uploadButton];
    [modelPathRow addArrangedSubview:uploadAllButton];
    [browseButton.widthAnchor constraintEqualToConstant:74.0].active = YES;
    [uploadButton.widthAnchor constraintEqualToConstant:74.0].active = YES;
    [uploadAllButton.widthAnchor constraintEqualToConstant:88.0].active = YES;

    NSStackView* batchRow = make_stack(NSUserInterfaceLayoutOrientationHorizontal, 8.0);
    [batchRow addArrangedSubview:photoAllButton];
    [batchRow addArrangedSubview:aiOnButton];
    [batchRow addArrangedSubview:aiOffButton];

    NSTextField* gatewayLabel = make_label(@"gateway :: POST /api/v1/batch  |  GET /api/v1/devices  |  :49020", 11.0, NSFontWeightRegular, hex_color(0xA8B7C2));
    gatewayLabel.lineBreakMode = NSLineBreakByWordWrapping;
    gatewayLabel.maximumNumberOfLines = 2;

    NSScrollView* rawScroll = make_text_scroll(&_rawView);
    [rawScroll.heightAnchor constraintGreaterThanOrEqualToConstant:320.0].active = YES;

    NSScrollView* transferScroll = make_text_scroll(&_transferView);
    [transferScroll.heightAnchor constraintGreaterThanOrEqualToConstant:150.0].active = YES;

    NSStackView* body = make_stack(NSUserInterfaceLayoutOrientationVertical, 10.0);
    [body addArrangedSubview:aliasRow];
    [body addArrangedSubview:modelRow];
    [body addArrangedSubview:modelMetaRow];
    [body addArrangedSubview:modelPathRow];
    [body addArrangedSubview:batchRow];
    [body addArrangedSubview:gatewayLabel];
    [body addArrangedSubview:_networkLabel];
    [body addArrangedSubview:_capabilityLabel];
    [body addArrangedSubview:_modelsLabel];
    [body addArrangedSubview:transferScroll];
    [body addArrangedSubview:rawScroll];

    return make_panel(@"MODELS / BATCH / RAW", body);
}

- (NSView*)buildTerminalPanel {
    NSScrollView* terminalScroll = make_text_scroll(&_terminalView);
    [terminalScroll.heightAnchor constraintGreaterThanOrEqualToConstant:180.0].active = YES;
    return make_panel(@"DATA TERMINAL", terminalScroll);
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
        value = snapshot.online ? "online" : "offline";
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
        [self refreshPresentation];
        return;
    }

    _selectedDeviceId = _devices[static_cast<std::size_t>(row)].device_id;
    [self loadControlsFromCurrentSelection];
    [self refreshPresentation];
}

- (void)refreshUI:(id)sender {
    (void)sender;

    _devices = _runtime->snapshots();
    [_tableView reloadData];

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
        }
    }

    const std::vector<UiLogEntry> logs = _runtime->logs();
    if (logs.size() != _lastLogCount) {
        std::ostringstream stream;
        for (const auto& entry : logs) {
            stream << "[" << entry.timestamp << "] " << entry.level << " " << entry.message << '\n';
        }
        _terminalView.string = to_ns_string(stream.str());
        [_terminalView scrollRangeToVisible:NSMakeRange(_terminalView.string.length, 0)];
        _lastLogCount = logs.size();
    }

    const std::vector<ModelTransferSnapshot> transfers = _runtime->model_transfers();
    std::ostringstream transfer_stream;
    if (transfers.empty()) {
        transfer_stream << "no model transfers yet";
    } else {
        for (std::size_t index = 0; index < transfers.size(); ++index) {
            if (index > 0) {
                transfer_stream << "\n\n";
            }
            transfer_stream << transfer_digest(transfers[index]);
        }
    }
    _transferView.string = to_ns_string(transfer_stream.str());

    [self refreshPresentation];
    [self refreshSliderLabels];
    [self refreshControlAvailability];
}

- (void)refreshPresentation {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        _summaryLabel.stringValue = @"no device selected";
        _networkLabel.stringValue = @"network: no device selected";
        _capabilityLabel.stringValue = @"capabilities: no device selected";
        _modelsLabel.stringValue = @"models: no device selected";
        _rawView.string = @"";
        [self refreshPreviewForSnapshot:nullptr];
        return;
    }

    const Value* status = snapshot->status_payload.is_object() ? &snapshot->status_payload : nullptr;
    const std::string capture_mode = status == nullptr ? "n/a" : string_or(find_in_object(*status, "captureMode"), "n/a");
    const std::string focus_mode = status == nullptr ? "n/a" : string_or(find_in_object(*status, "focusMode"), "n/a");
    const std::string selected_lens = status == nullptr ? "n/a" : string_or(find_in_object(*status, "selectedLens"), "n/a");
    const std::string profile = status == nullptr ? "n/a" : string_or(find_in_object(*status, "recordingProfile"), "n/a");
    const std::string remote_post = status == nullptr ? "" : string_or(find_in_object(*status, "remotePostURL"));

    std::ostringstream summary;
    summary
        << snapshot->device_id
        << " | " << (snapshot->alias.empty() ? snapshot->device_id : snapshot->alias)
        << " | " << (snapshot->online ? "online" : "offline")
        << " | " << snapshot->host << ":" << snapshot->port
        << " | last=" << snapshot->last_seen
        << " | msg=" << snapshot->last_message << "\n"
        << "mode=" << capture_mode
        << " | focus=" << focus_mode
        << " | lens=" << selected_lens
        << " | profile=" << profile
        << " | record=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "isRecording"), false))
        << " | ai=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "inferenceEnabled"), false))
        << " | store=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "persistMediaEnabled"), false))
        << " | flash=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "flashEnabled"), false))
        << " | smoothAF=" << bool_text(status != nullptr && bool_or(find_in_object(*status, "smoothAutoFocusEnabled"), false))
        << " | previewFrame=" << snapshot->preview_frame_index << "\n"
        << "ips=" << network_digest(*snapshot) << "\n"
        << "models=" << models_digest(*snapshot)
        << " | post=" << (remote_post.empty() ? "disabled" : remote_post);
    _summaryLabel.stringValue = to_ns_string(summary.str());
    _networkLabel.stringValue = to_ns_string("network: " + network_digest(*snapshot));
    _capabilityLabel.stringValue = to_ns_string("capabilities: " + capability_digest(*snapshot));
    _modelsLabel.stringValue = to_ns_string("models: " + models_digest(*snapshot));
    _rawView.string = to_ns_string(snapshot_dump(*snapshot));
    [self refreshPreviewForSnapshot:snapshot];
}

- (void)loadControlsFromCurrentSelection {
    const DeviceSnapshot* snapshot = [self currentSnapshot];
    if (snapshot == nullptr) {
        [self refreshControlAvailability];
        return;
    }

    _aliasField.stringValue = to_ns_string(snapshot->alias);
    if (!snapshot->status_payload.is_object()) {
        [self refreshControlAvailability];
        return;
    }

    const Value& status = snapshot->status_payload;

    const auto* captureMode = find_in_object(status, "captureMode");
    if (captureMode != nullptr && captureMode->is_string()) {
        [_modePopup selectItemWithTitle:to_ns_string(captureMode->as_string())];
    }

    const auto* focusMode = find_in_object(status, "focusMode");
    if (focusMode != nullptr && focusMode->is_string()) {
        [_focusPopup selectItemWithTitle:to_ns_string(focusMode->as_string())];
    }

    const auto* selectedLens = find_in_object(status, "selectedLens");
    if (selectedLens != nullptr && selectedLens->is_string()) {
        [_lensPopup selectItemWithTitle:to_ns_string(selectedLens->as_string())];
    }

    const auto* recordingProfile = find_in_object(status, "recordingProfile");
    if (recordingProfile != nullptr && recordingProfile->is_string()) {
        [_profilePopup selectItemWithTitle:to_ns_string(recordingProfile->as_string())];
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
    _remotePostField.stringValue = to_ns_string(string_or(find_in_object(status, "remotePostURL")));

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
                    replace_popup_items(_lensPopup, items);
                    [_lensPopup selectItemWithTitle:to_ns_string(string_or(selectedLens, items.front()))];
                }
            }

            if (const auto* supportsProRes = find_in_object(*capabilities, "supportsProRes"); supportsProRes != nullptr) {
                if (bool_or(supportsProRes, false)) {
                    replace_popup_items(_profilePopup, {"h264", "hevc", "proRes"});
                } else {
                    replace_popup_items(_profilePopup, {"h264", "hevc"});
                }
                [_profilePopup selectItemWithTitle:to_ns_string(string_or(recordingProfile, "hevc"))];
            }
        }
    }

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
        _previewTitleLabel.stringValue = @"LIVE PREVIEW MIRROR RESERVED";
        _previewSubtitleLabel.stringValue = @"select a device to inspect latest media, inference digest, and runtime artifact state";
        return;
    }

    const std::string inference_summary = inference_digest(*snapshot);
    if (!snapshot->preview_jpeg_base64.empty() && snapshot->preview_frame_index > 0) {
        NSData* image_data = [[NSData alloc] initWithBase64EncodedString:to_ns_string(snapshot->preview_jpeg_base64) options:0];
        NSImage* image = image_data == nil ? nil : [[NSImage alloc] initWithData:image_data];
        _previewImageView.image = image;
        _previewTitleLabel.stringValue = @"LIVE MIRROR";
        _previewSubtitleLabel.stringValue = to_ns_string(
            "frame=" + std::to_string(snapshot->preview_frame_index)
            + " | size=" + std::to_string(snapshot->preview_image_width) + "x" + std::to_string(snapshot->preview_image_height)
            + " | received=" + snapshot->preview_seen + "\n"
            + "latest inference :: " + inference_summary
        );
        return;
    }

    if (!snapshot->last_media_path.empty()) {
        const bool is_image = is_image_media_path(snapshot->last_media_path);
        const std::string category = snapshot->last_media_category.empty() ? "media" : snapshot->last_media_category;
        const std::string file_name = std::filesystem::path(snapshot->last_media_path).filename().string();

        if (is_image) {
            NSImage* image = [[NSImage alloc] initWithContentsOfFile:to_ns_string(snapshot->last_media_path)];
            _previewImageView.image = image;
        } else {
            _previewImageView.image = nil;
        }

        _previewTitleLabel.stringValue = to_ns_string("LATEST " + std::string(is_image ? "IMAGE" : "ARTIFACT") + " · " + category);
        _previewSubtitleLabel.stringValue = to_ns_string(
            file_name + "\n"
            + compact_path(snapshot->last_media_path) + "\n"
            + "received=" + (snapshot->last_media_seen.empty() ? snapshot->last_seen : snapshot->last_media_seen)
            + " | " + inference_summary
        );
        return;
    }

    _previewImageView.image = nil;
    _previewTitleLabel.stringValue = @"NO MEDIA RECEIVED YET";
    _previewSubtitleLabel.stringValue = to_ns_string(
        "latest inference :: " + inference_summary + "\n"
        + "desktop runtime media path will populate here after remote photo / video capture completes"
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

    const bool lockedFocus = [[_focusPopup titleOfSelectedItem] isEqualToString:@"locked"];

    _productField.enabled = hasSelection;
    _pointField.enabled = hasSelection;
    _jobField.enabled = hasSelection;
    _aliasField.enabled = hasSelection;
    _modelField.enabled = hasSelection;
    _modelVersionField.enabled = hasSelection;
    _activateAfterInstallToggle.enabled = hasSelection;

    _remotePostField.enabled = isOnline;
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
    const std::string host = to_std_string(_hostField.stringValue);
    if (!host.empty()) {
        _runtime->connect_host(host);
    }
}

- (void)scanPressed:(id)sender {
    (void)sender;
    _runtime->scan_prefix_async(
        to_std_string(_scanPrefixField.stringValue),
        std::max(0, _scanStartField.intValue),
        std::max(0, _scanEndField.intValue)
    );
}

- (void)startBonjourDiscovery {
    if (_serviceBrowser != nil) {
        return;
    }

    _serviceBrowser = [[NSNetServiceBrowser alloc] init];
    _serviceBrowser.delegate = self;
    _bonjourLabel.stringValue = @"Bonjour searching _vino-control._tcp";
    [_serviceBrowser searchForServicesOfType:@"_vino-control._tcp." inDomain:@""];
}

- (void)rebuildBonjourPopup {
    [_bonjourPopup removeAllItems];

    NSArray<NSNetService*>* services = [[_bonjourServices allValues] sortedArrayUsingComparator:^NSComparisonResult(NSNetService* lhs, NSNetService* rhs) {
        return [lhs.name compare:rhs.name options:NSCaseInsensitiveSearch];
    }];

    if (services.count == 0) {
        [_bonjourPopup addItemWithTitle:@"No Bonjour devices"];
        _bonjourPopup.enabled = NO;
        return;
    }

    _bonjourPopup.enabled = YES;
    for (NSNetService* service in services) {
        const std::string host = host_from_service(service);
        NSString* title = host.empty()
            ? [NSString stringWithFormat:@"%@ · resolving", service.name]
            : [NSString stringWithFormat:@"%@ · %@:%ld", service.name, to_ns_string(host), static_cast<long>(service.port > 0 ? service.port : 48920)];
        [_bonjourPopup addItemWithTitle:title];
        _bonjourPopup.lastItem.representedObject = service;
    }

    _bonjourLabel.stringValue = [NSString stringWithFormat:@"Bonjour discovered %lu device(s)", static_cast<unsigned long>(services.count)];
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
        _bonjourLabel.stringValue = [NSString stringWithFormat:@"Resolving %@", service.name];
        return;
    }

    _hostField.stringValue = to_ns_string(host);
    _runtime->connect_host(host, service.port > 0 ? static_cast<int>(service.port) : 48920);
}

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser*)browser {
    (void)browser;
    _bonjourLabel.stringValue = @"Bonjour searching _vino-control._tcp";
}

- (void)netServiceBrowser:(NSNetServiceBrowser*)browser didNotSearch:(NSDictionary<NSString*, NSNumber*>*)errorDict {
    (void)browser;
    _bonjourLabel.stringValue = [NSString stringWithFormat:@"Bonjour search failed %@", errorDict.description];
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
    [self refreshSliderLabels];
}

- (void)controlChanged:(id)sender {
    (void)sender;
    [self refreshControlAvailability];
}

- (void)togglePressed:(id)sender {
    (void)sender;
    [self refreshControlAvailability];
}

- (void)applyPatchPressed:(id)sender {
    (void)sender;

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
    payload["captureMode"] = to_std_string(_modePopup.selectedItem.title);
    payload["focusMode"] = to_std_string(_focusPopup.selectedItem.title);
    payload["selectedLens"] = to_std_string(_lensPopup.selectedItem.title);
    payload["recordingProfile"] = to_std_string(_profilePopup.selectedItem.title);
    payload["smoothAutoFocusEnabled"] = (_smoothAFToggle.state == NSControlStateValueOn);
    payload["flashEnabled"] = (_flashToggle.state == NSControlStateValueOn);
    payload["inferenceEnabled"] = (_inferenceToggle.state == NSControlStateValueOn);
    payload["persistMediaEnabled"] = (_persistToggle.state == NSControlStateValueOn);
    payload["remotePostURL"] = to_std_string(_remotePostField.stringValue);
    payload["settings"] = settings;

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
    _runtime->install_model_to_device(
        snapshot->device_id,
        path,
        model_id,
        model_id,
        version,
        _activateAfterInstallToggle.state == NSControlStateValueOn
    );
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
    _runtime->install_model_to_devices(
        device_ids,
        path,
        model_id,
        model_id,
        version,
        _activateAfterInstallToggle.state == NSControlStateValueOn
    );
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
