# wio

wio is a platform abstraction library. It provides:

- window management and events
- clipboard access
- alert dialogs
- joystick input
- audio
- OpenGL and Vulkan WSI

## Getting started

wio follows the [Mach nominated Zig version][1].

The public API can be browsed in [src/wio.zig][2]. The [example][3] directory
contains a test program covering most features.

## Platform notes

### Windows

By default, wio embeds an [application manifest][4] for proper functionality.
When using a custom manifest, set the `win32_manifest` build option to false.

If audio is enabled, wio initializes COM with options `COINIT_MULTITHREADED`
and `COINIT_DISABLE_OLE1DDE`.

### macOS

Versions 10.15 and above are supported.

The example directory contains an application bundle, which can be adapted by
changing the `CFBundleExecutable` and `CFBundleName` values in Info.plist.

### Unix

Unix-like systems support different backends in the same executable, with the
most appropriate being chosen at runtime. To restrict the available choices,
set the `unix_backends` build option to a comma-separated list.

For X11, the following libraries are loaded:

- `libX11.so.6`
- `libXcursor.so.1`
- `libGL.so.1` (if OpenGL is enabled)

For Wayland, the following libraries are loaded:

- `libwayland-client.so.0`
- `libxkbcommon.so.0`
- `libdecor-0.so.0`
- `libwayland-egl.so.1` (if OpenGL is enabled)
- `libEGL.so.1` (if OpenGL is enabled)

Additionally, the following libraries are loaded for Linux:

- `libudev.so.1` (if joysticks are enabled)
- `libpulse.so.0` (if audio is enabled)

When building a project that uses wio, you may pass any of the following flags
to `zig build` to attempt to find the relevant libraries with pkg-config:

- `-fsys=x11`
- `-fsys=gl`
- `-fsys=wayland`
- `-fsys=egl`
- `-fsys=vulkan`
- `-fsys=udev`
- `-fsys=pulse`

## Platform-specific API

The following variables and fields may be considered part of the public API
when targeting a given platform:

### Windows

- `Window.backend.window` is the Win32 `HWND`

### macOS

- `Window.backend.window` is the AppKit `NSWindow*`

### Unix

`wio.backend.active` is an enum describing the backend in use:

#### `.x11`

- `wio.backend.x11.display` is the Xlib display
- `Window.backend.x11.window` is the Xlib window

#### `.wayland`

- `wio.backend.wayland.display` is the Wayland `wl_display*`
- `Window.backend.wayland.surface` is the Wayland `wl_surface*`


[1]: https://machengine.org/docs/nominated-zig/
[2]: https://github.com/ypsvlq/wio/blob/master/src/wio.zig
[3]: https://github.com/ypsvlq/wio/tree/master/example
[4]: https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests
