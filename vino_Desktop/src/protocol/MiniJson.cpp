#include "vino_desktop/MiniJson.hpp"

#include <cctype>
#include <cmath>
#include <iomanip>
#include <sstream>

namespace vino::desktop::json {

namespace {

class Parser {
public:
    explicit Parser(std::string_view input)
        : input_(input) {}

    Value parse_root() {
        skip_whitespace();
        Value value = parse_value();
        skip_whitespace();
        if (!is_end()) {
            throw ParseError("unexpected trailing characters");
        }
        return value;
    }

private:
    Value parse_value() {
        if (is_end()) {
            throw ParseError("unexpected end of json");
        }

        const char token = current();
        if (token == 'n') {
            consume_literal("null");
            return Value(nullptr);
        }
        if (token == 't') {
            consume_literal("true");
            return Value(true);
        }
        if (token == 'f') {
            consume_literal("false");
            return Value(false);
        }
        if (token == '"') {
            return Value(parse_string_literal());
        }
        if (token == '{') {
            return Value(parse_object());
        }
        if (token == '[') {
            return Value(parse_array());
        }
        if (token == '-' || std::isdigit(static_cast<unsigned char>(token))) {
            return Value(parse_number_literal());
        }

        throw ParseError("unexpected token while parsing json");
    }

    Value::Object parse_object() {
        expect('{');
        skip_whitespace();

        Value::Object object;
        if (try_consume('}')) {
            return object;
        }

        while (true) {
            skip_whitespace();
            if (current() != '"') {
                throw ParseError("object key must be a string");
            }
            const std::string key = parse_string_literal();
            skip_whitespace();
            expect(':');
            skip_whitespace();
            object.emplace(key, parse_value());
            skip_whitespace();

            if (try_consume('}')) {
                break;
            }

            expect(',');
            skip_whitespace();
        }

        return object;
    }

    Value::Array parse_array() {
        expect('[');
        skip_whitespace();

        Value::Array array;
        if (try_consume(']')) {
            return array;
        }

        while (true) {
            skip_whitespace();
            array.emplace_back(parse_value());
            skip_whitespace();

            if (try_consume(']')) {
                break;
            }

            expect(',');
            skip_whitespace();
        }

        return array;
    }

    std::string parse_string_literal() {
        expect('"');
        std::string output;

        while (!is_end()) {
            const char character = current();
            advance();

            if (character == '"') {
                return output;
            }

            if (character == '\\') {
                if (is_end()) {
                    throw ParseError("unexpected end after escape");
                }

                const char escaped = current();
                advance();

                switch (escaped) {
                case '"':
                case '\\':
                case '/':
                    output.push_back(escaped);
                    break;
                case 'b':
                    output.push_back('\b');
                    break;
                case 'f':
                    output.push_back('\f');
                    break;
                case 'n':
                    output.push_back('\n');
                    break;
                case 'r':
                    output.push_back('\r');
                    break;
                case 't':
                    output.push_back('\t');
                    break;
                case 'u':
                    throw ParseError("unicode escape is not supported in this parser");
                default:
                    throw ParseError("invalid escape sequence");
                }

                continue;
            }

            output.push_back(character);
        }

        throw ParseError("unterminated string literal");
    }

    double parse_number_literal() {
        const std::size_t start = position_;

        if (current() == '-') {
            advance();
        }

        consume_digits();

        if (!is_end() && current() == '.') {
            advance();
            consume_digits();
        }

        if (!is_end() && (current() == 'e' || current() == 'E')) {
            advance();
            if (!is_end() && (current() == '+' || current() == '-')) {
                advance();
            }
            consume_digits();
        }

        const std::string literal(input_.substr(start, position_ - start));
        try {
            return std::stod(literal);
        } catch (...) {
            throw ParseError("invalid number literal");
        }
    }

    void consume_digits() {
        if (is_end() || !std::isdigit(static_cast<unsigned char>(current()))) {
            throw ParseError("expected digit");
        }

        while (!is_end() && std::isdigit(static_cast<unsigned char>(current()))) {
            advance();
        }
    }

    void consume_literal(std::string_view literal) {
        for (const char expected : literal) {
            if (is_end() || current() != expected) {
                throw ParseError("unexpected literal");
            }
            advance();
        }
    }

    void skip_whitespace() {
        while (!is_end() && std::isspace(static_cast<unsigned char>(current()))) {
            advance();
        }
    }

    void expect(char expected) {
        if (is_end() || current() != expected) {
            throw ParseError("unexpected token");
        }
        advance();
    }

    bool try_consume(char expected) {
        if (!is_end() && current() == expected) {
            advance();
            return true;
        }
        return false;
    }

    [[nodiscard]] bool is_end() const {
        return position_ >= input_.size();
    }

    [[nodiscard]] char current() const {
        return input_[position_];
    }

    void advance() {
        ++position_;
    }

