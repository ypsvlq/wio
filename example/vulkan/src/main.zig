const std = @import("std");
const wio = @import("wio");
const vk = @import("vulkan");

var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
const allocator = gpa.allocator();

var window: wio.Window = undefined;
var size = wio.Size{ .width = 640, .height = 480 };
var visible = true;

const apis: []const vk.ApiInfo = &.{
    vk.features.version_1_0,
    vk.extensions.khr_surface,
    vk.extensions.khr_swapchain,
};
var vkb: vk.BaseWrapper(apis) = undefined;

pub fn main() !void {
    try wio.init(allocator, .{});
    window = try wio.createWindow(.{ .title = "Vulkan", .size = size, .scale = 1 });

    vkb = try .load(@as(*const fn (vk.Instance, [*:0]const u8) ?*const fn () void, @ptrCast(&wio.vkGetInstanceProcAddr)));
    try createInstance();
    try createSurface();
    try pickPhysicalDevice();
    try createLogicalDevice();
    try chooseSurfaceFormat();
    try createRenderPass();
    try createGraphicsPipeline();
    try createCommandBuffer();
    try createSyncObjects();

    return wio.run(loop);
}

var vki: vk.InstanceWrapper(apis) = undefined;
var instance: vk.InstanceProxy(apis) = undefined;

fn createInstance() !void {
    var enabled_extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer enabled_extensions.deinit();
    try enabled_extensions.appendSlice(wio.getVulkanExtensions());

    var has_portability = false;
    const extensions = try vkb.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(extensions);
    for (extensions) |extension| {
        const name = std.mem.sliceTo(&extension.extension_name, 0);
        if (std.mem.eql(u8, name, "VK_KHR_portability_enumeration")) {
            try enabled_extensions.append("VK_KHR_portability_enumeration");
            has_portability = true;
        }
    }

    const handle = try vkb.createInstance(&.{
        .flags = .{ .enumerate_portability_bit_khr = has_portability },
        .p_application_info = &.{
            .application_version = 0,
            .engine_version = 0,
            .api_version = vk.API_VERSION_1_1,
        },
        .enabled_extension_count = @intCast(enabled_extensions.items.len),
        .pp_enabled_extension_names = enabled_extensions.items.ptr,
    }, null);

    vki = try .load(handle, vkb.dispatch.vkGetInstanceProcAddr);
    instance = .init(handle, &vki);
}

var surface: vk.SurfaceKHR = undefined;

fn createSurface() !void {
    const result: vk.Result = @enumFromInt(window.createSurface(@intFromEnum(instance.handle), null, @ptrCast(&surface)));
    if (result != .success) return error.Unknown;
}

var physical_device: vk.PhysicalDevice = undefined;
var graphics_queue_index: u32 = undefined;
var present_queue_index: u32 = undefined;

fn pickPhysicalDevice() !void {
    const physical_devices = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(physical_devices);

    for (physical_devices) |handle| {
        var has_swapchain = false;
        const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(handle, null, allocator);
        defer allocator.free(extensions);
        for (extensions) |extension| {
            if (std.mem.eql(u8, std.mem.sliceTo(&extension.extension_name, 0), "VK_KHR_swapchain")) {
                has_swapchain = true;
            }
        }
        if (!has_swapchain) continue;

        var surface_format_count: u32 = 0;
        _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(handle, surface, &surface_format_count, null);
        var present_mode_count: u32 = 0;
        _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(handle, surface, &present_mode_count, null);
        if (surface_format_count == 0 or present_mode_count == 0) continue;

        var has_graphics = false;
        var has_present = false;
        const queue_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, allocator);
        defer allocator.free(queue_families);
        for (queue_families, 0..) |queue_family, i| {
            const index: u32 = @intCast(i);
            if (!has_graphics and queue_family.queue_flags.graphics_bit) {
                graphics_queue_index = index;
                has_graphics = true;
            }
            if (!has_present and try instance.getPhysicalDeviceSurfaceSupportKHR(handle, index, surface) == vk.TRUE) {
                present_queue_index = index;
                has_present = true;
            }
        }
        if (!has_graphics or !has_present) continue;

        physical_device = handle;
        return;
    }

    return error.NoSuitableDevice;
}

var vkd: vk.DeviceWrapper(apis) = undefined;
var device: vk.DeviceProxy(apis) = undefined;
var graphics_queue: vk.Queue = undefined;
var present_queue: vk.Queue = undefined;

