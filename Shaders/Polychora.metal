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
    float4 style;       // ringMix, fresnelPower, specular, transition (0 legacy fade, 1 dissolve)
    float4 viewport;    // width, height (pixels), focal length 1/tan(fovY/2)
    float4 pole;        // radius cap (in λ), pole-fog start λ, pole-fog end λ
    float4 glow;        // rgb, mode (0 none, 1 horizon band, 2 backlight halo)
    float4 glowShape;   // centre x, centre y (uv), width / radius (screen heights)
    float4 rimLight;    // rgb (colour × strength)
    float4 highlight;   // rgb: the theme's "highlight" (dissolve glow), w: EDR highlight gain
    float4 hdr;         // x: highlight ceiling = min(theme peak, display headroom), y: EDR active 0…1
    float4 metal;       // specular exponent, reflection, softbox, diffuse
    float4 metalTint;   // x: how far reflections take the base colour (0 steel, 1 brass)
    float4 glass;       // glass alpha, bubble alpha, seam brightness
};

// EDR gain for highlights; 1 on SDR displays.
static float highlightGain(constant Uniforms& u) { return 1.0 + (u.highlight.w - 1.0) * u.hdr.y; }

// Values above 1 roll off exponentially towards the ceiling (hard clip at 1 on SDR).
static float3 toneCeiling(float3 c, constant Uniforms& u) {
    float k = u.hdr.x - 1.0;
    if (k < 1e-3) return min(c, 1.0);
    return min(c, 1.0) + k * (1.0 - exp(-max(c - 1.0, 0.0) / k));
}

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
    float4 obj;         // unrotated 4D position, so the dissolve pattern stays attached to the polytope
    float coverage;     // < 1 for tubes/spheres thinner than the pixel floor (alpha-to-coverage)
};

// Thin far tubes alias under MSAA. Floor the radius at `minPx` pixels and report the true
// fraction as coverage, which alpha-to-coverage turns into partial sample coverage.
struct Floored { float radius; float coverage; };
static Floored pixelFloor(float3 centre, float r, float minPx, constant Uniforms& u) {
    float w = max((u.viewProj * float4(centre, 1.0)).w, 1e-4);
    float pxPerUnit = 0.5 * u.viewport.y * u.viewport.z / w;
    Floored f;
    f.coverage = saturate(r * pxPerUnit / minPx);
    f.radius = max(r, minPx / pxPerUnit);
    return f;
}

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
    float spec = pow(max(dot(n, H), 0.0), 40.0) * specK * highlightGain(u);
    float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0);
    return base * (0.62 * key + 0.30 * hemi + 0.12) + spec + 0.25 * rim * base + u.rimLight.xyz * rim;
}

// MARK: Dissolve transition

static float hash4(float4 p) {
    p = fract(p * float4(0.1031, 0.1030, 0.0973, 0.1099));
    p += dot(p, p.wzxy + 33.33);
    return fract((p.x + p.y) * (p.z + p.w));
}

// 4D value noise: smooth interpolation of hashed lattice values over the 16 corners of the cell.
static float noise4(float4 p) {
    float4 i = floor(p), f = fract(p);
    float4 w = f * f * (3.0 - 2.0 * f);
    float r = 0.0;
    for (int k = 0; k < 16; k++) {
        float4 o = float4(k & 1, (k >> 1) & 1, (k >> 2) & 1, (k >> 3) & 1);
        float4 s = mix(1.0 - w, w, o);
        r += hash4(i + o) * s.x * s.y * s.z * s.w;
    }
    return r;
}

// Progress is radii.z (1 = fully present). Fragments whose noise exceeds the threshold are gone;
// a thin band just inside it glows. Returns the glow amount.
// `lead` > 0 makes an element leave earlier and return later (faces go first, then the frame).
static float dissolve(float4 obj, float lead, constant Uniforms& u) {
    if (u.style.w < 0.5 || u.radii.z > 0.999) return 0.0;
    float n = 0.65 * noise4(obj * 3.0 + 11.0) + 0.35 * noise4(obj * 7.0 - 5.0);
    n = saturate((n - 0.22) / 0.56);    // value noise clusters around 0.5; spread it over [0, 1]
    const float band = 0.05;
    float progress = saturate((u.radii.z - lead) / (1.0 - lead));
    float k = progress * (1.0 + band);
    if (k <= 0.0 || n > k) discard_fragment();
    return smoothstep(k - band, k, n);
}

