#include "RegolithSprite.h"
#include "RegolithWorld.h"
#include "RegolithDebugDraw.h"
#include "RegolithRopeRender.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static void initialize_regolith(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }

    GDREGISTER_CLASS(RegolithWorld);
    GDREGISTER_CLASS(RegolithSprite);
    GDREGISTER_CLASS(RegolithDebugDraw);
    GDREGISTER_CLASS(RegolithRopeRender);
}

static void uninitialize_regolith(ModuleInitializationLevel level) {}

extern "C" {

GDExtensionBool GDE_EXPORT regolith_library_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);

    init.register_initializer(initialize_regolith);
    init.register_terminator(uninitialize_regolith);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

    return init.init();
}

}
