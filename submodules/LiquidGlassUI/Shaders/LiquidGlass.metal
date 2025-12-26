#include <metal_stdlib>
using namespace metal;

constant float PI = 3.14159265359;
constant float N_R = 1.0 - 0.02;
constant float N_G = 1.0;
constant float N_B = 1.0 + 0.02;
constant int MAX_BLUR_RADIUS = 200;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct BGUniforms {
    float2 resolution;
    float dpr;
    float2 mouseSpring;
    float mergeRate;
    float shapeWidth;
    float shapeHeight;
    float cornerRadius;
    float shapeRoundness;
    float motionStretch;
    float motionSquash;
    float motionBias;
};

struct BlurUniforms {
    float2 resolution;
    uint blurRadius;
};

struct MainUniforms {
    float2 resolution;
    float dpr;
    float2 mouseSpring;
    float mergeRate;
    float shapeWidth;
    float shapeHeight;
    float cornerRadius;
    float shapeRoundness;
    float motionStretch;
    float motionSquash;
    float motionBias;
    float shadowExpand;
    float shadowFactor;
    float2 shadowPosition;
    float4 tint;
    float4 glareTint;
    float4 glareOppositeTint;
    float refThickness;
    float refFactor;
    float refDispersion;
    float zoomOutFactor;
    float refFresnelRange;
    float refFresnelFactor;
    float refFresnelHardness;
    float glareRange;
    float glareConvergence;
    float glareOppositeFactor;
    float glareFactor;
    float glareHardness;
    float glareAngle;
    uint blurEdge;
    int step;
};

vertex VertexOut liquidGlassVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 positions[4] = {
        float2(-1.0, -1.0),
        float2(1.0, -1.0),
        float2(-1.0, 1.0),
        float2(1.0, 1.0)
    };
    constexpr float2 uvs[4] = {
        float2(0.0, 0.0),
        float2(1.0, 0.0),
        float2(0.0, 1.0),
        float2(1.0, 1.0)
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv = uvs[vertexID];
    return out;
}

fragment float4 liquidGlassOverlayFragment(VertexOut in [[stage_in]],
                                          texture2d<float> overlayTexture [[texture(0)]],
                                          sampler overlaySampler [[sampler(0)]]) {
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    return overlayTexture.sample(overlaySampler, uv);
}

fragment float4 liquidGlassCopyFlipYFragment(VertexOut in [[stage_in]],
                                            texture2d<float> inputTexture [[texture(0)]],
                                            sampler inputSampler [[sampler(0)]]) {
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    return inputTexture.sample(inputSampler, uv);
}

inline float saturate1(float v) {
    return clamp(v, 0.0, 1.0);
}

float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float superellipseCornerSDF(float2 p, float r, float n) {
    p = abs(p);
    float v = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
    return v - r;
}

float roundedRectSDF(float2 p, float2 center, float width, float height, float cornerRadius, float n, float dpr) {
    p -= center;
    float cr = cornerRadius * dpr;
    float2 halfSize = float2(width * dpr, height * dpr) * 0.5;
    float2 inner = max(float2(0.0), halfSize - float2(cr));

    // Branchless rounded-rect SDF (round box), with a superellipse corner metric.
    // This avoids the "sign(0) == 0" quadrant selection seam that can manifest as
    // tiny pointed side protrusions ("ears") when the pill is stretched.
    float2 q = abs(p) - inner;
    float2 outer = max(q, float2(0.0));
    float cornerDist = superellipseCornerSDF(outer, cr, n);
    float innerDist = min(max(q.x, q.y), 0.0);
    return cornerDist + innerDist;
}

float mainSDF(float2 p2, float2 p, float2 resolution, float dpr, float mergeRate, float shapeWidth, float shapeHeight, float cornerRadius, float shapeRoundness, float motionStretch, float motionSquash, float motionBias) {
    float2 p2n = p2 + p / resolution.y;
    float stretchScale = max(0.0001, 1.0 + motionStretch);
    float squashScale = max(0.0001, 1.0 + motionSquash);
    // Directional "pull" anchoring: if motionBias is set, shift the SDF center so the
    // stretched blob extends primarily toward the bias sign (keeps the opposite side anchored).
    if (fabs(motionBias) > 0.0001) {
        float signBias = motionBias >= 0.0 ? 1.0 : -1.0;
        float baseWidth = shapeWidth / squashScale;
        float stretchedWidth = baseWidth * stretchScale;
        float shiftPoints = (stretchedWidth - baseWidth) * 0.5 * signBias;
        p2n.x -= (shiftPoints * dpr) / resolution.y;
    }
    // Keep the blob visually cohesive by preserving its projected "volume" (area) during stretch/squash.
    // Exponent < 1.0 allows a tiny, controlled area increase during fast motion.
    float heightCompression = pow(1.0 / stretchScale, 0.9);
    float width = shapeWidth * stretchScale / squashScale;
    float height = shapeHeight * heightCompression * squashScale;
    float radius = cornerRadius * heightCompression * squashScale;
    radius = min(radius, min(width, height) * 0.5);
    // Motion asymmetry previously used a y-dependent x-warp driven by velocity sign.
    // That warp can create small pointed side protrusions ("ears") when the capsule stretches.
    // For UI knobs we prioritize a clean silhouette; asymmetry is handled by timing/overshoot
    // and stretch/squash only.
    float d2 = roundedRectSDF(
        p2n,
        float2(0.0),
        width / resolution.y,
        height / resolution.y,
        radius / resolution.y,
        shapeRoundness,
        dpr
    );
    return smin(1.0, d2, mergeRate);
}

