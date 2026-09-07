#pragma once

#include <string>
#include <string_view>

struct [[Struct]] AssetMetadata {
    std::string name;

    AssetMetadata() {}

    explicit AssetMetadata(const std::string name)
        : name (name)
    {}
};
