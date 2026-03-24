#include "vino_desktop/PostGateway.hpp"

#include <sstream>

namespace vino::desktop {

std::vector<EndpointDoc> PostGatewayBlueprint::endpoints() const {
    return {
        {"POST", "/api/v1/batch", "queue multiple operations against live iPhones"},
        {"GET", "/api/v1/devices", "inspect discovered devices and heartbeat snapshots"},
        {"GET", "/api/v1/jobs/{jobId}", "inspect a batch job execution summary"}
    };
}

std::string PostGatewayBlueprint::render_documentation() const {
    std::ostringstream stream;
    stream
        << "POST gateway blueprint\n"
        << "----------------------------------------\n";

    for (const auto& endpoint : endpoints()) {
        stream
            << "- " << endpoint.method
            << ' ' << endpoint.path
            << " :: " << endpoint.summary
            << '\n';
    }

    return stream.str();
}

std::string PostGatewayBlueprint::render_example_request() const {
    std::ostringstream stream;
    stream
        << "{\n"
        << "  \"requestId\": \"batch-20260324-001\",\n"
        << "  \"operations\": [\n"
        << "    {\n"
        << "      \"target\": { \"deviceIds\": [\"iphone-001\"] },\n"
        << "      \"action\": \"camera.config.patch\",\n"
        << "      \"context\": {\n"
        << "        \"productUUID\": \"P-2026-03-24-0001\",\n"
        << "        \"pointIndex\": 3\n"
        << "      },\n"
        << "      \"payload\": {\n"
        << "        \"captureMode\": \"photo\",\n"
        << "        \"settings\": {\n"
        << "          \"frameRate\": 24,\n"
        << "          \"iso\": 80,\n"
        << "          \"zoomFactor\": 2.0\n"
        << "        }\n"
        << "      }\n"
        << "    },\n"
        << "    {\n"
        << "      \"target\": { \"deviceIds\": [\"iphone-001\"] },\n"
        << "      \"action\": \"capture.photo.trigger\",\n"
        << "      \"context\": {\n"
        << "        \"productUUID\": \"P-2026-03-24-0001\",\n"
        << "        \"pointIndex\": 3\n"
        << "      },\n"
        << "      \"payload\": {}\n"
        << "    }\n"
        << "  ]\n"
        << "}\n";

    return stream.str();
}

} // namespace vino::desktop