float2 getNormal(float2 p2, float2 p, float2 resolution, float dpr, float mergeRate, float shapeWidth, float shapeHeight, float cornerRadius, float shapeRoundness, float motionStretch, float motionSquash, float motionBias) {
    float hx = max(fabs(dfdx(p.x)), 0.0001);
    float hy = max(fabs(dfdy(p.y)), 0.0001);

    float2 grad = float2(
        mainSDF(p2, p + float2(hx, 0.0), resolution, dpr, mergeRate, shapeWidth, shapeHeight, cornerRadius, shapeRoundness, motionStretch, motionSquash, motionBias) -
        mainSDF(p2, p - float2(hx, 0.0), resolution, dpr, mergeRate, shapeWidth, shapeHeight, cornerRadius, shapeRoundness, motionStretch, motionSquash, motionBias),
        mainSDF(p2, p + float2(0.0, hy), resolution, dpr, mergeRate, shapeWidth, shapeHeight, cornerRadius, shapeRoundness, motionStretch, motionSquash, motionBias) -
        mainSDF(p2, p - float2(0.0, hy), resolution, dpr, mergeRate, shapeWidth, shapeHeight, cornerRadius, shapeRoundness, motionStretch, motionSquash, motionBias)
    ) / (float2(hx, hy) * 2.0);

    return grad * 1.414213562f * 1000.0f;
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// from https://github.com/Rachmanin0xFF/GLSL-Color-Functions/blob/main/color-functions.glsl
constant float3 D65_WHITE = float3(0.95045592705, 1.0, 1.08905775076);
constant float3 WHITE = D65_WHITE;
constant float3x3 RGB_TO_XYZ_M = float3x3(
    float3(0.4124, 0.3576, 0.1805),
    float3(0.2126, 0.7152, 0.0722),
    float3(0.0193, 0.1192, 0.9505)
);
constant float3x3 XYZ_TO_XYZ50_M = float3x3(
    float3(1.0479298208405488, 0.022946793341019088, -0.05019222954313557),
    float3(0.029627815688159344, 0.990434484573249, -0.01707382502938514),
    float3(-0.009243058152591178, 0.015055144896577895, 0.7518742899580008)
);
constant float3x3 XYZ_TO_RGB_M = float3x3(
    float3(3.2406255, -1.537208, -0.4986286),
    float3(-0.9689307, 1.8757561, 0.0415175),
    float3(0.0557101, -0.2040211, 1.0569959)
);
constant float3x3 XYZ50_TO_XYZ_M = float3x3(
    float3(0.9554734527042182, -0.023098536874261423, 0.0632593086610217),
    float3(-0.028369706963208136, 1.0099954580058226, 0.021041398966943008),
    float3(0.012314001688319899, -0.020507696433477912, 1.3303659366080753)
);

float UNCOMPAND_SRGB(float a) {
    return a > 0.04045 ? pow((a + 0.055) / 1.055, 2.4) : a / 12.92;
}

float COMPAND_RGB(float a) {
    return a <= 0.0031308 ? 12.92 * a : 1.055 * pow(a, 0.41666666666) - 0.055;
}

float3 rowMul(float3 v, float3x3 m) {
    return float3(dot(v, m[0]), dot(v, m[1]), dot(v, m[2]));
}

float3 RGB_TO_XYZ(float3 rgb) {
    bool useD65 = all(WHITE == D65_WHITE);
    float3 xyz = rowMul(rgb, RGB_TO_XYZ_M);
    return useD65 ? xyz : rowMul(xyz, XYZ_TO_XYZ50_M);
}

float3 SRGB_TO_RGB(float3 srgb) {
    return float3(UNCOMPAND_SRGB(srgb.x), UNCOMPAND_SRGB(srgb.y), UNCOMPAND_SRGB(srgb.z));
}

float3 RGB_TO_SRGB(float3 rgb) {
    return float3(COMPAND_RGB(rgb.x), COMPAND_RGB(rgb.y), COMPAND_RGB(rgb.z));
}

float3 SRGB_TO_XYZ(float3 srgb) {
    return RGB_TO_XYZ(SRGB_TO_RGB(srgb));
}

float XYZ_TO_LAB_F(float x) {
    return x > 0.00885645167 ? pow(x, 0.333333333) : 7.78703703704 * x + 0.13793103448;
}

float3 XYZ_TO_LAB(float3 xyz) {
    float3 xyz_scaled = xyz / WHITE;
    xyz_scaled = float3(
        XYZ_TO_LAB_F(xyz_scaled.x),
        XYZ_TO_LAB_F(xyz_scaled.y),
        XYZ_TO_LAB_F(xyz_scaled.z)
    );
    return float3(
        116.0 * xyz_scaled.y - 16.0,
        500.0 * (xyz_scaled.x - xyz_scaled.y),
        200.0 * (xyz_scaled.y - xyz_scaled.z)
    );
}

float3 SRGB_TO_LAB(float3 srgb) {
    return XYZ_TO_LAB(SRGB_TO_XYZ(srgb));
}

float3 LAB_TO_LCH(float3 Lab) {
    return float3(Lab.x, sqrt(dot(Lab.yz, Lab.yz)), atan2(Lab.z, Lab.y) * 57.2957795131);
}

float3 SRGB_TO_LCH(float3 srgb) {
    return LAB_TO_LCH(SRGB_TO_LAB(srgb));
}

float3 XYZ_TO_RGB(float3 xyz) {
    bool useD65 = all(WHITE == D65_WHITE);
    float3 toD65 = useD65 ? xyz : rowMul(xyz, XYZ50_TO_XYZ_M);
    return rowMul(toD65, XYZ_TO_RGB_M);
}

float3 XYZ_TO_SRGB(float3 xyz) {
    return RGB_TO_SRGB(XYZ_TO_RGB(xyz));
}

float LAB_TO_XYZ_F(float x) {
    return x > 0.206897 ? x * x * x : 0.12841854934 * (x - 0.137931034);
}

float3 LAB_TO_XYZ(float3 Lab) {
    float w = (Lab.x + 16.0) / 116.0;
    return WHITE * float3(LAB_TO_XYZ_F(w + Lab.y / 500.0), LAB_TO_XYZ_F(w), LAB_TO_XYZ_F(w - Lab.z / 200.0));
}

float3 LAB_TO_SRGB(float3 lab) {
    return XYZ_TO_SRGB(LAB_TO_XYZ(lab));
}

float3 LCH_TO_LAB(float3 LCh) {
    return float3(LCh.x, LCh.y * cos(LCh.z * 0.01745329251), LCh.y * sin(LCh.z * 0.01745329251));
}

float3 LCH_TO_SRGB(float3 lch) {
    return LAB_TO_SRGB(LCH_TO_LAB(lch));
}

float vec2ToAngle(float2 v) {
    float angle = atan2(v.y, v.x);
    if (angle < 0.0) angle += 2.0 * PI;
    return angle;
}

float3 vec2ToRgb(float2 v) {
    float angle = atan2(v.y, v.x);
    if (angle < 0.0) angle += 2.0 * PI;
    float hue = angle / (2.0 * PI);
    float3 hsv = float3(hue, 1.0, 1.0);
    return hsv2rgb(hsv);
}

float4 getTextureDispersion(
    texture2d<float> tex1,
    texture2d<float> tex2,
    sampler samp,
    float2 uv,
    float mixRate,
    float2 offset,
    float factor
) {
    float4 pixel = float4(1.0);

    float bgR = tex1.sample(samp, uv + offset * (1.0 - (N_R - 1.0) * factor)).r;
    float bgG = tex1.sample(samp, uv + offset * (1.0 - (N_G - 1.0) * factor)).g;
    float bgB = tex1.sample(samp, uv + offset * (1.0 - (N_B - 1.0) * factor)).b;

    float blurR = tex2.sample(samp, uv + offset * (1.0 - (N_R - 1.0) * factor)).r;
    float blurG = tex2.sample(samp, uv + offset * (1.0 - (N_G - 1.0) * factor)).g;
    float blurB = tex2.sample(samp, uv + offset * (1.0 - (N_B - 1.0) * factor)).b;

    pixel.r = mix(bgR, blurR, mixRate);
    pixel.g = mix(bgG, blurG, mixRate);
    pixel.b = mix(bgB, blurB, mixRate);

    return pixel;
}

fragment float4 liquidGlassBgFragment(
    VertexOut in [[stage_in]],
    constant BGUniforms &u [[buffer(1)]],
    texture2d<float> bgTexture [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    float3 bgColor = bgTexture.sample(samp, in.uv).rgb;
    return float4(bgColor, 1.0);
}

fragment float4 liquidGlassVBlurFragment(
    VertexOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(1)]],
    constant float *weights [[buffer(2)]],
    texture2d<float> prevPassTexture [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    float2 texelSize = 1.0 / u.resolution;
    uint radius = min(u.blurRadius, (uint)MAX_BLUR_RADIUS);
    float4 color = prevPassTexture.sample(samp, in.uv) * weights[0];
    for (uint i = 1; i <= radius; ++i) {
        float w = weights[i];
        float2 offset = float2(float(i)) * texelSize;
        color += prevPassTexture.sample(samp, in.uv + float2(offset.x, 0.0)) * w;
        color += prevPassTexture.sample(samp, in.uv - float2(offset.x, 0.0)) * w;
    }
    return color;
}

fragment float4 liquidGlassHBlurFragment(
    VertexOut in [[stage_in]],
    constant BlurUniforms &u [[buffer(1)]],
    constant float *weights [[buffer(2)]],
    texture2d<float> prevPassTexture [[texture(0)]],
    sampler samp [[sampler(0)]]
) {
    float2 texelSize = 1.0 / u.resolution;
    uint radius = min(u.blurRadius, (uint)MAX_BLUR_RADIUS);
    float4 color = prevPassTexture.sample(samp, in.uv) * weights[0];
    for (uint i = 1; i <= radius; ++i) {
        float w = weights[i];
        float2 offset = float2(float(i)) * texelSize;
        color += prevPassTexture.sample(samp, in.uv + float2(0.0, offset.y)) * w;
        color += prevPassTexture.sample(samp, in.uv - float2(0.0, offset.y)) * w;
    }
    return color;
}

fragment float4 liquidGlassMainFragment(
    VertexOut in [[stage_in]],
    constant MainUniforms &u [[buffer(1)]],
    texture2d<float> blurredBg [[texture(0)]],
    texture2d<float> bg [[texture(1)]],
    sampler samp [[sampler(0)]]
) {
    float2 fragCoord = float2(in.uv.x * u.resolution.x, in.uv.y * u.resolution.y);
    float2 resolution1x = u.resolution / u.dpr;
    float2 p2 = (float2(0.0) - u.mouseSpring) / u.resolution.y;
    float merged = mainSDF(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);

    float4 outColor;
    if (u.step <= 0) {
        float px = 2.0 / u.resolution.y;
        float3 col = merged > 0.0 ? float3(1.0, 1.0, 1.0) * merged : float3(1.0, 1.0, 1.0) * -merged * 2.0;
        col *= 3.0;
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(0.5 / resolution1x.y - px, 0.5 / resolution1x.y + px, fabs(merged))
        );
        outColor = float4(col, 1.0);
    } else if (u.step <= 1) {
        float px = 2.0 / u.resolution.y;
        float3 col = merged > 0.0 ? float3(0.9, 0.6, 0.3) : float3(0.65, 0.85, 1.0);
        col *= 1.0 - exp(-0.03 * fabs(merged) * resolution1x.y);
        col *= 0.6 + 0.4 * smoothstep(-0.5, 0.5, cos(0.25 * fabs(merged) * resolution1x.y * 2.0));
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(1.5 / resolution1x.y - px, 1.5 / resolution1x.y + px, fabs(merged))
        );
        outColor = float4(col, 1.0);
    } else if (u.step <= 2) {
        if (merged < 0.0) {
            float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);
            float3 normalColor = vec2ToRgb(normal);
            float l = length(normal);
            outColor = float4(normalColor, l);
        } else {
            outColor = float4(float3(0.8), 0.0);
        }
    } else if (u.step <= 3) {
        if (merged < 0.0) {
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / u.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            if (nmerged < u.refThickness) {
                outColor = float4(float3(edgeFactor), 1.0);
            } else {
                outColor = float4(float3(0.0), 1.0);
            }
        } else {
            outColor = float4(0.0);
        }
    } else if (u.step <= 4) {
        if (merged < 0.0) {
            float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);
            float3 normalColor = vec2ToRgb(normal);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float x_R_ratio = 1.0 - nmerged / u.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            outColor = float4(normalColor * edgeFactor * u.dpr * length(normal), 1.0);
        } else {
            outColor = float4(0.0);
        }
    } else if (u.step <= 5) {
        if (merged < 0.0) {
            outColor = blurredBg.sample(samp, in.uv);
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 6) {
        if (merged < 0.0) {
            float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = u.mouseSpring / u.resolution;
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset);
                outColor = blurredPixel;
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 7) {
        if (merged < 0.0) {
            float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = u.mouseSpring / u.resolution;
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                        u.refFresnelHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset, bias(u.refDispersion));
                outColor = mix(blurredPixel, float4(1.0), fresnelFactor * u.refFresnelFactor * 0.7);
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 8) {
        if (merged < 0.0) {
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = u.mouseSpring / u.resolution;
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                        u.refFresnelHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            float glareGeoFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.glareRange, 2.0) +
                        u.glareHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);

                float glareAngle = (vec2ToAngle(normalize(normal)) - PI / 4.0 + u.glareAngle) * 2.0;
                int glareFarside = 0;
                if ((glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5)) ||
                    glareAngle < PI * (0.0 - 0.5)) {
                    glareFarside = 1;
                }

                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) *
                    (glareFarside == 1 ? 1.2 * u.glareOppositeFactor : 1.2) *
                    u.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.3 + u.glareConvergence * 1.5), 0.0, 1.0);

                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset, bias(u.refDispersion));
                outColor = blurredPixel;

                float3 tintLCH = SRGB_TO_LCH(
                    mix(float3(1.0), float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                tintLCH.x += 20.0 * fresnelFactor * u.refFresnelFactor;
                tintLCH.x = clamp(tintLCH.x, 0.0, 100.0);

                outColor = mix(
                    outColor,
                    float4(1.0),
                    fresnelFactor * u.refFresnelFactor * 0.7
                );

                float4 glareSideTint = glareFarside == 1 ? u.glareOppositeTint : u.glareTint;
                float3 glareColor = mix(float3(1.0), glareSideTint.rgb, glareSideTint.a);

                outColor = mix(
                    outColor,
                    float4(glareColor, 1.0),
                    glareAngleFactor * glareGeoFactor
                );
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else {
        if (merged < 0.005) {
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = u.mouseSpring / u.resolution;
            float depthPx = max(0.0, nmerged);
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-depthPx / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - depthPx / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (depthPx <= 0.0001 || depthPx >= safeThickness) {
                edgeFactor = 0.0;
            }

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
                outColor = mix(outColor, float4(u.tint.r, u.tint.g, u.tint.b, 1.0), u.tint.a * 0.8);
            } else {
                float edgeH = clamp(depthPx / safeThickness, 0.0, 1.0);
                float2 normal = getNormal(p2, fragCoord, u.resolution, u.dpr, u.mergeRate, u.shapeWidth, u.shapeHeight, u.cornerRadius, u.shapeRoundness, u.motionStretch, u.motionSquash, u.motionBias);
                float2 dispOffset =
                    -normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / (resolution1x.x * u.dpr),
                        1.0
                    );
                float4 blurredPixel = getTextureDispersion(
                    bg,
                    blurredBg,
                    samp,
                    zoomedUV,
                    u.blurEdge > 0 ? 1.0 : edgeH,
                    dispOffset,
                    u.refDispersion
                );

                outColor = mix(blurredPixel, float4(u.tint.r, u.tint.g, u.tint.b, 1.0), u.tint.a * 0.8);

                float fresnelFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                            u.refFresnelHardness,
                        5.0
                    ),
                    0.0,
                    1.0
                );

                float3 fresnelTintLCH = SRGB_TO_LCH(
                    mix(float3(1.0), float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                fresnelTintLCH.x += 20.0 * fresnelFactor * u.refFresnelFactor;
                fresnelTintLCH.x = clamp(fresnelTintLCH.x, 0.0, 100.0);

                outColor = mix(
                    outColor,
                    float4(LCH_TO_SRGB(fresnelTintLCH), 1.0),
                    fresnelFactor * u.refFresnelFactor * 0.7 * length(normal)
                );

                float glareGeoFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / 1500.0 * pow(500.0 / u.glareRange, 2.0) +
                            u.glareHardness,
                        5.0
                    ),
                    0.0,
                    1.0
                );

                float glareAngle = (vec2ToAngle(normalize(normal)) - PI / 4.0 + u.glareAngle) * 2.0;
                int glareFarside = 0;
                if ((glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5)) ||
                    glareAngle < PI * (0.0 - 0.5)) {
                    glareFarside = 1;
                }
                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) *
                    (glareFarside == 1
                        ? 1.2 * u.glareOppositeFactor
                        : 1.2) *
                    u.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.1 + u.glareConvergence * 2.0), 0.0, 1.0);

                float3 glareTintLCH = SRGB_TO_LCH(
                    mix(blurredPixel.rgb, float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                glareTintLCH.x += 150.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.y += 30.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.x = clamp(glareTintLCH.x, 0.0, 120.0);

                float4 glareSideTint = glareFarside == 1 ? u.glareOppositeTint : u.glareTint;
                float3 glareRgb = LCH_TO_SRGB(glareTintLCH) * mix(float3(1.0), glareSideTint.rgb, glareSideTint.a);

                outColor = mix(
                    outColor,
                    float4(glareRgb, 1.0),
                    glareAngleFactor * glareGeoFactor * length(normal)
                );
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }

    }

    // Analytic AA for the SDF edge (keeps the silhouette stable during motion).
    float edgeSoftness = max(0.0015, fwidth(merged));
    float bubbleMask = 1.0 - smoothstep(-edgeSoftness, edgeSoftness, merged);
    // Slightly wider mask for shadow blending (reduces the "outline/border" feel).
    float bubbleMaskShadow = 1.0 - smoothstep(-edgeSoftness * 2.8, edgeSoftness * 2.8, merged);

    // The knob view renders on a transparent surface; we want:
    // - glass only inside the blob
    // - a soft drop shadow outside the blob
    // - shadow shading visible through the glass (the knob is transparent)
    // So we apply bubbleMask to the glass, composite a black alpha shadow outside,
    // and darken the glass slightly where the shadow overlaps it.
    float4 glass = outColor * bubbleMask;

    float shadowAlphaOutside = 0.0;
    float shadowAlphaInside = 0.0;
    if (u.shadowFactor > 0.0001 && u.shadowExpand > 0.0001) {
        float2 shadowOffset = float2(u.shadowPosition.x * u.dpr, -u.shadowPosition.y * u.dpr);
        float2 p2s = (float2(0.0) - u.mouseSpring + shadowOffset) / u.resolution.y;
        float mergedShadow = mainSDF(
            p2s,
            fragCoord,
            u.resolution,
            u.dpr,
            u.mergeRate,
            u.shapeWidth,
            u.shapeHeight,
            u.cornerRadius,
            u.shapeRoundness,
            u.motionStretch,
            u.motionSquash,
            u.motionBias
        );

        float shadowSoftnessPx = max(0.001, u.shadowExpand * 2.6);

        // Outside drop shadow (black alpha): use both a directional (offset) component and
        // a subtle ambient one so we don't get a hard "shadow end" seam on the opposite side.
        float pxDistOutsideOffset = max(0.0, mergedShadow) * resolution1x.y;
        float pxDistOutsideAmbient = max(0.0, merged) * resolution1x.y;

        float shadowDirectional = exp(-pxDistOutsideOffset / shadowSoftnessPx) * (0.55 * u.shadowFactor);
        float shadowAmbient = exp(-pxDistOutsideAmbient / max(0.001, shadowSoftnessPx * 1.15)) * (0.18 * u.shadowFactor);
        float shadowOutside = saturate1(shadowDirectional + shadowAmbient);
        shadowAlphaOutside = shadowOutside * (1.0 - bubbleMaskShadow);

        // Inside: fade inward from the (offset) shadow edge, so it reads like a soft inset shadow
        // instead of a hard outline.
        float pxDistInsideOffset = max(0.0, -mergedShadow) * resolution1x.y;
        float shadowInset = exp(-pxDistInsideOffset / max(0.001, shadowSoftnessPx * 0.85)) * (0.35 * u.shadowFactor);
        shadowAlphaInside = saturate1(shadowInset) * bubbleMaskShadow;
    }

    glass.rgb = mix(glass.rgb, float3(0.0), shadowAlphaInside);
    float outAlpha = glass.a + shadowAlphaOutside * (1.0 - glass.a);
    return float4(glass.rgb, outAlpha);
}

