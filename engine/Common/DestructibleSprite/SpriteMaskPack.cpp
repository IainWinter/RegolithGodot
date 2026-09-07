#include "SpriteMaskPack.h"

static SpriteCellMaskType pixel_to_mask_type(const uint8_t* pixels, int index) {
    if (pixels[index + 2] == 0) {
        return SpriteCellMaskType_Empty;
    }

    switch (pixels[index]) {
        case 50: return SpriteCellMaskType_Joint1;
        case 100: return SpriteCellMaskType_Joint2;
        case 150: return SpriteCellMaskType_Joint3;
        case 200: return SpriteCellMaskType_Joint4;
        case 250: return SpriteCellMaskType_Rope;
    }

    switch (pixels[index + 1]) {
        case 100: return SpriteCellMaskType_Filled;
        case 200: return SpriteCellMaskType_Core;
        case 250: return SpriteCellMaskType_Weakpoint1;
        case 251: return SpriteCellMaskType_Weakpoint2;
        case 252: return SpriteCellMaskType_Weakpoint3;
        case 253: return SpriteCellMaskType_Weakpoint4;
    }

    return SpriteCellMaskType_Empty;
}

static void mask_type_to_pixel(SpriteCellMaskType type, uint8_t& r, uint8_t& g) {
    r = 0;
    g = 0;

    switch (type) {
        case SpriteCellMaskType_Joint1: r = 50; break;
        case SpriteCellMaskType_Joint2: r = 100; break;
        case SpriteCellMaskType_Joint3: r = 150; break;
        case SpriteCellMaskType_Joint4: r = 200; break;
        case SpriteCellMaskType_Rope: r = 250; break;
        case SpriteCellMaskType_Filled: g = 100; break;
        case SpriteCellMaskType_Core: g = 200; break;
        case SpriteCellMaskType_Weakpoint1: g = 250; break;
        case SpriteCellMaskType_Weakpoint2: g = 251; break;
        case SpriteCellMaskType_Weakpoint3: g = 252; break;
        case SpriteCellMaskType_Weakpoint4: g = 253; break;
        default: break;
    }
}

uint8_t pack_sprite_mask_cell(SpriteCellMaskType type, uint8_t cell_class, bool emissive) {
    uint8_t packed = static_cast<uint8_t>(type) & 0b1111;

    packed |= static_cast<uint8_t>((cell_class & 0b111) << 4);

    if (emissive) {
        packed |= 0b10000000;
    }

    return packed;
}

SpriteCellMaskType packed_mask_type(uint8_t packed) {
    uint8_t type = packed & 0b1111;

    if (type >= SpriteCellMaskType_Count) {
        return SpriteCellMaskType_Empty;
    }

    return static_cast<SpriteCellMaskType>(type);
}

uint8_t packed_mask_class(uint8_t packed) {
    return (packed >> 4) & 0b111;
}

bool packed_mask_emissive(uint8_t packed) {
    return (packed >> 7) & 0b1;
}

std::vector<uint8_t> pack_sprite_mask_image(const uint8_t* mask_pixels, int width, int height) {
    std::vector<uint8_t> cells(static_cast<size_t>(width) * height, 0);

    for (int i = 0; i < width * height; i++) {
        int index = i * 4;

        SpriteCellMaskType type = pixel_to_mask_type(mask_pixels, index);

        if (type == SpriteCellMaskType_Empty) {
            continue;
        }

        uint8_t cell_class = static_cast<uint8_t>(255 - mask_pixels[index + 2]) & 0b111;
        bool emissive = mask_pixels[index + 3] == 254;

        cells[i] = pack_sprite_mask_cell(type, cell_class, emissive);
    }

    return cells;
}

std::vector<uint8_t> unpack_sprite_mask_image(const uint8_t* packed_cells, int width, int height) {
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4, 0);

    for (int i = 0; i < width * height; i++) {
        SpriteCellMaskType type = packed_mask_type(packed_cells[i]);
        int index = i * 4;

        if (type == SpriteCellMaskType_Empty) {
            continue;
        }

        uint8_t r = 0;
        uint8_t g = 0;
        mask_type_to_pixel(type, r, g);

        pixels[index] = r;
        pixels[index + 1] = g;
        pixels[index + 2] = static_cast<uint8_t>(255 - packed_mask_class(packed_cells[i]));
        pixels[index + 3] = packed_mask_emissive(packed_cells[i]) ? 254 : 255;
    }

    return pixels;
}
