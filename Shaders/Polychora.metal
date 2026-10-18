#include <metal_stdlib>
using namespace metal;

// Layout mirrors `Uniforms` in Renderer.swift: float4 / float4x4 members only.
struct Uniforms {
    float4x4 rot4;
    float4x4 viewProj;
    float4 cameraPos;   // xyz
    float4 proj;        // d, sphericalBlend, scale, poleEpsilon
    float4 radii;       // edge, vertex, fade, time
    float4 fog;         // density, nearFadeStart, nearFadeEnd, faceAlpha
    float4 bgTop;
    float4 bgBottom;
    float4 edgeColor;
    float4 vertexColor;
    float4 faceColor;
    float4 lightDir;
    float4 palA, palB, palC, palD;
    float4 style;       // ringMix, fresnelPower, specular, unused
    float4 viewport;    // width, height
    float4 pole;        // radius cap (in λ), pole-fog start λ, pole-fog end λ
    float4 glow;        // rgb, mode (0 none, 1 horizon band, 2 backlight halo)
    float4 glowShape;   // centre x, centre y (uv), width / radius (screen heights)
    float4 rimLight;    // rgb (colour × strength)
};

struct Instance {
    float4 a;
    float4 b;
    float4 c;
    float4 info;        // x: ring index (<0: none)
};

struct VOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 color;
    float valid;
    float lambda;
};

struct Projected { float3 p; float lambda; float valid; };

// Unified 4D→3D map: perspective from (0,0,0,d), optionally after pushing the
// point onto S³. d = 1 with full blend is stereographic projection.
static Projected project4(float4 q, constant Uniforms& u) {
    float4 s = mix(q, normalize(q), u.proj.y);
    float denom = u.proj.x - s.w;
    Projected r;
    r.valid = step(u.proj.w, denom);
    denom = max(denom, u.proj.w);
    r.lambda = u.proj.z / denom;
    r.p = s.xyz * r.lambda;
    return r;
}

// `t` is the ring index normalised to [0, 1); negative means "not on a ring".
static float3 ringColor(float t, float baseMix, float3 base, constant Uniforms& u) {
    if (t < 0.0) return base;
    float3 pal = u.palA.xyz + u.palB.xyz * cos(6.2831853 * (u.palC.xyz * t + u.palD.xyz));
    return mix(base, pal, baseMix);
}

// Visibility near the projection pole, where stereographic scale λ blows up.
static float poleVisibility(float lambda, constant Uniforms& u) {
    return 1.0 - smoothstep(u.pole.y, u.pole.z, lambda);
}

static float3 applyFog(float3 c, float3 world, float lambda, constant Uniforms& u) {
    float dist = length(u.cameraPos.xyz - world);
    float f = exp(-u.fog.x * max(dist - 1.0, 0.0)) * poleVisibility(lambda, u);
    float3 fogColor = mix(u.bgBottom.xyz, u.bgTop.xyz, 0.5);
    return mix(fogColor, c, f);
}

static float3 shade(float3 base, float3 n, float3 world, float specK, constant Uniforms& u) {
    float3 V = normalize(u.cameraPos.xyz - world);
    if (dot(n, V) < 0.0) n = -n;
    float3 L = normalize(u.lightDir.xyz);
    float key = max(dot(n, L), 0.0);
    float hemi = 0.5 + 0.5 * n.y;
    float3 H = normalize(L + V);
    float spec = pow(max(dot(n, H), 0.0), 40.0) * specK;
    float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0);
    return base * (0.62 * key + 0.30 * hemi + 0.12) + spec + 0.25 * rim * base + u.rimLight.xyz * rim;
}

// MARK: Background

struct BgOut { float4 position [[position]]; float2 uv; };

vertex BgOut background_vs(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    BgOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = p;
    return o;
}

static float3 glowLight(float2 uv, constant Uniforms& u) {
    float mode = u.glow.w;
    if (mode < 0.5) return float3(0.0);
    float aspect = u.viewport.x / max(u.viewport.y, 1.0);
    if (mode < 1.5) {
        float dy = (uv.y - u.glowShape.y) / u.glowShape.z;
        float dx = uv.x - 0.5;
        return u.glow.xyz * exp(-dy * dy) * (1.0 - 0.6 * dx * dx);
    }
    // Elliptical halo, a little taller than wide, as light spilling round an object on a plinth.
    float2 d = float2((uv.x - u.glowShape.x) * aspect, (uv.y - u.glowShape.y) * 0.85) / u.glowShape.z;
    return u.glow.xyz * exp(-dot(d, d));
}

static float3 backgroundColor(float2 uv, float4 frag, constant Uniforms& u) {
    float3 c = mix(u.bgBottom.xyz, u.bgTop.xyz, saturate(uv.y));
    float2 d = uv - 0.5;
    c *= 1.0 - 0.35 * dot(d, d);
    c += glowLight(uv, u);
    // Dither against 8-bit banding.
    float n = fract(sin(dot(frag.xy, float2(12.9898, 78.233))) * 43758.5453);
    return c + (n - 0.5) / 255.0;
}

