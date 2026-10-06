const std = @import("std");
const wio = @import("wio");
const vk = @import("vulkan");

comptime {
    _ = wio; // for Android
}

pub const std_options: std.Options = .{ .logFn = wio.logFn };

fn isWayland() bool {
    return wio.backend_name == .unix and wio.backend.active == .wayland;
}

pub fn main() !void {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    const gpa = gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{});

    try wio.init(.{
        .allocator = gpa,
        .io = threaded.io(),
        .eventFn = wio.EventQueue.eventFn,
    });
    defer wio.deinit();

    var event_queue: wio.EventQueue = .empty;
    const initial_size: wio.Size = .{ .width = 640, .height = 480 };
    var window: wio.Window = try .create(.{
        .event_fn_data = &event_queue,
        .title = "Vulkan",
        .size = initial_size,
        .scale = 1,
    });
    defer {
        window.destroy();
        event_queue.deinit();
    }

    if (isWayland()) {
        // normal vsync makes window resizing slow on wayland
        window.enableDrawAvailableEvents();
    }

    var renderer: Renderer = try .initWithSurface(gpa, initial_size, &window);
    defer renderer.deinit(gpa);

    var visible = true;

    while (true) {
        var draw = !isWayland();

        while (event_queue.pop()) |event| {
            switch (event) {
                .visible => {
                    visible = true;
                    if (wio.backend_name == .android and !renderer.hasSurface()) {
                        try renderer.initSurface();
                    }
                },

                .hidden => {
                    visible = false;
                    if (wio.backend_name == .android) {
                        renderer.deinitSurface(gpa);
                    }
                },

                .size_physical => |new_size| try renderer.resize(gpa, new_size),

                .draw => {
                    if (isWayland()) draw = true;
                },

                .close => return,

                else => {},
            }
        }

        if (draw and visible and renderer.hasSurface()) {
            try renderer.draw(gpa);
        }

        wio.update();
    }
}

const Renderer = struct {
    window_size: wio.Size,

    vki_ptr: *vk.InstanceWrapper, // heap-allocated so the proxies' pointers stay valid
    instance: vk.InstanceProxy,

    surface: ?Surface = null,

    pub const InitError = CreateInstanceError || std.mem.Allocator.Error;

    pub fn init(gpa: std.mem.Allocator, window_size: wio.Size) InitError!Renderer {
        const vkb: vk.BaseWrapper = .load(@as(*const fn (?*vk.Instance, [*:0]const u8) ?*const fn () void, @ptrCast(&wio.vkGetInstanceProcAddr)));

        const vki_ptr = try gpa.create(vk.InstanceWrapper);
        errdefer gpa.destroy(vki_ptr);

        const vki_value, const instance_handle = try createInstance(gpa, vkb);
        vki_ptr.* = vki_value;

        return .{
            .window_size = window_size,
            .vki_ptr = vki_ptr,
            .instance = .init(instance_handle, vki_ptr),
        };
    }

    pub const InitWithSurfaceError = InitError || Surface.InitError;

    pub fn initWithSurface(gpa: std.mem.Allocator, window_size: wio.Size, window_ptr: *wio.Window) InitWithSurfaceError!Renderer {
        var self: Renderer = try .init(gpa, window_size);
        try self.initSurface(gpa, window_ptr);
        return self;
    }

    pub fn deinit(self: *Renderer, gpa: std.mem.Allocator) void {
        self.deinitSurface(gpa);
        self.instance.destroyInstance(null);
        gpa.destroy(self.vki_ptr);
    }

    pub fn hasSurface(self: *const Renderer) bool {
        return self.surface != null;
    }

    pub fn initSurface(self: *Renderer, gpa: std.mem.Allocator, window_ptr: *wio.Window) Surface.InitError!void {
        std.debug.assert(self.surface == null);
        self.surface = try .init(gpa, self.instance, window_ptr, self.window_size);
    }

    pub fn deinitSurface(self: *Renderer, gpa: std.mem.Allocator) void {
        if (self.surface) |*surface| {
            surface.deinit(gpa, self.instance);
            self.surface = null;
        }
    }

    pub fn resize(self: *Renderer, gpa: std.mem.Allocator, new_size: wio.Size) Surface.RecreateSwapchainError!void {
        if (std.meta.eql(new_size, self.window_size)) return;
        self.window_size = new_size;
        if (self.surface) |*surface| try surface.recreateSwapchain(gpa, self.instance, new_size);
    }

    pub const DrawError = Surface.DrawFrameError || Surface.RecreateSwapchainError;

    /// Draws a frame, recovering from out-of-date swapchains and lost surfaces.
    pub fn draw(self: *Renderer, gpa: std.mem.Allocator) DrawError!void {
        if (self.surface) |*surface| surface.drawFrame() catch |err| switch (err) {
            error.OutOfDateKHR, error.SuboptimalKHR => try surface.recreateSwapchain(gpa, self.instance, self.window_size),
            error.SurfaceLostKHR => self.deinitSurface(gpa),
            else => return err,
        };
    }
};