// MARK: - LiquidChat (multi-shape) glass (shares the same shading logic as liquidGlassMainFragment)

struct LiquidChatMainUniforms {
    float2 resolution;
    float dpr;
    float mergeRate;
    float shapeRoundness;
    float padding0;

    float2 shape0Center;
    float2 shape0Size;
    float shape0CornerRadius;
    uint shape0Enabled;

    float2 shape1Center;
    float2 shape1Size;
    float shape1CornerRadius;
    uint shape1Enabled;

    float2 shape2Center;
    float2 shape2Size;
    float shape2CornerRadius;
    uint shape2Enabled;

    float2 shape0Direction;
    float2 shape1Direction;
    float2 shape2Direction;

    float shadowExpand;
    float shadowFactor;
    float2 shadowPosition;
    float4 tint;

    float4 glareTint;
    float4 glareOppositeTint;

    float refThickness;
    float refFactor;
    float refDispersion;
    float zoomOutFactor;
    float refFresnelRange;
    float refFresnelFactor;
    float refFresnelHardness;
    float glareRange;
    float glareConvergence;
    float glareOppositeFactor;
    float glareFactor;
    float glareHardness;
    float glareAngle;
    uint blurEdge;
    int step;
    uint padding1;
};

static inline float liquidChatShapeSDF(
    float2 centerPixels,
    float2 sizePoints,
    float cornerRadiusPoints,
    uint enabled,
    float2 direction,
    float2 fragCoordPixels,
    float2 resolution,
    float dpr,
    float shapeRoundness
) {
    if (enabled == 0) {
        return 1e20;
    }

    float2 pBase = (float2(0.0) - centerPixels) / resolution.y;
    float2 pn = pBase + fragCoordPixels / resolution.y;

    float2 dir = direction;
    float dirLen = length(dir);
    if (dirLen < 0.0001) {
        dir = float2(1.0, 0.0);
    } else {
        dir /= dirLen;
    }

    float2 axisX = dir;
    float2 axisY = float2(-dir.y, dir.x);
    float2 pr = float2(dot(pn, axisX), dot(pn, axisY));

    return roundedRectSDF(
        pr,
        float2(0.0),
        sizePoints.x / resolution.y,
        sizePoints.y / resolution.y,
        cornerRadiusPoints / resolution.y,
        shapeRoundness,
        dpr
    );
}

