import Metal

enum FoldShaderLibrary {
    static func make(device: any MTLDevice) throws -> any MTLLibrary {
        try device.makeLibrary(source: source, options: nil)
    }

    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct FoldVertex {
        float2 position [[attribute(0)]];
        float2 textureCoordinate [[attribute(1)]];
    };

    struct FoldUniforms {
        float4 geometry;
        float4 cameraAndBlur;
        float4 voidAndRim;
        float4 finish;
        float4 dimensions;
        float4 colorAndTap;
        float4 quality;
    };

    struct FoldVaryings {
        float4 position [[position]];
        float2 textureCoordinate;
        float panelV;
    };

    vertex FoldVaryings backdropVertex(FoldVertex input [[stage_in]])
    {
        FoldVaryings output;
        output.position = float4(input.position, 0.0f, 1.0f);
        output.textureCoordinate = input.textureCoordinate;
        output.panelV = 1.0f - input.textureCoordinate.y;
        return output;
    }

    fragment float4 backdropFragment(
        FoldVaryings input [[stage_in]],
        texture2d<float> source [[texture(0)]],
        sampler sourceSampler [[sampler(0)]],
        constant FoldUniforms &uniforms [[buffer(1)]])
    {
        // The six-level mip still contains large window silhouettes. Average
        // fixed points instead of sampling at the fragment's screen position:
        // the revealed backing keeps the scene's color, but no second copy of
        // its content can appear behind the moving panel.
        const float maxLOD = max(float(source.get_num_mip_levels()) - 1.0f, 0.0f);
        float3 backingColor = float3(0.0f);
        for (uint row = 0; row < 3; ++row) {
            for (uint column = 0; column < 3; ++column) {
                const float2 point = (float2(column, row) + 0.5f) / 3.0f;
                backingColor += source.sample(sourceSampler, point, level(maxLOD)).rgb;
            }
        }
        backingColor *= 1.0f / 9.0f;
        const float sealFade = smoothstep(
            uniforms.quality.z, 1.0f, clamp(uniforms.geometry.x, 0.0f, 1.0f)
        );
        return float4(mix(backingColor, uniforms.colorAndTap.xyz, sealFade), 1.0f);
    }

    vertex FoldVaryings foldVertex(
        FoldVertex input [[stage_in]],
        constant FoldUniforms &uniforms [[buffer(1)]])
    {
        const float progress = uniforms.geometry.x;
        const float squashGain = uniforms.geometry.y;
        const float geometryProgress = pow(
            clamp(progress, 0.0f, 1.0f),
            max(uniforms.quality.y, 0.01f)
        );
        const float rotation = uniforms.geometry.z * geometryProgress;
        const float fieldOfView = uniforms.geometry.w;
        const float eyeDistance = uniforms.cameraAndBlur.x;
        const float eyeOffset = uniforms.cameraAndBlur.y;

        // Texture coordinates use Metal's top-left convention, while panelV is
        // defined by the design as zero at the bottom hinge.
        const float panelV = 1.0f - input.textureCoordinate.y;
        const float squashedV = pow(panelV, 1.0f + squashGain * geometryProgress);
        const float depth = squashedV * sin(rotation);
        const float rotatedHeight = squashedV * cos(rotation);
        const float focalScale = 1.0f / tan(max(fieldOfView, 0.01f) * 0.5f);
        const float cameraDistance = max(eyeDistance * focalScale, 0.01f);
        const float perspective = cameraDistance / (cameraDistance + depth);

        FoldVaryings output;
        output.position = float4(
            input.position.x * perspective,
            -1.0f + 2.0f * rotatedHeight * perspective
                + eyeOffset * depth * geometryProgress,
            0.0f,
            1.0f
        );
        output.textureCoordinate = input.textureCoordinate;
        output.panelV = panelV;
        return output;
    }