/// Everything that exists only while we have a window surface.
const Surface = struct {
    handle: vk.SurfaceKHR,
    format: vk.SurfaceFormatKHR,

    physical_device: vk.PhysicalDevice,
    vkd_ptr: *vk.DeviceWrapper, // heap-allocated so `device`'s pointer stays valid
    device: vk.DeviceProxy,

    graphics_queue: vk.Queue,
    graphics_queue_index: u32,
    present_queue: vk.Queue,
    present_queue_index: u32,

    render_pass: vk.RenderPass,
    pipeline_layout: vk.PipelineLayout,
    pipeline: vk.Pipeline,

    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,

    in_flight_fence: vk.Fence,
    image_available_semaphore: vk.Semaphore,

    swapchain: Swapchain,

    pub const InitError = CreateSurfaceError || PickPhysicalDeviceError || CreateLogicalDeviceError ||
        ChooseSurfaceFormatError || CreateRenderPassError || CreateGraphicsPipelineError ||
        CreateCommandBufferError || CreateSyncObjectsError || Swapchain.InitError || std.mem.Allocator.Error;

    pub fn init(
        gpa: std.mem.Allocator,
        instance: vk.InstanceProxy,
        window_ptr: *wio.Window,
        window_size: wio.Size,
    ) InitError!Surface {
        const handle = try createSurface(window_ptr, instance);
        errdefer instance.destroySurfaceKHR(handle, null);

        const choice = try pickPhysicalDevice(gpa, instance, handle);

        const vkd_ptr = try gpa.create(vk.DeviceWrapper);
        errdefer gpa.destroy(vkd_ptr);
        const device = try createLogicalDevice(gpa, instance, vkd_ptr, choice);
        errdefer device.destroyDevice(null);

        const format = try chooseSurfaceFormat(gpa, instance, choice.handle, handle);
        const render_pass = try createRenderPass(device, format);
        errdefer device.destroyRenderPass(render_pass, null);
        const pipeline_layout, const pipeline = try createGraphicsPipeline(device, render_pass);
        errdefer device.destroyPipelineLayout(pipeline_layout, null);
        errdefer device.destroyPipeline(pipeline, null);
        const command_pool, const command_buffer = try createCommandBuffer(device, choice.graphics_queue_index);
        errdefer device.destroyCommandPool(command_pool, null);
        const image_available_semaphore, const in_flight_fence = try createSyncObjects(device);
        errdefer device.destroySemaphore(image_available_semaphore, null);
        errdefer device.destroyFence(in_flight_fence, null);

        const swapchain = try Swapchain.init(gpa, .{
            .instance = instance,
            .device = device,
            .physical_device = choice.handle,
            .surface = handle,
            .format = format,
            .render_pass = render_pass,
            .graphics_queue_index = choice.graphics_queue_index,
            .present_queue_index = choice.present_queue_index,
        }, window_size);

        return .{
            .handle = handle,
            .format = format,
            .physical_device = choice.handle,
            .vkd_ptr = vkd_ptr,
            .device = device,
            .graphics_queue = device.getDeviceQueue(choice.graphics_queue_index, 0),
            .graphics_queue_index = choice.graphics_queue_index,
            .present_queue = device.getDeviceQueue(choice.present_queue_index, 0),
            .present_queue_index = choice.present_queue_index,
            .render_pass = render_pass,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .command_pool = command_pool,
            .command_buffer = command_buffer,
            .in_flight_fence = in_flight_fence,
            .image_available_semaphore = image_available_semaphore,
            .swapchain = swapchain,
        };
    }

    pub fn deinit(self: *Surface, gpa: std.mem.Allocator, instance: vk.InstanceProxy) void {
        self.device.deviceWaitIdle() catch {};

        self.swapchain.deinit(gpa, self.device);
        self.device.destroyFence(self.in_flight_fence, null);
        self.device.destroySemaphore(self.image_available_semaphore, null);
        self.device.destroyCommandPool(self.command_pool, null);
        self.device.destroyPipeline(self.pipeline, null);
        self.device.destroyPipelineLayout(self.pipeline_layout, null);
        self.device.destroyRenderPass(self.render_pass, null);
        self.device.destroyDevice(null);
        gpa.destroy(self.vkd_ptr);
        instance.destroySurfaceKHR(self.handle, null);
    }

    pub fn swapchainContext(self: *const Surface, instance: vk.InstanceProxy) Swapchain.Context {
        return .{
            .instance = instance,
            .device = self.device,
            .physical_device = self.physical_device,
            .surface = self.handle,
            .format = self.format,
            .render_pass = self.render_pass,
            .graphics_queue_index = self.graphics_queue_index,
            .present_queue_index = self.present_queue_index,
        };
    }

    pub const RecreateSwapchainError = vk.DeviceProxy.DeviceWaitIdleError || Swapchain.InitError;

    pub fn recreateSwapchain(self: *Surface, gpa: std.mem.Allocator, instance: vk.InstanceProxy, window_size: wio.Size) RecreateSwapchainError!void {
        try self.device.deviceWaitIdle();
        self.swapchain.deinit(gpa, self.device);
        self.swapchain = try Swapchain.init(gpa, self.swapchainContext(instance), window_size);
    }

    pub const DrawFrameError = vk.DeviceProxy.WaitForFencesError || vk.DeviceProxy.AcquireNextImageKHRError ||
        vk.DeviceProxy.ResetCommandBufferError || RecordCommandBufferError || vk.DeviceProxy.ResetFencesError ||
        vk.DeviceProxy.QueueSubmitError || vk.DeviceProxy.QueuePresentKHRError || error{SuboptimalKHR};

    pub fn drawFrame(self: *Surface) DrawFrameError!void {
        _ = try self.device.waitForFences(&.{self.in_flight_fence}, .true, std.math.maxInt(u64));

        const image_index = (try self.device.acquireNextImageKHR(
            self.swapchain.handle,
            std.math.maxInt(u64),
            self.image_available_semaphore,
            .null_handle,
        )).image_index;
        const render_finished = self.swapchain.render_finished_semaphores[image_index];

        try self.device.resetCommandBuffer(self.command_buffer, .{});
        try self.recordCommandBuffer(image_index);

        try self.device.resetFences(&.{self.in_flight_fence});
        try self.device.queueSubmit(
            self.graphics_queue,
            &.{.{
                .wait_semaphore_count = 1,
                .p_wait_semaphores = &.{self.image_available_semaphore},
                .p_wait_dst_stage_mask = &.{.{ .color_attachment_output = true }},
                .command_buffer_count = 1,
                .p_command_buffers = &.{self.command_buffer},
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &.{render_finished},
            }},
            self.in_flight_fence,
        );

        switch (try self.device.queuePresentKHR(self.present_queue, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{render_finished},
            .swapchain_count = 1,
            .p_swapchains = &.{self.swapchain.handle},
            .p_image_indices = &.{image_index},
        })) {
            .suboptimal_khr => return error.SuboptimalKHR,
            else => {},
        }
    }

    pub const RecordCommandBufferError = vk.DeviceProxy.BeginCommandBufferError || vk.DeviceProxy.EndCommandBufferError;

    pub fn recordCommandBuffer(self: *Surface, image_index: u32) RecordCommandBufferError!void {
        const extent = self.swapchain.extent;

        try self.device.beginCommandBuffer(self.command_buffer, &.{});

        self.device.cmdBeginRenderPass(self.command_buffer, &.{
            .render_pass = self.render_pass,
            .framebuffer = self.swapchain.framebuffers[image_index],
            .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .clear_value_count = 1,
            .p_clear_values = &.{.{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } }},
        }, .@"inline");

        self.device.cmdBindPipeline(self.command_buffer, .graphics, self.pipeline);

        self.device.cmdSetViewport(self.command_buffer, 0, &.{.{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(extent.width),
            .height = @floatFromInt(extent.height),
            .min_depth = 0,
            .max_depth = 1,
        }});

        self.device.cmdSetScissor(self.command_buffer, 0, &.{.{
            .offset = .{ .x = 0, .y = 0 },
            .extent = extent,
        }});

        self.device.cmdDraw(self.command_buffer, 3, 1, 0, 0);

        self.device.cmdEndRenderPass(self.command_buffer);

        try self.device.endCommandBuffer(self.command_buffer);
    }
};