static inline float liquidChatMainSDF(
    constant LiquidChatMainUniforms &u,
    float2 fragCoordPixels,
    float2 centerOffsetPixels
) {
    float d0 = liquidChatShapeSDF(
        u.shape0Center + centerOffsetPixels,
        u.shape0Size,
        u.shape0CornerRadius,
        u.shape0Enabled,
        u.shape0Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );
    float d1 = liquidChatShapeSDF(
        u.shape1Center + centerOffsetPixels,
        u.shape1Size,
        u.shape1CornerRadius,
        u.shape1Enabled,
        u.shape1Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );
    float d2 = liquidChatShapeSDF(
        u.shape2Center + centerOffsetPixels,
        u.shape2Size,
        u.shape2CornerRadius,
        u.shape2Enabled,
        u.shape2Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );

    float d = d0;
    if (u.shape1Enabled == 1) {
        d = smin(d, d1, u.mergeRate);
    }
    if (u.shape2Enabled == 1) {
        d = smin(d, d2, u.mergeRate);
    }
    return d;
}

static inline float2 liquidChatActiveCenterPixels(constant LiquidChatMainUniforms &u, float2 fragCoordPixels) {
    float d0 = liquidChatShapeSDF(
        u.shape0Center,
        u.shape0Size,
        u.shape0CornerRadius,
        u.shape0Enabled,
        u.shape0Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );
    float d1 = liquidChatShapeSDF(
        u.shape1Center,
        u.shape1Size,
        u.shape1CornerRadius,
        u.shape1Enabled,
        u.shape1Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );
    float d2 = liquidChatShapeSDF(
        u.shape2Center,
        u.shape2Size,
        u.shape2CornerRadius,
        u.shape2Enabled,
        u.shape2Direction,
        fragCoordPixels,
        u.resolution,
        u.dpr,
        u.shapeRoundness
    );

    float best = d0;
    float2 center = u.shape0Center;
    if (d1 < best) {
        best = d1;
        center = u.shape1Center;
    }
    if (d2 < best) {
        center = u.shape2Center;
    }
    return center;
}

