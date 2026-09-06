#pragma once

#include <string>

struct Error {
    std::string reason;
    bool hasError;

    Error(const std::string& reason) 
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

    Optional(T&& value) 
        : value    (std::move(value))
        , hasValue (true)
    {}

    Optional(Nothing&&)
        : hasValue (false)
    {}
};