const Swapchain = struct {
    handle: vk.SwapchainKHR,
    extent: vk.Extent2D,
    images: []vk.Image,
    image_views: []vk.ImageView,
    framebuffers: []vk.Framebuffer,
    render_finished_semaphores: []vk.Semaphore,

    /// Everything a swapchain needs from its parent `Surface`.
    pub const Context = struct {
        instance: vk.InstanceProxy,
        device: vk.DeviceProxy,
        physical_device: vk.PhysicalDevice,
        surface: vk.SurfaceKHR,
        format: vk.SurfaceFormatKHR,
        render_pass: vk.RenderPass,
        graphics_queue_index: u32,
        present_queue_index: u32,
    };

    pub const InitError = vk.InstanceProxy.GetPhysicalDeviceSurfaceCapabilitiesKHRError ||
        vk.DeviceProxy.CreateSwapchainKHRError || vk.DeviceProxy.GetSwapchainImagesAllocKHRError ||
        std.mem.Allocator.Error || vk.DeviceProxy.CreateImageViewError ||
        vk.DeviceProxy.CreateFramebufferError || vk.DeviceProxy.CreateSemaphoreError;

    pub fn init(gpa: std.mem.Allocator, ctx: Context, window_size: wio.Size) InitError!Swapchain {
        const device = ctx.device;
        const concurrent = ctx.graphics_queue_index != ctx.present_queue_index;

        const capabilities = try ctx.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(ctx.physical_device, ctx.surface);

        const extent: vk.Extent2D = .{
            .width = std.math.clamp(window_size.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
            .height = std.math.clamp(window_size.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
        };

        const handle = try device.createSwapchainKHR(&.{
            .surface = ctx.surface,
            .min_image_count = if (capabilities.max_image_count == capabilities.min_image_count) capabilities.min_image_count else capabilities.min_image_count + 1,
            .image_format = ctx.format.format,
            .image_color_space = ctx.format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment = true },
            .image_sharing_mode = if (concurrent) .concurrent else .exclusive,
            .queue_family_index_count = if (concurrent) 2 else 0,
            .p_queue_family_indices = &.{ ctx.graphics_queue_index, ctx.present_queue_index },
            .pre_transform = if (capabilities.supported_transforms.identity_khr) .{ .identity_khr = true } else .{ .inherit_khr = true },
            .composite_alpha = if (capabilities.supported_composite_alpha.opaque_khr) .{ .opaque_khr = true } else .{ .inherit_khr = true },
            .present_mode = .fifo_khr,
            .clipped = .true,
        }, null);
        errdefer device.destroySwapchainKHR(handle, null);

        const images = try device.getSwapchainImagesAllocKHR(handle, gpa);
        errdefer gpa.free(images);

        const image_views = try gpa.alloc(vk.ImageView, images.len);
        errdefer gpa.free(image_views);
        var image_views_created: usize = 0;
        errdefer for (image_views[0..image_views_created]) |v| device.destroyImageView(v, null);
        for (images, image_views) |image, *view| {
            view.* = try device.createImageView(&.{
                .image = image,
                .view_type = .@"2d",
                .format = ctx.format.format,
                .components = .{
                    .r = .identity,
                    .g = .identity,
                    .b = .identity,
                    .a = .identity,
                },
                .subresource_range = .{
                    .aspect_mask = .{ .color = true },
                    .base_mip_level = 0,
                    .level_count = 1,
                    .base_array_layer = 0,
                    .layer_count = 1,
                },
            }, null);
            image_views_created += 1;
        }

        const framebuffers = try gpa.alloc(vk.Framebuffer, image_views.len);
        errdefer gpa.free(framebuffers);
        var framebuffers_created: usize = 0;
        errdefer for (framebuffers[0..framebuffers_created]) |fb| device.destroyFramebuffer(fb, null);
        for (image_views, framebuffers) |view, *framebuffer| {
            framebuffer.* = try device.createFramebuffer(&.{
                .render_pass = ctx.render_pass,
                .attachment_count = 1,
                .p_attachments = &.{view},
                .width = extent.width,
                .height = extent.height,
                .layers = 1,
            }, null);
            framebuffers_created += 1;
        }

        const render_finished_semaphores = try gpa.alloc(vk.Semaphore, images.len);
        errdefer gpa.free(render_finished_semaphores);
        var semaphores_created: usize = 0;
        errdefer for (render_finished_semaphores[0..semaphores_created]) |sem| device.destroySemaphore(sem, null);
        for (render_finished_semaphores) |*semaphore| {
            semaphore.* = try device.createSemaphore(&.{}, null);
            semaphores_created += 1;
        }

        return .{
            .handle = handle,
            .extent = extent,
            .images = images,
            .image_views = image_views,
            .framebuffers = framebuffers,
            .render_finished_semaphores = render_finished_semaphores,
        };
    }

    pub fn deinit(self: *Swapchain, gpa: std.mem.Allocator, device: vk.DeviceProxy) void {
        for (self.render_finished_semaphores) |semaphore| device.destroySemaphore(semaphore, null);
        gpa.free(self.render_finished_semaphores);
        for (self.framebuffers) |framebuffer| device.destroyFramebuffer(framebuffer, null);
        gpa.free(self.framebuffers);
        for (self.image_views) |image_view| device.destroyImageView(image_view, null);
        gpa.free(self.image_views);
        gpa.free(self.images);
        device.destroySwapchainKHR(self.handle, null);
    }
};

const CreateInstanceError = vk.BaseWrapper.EnumerateInstanceLayerPropertiesAllocError || std.mem.Allocator.Error ||
    vk.BaseWrapper.EnumerateInstanceExtensionPropertiesAllocError || vk.BaseWrapper.CreateInstanceError;

fn createInstance(
    allocator: std.mem.Allocator,
    vkb: vk.BaseWrapper,
) CreateInstanceError!struct {
    vk.InstanceWrapper,
    vk.Instance,
} {
    var enabled_layers: std.ArrayList([*:0]const u8) = .empty;
    defer enabled_layers.deinit(allocator);

    const layers = try vkb.enumerateInstanceLayerPropertiesAlloc(allocator);
    defer allocator.free(layers);
    for (layers) |layer| {
        const name = std.mem.sliceTo(&layer.layer_name, 0);
        if (std.mem.eql(u8, name, "VK_LAYER_KHRONOS_validation")) {
            try enabled_layers.append(allocator, "VK_LAYER_KHRONOS_validation");
        }
    }

    var enabled_extensions: std.ArrayList([*:0]const u8) = .empty;
    defer enabled_extensions.deinit(allocator);
    try enabled_extensions.appendSlice(allocator, wio.getRequiredVulkanInstanceExtensions());

    var has_portability = false;
    const extensions = try vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(extensions);
    for (extensions) |extension| {
        const name = std.mem.sliceTo(&extension.extension_name, 0);
        if (std.mem.eql(u8, name, "VK_KHR_portability_enumeration")) {
            try enabled_extensions.append(allocator, "VK_KHR_portability_enumeration");
            has_portability = true;
        }
    }

    const handle = try vkb.createInstance(
        &.{
            .flags = .{ .enumerate_portability_khr = has_portability },
            .p_application_info = &.{
                .application_version = 0,
                .engine_version = 0,
                .api_version = @bitCast(vk.API_VERSION_1_2),
            },
            .enabled_layer_count = @intCast(enabled_layers.items.len),
            .pp_enabled_layer_names = enabled_layers.items.ptr,
            .enabled_extension_count = @intCast(enabled_extensions.items.len),
            .pp_enabled_extension_names = enabled_extensions.items.ptr,
        },
        null,
    );

    const vki: vk.InstanceWrapper = .load(handle, vkb.dispatch.vkGetInstanceProcAddr.?);

    return .{ vki, handle };
}

const CreateSurfaceError = error{ OutOfHostMemory, OutOfDeviceMemory, Unknown, ValidationFailure, NativeWindowInUse, Unexpected };

fn createSurface(window_ptr: *wio.Window, instance: vk.InstanceProxy) CreateSurfaceError!vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;

    try window_ptr.vkCreateSurface(@intFromPtr(instance.handle), null, @ptrCast(&surface));

    return surface;
}

