#include "SpriteCommit.h"

#include "Parallel.h"

std::vector<SpriteCommitResult> sprite_commit_all(const std::vector<SpriteCommitProxy>& proxies, const SpriteCommitConfig& config) {
    std::vector<SpriteCommitResult> results(proxies.size());

    // find splits, remove islands, cut sprites. each proxy only touches its own
    // sprite, pool allocation is locked
    parallel_for(0, proxies.size(), [&](size_t i) {
        const SpriteCommitProxy& proxy = proxies.at(i);
        results.at(i) = proxy.sprite->commit_dirty_chunks(*proxy.transform, config);
    });

    // recompute the edge cells (the surface) of every chunk the commits
    // touched, across all sprites at once
    struct SurfaceChunk {
        Sprite* sprite;
        SpriteChunk* chunk;
    };

    size_t surface_count = 0;
    for (const SpriteCommitResult& result : results) {
        surface_count += result.dirty_chunks.size();
    }

    std::vector<SurfaceChunk> surface;
    surface.reserve(surface_count);

    for (size_t i = 0; i < results.size(); i++) {
        for (SpriteChunk* chunk : results.at(i).dirty_chunks) {
            surface.push_back({proxies.at(i).sprite, chunk});
        }
    }

    parallel_for(0, surface.size(), [&](size_t i) {
        surface.at(i).sprite->recalc_chunk_surface(surface.at(i).chunk);
    });

    return results;
}

void sprite_commit_sync_mass(const Sprite& sprite, PhysicsBody& body) {
    SpriteMassInfo info = sprite.mass_info();

    body.inv_mass = info.inv_mass;
    body.inv_inertia = info.inv_inertia;
    body.center_of_mass = info.center_of_mass;
}

PhysicsBody sprite_commit_split_body(const Transform& split_transform, const PhysicsBody& source) {
    PhysicsBody body;

    body.position = split_transform.position;
    body.last_position = split_transform.position;
    body.angle = split_transform.angle;
    body.last_angle = split_transform.angle;
    body.linear_velocity = source.linear_velocity;
    body.angular_velocity = source.angular_velocity;

    return body;
}

bool sprite_commit_has_rotator(const PhysicsBody& body) {
    for (const PhysicsJoint& joint : body.joints) {
        if (joint.type == PhysicsJointType_Rotator) {
            return true;
        }
    }

    return false;
}