    fragment float4 foldFragment(
        FoldVaryings input [[stage_in]],
        texture2d<float> source [[texture(0)]],
        texture2d<float, access::read> blueNoise [[texture(1)]],
        sampler sourceSampler [[sampler(0)]],
        constant FoldUniforms &uniforms [[buffer(1)]])
    {
        const float progress = uniforms.geometry.x;
        const float maxBlur = uniforms.cameraAndBlur.z;
        const float blurExponent = uniforms.cameraAndBlur.w;
        const float sourceHeight = uniforms.dimensions.w;
        const float panelV = input.panelV;

        const float radius = pow(progress, blurExponent)
            * (0.15f + 1.85f * pow(panelV, 1.4f)) * maxBlur;
        const float maxLOD = max(float(source.get_num_mip_levels()) - 1.0f, 0.0f);
        const float lod = clamp(log2(max(radius, 1.0f)), 0.0f, maxLOD);
        const float tapOffset = uniforms.colorAndTap.w * radius / max(sourceHeight, 1.0f);
        float4 color = source.sample(sourceSampler, input.textureCoordinate, level(lod));
        if (uniforms.quality.x < 0.5f) {
            color *= 0.72f;
            color += source.sample(
                sourceSampler,
                input.textureCoordinate + float2(0.0f, tapOffset),
                level(lod)
            ) * 0.14f;
            color += source.sample(
                sourceSampler,
                input.textureCoordinate - float2(0.0f, tapOffset),
                level(lod)
            ) * 0.14f;
        }

        const float horizon = uniforms.voidAndRim.x * progress;
        const float softness = max(uniforms.voidAndRim.y, 0.0001f);
        const float lit = smoothstep(0.0f, 1.0f, (panelV - horizon) / softness);
        const float3 warmBlack = uniforms.colorAndTap.xyz;
        const float voidAmount = (1.0f - lit) * progress;
        color.rgb = mix(color.rgb, warmBlack, voidAmount);

        const float widenedRim = max(
            uniforms.voidAndRim.z * mix(1.0f, uniforms.finish.x, progress),
            0.0001f
        );
        const float rimCoordinate = (panelV - horizon) / widenedRim;
        const float rim = exp(-(rimCoordinate * rimCoordinate))
            * uniforms.voidAndRim.w * progress;
        color.rgb += rim * float3(0.38f, 0.68f, 1.0f);

        const float coolAmount = uniforms.finish.y * progress;
        color.rgb = mix(color.rgb, color.rgb * float3(0.92f, 1.0f, 1.10f), coolAmount);

        const float2 centered = input.textureCoordinate * 2.0f - 1.0f;
        const float vignette = smoothstep(0.35f, 1.25f, length(centered));
        color.rgb *= 1.0f - uniforms.finish.z * progress * vignette;

        const float sealFade = smoothstep(
            uniforms.quality.z, 1.0f, clamp(progress, 0.0f, 1.0f)
        );
        color.rgb = mix(color.rgb, warmBlack, sealFade);

        const uint2 noiseCoordinate = uint2(input.position.xy)
            % uint2(blueNoise.get_width(), blueNoise.get_height());
        const float dither = blueNoise.read(noiseCoordinate).r - 0.5f;
        color.rgb += dither * uniforms.finish.w * progress;
        return float4(clamp(color.rgb, 0.0f, 1.0f), color.a);
    }

    kernel void gaussianHorizontal(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) {
            return;
        }
        const int sourceX = int(gid.x) * 2;
        const int sourceY = int(gid.y);
        const int maximumX = int(source.get_width()) - 1;
        float4 sum = float4(0.0f);
        constexpr float weights[5] = { 0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f };
        for (int tap = -2; tap <= 2; ++tap) {
            const uint x = uint(clamp(sourceX + tap, 0, maximumX));
            sum += source.read(uint2(x, uint(sourceY))) * weights[tap + 2];
        }
        destination.write(sum, gid);
    }

    kernel void gaussianVertical(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> destination [[texture(1)]],
        uint2 gid [[thread_position_in_grid]])
    {
        if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) {
            return;
        }
        const int sourceX = int(gid.x);
        const int sourceY = int(gid.y) * 2;
        const int maximumY = int(source.get_height()) - 1;
        float4 sum = float4(0.0f);
        constexpr float weights[5] = { 0.0625f, 0.25f, 0.375f, 0.25f, 0.0625f };
        for (int tap = -2; tap <= 2; ++tap) {
            const uint y = uint(clamp(sourceY + tap, 0, maximumY));
            sum += source.read(uint2(uint(sourceX), y)) * weights[tap + 2];
        }
        destination.write(sum, gid);
    }
    """#
}