const ChooseSurfaceFormatError = vk.InstanceProxy.GetPhysicalDeviceSurfaceFormatsAllocKHRError;

fn chooseSurfaceFormat(
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxy,
    physical_device: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) ChooseSurfaceFormatError!vk.SurfaceFormatKHR {
    const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(formats);
    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            return format;
        }
    }
    return formats[0];
}

const CreateRenderPassError = vk.DeviceProxy.CreateRenderPassError;

fn createRenderPass(device: vk.DeviceProxy, surface_format: vk.SurfaceFormatKHR) CreateRenderPassError!vk.RenderPass {
    return try device.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = &.{.{
            .format = surface_format.format,
            .samples = .{ .@"1" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .undefined,
            .final_layout = .present_src_khr,
        }},
        .subpass_count = 1,
        .p_subpasses = &.{.{
            .pipeline_bind_point = .graphics,
            .color_attachment_count = 1,
            .p_color_attachments = &.{.{
                .attachment = 0,
                .layout = .color_attachment_optimal,
            }},
        }},
        .dependency_count = 1,
        .p_dependencies = &.{.{
            .src_subpass = vk.SUBPASS_EXTERNAL,
            .dst_subpass = 0,
            .src_stage_mask = .{ .color_attachment_output = true },
            .dst_stage_mask = .{ .color_attachment_output = true },
            .dst_access_mask = .{ .color_attachment_write = true },
        }},
    }, null);
}

