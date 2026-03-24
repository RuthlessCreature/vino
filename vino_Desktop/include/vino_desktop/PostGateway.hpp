#pragma once

#include <string>
#include <vector>

namespace vino::desktop {

struct EndpointDoc {
    std::string method {};
    std::string path {};
    std::string summary {};
};

class PostGatewayBlueprint {
public:
    [[nodiscard]] std::vector<EndpointDoc> endpoints() const;
    [[nodiscard]] std::string render_documentation() const;
    [[nodiscard]] std::string render_example_request() const;
};

} // namespace vino::desktop