// The dissolve front takes the theme's highlight colour (ember for Brass, gold seams for Porcelain…).
static float3 ember(float3 c, float glow, constant Uniforms& u) {
    return mix(c, u.highlight.xyz * highlightGain(u), glow);
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

// Deprecated: plain cross-fade to background, superseded by the dissolve. Used only with transition = fade.
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
    Floored r = pixelFloor(c.p, u.radii.x * min(c.lambda, u.pole.x), 0.7, u);
    float3 world = c.p + n * r.radius;

    VOut o;
    o.coverage = r.coverage;
    o.position = u.viewProj * float4(world, 1.0);
    o.world = world;
    o.normal = n;
    o.color = ringColor(e.info.x, u.style.x, u.edgeColor.xyz, u);
    o.valid = c.valid * c0.valid * c1.valid;
    o.lambda = c.lambda;
    o.obj = mix(e.a, e.b, tv.x);
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
    Floored r = pixelFloor(c.p, u.radii.y * min(c.lambda, u.pole.x), 0.7, u);
    float3 world = c.p + n * r.radius;
    VOut o;
    o.coverage = r.coverage;
    o.position = u.viewProj * float4(world, 1.0);
    o.world = world;
    o.normal = n;
    o.color = ringColor(v.info.x, u.style.x, u.vertexColor.xyz, u);
    o.valid = c.valid;
    o.lambda = c.lambda;
    o.obj = v.a;
    return o;
}

// What the framework reflects: the theme gradient by elevation, an overhead softbox (so dark themes
// still have something to mirror), and the theme's glow (horizon band, or halo behind the object).
static float3 environment(float3 R, constant Uniforms& u) {
    float3 c = mix(u.bgBottom.xyz, u.bgTop.xyz, saturate(0.5 + 0.5 * R.y));
    c += u.metal.z * smoothstep(0.55, 0.85, R.y);
    if (u.glow.w > 1.5) {
        c += u.glow.xyz * pow(saturate(-R.z), 4.0);
    } else if (u.glow.w > 0.5) {
        float dy = (R.y - (u.glowShape.y * 2.0 - 1.0) * 0.5) / (2.0 * u.glowShape.z);
        c += u.glow.xyz * exp(-dy * dy);
    }
    return c;
}

// Edges and joints as one cast-metal piece: environment reflection plus a sharp key highlight,
// tinted by the base colour to the theme's degree, over a weak diffuse term.
static float3 metalShade(float3 base, float3 n, float3 world, constant Uniforms& u) {
    float3 V = normalize(u.cameraPos.xyz - world);
    if (dot(n, V) < 0.0) n = -n;
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + V);
    float3 R = reflect(-V, n);
    float NoV = saturate(dot(n, V));
    float3 tint = mix(float3(1.0), base / max(max(base.r, max(base.g, base.b)), 1e-3), u.metalTint.x);
    float spec = pow(saturate(dot(n, H)), u.metal.x) * u.style.z * highlightGain(u);
    // Schlick reflectance from metal.y head-on, rising at grazing angles but capped at 0.35 so dark
    // metal never grows a bright outline.
    float F = mix(u.metal.y, max(u.metal.y, 0.35), pow(1.0 - NoV, 5.0));
    float3 reflection = tint * (F * environment(R, u) + spec);
    float3 diffuse = base * (0.6 * saturate(dot(n, L)) + 0.3 * (0.5 + 0.5 * n.y) + 0.1) * u.metal.w;
    float rim = pow(1.0 - NoV, 3.0);
    return diffuse + reflection + u.rimLight.xyz * rim;
}

fragment float4 opaque_fs(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    if (in.valid < 0.999 || in.lambda > u.pole.z) discard_fragment();
    float glow = dissolve(in.obj, 0.0, u);
    float3 c = metalShade(in.color, normalize(in.normal), in.world, u);
    return float4(toneCeiling(applyFog(ember(c, glow, u), in.world, in.lambda, u), u), in.coverage);
}

// MARK: Faces (subdivided triangles, curved onto S³ by the blend)

struct FaceOut {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 color;
    float valid;
    float lambda;
    float4 obj;
    float3 border;      // distance to each polygon-border side of the fan triangle, in edge lengths (10: not a border)
};

