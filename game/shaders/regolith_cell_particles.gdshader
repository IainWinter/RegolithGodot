// port of the engine's cell particle spawn on the ParticlePass. the node
// emits nothing on its own, every particle comes from emit_particle with
// position, velocity, color and custom = (age, sprite angle, cell pixels,
// start alpha). the tumble and lifetime are hashed from the particle index
// so nothing else needs storing. velocity damps, the square spins in three
// axes and shrinks to nothing, the alpha holds then drops at the end

shader_type particles;

const float damping = 0.02;
const float pi = 3.14159265;

float hash(uint n) {
    n = (n << 13u) ^ n;
    n = n * (n * n * 15731u + 789221u) + 1376312589u;
    return float(n & 0x7fffffffu) / float(0x7fffffff);
}

void start() {
    CUSTOM.x = 0.0;
    CUSTOM.w = COLOR.a;
}

void process() {
    CUSTOM.x += DELTA;

    float age = CUSTOM.x;
    float life = mix(5.0, 10.0, hash(INDEX * 3u + 1u));

    if (age >= life) {
        ACTIVE = false;
    }

    float ratio = min(age / life, 1.0);
    float decay = (1.0 - exp(-damping * age)) / damping;

    vec3 spin = (vec3(hash(INDEX * 3u + 2u), hash(INDEX * 3u + 3u), hash(INDEX * 3u + 4u)) * 2.0 - 1.0) * pi;
    vec3 angle = vec3(0.0, 0.0, CUSTOM.y) + spin * decay;

    float cx = cos(angle.x); float sx = sin(angle.x);
    float cy = cos(angle.y); float sy = sin(angle.y);
    float cz = cos(angle.z); float sz = sin(angle.z);

    float scale = CUSTOM.z * (1.0 - ratio);

    VELOCITY *= exp(-damping * DELTA);
    TRANSFORM[3].xy += VELOCITY.xy * DELTA;
    TRANSFORM[0] = vec4(cy * cz, cy * sz, 0.0, 0.0) * scale;
    TRANSFORM[1] = vec4(sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, 0.0, 0.0) * scale;

    COLOR.a = CUSTOM.w * (1.0 - pow(ratio, 10.0));
}
