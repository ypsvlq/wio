# wio

wio is a platform abstraction library. It provides:

- window management and events
- clipboard access
- alert dialogs
- joystick input
- audio
- OpenGL and Vulkan WSI

## Getting started

The public API can be browsed in [src/wio.zig][1]. The [example][2] directory
contains a test program covering most features.

The `features` build option can be used to disable optional functionality,
or enable Vulkan support (which is not available on all platforms).

## Platform support

### Tier 1

- Windows
- macOS (10.15+)
- Linux
- WebAssembly

### Tier 2

Not actively tested, but most code is shared with tier 1 targets.

- OpenBSD
- NetBSD
- FreeBSD
- DragonFlyBSD
- illumos

### Tier 3

Not actively tested.

- Haiku

## Platform notes

### Windows

By default, wio embeds an [application manifest][3] for proper functionality.
When using a custom manifest, set the `win32_manifest` build option to false.

If audio is enabled, wio initializes COM with options `COINIT_MULTITHREADED`
and `COINIT_DISABLE_OLE1DDE`.

### macOS

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

When building a project that uses wio, passing `-fsys=wio` to `zig build` will
link libraries explicitly (instead of using dlopen).

## Platform-specific API

The following variables and fields may be considered part of the public API
when targeting a given platform:

### Windows

- `Window.backend.window` is the Win32 `HWND`
- `wio.backend.win32` is the Win32 API bindings

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


[1]: https://github.com/ypsvlq/wio/blob/master/src/wio.zig
[2]: https://github.com/ypsvlq/wio/tree/master/example
[3]: https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests
