# wio

wio is a platform abstraction library, providing:

- window management and events
- clipboard access
- alert dialogs
- joystick input
- audio
- OpenGL and Vulkan WSI

## Getting started

The public API can be browsed in [src/wio.zig][1]. The [example][2] directory
contains a test program covering most features.

The `features` build option can be used to disable some functions, or enable
Vulkan support.

## Platform support

### Tier 1

- Windows
- macOS (10.13+)
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

wio embeds an [application manifest][3] by default. To use a custom manifest,
set the `win32_manifest` build option to `false`.

If audio is enabled, wio initializes COM with options `COINIT_MULTITHREADED`
and `COINIT_DISABLE_OLE1DDE`.

### macOS

The example directory contains an application bundle, which can be adapted by
changing the `CFBundleExecutable` and `CFBundleName` values in Info.plist.

### Unix

Unix-like systems support different backends in the same executable. By default
all backends are enabled, the `unix_backends` build option can be used to
limit the choices.

When building a project that uses wio, passing `-fsys=wio` to `zig build` will
link libraries explicitly (rather than using `dlopen`).

It is recommended to expose `unix_backends` in your build script and document
the existance of `-fsys=wio`, to assist with packaging your project.

The following libraries are loaded for the X11 backend:

- `libX11.so.6`
- `libXcursor.so.1`
- `libGL.so.1` (if OpenGL is enabled)

The following libraries are loaded for the Wayland backend:

- `libwayland-client.so.0`
- `libxkbcommon.so.0`
- `libdecor-0.so.0`
- `libwayland-egl.so.1` (if OpenGL is enabled)
- `libEGL.so.1` (if OpenGL is enabled)

The following libraries are loaded under Linux:

- `libudev.so.1` (if joysticks are enabled)
- `libpulse.so.0` (if audio is enabled)

### WebAssembly

If OpenGL is enabled, wio imports `createContext` and `makeContextCurrent`
from the `gl` module. The example directory contains bindings to WebGL 1.

`glGetProcAddress` always returns null.

## Platform-specific API

The following variables and fields may be considered part of the public API
for a given platform:

### Windows

- `Window.backend.window` is the Win32 `HWND`
- `wio.backend.win32` is a set of Win32 API bindings

### macOS

- `Window.backend.window` is the AppKit `NSWindow`

### Unix

`wio.backend.active` is an enum variable specifying the backend in use:

#### `.x11`

- `wio.backend.x11.display` is the Xlib display
- `Window.backend.x11.window` is the Xlib window

#### `.wayland`

- `wio.backend.wayland.display` is the Wayland `wl_display`
- `Window.backend.wayland.surface` is the Wayland `wl_surface`


[1]: https://github.com/ypsvlq/wio/blob/master/src/wio.zig
[2]: https://github.com/ypsvlq/wio/tree/master/example
[3]: https://learn.microsoft.com/en-us/windows/win32/sbscs/application-manifests