fragment float4 background_fs(BgOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    return float4(backgroundColor(in.uv, in.position, u), 1.0);
}

// Cross-fade to background during slideshow transitions.
fragment float4 fade_fs(BgOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float a = 1.0 - u.radii.z;
    return float4(backgroundColor(in.uv, in.position, u) * a, a);
}

// MARK: Edges (tubes along the projected 4D segment / great arc)

vertex VOut edge_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
                    const device float2* tmpl [[buffer(0)]],
                    const device Instance* inst [[buffer(1)]],
                    constant Uniforms& u [[buffer(2)]]) {
    float2 tv = tmpl[vid];
    Instance e = inst[iid];
    float4 a = u.rot4 * e.a;
    float4 b = u.rot4 * e.b;
    const float h = 0.02;
    Projected c = project4(mix(a, b, tv.x), u);
    Projected c0 = project4(mix(a, b, tv.x - h), u);
    Projected c1 = project4(mix(a, b, tv.x + h), u);
    float3 T = normalize(c1.p - c0.p);
    float3 V = normalize(u.cameraPos.xyz - c.p);
    float3 N1 = cross(T, V);
    if (length(N1) < 1e-4) N1 = cross(T, float3(0.0, 1.0, 0.0));
    N1 = normalize(N1);
    float3 N2 = cross(T, N1);
    float3 n = cos(tv.y) * N1 + sin(tv.y) * N2;
    float3 world = c.p + n * (u.radii.x * min(c.lambda, u.pole.x));

    VOut o;
    o.position = u.viewProj * float4(world, 1.0);
    o.world = world;
    o.normal = n;
    o.color = ringColor(e.info.x, u.style.x, u.edgeColor.xyz, u);
    o.valid = c.valid * c0.valid * c1.valid;
    o.lambda = c.lambda;
    return o;
}

// MARK: Vertices (spheres)

vertex VOut vertex_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
                      const device float3* tmpl [[buffer(0)]],
                      const device Instance* inst [[buffer(1)]],
                      constant Uniforms& u [[buffer(2)]]) {
    float3 n = tmpl[vid];
    Instance v = inst[iid];
    Projected c = project4(u.rot4 * v.a, u);
    float3 world = c.p + n * (u.radii.y * min(c.lambda, u.pole.x));
    VOut o;
    o.position = u.viewProj * float4(world, 1.0);
    o.world = world;
    o.normal = n;
    o.color = ringColor(v.info.x, u.style.x, u.vertexColor.xyz, u);
    o.valid = c.valid;
    o.lambda = c.lambda;
    return o;
}

fragment float4 opaque_fs(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    if (in.valid < 0.999 || in.lambda > u.pole.z) discard_fragment();
    float3 c = shade(in.color, normalize(in.normal), in.world, u.style.z, u);
    return float4(applyFog(c, in.world, in.lambda, u), 1.0);
}

// MARK: Faces (subdivided triangles, curved onto S³ by the blend)

vertex VOut face_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
                    const device float2* tmpl [[buffer(0)]],
                    const device Instance* inst [[buffer(1)]],
                    constant Uniforms& u [[buffer(2)]]) {
    float2 bc = tmpl[vid];
    Instance f = inst[iid];
    float4 a = u.rot4 * f.a, b = u.rot4 * f.b, c = u.rot4 * f.c;
    const float h = 0.01;
    float4 p = a + bc.x * (b - a) + bc.y * (c - a);
    Projected q = project4(p, u);
    Projected qu = project4(p + h * (b - a), u);
    Projected qv = project4(p + h * (c - a), u);
    VOut o;
    o.position = u.viewProj * float4(q.p, 1.0);
    o.world = q.p;
    o.normal = normalize(cross(qu.p - q.p, qv.p - q.p));
    o.color = ringColor(f.info.x, u.style.x, u.faceColor.xyz, u);
    o.valid = q.valid;
    o.lambda = q.lambda;
    return o;
}

fragment float4 face_fs(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    if (in.valid < 0.999 || in.lambda > u.pole.z) discard_fragment();
    float3 n = normalize(in.normal);
    float3 V = normalize(u.cameraPos.xyz - in.world);
    float facing = abs(dot(n, V));
    float fresnel = pow(1.0 - facing, u.style.y);
    float alpha = u.fog.w * (0.35 + 0.65 * fresnel);
    float dist = length(u.cameraPos.xyz - in.world);
    alpha *= smoothstep(u.fog.y, u.fog.z, dist) * poleVisibility(in.lambda, u);
    float3 c = shade(in.color, n, in.world, u.style.z * 0.5, u);
    c = applyFog(c, in.world, in.lambda, u);
    return float4(c * alpha, alpha);
}
