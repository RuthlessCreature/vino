#pragma once

#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace vino::desktop::json {

class Value {
public:
    using Array = std::vector<Value>;
    using Object = std::map<std::string, Value>;

    Value() = default;
    Value(std::nullptr_t);
    Value(bool value);
    Value(int value);
    Value(double value);
    Value(std::string value);
    Value(const char* value);
    Value(Array value);
    Value(Object value);

    [[nodiscard]] bool is_null() const;
    [[nodiscard]] bool is_bool() const;
    [[nodiscard]] bool is_number() const;
    [[nodiscard]] bool is_string() const;
    [[nodiscard]] bool is_array() const;
    [[nodiscard]] bool is_object() const;

    [[nodiscard]] bool as_bool() const;
    [[nodiscard]] double as_number() const;
    [[nodiscard]] int as_int() const;
    [[nodiscard]] const std::string& as_string() const;
    [[nodiscard]] const Array& as_array() const;
    [[nodiscard]] const Object& as_object() const;
    [[nodiscard]] Array& as_array();
    [[nodiscard]] Object& as_object();

    [[nodiscard]] bool contains(std::string_view key) const;
    [[nodiscard]] const Value& at(std::string_view key) const;
    [[nodiscard]] const Value* find(std::string_view key) const;

    [[nodiscard]] std::string stringify(int indent = 0) const;

private:
    std::variant<std::nullptr_t, bool, double, std::string, Array, Object> storage_ {nullptr};
};

class ParseError : public std::runtime_error {
public:
    explicit ParseError(const std::string& message);
};

[[nodiscard]] Value parse(std::string_view text);
[[nodiscard]] std::string escape(std::string_view input);

} // namespace vino::desktop::json

