// bootshards.frag - the boot overlay's black stage, cracking into glass shards and falling away.
// The stage is tessellated by a seeded, jittered Voronoi in log-polar space around the emblem
// (rings x 18 sectors: 18 = 3 x the emblem's six hexagon vertices), so the shards radiate from
// it and grow with distance. Each shard has its own clock (distance from the centre): an accent
// crack lights along its borders, then it lets go - drifts outward, turns, shrinks and fades -
// with a glint on its edge. The shader inverts each candidate shard's motion per pixel, so no
// geometry is needed; the cost is bounded (3x3 candidates x 3x3 cells), skipped before release.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 box;       // item size in px
    vec2 ctr;       // emblem centre in px
    float t;        // ms into the reveal
    float far;      // distance from the centre to the farthest corner
    float r0;       // log-polar core radius in px
    float seed;
    vec4 accent;
    vec4 edgeC;
};

const float N = 18.0;
const float TAU = 6.2831853;
const float LK = N / TAU;   // makes cells roughly square at any radius

float hash(vec2 p) {
    p = fract(p * vec2(443.897, 441.423) + seed);
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}
vec2 cellSeed(vec2 id) {   // jittered seed of cell id (angle index wraps)
    vec2 w = vec2(id.x, mod(id.y, N));
    return id + 0.5 + (vec2(hash(w), hash(w + 7.7)) - 0.5) * 0.9;
}
vec2 toQ(vec2 p) {
    vec2 d = p - ctr;
    return vec2(LK * log(1.0 + length(d) / r0), atan(d.y, d.x) * N / TAU);
}
vec2 toP(vec2 q) {
    float r = r0 * (exp(max(q.x, 0.0) / LK) - 1.0);
    float a = q.y * TAU / N;
    return ctr + r * vec2(cos(a), sin(a));
}

struct Hit { vec2 id; float edge; };   // nearest cell and px distance to its border

Hit voronoi(vec2 p) {
    vec2 q = toQ(p);
    vec2 b = floor(q);
    float d1 = 1e9, d2 = 1e9;
    vec2 s1 = vec2(0.0), s2 = vec2(0.0), i1 = vec2(0.0);
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec2 id = b + vec2(x, y);
        if (id.x < 0.0) continue;
        vec2 s = cellSeed(id);
        float d = dot(q - s, q - s);
        if (d < d1) { d2 = d1; s2 = s1; d1 = d; s1 = s; i1 = id; }
        else if (d < d2) { d2 = d; s2 = s; }
    }
    float r = length(p - ctr);
    float px = 0.5 * ((r0 + r) / LK + max(r, r0 * 0.5) * TAU / N);
    float db = (d2 - d1) / (2.0 * max(length(s2 - s1), 1e-3));
    Hit h; h.id = vec2(i1.x, mod(i1.y, N)); h.edge = db * px;
    return h;
}

float seg(float x, float a, float b) { return clamp((x - a) / (b - a), 0.0, 1.0); }

// shard state: x = release progress 0..1 (gone), plus its seed in px
struct Shard { float k; float h; float h2; vec2 s; };
Shard shardOf(vec2 id) {
    vec2 w = vec2(id.x, mod(id.y, N));
    Shard sh;
    sh.s = toP(cellSeed(id));
    sh.h = hash(w + 3.1);
    sh.h2 = hash(w + 9.3);
    float d = clamp(length(sh.s - ctr) / far, 0.0, 1.0);
    float rel = 380.0 + d * 480.0 + sh.h * 50.0;
    sh.k = seg(t, rel, rel + 480.0);
    return sh;
}

// colour (premultiplied) for pixel p0 of an intact-frame shard, k = its progress
vec4 shade(vec2 p0, Hit h, Shard sh) {
    float rr = length(p0 - ctr) / far;
    float lit = seg(t, 60.0 + rr * 440.0, 60.0 + rr * 440.0 + 140.0);
    float k = sh.k;
    float al = 1.0 - seg(k, 0.32, 1.0);
    vec3 col = vec3(0.0);
    // faint facet tint once cracked, brighter across the face as it turns away
    float facet = (sh.h - 0.5) * 0.04 + 0.03 * sin(dot(p0 - sh.s, vec2(0.6, 0.8)) * 0.02 + sh.h * 6.0) * seg(k, 0.0, 0.5);
    col += accent.rgb * 0.05 * lit * (0.5 + sh.h) + vec3(max(facet, 0.0)) * lit;
    // crack: crisp core + soft accent bloom, on the border
    float core = clamp(1.2 - (h.edge - 0.3), 0.0, 1.0);
    float glow = exp(-h.edge * 0.55);
    float crack = lit * (1.0 - 0.45 * seg(k, 0.0, 0.3));
    col = mix(col, accent.rgb, clamp(core * crack, 0.0, 1.0) * 0.9);
    col += accent.rgb * glow * 0.28 * crack;
    // glint as the shard lets go: edge colour, strongest just after release
    float gl = sin(3.14159 * seg(k, 0.02, 0.75));
    col = mix(col, edgeC.rgb, clamp(core * gl, 0.0, 1.0) * 0.85);
    col += edgeC.rgb * exp(-h.edge * 0.4) * gl * 0.12;
    return vec4(col * al, al);
}

void main() {
    vec2 p = qt_TexCoord0 * box;
    if (t < 0.0) { fragColor = vec4(0.0, 0.0, 0.0, 1.0) * qt_Opacity; return; }
    vec4 out_ = vec4(0.0);
    float best = 2.0;
    if (t < 380.0) {   // nothing has moved yet: the plain tessellation
        Hit h = voronoi(p);
        out_ = shade(p, h, shardOf(h.id));
        fragColor = out_ * qt_Opacity;
        return;
    }
    vec2 qb = floor(toQ(p));
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        vec2 id = qb + vec2(x, y);
        if (id.x < 0.0) continue;
        Shard sh = shardOf(id);
        if (sh.k >= 1.0 || sh.k > best) continue;
        // invert this shard's motion: outward drift, turn, shrink
        float f = sh.k * sh.k * (3.0 - 2.0 * sh.k);
        f = f * f * 0.5 + f * 0.5;
        vec2 dir = normalize(sh.s - ctr + 1e-3);
        vec2 off = dir * f * (40.0 + 110.0 * sh.h) + vec2(0.0, f * 30.0);
        float ang = f * (sh.h2 - 0.5) * 1.1;
        float sc = 1.0 - f * 0.55 + 0.02 * sin(3.14159 * seg(sh.k, 0.0, 0.25));
        vec2 d = p - sh.s - off;
        float c = cos(ang), s = sin(ang);
        vec2 p0 = sh.s + vec2(c * d.x + s * d.y, -s * d.x + c * d.y) / sc;
        Hit h = voronoi(p0);
        if (h.id != vec2(id.x, mod(id.y, N))) continue;
        best = sh.k;
        out_ = shade(p0, h, sh);
        out_.rgb *= 1.0; 
    }
    fragColor = out_ * qt_Opacity;
}