fn createLogicalDevice() !void {
    var enabled_extensions = std.ArrayList([*:0]const u8).init(allocator);
    defer enabled_extensions.deinit();
    try enabled_extensions.append("VK_KHR_swapchain");

    const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device, null, allocator);
    defer allocator.free(extensions);
    for (extensions) |extension| {
        const name = std.mem.sliceTo(&extension.extension_name, 0);
        if (std.mem.eql(u8, name, "VK_KHR_portability_subset")) {
            try enabled_extensions.append("VK_KHR_portability_subset");
        }
    }

    const handle = try instance.createDevice(physical_device, &.{
        .queue_create_info_count = if (graphics_queue_index == present_queue_index) 1 else 2,
        .p_queue_create_infos = &.{
            .{
                .queue_family_index = graphics_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
            .{
                .queue_family_index = present_queue_index,
                .queue_count = 1,
                .p_queue_priorities = &.{1},
            },
        },
        .enabled_extension_count = @intCast(enabled_extensions.items.len),
        .pp_enabled_extension_names = enabled_extensions.items.ptr,
    }, null);

    vkd = try .load(handle, vki.dispatch.vkGetDeviceProcAddr);
    device = .init(handle, &vkd);

    graphics_queue = device.getDeviceQueue(graphics_queue_index, 0);
    present_queue = device.getDeviceQueue(present_queue_index, 0);
}

var surface_format: vk.SurfaceFormatKHR = undefined;

fn chooseSurfaceFormat() !void {
    const formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(formats);
    for (formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            surface_format = format;
            return;
        }
    }
    surface_format = formats[0];
}

var render_pass: vk.RenderPass = undefined;

fn createRenderPass() !void {
    render_pass = try device.createRenderPass(&.{
        .attachment_count = 1,
        .p_attachments = &.{.{
            .format = surface_format.format,
            .samples = .{ .@"1_bit" = true },
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
            .src_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_stage_mask = .{ .color_attachment_output_bit = true },
            .dst_access_mask = .{ .color_attachment_write_bit = true },
        }},
    }, null);
}

var pipeline_layout: vk.PipelineLayout = undefined;
var pipeline: vk.Pipeline = undefined;

fn createGraphicsPipeline() !void {
    const vertex_code = @embedFile("shader.vert.spv");
    const fragment_code = @embedFile("shader.frag.spv");

    const vertex_module = try device.createShaderModule(&.{ .code_size = vertex_code.len, .p_code = @alignCast(@ptrCast(vertex_code)) }, null);
    defer device.destroyShaderModule(vertex_module, null);
    const fragment_module = try device.createShaderModule(&.{ .code_size = fragment_code.len, .p_code = @alignCast(@ptrCast(fragment_code)) }, null);
    defer device.destroyShaderModule(fragment_module, null);

    pipeline_layout = try device.createPipelineLayout(&.{}, null);
    _ = try device.createGraphicsPipelines(.null_handle, 1, &.{.{
        .stage_count = 2,
        .p_stages = &.{
            .{ .stage = .{ .vertex_bit = true }, .module = vertex_module, .p_name = "main" },
            .{ .stage = .{ .fragment_bit = true }, .module = fragment_module, .p_name = "main" },
        },
        .p_vertex_input_state = &.{},
        .p_input_assembly_state = &.{
            .topology = .triangle_list,
            .primitive_restart_enable = vk.FALSE,
        },
        .p_viewport_state = &.{
            .viewport_count = 1,
            .scissor_count = 1,
        },
        .p_rasterization_state = &.{
            .depth_clamp_enable = vk.FALSE,
            .rasterizer_discard_enable = vk.FALSE,
            .polygon_mode = .fill,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
            .line_width = 1,
        },
        .p_multisample_state = &.{
            .sample_shading_enable = vk.FALSE,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        },
        .p_color_blend_state = &.{
            .logic_op_enable = vk.FALSE,
            .logic_op = .copy,
            .attachment_count = 1,
            .p_attachments = &.{.{
                .blend_enable = vk.TRUE,
                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
                .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
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
    }}, null, @ptrCast(&pipeline));
}

var command_pool: vk.CommandPool = undefined;
var command_buffer: vk.CommandBuffer = undefined;

fn createCommandBuffer() !void {
    command_pool = try device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = graphics_queue_index,
    }, null);

    try device.allocateCommandBuffers(&.{
        .command_pool = command_pool,
        .level = .primary,
        .command_buffer_count = 1,
    }, @ptrCast(&command_buffer));
}

var image_available_semaphore: vk.Semaphore = undefined;
var in_flight_fence: vk.Fence = undefined;

fn createSyncObjects() !void {
    image_available_semaphore = try device.createSemaphore(&.{}, null);
    in_flight_fence = try device.createFence(&.{ .flags = .{ .signaled_bit = true } }, null);
}

var swapchain: vk.SwapchainKHR = .null_handle;
var images: []vk.Image = &.{};
var image_views: []vk.ImageView = &.{};
var framebuffers: []vk.Framebuffer = &.{};
var render_finished_semaphores: []vk.Semaphore = &.{};

fn recreateSwapchain() !void {
    try device.deviceWaitIdle();
    destroySwapchain();

    const capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);
    swapchain = try device.createSwapchainKHR(&.{
        .surface = surface,
        .min_image_count = if (capabilities.max_image_count == capabilities.min_image_count) capabilities.min_image_count else capabilities.min_image_count + 1,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = .{ .width = size.width, .height = size.height },
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = if (graphics_queue_index != present_queue_index) .concurrent else .exclusive,
        .queue_family_index_count = if (graphics_queue_index != present_queue_index) 2 else 0,
        .p_queue_family_indices = &.{ graphics_queue_index, present_queue_index },
        .pre_transform = capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = .fifo_khr,
        .clipped = vk.TRUE,
    }, null);

    images = try device.getSwapchainImagesAllocKHR(swapchain, allocator);

    image_views = try allocator.alloc(vk.ImageView, images.len);
    for (images, image_views) |image, *view| {
        view.* = try device.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = surface_format.format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
    }

    framebuffers = try allocator.alloc(vk.Framebuffer, image_views.len);
    for (image_views, framebuffers) |view, *framebuffer| {
        framebuffer.* = try device.createFramebuffer(&.{
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = &.{view},
            .width = size.width,
            .height = size.height,
            .layers = 1,
        }, null);
    }

    render_finished_semaphores = try allocator.alloc(vk.Semaphore, images.len);
    for (render_finished_semaphores) |*semaphore| {
        semaphore.* = try device.createSemaphore(&.{}, null);
    }
}

