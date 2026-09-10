#pragma once

#include <godot_cpp/variant/string.hpp>

struct Error {
    godot::String reason;
    bool hasError;

    Error(const godot::String& reason)
        : reason   (reason)
        , hasError (true)
    {}

    Error()
        : hasError (false)
    {}

    operator bool() const {
        return hasError;
    }
};

template<typename T>
struct Result {
    T value;
    Error error;

    Result() = default;

    Result(T&& value)
        : value (std::move(value))
    {}

    Result(const T& value)
        : value (value)
    {}

    Result(Error&& error)
        : error (std::move(error))
    {}

    Result(const Error& error)
        : error (error)
    {}

    operator const T&() const {
        return value;
    }

    bool has_error() const {
        return error == true;
    }
};

struct Nothing {};

template<typename T>
struct Optional {
    T value;
    bool hasValue;

    Optional()
        : hasValue (false)
    {}

    Optional(const T& v)
        : value    (v)
        , hasValue (true)
    {}

    Optional(T&& v)
        : value    (std::move(v))
        , hasValue (true)
    {}

    Optional(Nothing&&)
        : hasValue (false)
    {}

    explicit operator bool() const { return hasValue; }
    T* operator->() { return &value; }
    const T* operator->() const { return &value; }
    T& operator*() { return value; }
    const T& operator*() const { return value; }
};