const CreateGraphicsPipelineError = vk.DeviceProxy.CreateShaderModuleError ||
    vk.DeviceProxy.CreatePipelineLayoutError || vk.DeviceProxy.CreateGraphicsPipelinesError;

fn createGraphicsPipeline(device: vk.DeviceProxy, render_pass: vk.RenderPass) CreateGraphicsPipelineError!struct { vk.PipelineLayout, vk.Pipeline } {
    const vertex_code = @embedFile("vertex");
    const fragment_code = @embedFile("fragment");

    const vertex_module = try device.createShaderModule(
        &.{
            .code_size = vertex_code.len,
            .p_code = @ptrCast(@alignCast(vertex_code)),
        },
        null,
    );
    defer device.destroyShaderModule(vertex_module, null);

    const fragment_module = try device.createShaderModule(
        &.{
            .code_size = fragment_code.len,
            .p_code = @ptrCast(@alignCast(fragment_code)),
        },
        null,
    );
    defer device.destroyShaderModule(fragment_module, null);

    const pipeline_layout = try device.createPipelineLayout(&.{}, null);
    errdefer device.destroyPipelineLayout(pipeline_layout, null);
    var pipeline: vk.Pipeline = undefined;

    _ = try device.createGraphicsPipelines(
        .null_handle,
        &.{.{
            .stage_count = 2,
            .p_stages = &.{
                .{ .stage = .{ .vertex = true }, .module = vertex_module, .p_name = "main" },
                .{ .stage = .{ .fragment = true }, .module = fragment_module, .p_name = "main" },
            },
            .p_vertex_input_state = &.{},
            .p_input_assembly_state = &.{
                .topology = .triangle_list,
                .primitive_restart_enable = .false,
            },
            .p_viewport_state = &.{
                .viewport_count = 1,
                .scissor_count = 1,
            },
            .p_rasterization_state = &.{
                .depth_clamp_enable = .false,
                .rasterizer_discard_enable = .false,
                .polygon_mode = .fill,
                .cull_mode = .{ .back = true },
                .front_face = .clockwise,
                .depth_bias_enable = .false,
                .depth_bias_constant_factor = 0,
                .depth_bias_clamp = 0,
                .depth_bias_slope_factor = 0,
                .line_width = 1,
            },
            .p_multisample_state = &.{
                .sample_shading_enable = .false,
                .rasterization_samples = .{ .@"1" = true },
                .min_sample_shading = 1,
                .alpha_to_coverage_enable = .false,
                .alpha_to_one_enable = .false,
            },
            .p_color_blend_state = &.{
                .logic_op_enable = .false,
                .logic_op = .copy,
                .attachment_count = 1,
                .p_attachments = &.{.{
                    .blend_enable = .true,
                    .src_color_blend_factor = .src_alpha,
                    .dst_color_blend_factor = .one_minus_src_alpha,
                    .color_blend_op = .add,
                    .src_alpha_blend_factor = .one,
                    .dst_alpha_blend_factor = .zero,
                    .alpha_blend_op = .add,
                    .color_write_mask = .{ .r = true, .g = true, .b = true, .a = true },
                }},
                .blend_constants = .{ 0, 0, 0, 0 },
            },
            .p_dynamic_state = &.{
                .dynamic_state_count = 2,
                .p_dynamic_states = &.{ .viewport, .scissor },
            },
            .layout = pipeline_layout,
            .render_pass = render_pass,
            .subpass = 0,
            .base_pipeline_index = -1,
        }},
        null,
        (&pipeline)[0..1],
    );

    return .{ pipeline_layout, pipeline };
}