fn destroySwapchain() void {
    for (render_finished_semaphores) |semaphore| device.destroySemaphore(semaphore, null);
    allocator.free(render_finished_semaphores);
    for (framebuffers) |framebuffer| device.destroyFramebuffer(framebuffer, null);
    allocator.free(framebuffers);
    for (image_views) |image_view| device.destroyImageView(image_view, null);
    allocator.free(image_views);
    allocator.free(images);
    device.destroySwapchainKHR(swapchain, null);
}

fn recordCommandBuffer(image_index: u32) !void {
    const extent = vk.Extent2D{ .width = size.width, .height = size.height };

    try device.beginCommandBuffer(command_buffer, &.{});

    device.cmdBeginRenderPass(command_buffer, &.{
        .render_pass = render_pass,
        .framebuffer = framebuffers[image_index],
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
        .clear_value_count = 1,
        .p_clear_values = &.{.{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } }},
    }, .@"inline");

    device.cmdBindPipeline(command_buffer, .graphics, pipeline);

    device.cmdSetViewport(command_buffer, 0, 1, &.{.{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(size.width),
        .height = @floatFromInt(size.height),
        .min_depth = 0,
        .max_depth = 1,
    }});

    device.cmdSetScissor(command_buffer, 0, 1, &.{.{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    }});

    device.cmdDraw(command_buffer, 3, 1, 0, 0);

    device.cmdEndRenderPass(command_buffer);

    try device.endCommandBuffer(command_buffer);
}

fn drawFrame() !void {
    _ = try device.waitForFences(1, &.{in_flight_fence}, vk.TRUE, std.math.maxInt(u64));

    const image_index = (try device.acquireNextImageKHR(swapchain, std.math.maxInt(u64), image_available_semaphore, .null_handle)).image_index;
    try device.resetCommandBuffer(command_buffer, .{});
    try recordCommandBuffer(image_index);

    try device.resetFences(1, &.{in_flight_fence});
    try device.queueSubmit(
        graphics_queue,
        1,
        &.{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{image_available_semaphore},
            .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},
            .command_buffer_count = 1,
            .p_command_buffers = &.{command_buffer},
            .signal_semaphore_count = 1,
            .p_signal_semaphores = &.{render_finished_semaphores[image_index]},
        }},
        in_flight_fence,
    );

    _ = try device.queuePresentKHR(present_queue, &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{render_finished_semaphores[image_index]},
        .swapchain_count = 1,
        .p_swapchains = &.{swapchain},
        .p_image_indices = &.{image_index},
    });
}

fn loop() !bool {
    while (window.getEvent()) |event| {
        switch (event) {
            .close => {
                try device.deviceWaitIdle();
                destroySwapchain();
                device.destroyFence(in_flight_fence, null);
                device.destroySemaphore(image_available_semaphore, null);
                device.destroyCommandPool(command_pool, null);
                device.destroyPipeline(pipeline, null);
                device.destroyPipelineLayout(pipeline_layout, null);
                device.destroyRenderPass(render_pass, null);
                device.destroyDevice(null);
                instance.destroySurfaceKHR(surface, null);
                instance.destroyInstance(null);
                window.destroy();
                wio.deinit();
                _ = gpa.deinit();
                return false;
            },
            .framebuffer => |new_size| {
                size = new_size;
                try recreateSwapchain();
            },
            .visible => visible = true,
            .hidden => visible = false,
            else => {},
        }
    }

    if (visible) {
        drawFrame() catch |err| switch (err) {
            error.OutOfDateKHR => try recreateSwapchain(),
            else => return err,
        };
    }

    return true;
}