    std::string_view input_;
    std::size_t position_ {0};
};

std::string stringify_impl(const Value& value, int indent, int level) {
    const auto indent_string = [&](int depth) {
        return std::string(depth * indent, ' ');
    };

    if (value.is_null()) {
        return "null";
    }
    if (value.is_bool()) {
        return value.as_bool() ? "true" : "false";
    }
    if (value.is_number()) {
        std::ostringstream stream;
        stream << std::setprecision(15) << value.as_number();
        return stream.str();
    }
    if (value.is_string()) {
        return "\"" + escape(value.as_string()) + "\"";
    }
    if (value.is_array()) {
        const auto& array = value.as_array();
        if (array.empty()) {
            return "[]";
        }

        std::ostringstream stream;
        stream << "[";
        for (std::size_t index = 0; index < array.size(); ++index) {
            if (index > 0) {
                stream << ",";
            }
            if (indent > 0) {
                stream << "\n" << indent_string(level + 1);
            }
            stream << stringify_impl(array[index], indent, level + 1);
        }
        if (indent > 0) {
            stream << "\n" << indent_string(level);
        }
        stream << "]";
        return stream.str();
    }

    const auto& object = value.as_object();
    if (object.empty()) {
        return "{}";
    }

    std::ostringstream stream;
    stream << "{";
    bool is_first = true;
    for (const auto& [key, entry] : object) {
        if (!is_first) {
            stream << ",";
        }
        is_first = false;
        if (indent > 0) {
            stream << "\n" << indent_string(level + 1);
        }
        stream << "\"" << escape(key) << "\":";
        if (indent > 0) {
            stream << " ";
        }
        stream << stringify_impl(entry, indent, level + 1);
    }
    if (indent > 0) {
        stream << "\n" << indent_string(level);
    }
    stream << "}";
    return stream.str();
}

} // namespace

Value::Value(std::nullptr_t)
    : storage_(nullptr) {}

Value::Value(bool value)
    : storage_(value) {}

Value::Value(int value)
    : storage_(static_cast<double>(value)) {}

Value::Value(double value)
    : storage_(value) {}

Value::Value(std::string value)
    : storage_(std::move(value)) {}

Value::Value(const char* value)
    : storage_(std::string(value)) {}

Value::Value(Array value)
    : storage_(std::move(value)) {}

Value::Value(Object value)
    : storage_(std::move(value)) {}

bool Value::is_null() const { return std::holds_alternative<std::nullptr_t>(storage_); }
bool Value::is_bool() const { return std::holds_alternative<bool>(storage_); }
bool Value::is_number() const { return std::holds_alternative<double>(storage_); }
bool Value::is_string() const { return std::holds_alternative<std::string>(storage_); }
bool Value::is_array() const { return std::holds_alternative<Array>(storage_); }
bool Value::is_object() const { return std::holds_alternative<Object>(storage_); }

bool Value::as_bool() const { return std::get<bool>(storage_); }
double Value::as_number() const { return std::get<double>(storage_); }
int Value::as_int() const { return static_cast<int>(std::llround(std::get<double>(storage_))); }
const std::string& Value::as_string() const { return std::get<std::string>(storage_); }
const Value::Array& Value::as_array() const { return std::get<Array>(storage_); }
const Value::Object& Value::as_object() const { return std::get<Object>(storage_); }
Value::Array& Value::as_array() { return std::get<Array>(storage_); }
Value::Object& Value::as_object() { return std::get<Object>(storage_); }

bool Value::contains(std::string_view key) const {
    if (!is_object()) {
        return false;
    }
    return as_object().find(std::string(key)) != as_object().end();
}

const Value& Value::at(std::string_view key) const {
    return as_object().at(std::string(key));
}

const Value* Value::find(std::string_view key) const {
    if (!is_object()) {
        return nullptr;
    }
    const auto iterator = as_object().find(std::string(key));
    if (iterator == as_object().end()) {
        return nullptr;
    }
    return &iterator->second;
}

std::string Value::stringify(int indent) const {
    return stringify_impl(*this, indent, 0);
}

ParseError::ParseError(const std::string& message)
    : std::runtime_error(message) {}

Value parse(std::string_view text) {
    return Parser(text).parse_root();
}

std::string escape(std::string_view input) {
    std::string output;
    output.reserve(input.size() + 8);

    for (const char character : input) {
        switch (character) {
        case '\\':
            output += "\\\\";
            break;
        case '"':
            output += "\\\"";
            break;
        case '\b':
            output += "\\b";
            break;
        case '\f':
            output += "\\f";
            break;
        case '\n':
            output += "\\n";
            break;
        case '\r':
            output += "\\r";
            break;
        case '\t':
            output += "\\t";
            break;
        default:
            output.push_back(character);
            break;
        }
    }

    return output;
}

} // namespace vino::desktop::json

