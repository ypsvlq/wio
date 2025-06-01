const std = @import("std");
const wio = @import("wio.zig");

pub var allocator: std.mem.Allocator = undefined;
pub var init_options: wio.InitOptions = undefined;
