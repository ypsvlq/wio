# wio

wio is a window system abstraction library.

## Getting started

wio follows the [Mach nominated Zig version][1].

The public API can be browsed in [src/wio.zig][2]. The [example][3] directory
contains a test program covering most features.

## Platform-specific API

The following variables and fields may be considered part of the public API
when targeting a given platform:

### Windows

- `Window.backend.window` is the Win32 `HWND`

### macOS

- `Window.backend.window` is the AppKit `NSWindow*`

### X11

- `wio.backend.display` is the Xlib display
- `Window.backend.window` is the Xlib window


[1]: https://machengine.org/docs/nominated-zig/
[2]: https://github.com/ypsvlq/wio/blob/master/src/wio.zig
[3]: https://github.com/ypsvlq/wio/tree/master/example
