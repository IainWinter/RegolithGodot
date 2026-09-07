#pragma once

#include "Color.h"
#include "Math/Vector.h"

#include <inttypes.h>
#include <string_view>

static const int k_sprite_class_count = 9;

struct [[Struct]] ClassMask {
    uint16_t bits = 0xFFFF;
};

// sprite enum stuff

enum SpriteCellMaskType {
    SpriteCellMaskType_Empty,
    SpriteCellMaskType_Filled,
    SpriteCellMaskType_Core,
    SpriteCellMaskType_Weakpoint1,
    SpriteCellMaskType_Weakpoint2,
    SpriteCellMaskType_Weakpoint3,
    SpriteCellMaskType_Weakpoint4,
    SpriteCellMaskType_Joint1,
    SpriteCellMaskType_Joint2,
    SpriteCellMaskType_Joint3,
    SpriteCellMaskType_Joint4,
    SpriteCellMaskType_Rope,
    SpriteCellMaskType_Count
};

enum SpriteCellMaskBits : uint16_t {
};

inline constexpr std::string_view sprite_cell_mask_type_name(SpriteCellMaskType type) {
    constexpr const char* names[SpriteCellMaskType_Count] = {
        "Empty",
        "Filled",
        "Core",
        "Weakpoint1",
        "Weakpoint2",
        "Weakpoint3",
        "Weakpoint4",
        "Joint1",
        "Joint2",
        "Joint3",
        "Joint4",
        "Rope",
    };

    return names[type];
}

struct [[Struct]] SpriteCellMask {
    uint16_t bits;

    // Bit layout:
    // bits  0-4  : type    (5 bits)
    // bit     5  : removed (1 bit)
    // bit     6  : lookup  (1 bit)  // sample color from palette LUT using rgb as index
    // bits  7-9  : class   (3 bits) // armor class / cell health, 0 = normal health
    // bits 10-13 : heat    (4 bits) // burn / pulse heat 0-15, decays in SpriteHeatDecayUpdate
    // bit    14  : emissive (1 bit) // cell writes its color to the emission map
    // bit    15  : unused  (1 bit)

    SpriteCellMask()
        : bits(0u) {}

    explicit SpriteCellMask(SpriteCellMaskType type)
        : bits(0u) {
        set_type(type);
    }

    explicit SpriteCellMask(uint16_t bits)
        : bits(bits) {}

    bool operator==(const SpriteCellMask& other) const {
        return bits == other.bits;
    }

    bool operator!=(const SpriteCellMask& other) const {
        return !(*this == other);
    }

    SpriteCellMaskBits get_bits() const {
        return static_cast<SpriteCellMaskBits>(bits);
    }

    SpriteCellMaskType get_type() const {
        return static_cast<SpriteCellMaskType>(bits & 0b0000000000011111);
    }

    bool get_removed() const {
        return (bits >> 5) & 0b1;
    }

    bool get_lookup() const {
        return (bits >> 6) & 0b1;
    }

    uint8_t get_class() const {
        if (is_empty()) {
            return 0;
        }

        return (bits >> 7) & 0b111;
    }

    uint8_t get_heat() const {
        return (bits >> 10) & 0b1111;
    }

    bool get_emissive() const {
        return (bits >> 14) & 0b1;
    }

    void set_type(SpriteCellMaskType type) {
        bits = (bits & 0b1111111111100000) | (static_cast<uint16_t>(type) & 0b00011111);
    }

    void set_class(uint8_t cell_class) {
        bits = (bits & 0b1111110001111111) | ((static_cast<uint16_t>(cell_class) & 0b111) << 7);
    }

    void set_removed(bool removed) {
        if (removed) {
            bits |= (1 << 5);
        }

        else {
            bits &= ~(1 << 5);
        }
    }

    void set_lookup(bool lookup) {
        if (lookup) {
            bits |= (1 << 6);
        }

        else {
            bits &= ~(1 << 6);
        }
    }

    void set_heat(uint8_t heat) {
        bits = (bits & 0b1100001111111111) | ((static_cast<uint16_t>(heat) & 0b1111) << 10);
    }

    void set_emissive(bool emissive) {
        if (emissive) {
            bits |= (1 << 14);
        }

        else {
            bits &= ~(1 << 14);
        }
    }

    bool is_core_type() const {
        SpriteCellMaskType type = get_type();
        return type >= SpriteCellMaskType_Core && type <= SpriteCellMaskType_Weakpoint4;
    }

    bool is_rope() const {
        return get_type() == SpriteCellMaskType_Rope;
    }

    bool is_empty() const {
        return get_removed() || get_type() == static_cast<SpriteCellMaskType>(0);
    }

    bool is_filled() const {
        return !is_empty();
    }
};

struct [[Struct]] SpriteCell {
    Color4 color;
    SpriteCellMask type;
};

inline long long sprite_cell_key(int chunkIndex, int cellIndex) {
    return ((long long)chunkIndex << 32) | (unsigned)cellIndex;
}
