static constant float2 positions[] = {
    { -0.5, -0.5 },
    { 0.5, -0.5 },
    { 0.0, 0.5 },
};

static constant float3 colors[] = {
    { 1.0, 0.5, 0.0 },
    { 0.0, 1.0, 0.5 },
    { 0.5, 0.0, 1.0 },
};

struct VertexOutput {
    float4 position [[position]];
    float3 color;
};

vertex VertexOutput vertexShader(uint id [[vertex_id]]) {
    VertexOutput out;
    out.position = float4(positions[id].xy, 0.0, 1.0);
    out.color = colors[id];
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]]) {
    return float4(in.color, 1.0);
}