const CreateCommandBufferError = vk.DeviceProxy.CreateCommandPoolError || vk.DeviceProxy.AllocateCommandBuffersError;

fn createCommandBuffer(device: vk.DeviceProxy, graphics_queue_index: u32) CreateCommandBufferError!struct { vk.CommandPool, vk.CommandBuffer } {
    const command_pool = try device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer = true },
        .queue_family_index = graphics_queue_index,
    }, null);
    errdefer device.destroyCommandPool(command_pool, null);

    var command_buffer: vk.CommandBuffer = undefined;

    try device.allocateCommandBuffers(
        &.{
            .command_pool = command_pool,
            .level = .primary,
            .command_buffer_count = 1,
        },
        (&command_buffer)[0..1],
    );

    return .{ command_pool, command_buffer };
}

const CreateSyncObjectsError = vk.DeviceProxy.CreateSemaphoreError || vk.DeviceProxy.CreateFenceError;

fn createSyncObjects(device: vk.DeviceProxy) CreateSyncObjectsError!struct { vk.Semaphore, vk.Fence } {
    const image_available_semaphore = try device.createSemaphore(
        &.{},
        null,
    );
    errdefer device.destroySemaphore(image_available_semaphore, null);

    const in_flight_fence = try device.createFence(
        &.{
            .flags = .{ .signaled = true },
        },
        null,
    );

    return .{ image_available_semaphore, in_flight_fence };
}

