pub extern "wio" fn write([*]const u8, usize) void;
pub extern "wio" fn flush() void;
pub extern "wio" fn shift() u32;
pub extern "wio" fn shiftFloat() f32;
pub extern "wio" fn setCursor(u8) void;
pub extern "wio" fn setCursorMode(u8) void;
pub extern "wio" fn messageBox([*]const u8, usize) void;
pub extern "wio" fn setClipboardText([*]const u8, usize) void;