vertex FaceOut face_vs(uint vid [[vertex_id]], uint iid [[instance_id]],
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
    FaceOut o;
    o.position = u.viewProj * float4(q.p, 1.0);
    o.world = q.p;
    o.normal = normalize(cross(qu.p - q.p, qv.p - q.p));
    o.color = ringColor(f.info.x, u.style.x, u.faceColor.xyz, u);
    o.valid = q.valid;
    o.lambda = q.lambda;
    o.obj = f.a + bc.x * (f.b - f.a) + bc.y * (f.c - f.a);

    // Barycentric weight × height = distance to the opposite side (in the flat 4D triangle).
    float4 ab = f.b - f.a, ac = f.c - f.a;
    float twiceArea = sqrt(max(dot(ab, ab) * dot(ac, ac) - dot(ab, ac) * dot(ab, ac), 1e-12));
    float lbc = length(f.c - f.b), lab = length(ab), lac = length(ac);
    float wa = 1.0 - bc.x - bc.y, wb = bc.x, wc = bc.y;
    int flags = int(f.info.z + 0.5);
    o.border = float3(wa * twiceArea / lbc,
                      (flags & 1) ? wc * twiceArea / lab : 10.0 * lbc,
                      (flags & 2) ? wb * twiceArea / lac : 10.0 * lbc) / lbc;
    return o;
}

struct OITOut {
    float4 accum [[color(1)]];
    float reveal [[color(2)]];
};

// Solid glass (perspective) morphing into soap-film bubbles (stereographic), weighted into the OIT targets.
fragment OITOut face_fs(FaceOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    if (in.valid < 0.999 || in.lambda > u.pole.z) discard_fragment();
    float glow = 0.5 * dissolve(in.obj, 0.35, u);
    float3 n = normalize(in.normal);
    float3 V = normalize(u.cameraPos.xyz - in.world);
    if (dot(n, V) < 0.0) n = -n;
    float facing = saturate(dot(n, V));
    float3 L = normalize(u.lightDir.xyz);
    float3 H = normalize(L + V);
    float3 env = environment(reflect(-V, n), u);
    float schlick = pow(1.0 - facing, 5.0);
    float t = smoothstep(0.0, 1.0, u.proj.y);
    float body = 0.55 * saturate(dot(n, L)) + 0.35 * (0.5 + 0.5 * n.y) + 0.1;

    // Glass: substantial body, Fresnel reflection, sharp highlight, bright seams along the polygon border.
    float d = min(in.border.x, min(in.border.y, in.border.z));
    float seam = 1.0 - smoothstep(0.0, 0.08, d);
    float aGlass = u.glass.x + (1.0 - u.glass.x) * 0.6 * schlick + 0.02 * seam;
    float3 lGlass = (0.04 + 0.96 * schlick) * 0.8 * env
                  + pow(saturate(dot(n, H)), 120.0) * u.style.z * highlightGain(u)
                  + mix(in.color, float3(1.0), 0.5) * seam * u.glass.z;

    // Bubble: nearly clear face-on, the film thickening towards its silhouette; broad soft highlight.
    float aBubble = u.glass.y + 0.55 * pow(1.0 - facing, 2.5);
    float3 lBubble = (0.03 + 0.97 * schlick) * 0.6 * env
                   + pow(saturate(dot(n, H)), 30.0) * 0.5 * u.style.z * highlightGain(u);

    float alpha = saturate(mix(aGlass, aBubble, t));
    float3 c = in.color * body + mix(lGlass, lBubble, t) / max(alpha, 1e-3);
    float dist = length(u.cameraPos.xyz - in.world);
    alpha *= smoothstep(u.fog.y, u.fog.z, dist) * poleVisibility(in.lambda, u);
    c = toneCeiling(applyFog(ember(c, glow, u), in.world, in.lambda, u), u);
    alpha = mix(alpha, 0.5, glow);

    // McGuire & Bavoil's depth weight (their eq. 10), with distances in our scene units.
    float w = alpha * clamp(10.0 / (1e-5 + pow(dist / 5.0, 2.0) + pow(dist / 200.0, 6.0)), 1e-2, 3e3);
    OITOut o;
    o.accum = float4(c * alpha, alpha) * w;
    o.reveal = alpha;
    return o;
}

// Resolve: weighted average colour over the opaque frame, covering 1 − Π(1 − α).
fragment float4 oit_composite_fs(BgOut in [[stage_in]], float4 accum [[color(1)]], float reveal [[color(2)]]) {
    float a = 1.0 - reveal;
    if (a < 1e-4) discard_fragment();
    return float4(accum.rgb / max(accum.a, 1e-5) * a, a);
}