const PhysicalDeviceChoice = struct {
    handle: vk.PhysicalDevice,
    graphics_queue_index: u32,
    present_queue_index: u32,
};

const PickPhysicalDeviceError = vk.InstanceProxy.EnumeratePhysicalDevicesAllocError ||
    vk.InstanceProxy.EnumerateDeviceExtensionPropertiesAllocError || vk.InstanceProxy.GetPhysicalDeviceSurfaceFormatsKHRError ||
    vk.InstanceProxy.GetPhysicalDeviceSurfacePresentModesKHRError || std.mem.Allocator.Error ||
    vk.InstanceProxy.GetPhysicalDeviceSurfaceSupportKHRError || error{NoSuitableDevice};

fn pickPhysicalDevice(
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxy,
    surface: vk.SurfaceKHR,
) PickPhysicalDeviceError!PhysicalDeviceChoice {
    const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_devices);

    for (physical_devices) |handle| {
        var has_swapchain = false;
        const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(handle, null, allocator);
        defer allocator.free(extensions);
        for (extensions) |extension| {
            const name = std.mem.sliceTo(&extension.extension_name, 0);
            if (std.mem.eql(u8, name, "VK_KHR_swapchain")) {
                has_swapchain = true;
            }
        }
        if (!has_swapchain) continue;

        var surface_format_count: u32 = 0;
        _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(handle, surface, &surface_format_count, null);
        var present_mode_count: u32 = 0;
        _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(handle, surface, &present_mode_count, null);
        if (surface_format_count == 0 or present_mode_count == 0) continue;

        var graphics_index: ?u32 = null;
        var present_index: ?u32 = null;
        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, allocator);
        defer allocator.free(queue_families);
        for (queue_families, 0..) |queue_family, i| {
            const index: u32 = @intCast(i);
            if (graphics_index == null and queue_family.queue_flags.graphics) {
                graphics_index = index;
            }
            if (present_index == null and try instance.getPhysicalDeviceSurfaceSupportKHR(handle, index, surface) == .true) {
                present_index = index;
            }
        }

        return .{
            .handle = handle,
            .graphics_queue_index = graphics_index orelse continue,
            .present_queue_index = present_index orelse continue,
        };
    }

    return error.NoSuitableDevice;
}

