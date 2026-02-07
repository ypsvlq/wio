const std = @import("std");
const wio = @import("wio");
const w = wio.backend.win32;

var debug_allocator = std.heap.DebugAllocator(.{}).init;
const allocator = debug_allocator.allocator();

var window: wio.Window = undefined;

pub fn main() !void {
    defer _ = debug_allocator.deinit();

    try wio.init(allocator, .{});
    defer wio.deinit();
    window = try wio.createWindow(.{ .title = "D3D11", .scale = 1 });
    defer window.destroy();

    try createDevice();
    defer destroyDevice();
    try createRenderTargetView();
    defer destroyRenderTargetView();
    try createShaders();
    defer destroyShaders();

    while (true) {
        wio.update();
        while (window.getEvent()) |event| {
            switch (event) {
                .close => return,
                .framebuffer => |size| try resize(size),
                .draw => try draw(),
                else => {},
            }
        }
        wio.wait();
    }
}

var swapchain: *w.IDXGISwapChain = undefined;
var device: *w.ID3D11Device = undefined;
var device_context: *w.ID3D11DeviceContext = undefined;

fn createDevice() !void {
    try SUCCEED(w.D3D11CreateDeviceAndSwapChain(
        null,
        w.D3D_DRIVER_TYPE_HARDWARE,
        null,
        0,
        null,
        0,
        w.D3D11_SDK_VERSION,
        &.{
            .BufferDesc = .{
                .Width = 0,
                .Height = 0,
                .RefreshRate = .{
                    .Numerator = 0,
                    .Denominator = 1,
                },
                .Format = w.DXGI_FORMAT_B8G8R8A8_UNORM,
                .ScanlineOrdering = w.DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED,
                .Scaling = w.DXGI_MODE_SCALING_UNSPECIFIED,
            },
            .SampleDesc = .{
                .Count = 1,
                .Quality = 0,
            },
            .BufferUsage = w.DXGI_USAGE_RENDER_TARGET_OUTPUT,
            .BufferCount = 2,
            .OutputWindow = window.backend.window,
            .Windowed = w.TRUE,
            .SwapEffect = w.DXGI_SWAP_EFFECT_DISCARD,
            .Flags = 0,
        },
        @ptrCast(&swapchain),
        @ptrCast(&device),
        null,
        @ptrCast(&device_context),
    ), "D3D11CreateDeviceAndSwapChain");
}

fn destroyDevice() void {
    _ = device_context.Release();
    _ = device.Release();
    _ = swapchain.Release();
}

var render_target_view: *w.ID3D11RenderTargetView = undefined;

fn createRenderTargetView() !void {
    var render_target: *w.ID3D11Texture2D = undefined;
    try SUCCEED(swapchain.GetBuffer(0, &w.IID_ID3D11Texture2D, @ptrCast(&render_target)), "IDXGISwapChain::GetBuffer");
    defer _ = render_target.Release();
    try SUCCEED(device.CreateRenderTargetView(@ptrCast(render_target), null, @ptrCast(&render_target_view)), "ID3D11Device::CreateRenderTargetView");
    device_context.OMSetRenderTargets(1, @ptrCast(&render_target_view), null);
}

fn destroyRenderTargetView() void {
    _ = render_target_view.Release();
}

var vertex_shader: *w.ID3D11VertexShader = undefined;
var pixel_shader: *w.ID3D11PixelShader = undefined;

fn createShaders() !void {
    const shaders = @embedFile("shaders.hlsl");
    var blob: *w.ID3DBlob = undefined;

    {
        try SUCCEED(w.D3DCompile(shaders, shaders.len, null, null, null, "VSMain", "vs_4_0", 0, 0, @ptrCast(&blob), null), "D3DCompile");
        defer _ = blob.Release();
        try SUCCEED(device.CreateVertexShader(blob.GetBufferPointer(), blob.GetBufferSize(), null, @ptrCast(&vertex_shader)), "ID3D11Device::CreateVertexShader");
    }
    errdefer _ = vertex_shader.Release();

    {
        try SUCCEED(w.D3DCompile(shaders, shaders.len, null, null, null, "PSMain", "ps_4_0", 0, 0, @ptrCast(&blob), null), "D3DCompile");
        defer _ = blob.Release();
        try SUCCEED(device.CreatePixelShader(blob.GetBufferPointer(), blob.GetBufferSize(), null, @ptrCast(&pixel_shader)), "ID3D11Device::CreatePixelShader");
    }
    errdefer _ = pixel_shader.Release();

    device_context.IASetPrimitiveTopology(w.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
    device_context.VSSetShader(vertex_shader, null, 0);
    device_context.PSSetShader(pixel_shader, null, 0);
}

fn destroyShaders() void {
    _ = pixel_shader.Release();
    _ = vertex_shader.Release();
}

fn resize(size: wio.Size) !void {
    destroyRenderTargetView();
    try SUCCEED(swapchain.ResizeBuffers(0, 0, 0, w.DXGI_FORMAT_UNKNOWN, 0), "IDXGISwapChain::ResizeBuffers");
    try createRenderTargetView();
    device_context.RSSetViewports(1, &.{ .TopLeftX = 0, .TopLeftY = 0, .Width = @floatFromInt(size.width), .Height = @floatFromInt(size.height), .MinDepth = 0, .MaxDepth = 0 });
}

fn draw() !void {
    device_context.Draw(3, 0);
    try SUCCEED(swapchain.Present(1, 0), "IDXGISwapChain::Present");
}

fn SUCCEED(hr: w.HRESULT, name: []const u8) !void {
    if (hr < 0) {
        std.log.err("{s} failed, hr={x:0>8}", .{ name, @as(u32, @bitCast(hr)) });
        return error.Unexpected;
    }
}
