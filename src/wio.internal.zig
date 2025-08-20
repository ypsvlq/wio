const std = @import("std");
const wio = @import("wio.zig");

pub var allocator: std.mem.Allocator = undefined;
pub var init_options: wio.InitOptions = undefined;

pub const EventQueue = struct {
    events: std.ArrayList(wio.Event) = .empty,
    head: usize = 0,

    pub fn init() EventQueue {
        return .{};
    }

    pub fn deinit(self: *EventQueue) void {
        self.events.deinit(allocator);
    }

    pub fn push(self: *EventQueue, event: wio.Event) void {
        if (self.head != 0) {
            self.events.replaceRangeAssumeCapacity(0, self.head, &.{});
            self.head = 0;
        }

        switch (std.meta.activeTag(event)) {
            .draw, .framebuffer => |tag| {
                for (self.events.items, 0..) |item, i| {
                    if (item == tag) {
                        _ = self.events.orderedRemove(i);
                        break;
                    }
                }
            },
            else => {},
        }

        self.events.append(allocator, event) catch {};
    }

    pub fn pop(self: *EventQueue) ?wio.Event {
        if (self.head == self.events.items.len) return null;
        defer self.head += 1;
        return self.events.items[self.head];
    }
};
