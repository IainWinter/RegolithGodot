#pragma once

#include <godot_cpp/variant/string.hpp>

struct AssetMetadata {
    godot::String name;

    AssetMetadata() {}

    explicit AssetMetadata(const godot::String& name)
        : name (name)
    {}
};
