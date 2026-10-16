// shard.frag - one crystal-wing shard of WallpaperArt, drawn on the GPU.
// The item is the shard's bounding box in its own frame: x runs along the shard from the pivot,
// y is across it, centred at y = tw + 2 (2 px of padding for antialiasing). The item's
// Rotation turns it into place, so this shader never sees the angle.
//
// Reproduces the canvas version's three passes in one output: the gradient body ("lighter",
// i.e. additive, on dark skins; source-over on light ones), the shade triangle A-C-D, then the
// edge stroke A-B-C. Qt Quick blends premultiplied (src + dst * (1 - src.a)), so an additive
// contribution is colour with zero alpha.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 box;          // item size in px
    float r0;          // start of the shard along x
    float len;         // shard length
    float tw;          // half width
    float al;          // per-shard alpha
    float boost;       // sweep highlight, 0..0.4
    float lightSkin;   // 1 on light skins
    vec4 shardC;
    vec4 edgeC;
    vec4 shadeC;
};

// Signed distance from p to the line a->b (sign depends on winding; callers normalise it).
float side(vec2 p, vec2 a, vec2 b) {
    vec2 d = b - a;
    return (d.x * (p.y - a.y) - d.y * (p.x - a.x)) / max(length(d), 1e-4);
}

float segDist(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h);
}

void main() {
    vec2 p = vec2(qt_TexCoord0.x * box.x, qt_TexCoord0.y * box.y - (tw + 2.0));
    vec2 A = vec2(r0, -tw);
    vec2 B = vec2(r0 + len * 0.92, -tw * 0.25);
    vec2 C = vec2(r0 + len, 0.0);
    vec2 D = vec2(r0 + len * 0.3, tw);

    // body: convex quad A-B-C-D, 1 px antialiased edges
    float o = sign(side((A + B + C + D) * 0.25, A, B));
    o = o == 0.0 ? 1.0 : o;
    float dq = min(min(o * side(p, A, B), o * side(p, B, C)), min(o * side(p, C, D), o * side(p, D, A)));
    float covQ = clamp(dq + 0.5, 0.0, 1.0);

    // shade: triangle A-C-D
    float ot = sign(side((A + C + D) / 3.0, A, C));
    ot = ot == 0.0 ? 1.0 : ot;
    float dt = min(ot * side(p, A, C), min(ot * side(p, C, D), ot * side(p, D, A)));
    float covT = clamp(dt + 0.5, 0.0, 1.0);

    // edge: 0.8 px polyline A-B-C
    float dl = min(segDist(p, A, B), segDist(p, B, C));
    float covL = min(clamp(0.9 - dl, 0.0, 1.0), 0.8);

    // gradient along the shard: 0 at r0, a1 at 55 %, a2 at the tip
    float light = step(0.5, lightSkin);
    float a1 = clamp((0.55 * al + boost) * mix(0.8, 1.0, light), 0.0, 1.0);
    float a2 = clamp(0.9 * al + boost, 0.0, 1.0);
    float s = clamp((p.x - r0) / max(len, 1e-4), 0.0, 1.0);
    float ag = s < 0.55 ? mix(0.0, a1, s / 0.55) : mix(a1, a2, (s - 0.55) / 0.45);
    ag *= covQ;

    vec3 rgb = shardC.rgb * ag;      // premultiplied
    float a = ag * light;            // dark skins: additive (alpha 0)

    float as_ = mix(0.22, 0.12, light) * covT;
    rgb = shadeC.rgb * as_ + rgb * (1.0 - as_);
    a = as_ + a * (1.0 - as_);

    float ae = mix(0.35 * al, 0.45, light) * covL;
    rgb = edgeC.rgb * ae + rgb * (1.0 - ae);
    a = ae + a * (1.0 - ae);

    fragColor = vec4(rgb, a) * qt_Opacity;
}
