struct PSInput {
    float4 position : SV_POSITION;
    float4 color : COLOR;
};

static const float2 vertices[] = {
    float2(-0.5, -0.5),
    float2(0.0, 0.5),
    float2(0.5, -0.5),
};

static const float3 colors[] = {
    float3(1.0, 1.0, 0.0),
    float3(1.0, 0.0, 1.0),
    float3(0.0, 1.0, 1.0),
};

PSInput VSMain(uint id : SV_VERTEXID) {
    PSInput result;
    result.position = float4(vertices[id], 0.0, 1.0);
    result.color = float4(colors[id], 1.0);
    return result;
}

float4 PSMain(PSInput input) : SV_TARGET {
    return input.color;
}