const CreateLogicalDeviceError = std.mem.Allocator.Error || vk.InstanceProxy.EnumerateDeviceExtensionPropertiesAllocError ||
    vk.InstanceProxy.CreateDeviceError;

fn createLogicalDevice(
    allocator: std.mem.Allocator,
    instance: vk.InstanceProxy,
    vkd_ptr: *vk.DeviceWrapper,
    choice: PhysicalDeviceChoice,
) CreateLogicalDeviceError!vk.DeviceProxy {
    var enabled_extensions: std.ArrayList([*:0]const u8) = .empty;
    defer enabled_extensions.deinit(allocator);
    try enabled_extensions.append(allocator, "VK_KHR_swapchain");

    const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(choice.handle, null, allocator);
    defer allocator.free(extensions);
    for (extensions) |extension| {
        const name = std.mem.sliceTo(&extension.extension_name, 0);
        if (std.mem.eql(u8, name, "VK_KHR_portability_subset")) {
            try enabled_extensions.append(allocator, "VK_KHR_portability_subset");
        }
    }

    const handle = try instance.createDevice(choice.handle, &.{
        .queue_create_info_count = if (choice.graphics_queue_index == choice.present_queue_index) 1 else 2,
        .p_queue_create_infos = &.{
            .{
                .queue_family_index = choice.graphics_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
            .{
                .queue_family_index = choice.present_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
        },
        .enabled_extension_count = @intCast(enabled_extensions.items.len),
        .pp_enabled_extension_names = enabled_extensions.items.ptr,
        .p_enabled_features = &.{},
    }, null);

    vkd_ptr.* = .load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    return .init(handle, vkd_ptr);
}
