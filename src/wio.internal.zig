const std = @import("std");
const wio = @import("wio.zig");

pub var allocator: std.mem.Allocator = undefined;
pub var init_options: wio.InitOptions = undefined;

pub const EventQueue = struct {
    events: std.fifo.LinearFifo(wio.Event, .Dynamic),

    pub fn init() EventQueue {
        return .{ .events = .init(allocator) };
    }

    pub fn deinit(self: *EventQueue) void {
        self.events.deinit();
    }

    pub fn push(self: *EventQueue, event: wio.Event) void {
        self.events.writeItem(event) catch {};
    }

    pub fn pop(self: *EventQueue) ?wio.Event {
        return self.events.readItem();
    }
};
