const std = @import("std");
const wio = @import("wio");
const w = @import("win32");

pub fn main(init: std.process.Init) !void {
    try wio.init(.{
        .allocator = init.gpa,
        .io = init.io,
        .eventFn = WindowState.eventFn,
    });
    defer wio.deinit();

    var state: WindowState = .{ .events = .empty, .renderer = null };
    defer state.events.deinit();

    var window = try wio.Window.create(.{
        .event_fn_data = &state,
        .title = "D3D11",
        .scale = 1,
    });
    defer window.destroy();

    state.renderer = try Renderer.init(window);
    defer state.renderer.?.deinit();

    while (true) {
        wio.update();
        while (state.events.pop()) |event| {
            switch (event) {
                .close => return,
                else => _ = try state.renderer.?.handleEvent(event),
            }
        }
        wio.wait(.{});
    }
}

const WindowState = struct {
    events: wio.EventQueue,
    renderer: ?Renderer,

    /// Custom eventFn to process draw events during resize.
    pub fn eventFn(data: ?*anyopaque, event: wio.Event) void {
        const self: *WindowState = @ptrCast(@alignCast(data));
        if (self.renderer) |*renderer| {
            if (renderer.handleEvent(event) catch false) {
                return;
            }
        }
        wio.EventQueue.eventFn(&self.events, event);
    }
};

const Renderer = struct {
    device: Device,
    render_target_view: RenderTargetView,
    shaders: Shaders,

    pub fn init(window: wio.Window) !Renderer {
        const device = try Device.create(window);
        errdefer device.destroy();
        const render_target_view = try device.createRenderTargetView();
        errdefer render_target_view.destroy();
        const shaders = try device.createShaders();
        errdefer shaders.destroy();
        return .{
            .device = device,
            .render_target_view = render_target_view,
            .shaders = shaders,
        };
    }

    pub fn deinit(self: Renderer) void {
        self.shaders.destroy();
        self.render_target_view.destroy();
        self.device.destroy();
    }

    pub fn handleEvent(self: *Renderer, event: wio.Event) !bool {
        switch (event) {
            .size_physical => |size| {
                self.render_target_view.destroy();
                try SUCCEED(self.device.swapchain.ResizeBuffers(0, 0, 0, w.DXGI_FORMAT_UNKNOWN, 0), "IDXGISwapChain::ResizeBuffers");
                self.render_target_view = try self.device.createRenderTargetView();
                self.device.context.RSSetViewports(1, &.{ .TopLeftX = 0, .TopLeftY = 0, .Width = @floatFromInt(size.width), .Height = @floatFromInt(size.height), .MinDepth = 0, .MaxDepth = 0 });
                return true;
            },
            .draw => {
                self.device.context.Draw(3, 0);
                try SUCCEED(self.device.swapchain.Present(1, 0), "IDXGISwapChain::Present");
                return true;
            },
            else => return false,
        }
    }

    pub const Device = struct {
        swapchain: *w.IDXGISwapChain,
        device: *w.ID3D11Device,
        context: *w.ID3D11DeviceContext,

        pub fn create(window: wio.Window) !Device {
            var swapchain: *w.IDXGISwapChain = undefined;
            var device: *w.ID3D11Device = undefined;
            var context: *w.ID3D11DeviceContext = undefined;

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
                @ptrCast(&context),
            ), "D3D11CreateDeviceAndSwapChain");

            return .{
                .swapchain = swapchain,
                .device = device,
                .context = context,
            };
        }

        pub fn destroy(self: Device) void {
            _ = self.context.Release();
            _ = self.device.Release();
            _ = self.swapchain.Release();
        }

        pub fn createRenderTargetView(self: Device) !RenderTargetView {
            var render_target: *w.ID3D11Texture2D = undefined;
            try SUCCEED(self.swapchain.GetBuffer(0, &w.IID_ID3D11Texture2D, @ptrCast(&render_target)), "IDXGISwapChain::GetBuffer");
            defer _ = render_target.Release();

            var render_target_view: *w.ID3D11RenderTargetView = undefined;
            try SUCCEED(self.device.CreateRenderTargetView(@ptrCast(render_target), null, @ptrCast(&render_target_view)), "ID3D11Device::CreateRenderTargetView");
            self.context.OMSetRenderTargets(1, @ptrCast(&render_target_view), null);

            return .{ .render_target_view = render_target_view };
        }

        pub fn createShaders(self: Device) !Shaders {
            const shaders = @embedFile("shaders.hlsl");
            var blob: *w.ID3DBlob = undefined;

            var vertex: *w.ID3D11VertexShader = undefined;
            {
                try SUCCEED(w.D3DCompile(shaders, shaders.len, null, null, null, "VSMain", "vs_4_0", 0, 0, @ptrCast(&blob), null), "D3DCompile");
                defer _ = blob.Release();
                try SUCCEED(self.device.CreateVertexShader(blob.GetBufferPointer(), blob.GetBufferSize(), null, @ptrCast(&vertex)), "ID3D11Device::CreateVertexShader");
            }
            errdefer _ = vertex.Release();

            var pixel: *w.ID3D11PixelShader = undefined;
            {
                try SUCCEED(w.D3DCompile(shaders, shaders.len, null, null, null, "PSMain", "ps_4_0", 0, 0, @ptrCast(&blob), null), "D3DCompile");
                defer _ = blob.Release();
                try SUCCEED(self.device.CreatePixelShader(blob.GetBufferPointer(), blob.GetBufferSize(), null, @ptrCast(&pixel)), "ID3D11Device::CreatePixelShader");
            }
            errdefer _ = pixel.Release();

            self.context.IASetPrimitiveTopology(w.D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            self.context.VSSetShader(vertex, null, 0);
            self.context.PSSetShader(pixel, null, 0);

            return .{
                .vertex = vertex,
                .pixel = pixel,
            };
        }
    };

    pub const RenderTargetView = struct {
        render_target_view: *w.ID3D11RenderTargetView,

        pub fn destroy(self: RenderTargetView) void {
            _ = self.render_target_view.Release();
        }
    };

    pub const Shaders = struct {
        vertex: *w.ID3D11VertexShader,
        pixel: *w.ID3D11PixelShader,

        pub fn destroy(self: Shaders) void {
            _ = self.pixel.Release();
            _ = self.vertex.Release();
        }
    };

    fn SUCCEED(hr: w.HRESULT, name: []const u8) !void {
        if (hr < 0) {
            std.log.err("{s} failed, hr={x:0>8}", .{ name, @as(u32, @bitCast(hr)) });
            return error.Unexpected;
        }
    }
};