static inline float2 liquidChatCenterUV(constant LiquidChatMainUniforms &u, float2 fragCoordPixels) {
    return liquidChatActiveCenterPixels(u, fragCoordPixels) / u.resolution;
}

static inline float2 liquidChatGetNormal(constant LiquidChatMainUniforms &u, float2 fragCoordPixels) {
    float hx = max(fabs(dfdx(fragCoordPixels.x)), 0.0001);
    float hy = max(fabs(dfdy(fragCoordPixels.y)), 0.0001);

    float2 grad = float2(
        liquidChatMainSDF(u, fragCoordPixels + float2(hx, 0.0), float2(0.0)) -
            liquidChatMainSDF(u, fragCoordPixels - float2(hx, 0.0), float2(0.0)),
        liquidChatMainSDF(u, fragCoordPixels + float2(0.0, hy), float2(0.0)) -
            liquidChatMainSDF(u, fragCoordPixels - float2(0.0, hy), float2(0.0))
    ) / (float2(hx, hy) * 2.0);

    return grad * 1.414213562f * 1000.0f;
}

fragment float4 liquidChatGlassMainUnifiedFragment(
    VertexOut in [[stage_in]],
    constant LiquidChatMainUniforms &u [[buffer(1)]],
    texture2d<float> blurredBg [[texture(0)]],
    texture2d<float> bg [[texture(1)]],
    sampler samp [[sampler(0)]]
) {
    float2 fragCoord = float2(in.uv.x * u.resolution.x, in.uv.y * u.resolution.y);
    float2 resolution1x = u.resolution / u.dpr;
    float merged = liquidChatMainSDF(u, fragCoord, float2(0.0));

    float4 outColor;
    if (u.step <= 0) {
        float px = 2.0 / u.resolution.y;
        float3 col = merged > 0.0 ? float3(1.0, 1.0, 1.0) * merged : float3(1.0, 1.0, 1.0) * -merged * 2.0;
        col *= 3.0;
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(0.5 / resolution1x.y - px, 0.5 / resolution1x.y + px, fabs(merged))
        );
        outColor = float4(col, 1.0);
    } else if (u.step <= 1) {
        float px = 2.0 / u.resolution.y;
        float3 col = merged > 0.0 ? float3(0.9, 0.6, 0.3) : float3(0.65, 0.85, 1.0);
        col *= 1.0 - exp(-0.03 * fabs(merged) * resolution1x.y);
        col *= 0.6 + 0.4 * smoothstep(-0.5, 0.5, cos(0.25 * fabs(merged) * resolution1x.y * 2.0));
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(1.5 / resolution1x.y - px, 1.5 / resolution1x.y + px, fabs(merged))
        );
        outColor = float4(col, 1.0);
    } else if (u.step <= 2) {
        if (merged < 0.0) {
            float2 normal = liquidChatGetNormal(u, fragCoord);
            float3 normalColor = vec2ToRgb(normal);
            float l = length(normal);
            outColor = float4(normalColor, l);
        } else {
            outColor = float4(float3(0.8), 0.0);
        }
    } else if (u.step <= 3) {
        if (merged < 0.0) {
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / u.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            if (nmerged < u.refThickness) {
                outColor = float4(float3(edgeFactor), 1.0);
            } else {
                outColor = float4(float3(0.0), 1.0);
            }
        } else {
            outColor = float4(0.0);
        }
    } else if (u.step <= 4) {
        if (merged < 0.0) {
            float2 normal = liquidChatGetNormal(u, fragCoord);
            float3 normalColor = vec2ToRgb(normal);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float x_R_ratio = 1.0 - nmerged / u.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            outColor = float4(normalColor * edgeFactor * u.dpr * length(normal), 1.0);
        } else {
            outColor = float4(0.0);
        }
    } else if (u.step <= 5) {
        if (merged < 0.0) {
            outColor = blurredBg.sample(samp, in.uv);
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 6) {
        if (merged < 0.0) {
            float2 normal = liquidChatGetNormal(u, fragCoord);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = liquidChatCenterUV(u, fragCoord);
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset);
                outColor = blurredPixel;
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 7) {
        if (merged < 0.0) {
            float2 normal = liquidChatGetNormal(u, fragCoord);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = liquidChatCenterUV(u, fragCoord);
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                        u.refFresnelHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset, bias(u.refDispersion));
                outColor = mix(blurredPixel, float4(1.0), fresnelFactor * u.refFresnelFactor * 0.7);
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else if (u.step <= 8) {
        if (merged < 0.0) {
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = liquidChatCenterUV(u, fragCoord);
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-max(0.0, nmerged) / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - nmerged / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= u.refThickness) {
                edgeFactor = 0.0;
            }

            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                        u.refFresnelHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            float glareGeoFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / 1500.0 * pow(500.0 / u.glareRange, 2.0) +
                        u.glareHardness,
                    5.0
                ),
                0.0,
                1.0
            );

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
            } else {
                float2 normal = liquidChatGetNormal(u, fragCoord);

                float glareAngle = (vec2ToAngle(normalize(normal)) - PI / 4.0 + u.glareAngle) * 2.0;
                int glareFarside = 0;
                if ((glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5)) ||
                    glareAngle < PI * (0.0 - 0.5)) {
                    glareFarside = 1;
                }

                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) *
                    (glareFarside == 1 ? 1.2 * u.glareOppositeFactor : 1.2) *
                    u.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.3 + u.glareConvergence * 1.5), 0.0, 1.0);

                float2 dispOffset =
                    normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / resolution1x.x,
                        1.0
                    );
                float4 blurredPixel = blurredBg.sample(samp, zoomedUV - dispOffset, bias(u.refDispersion));
                outColor = blurredPixel;

                float3 tintLCH = SRGB_TO_LCH(
                    mix(float3(1.0), float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                tintLCH.x += 20.0 * fresnelFactor * u.refFresnelFactor;
                tintLCH.x = clamp(tintLCH.x, 0.0, 100.0);

                outColor = mix(
                    outColor,
                    float4(1.0),
                    fresnelFactor * u.refFresnelFactor * 0.7
                );

                float4 glareSideTint = glareFarside == 1 ? u.glareOppositeTint : u.glareTint;
                float3 glareColor = mix(float3(1.0), glareSideTint.rgb, glareSideTint.a);

                outColor = mix(
                    outColor,
                    float4(glareColor, 1.0),
                    glareAngleFactor * glareGeoFactor
                );
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }
    } else {
        if (merged < 0.005) {
            float nmerged = -1.0 * (merged * resolution1x.y);

            float safeThickness = max(0.001, u.refThickness);
            float2 centerUV = liquidChatCenterUV(u, fragCoord);
            float depthPx = max(0.0, nmerged);
            float zoomStrength = u.zoomOutFactor;
            float depth01 = 1.0 - exp(-depthPx / 18.0);
            float zoom = 1.0 + zoomStrength * depth01;
            float2 zoomedUV = centerUV + (in.uv - centerUV) * zoom;

            float x_R_ratio = clamp(1.0 - depthPx / safeThickness, 0.0, 1.0);
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / u.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (depthPx <= 0.0001 || depthPx >= safeThickness) {
                edgeFactor = 0.0;
            }

            if (edgeFactor <= 0.0) {
                outColor = blurredBg.sample(samp, zoomedUV);
                outColor = mix(outColor, float4(u.tint.r, u.tint.g, u.tint.b, 1.0), u.tint.a * 0.8);
            } else {
                float edgeH = clamp(depthPx / safeThickness, 0.0, 1.0);
                float2 normal = liquidChatGetNormal(u, fragCoord);
                float2 dispOffset =
                    -normal *
                    edgeFactor *
                    0.05 *
                    u.dpr *
                    float2(
                        u.resolution.y / (resolution1x.x * u.dpr),
                        1.0
                    );
                float4 blurredPixel = getTextureDispersion(
                    bg,
                    blurredBg,
                    samp,
                    zoomedUV,
                    u.blurEdge > 0 ? 1.0 : edgeH,
                    dispOffset,
                    u.refDispersion
                );

                outColor = mix(blurredPixel, float4(u.tint.r, u.tint.g, u.tint.b, 1.0), u.tint.a * 0.8);

                float fresnelFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / 1500.0 * pow(500.0 / u.refFresnelRange, 2.0) +
                            u.refFresnelHardness,
                        5.0
                    ),
                    0.0,
                    1.0
                );

                float3 fresnelTintLCH = SRGB_TO_LCH(
                    mix(float3(1.0), float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                fresnelTintLCH.x += 20.0 * fresnelFactor * u.refFresnelFactor;
                fresnelTintLCH.x = clamp(fresnelTintLCH.x, 0.0, 100.0);

                outColor = mix(
                    outColor,
                    float4(LCH_TO_SRGB(fresnelTintLCH), 1.0),
                    fresnelFactor * u.refFresnelFactor * 0.7 * length(normal)
                );

                float glareGeoFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / 1500.0 * pow(500.0 / u.glareRange, 2.0) +
                            u.glareHardness,
                        5.0
                    ),
                    0.0,
                    1.0
                );

                float glareAngle = (vec2ToAngle(normalize(normal)) - PI / 4.0 + u.glareAngle) * 2.0;
                int glareFarside = 0;
                if ((glareAngle > PI * (2.0 - 0.5) && glareAngle < PI * (4.0 - 0.5)) ||
                    glareAngle < PI * (0.0 - 0.5)) {
                    glareFarside = 1;
                }
                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) *
                    (glareFarside == 1
                        ? 1.2 * u.glareOppositeFactor
                        : 1.2) *
                    u.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.1 + u.glareConvergence * 2.0), 0.0, 1.0);

                float3 glareTintLCH = SRGB_TO_LCH(
                    mix(blurredPixel.rgb, float3(u.tint.r, u.tint.g, u.tint.b), u.tint.a * 0.5)
                );
                glareTintLCH.x += 150.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.y += 30.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.x = clamp(glareTintLCH.x, 0.0, 120.0);

                float4 glareSideTint = glareFarside == 1 ? u.glareOppositeTint : u.glareTint;
                float3 glareRgb = LCH_TO_SRGB(glareTintLCH) * mix(float3(1.0), glareSideTint.rgb, glareSideTint.a);

                outColor = mix(
                    outColor,
                    float4(glareRgb, 1.0),
                    glareAngleFactor * glareGeoFactor * length(normal)
                );
            }
        } else {
            outColor = bg.sample(samp, in.uv);
        }

    }

    // Analytic AA for the SDF edge (keeps the silhouette stable during motion).
    float edgeSoftness = max(0.0015, fwidth(merged));
    float bubbleMask = 1.0 - smoothstep(-edgeSoftness, edgeSoftness, merged);
    // Slightly wider mask for shadow blending (reduces the "outline/border" feel).
    float bubbleMaskShadow = 1.0 - smoothstep(-edgeSoftness * 2.8, edgeSoftness * 2.8, merged);

    float4 glass = outColor * bubbleMask;

    float shadowAlphaOutside = 0.0;
    float shadowAlphaInside = 0.0;
    if (u.shadowFactor > 0.0001 && u.shadowExpand > 0.0001) {
        float2 shadowOffset = float2(u.shadowPosition.x * u.dpr, -u.shadowPosition.y * u.dpr);
        float mergedShadow = liquidChatMainSDF(u, fragCoord, shadowOffset);

        float shadowSoftnessPx = max(0.001, u.shadowExpand * 2.6);

        float pxDistOutsideOffset = max(0.0, mergedShadow) * resolution1x.y;
        float pxDistOutsideAmbient = max(0.0, merged) * resolution1x.y;

        float shadowDirectional = exp(-pxDistOutsideOffset / shadowSoftnessPx) * (0.55 * u.shadowFactor);
        float shadowAmbient = exp(-pxDistOutsideAmbient / max(0.001, shadowSoftnessPx * 1.15)) * (0.18 * u.shadowFactor);
        float shadowOutside = saturate1(shadowDirectional + shadowAmbient);
        shadowAlphaOutside = shadowOutside * (1.0 - bubbleMaskShadow);

        float pxDistInsideOffset = max(0.0, -mergedShadow) * resolution1x.y;
        float shadowInset = exp(-pxDistInsideOffset / max(0.001, shadowSoftnessPx * 0.85)) * (0.35 * u.shadowFactor);
        shadowAlphaInside = saturate1(shadowInset) * bubbleMaskShadow;
    }

    glass.rgb = mix(glass.rgb, float3(0.0), shadowAlphaInside);
    float outAlpha = glass.a + shadowAlphaOutside * (1.0 - glass.a);
    return float4(glass.rgb, outAlpha);
}
