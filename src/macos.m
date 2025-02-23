#import <Cocoa/Cocoa.h>
#include <IOKit/hid/IOHIDKeys.h>

extern void wioClose(void *);
extern void wioFocus(void *);
extern void wioUnfocus(void *);
extern void wioSize(void *, uint8_t, UInt16, UInt16, UInt16, UInt16);
extern void wioScale(void *, Float32);
extern void wioChars(void *, const char *);
extern void wioKey(void *, UInt16, UInt8);
extern void wioButtonPress(void *, UInt8);
extern void wioButtonRelease(void *, UInt8);
extern void wioMouse(void *, UInt16, UInt16);
extern void wioMouseRelative(void *, SInt16, SInt16);
extern void wioScroll(void *, Float32, Float32);
extern char *wioDupeClipboardText(const void *, const char *, size_t *);

const CFStringRef wioHIDDeviceUsagePageKey = CFSTR(kIOHIDDeviceUsagePageKey);
const CFStringRef wioHIDDeviceUsageKey = CFSTR(kIOHIDDeviceUsageKey);
const CFStringRef wioHIDVendorIDKey = CFSTR(kIOHIDVendorIDKey);
const CFStringRef wioHIDProductIDKey = CFSTR(kIOHIDProductIDKey);
const CFStringRef wioHIDVersionNumberKey = CFSTR(kIOHIDVersionNumberKey);
const CFStringRef wioHIDSerialNumberKey = CFSTR(kIOHIDSerialNumberKey);
const CFStringRef wioHIDProductKey = CFSTR(kIOHIDProductKey);

static NSString *string(const char *ptr, size_t len) {
    return [[NSString alloc] initWithBytes:ptr length:len encoding:NSUTF8StringEncoding];
}

static void warpCursor(NSWindow *window) {
    NSRect frame = [window frame];
    NSRect screen = [[NSScreen mainScreen] frame];
    CGWarpMouseCursorPosition(CGPointMake(CGRectGetMidX(frame), CGRectGetMaxY(screen) - CGRectGetMidY(frame)));
}

@interface ApplicationDelegate : NSObject <NSApplicationDelegate>
@end

@interface WindowDelegate : NSObject <NSWindowDelegate>
@end

@interface View : NSView
- (uint8_t)cursorMode;
@end

@implementation ApplicationDelegate

- (void)applicationDidFinishLaunching:notification {
    [NSApp stop:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:sender {
    for (NSWindow *window in [NSApp windows]) {
        id delegate = [window delegate];
        if ([delegate respondsToSelector:@selector(windowShouldClose:)]) {
            [delegate windowShouldClose:window];
        }
    }
    return NSTerminateCancel;
}

@end

@implementation WindowDelegate
{
    void *ptr;
    NSOpenGLContext *context;
}

- (instancetype)initWithPointer:(void*)value {
    self = [super init];
    ptr = value;
    return self;
}

- (void)setContext:value {
    context = value;
}

- (void)windowDidEnterFullScreen:notification {
    [[[notification object] contentView] updateTrackingAreas];
}

- (BOOL)windowShouldClose:sender {
    wioClose(ptr);
    return NO;
}

- (void)windowDidBecomeKey:notification {
    wioFocus(ptr);

    NSWindow *window = [notification object];
    View *view = [window contentView];
    if ([view cursorMode] == 2) {
        warpCursor(window);
    }
}

- (void)windowDidResignKey:notification {
    wioUnfocus(ptr);
}

- (void)windowDidEndLiveResize:notification {
    NSWindow *window = [notification object];
    View *view = [window contentView];
    NSRect rect = [view frame];
    NSRect framebuffer = [view convertRectToBacking:rect];

    if ([view cursorMode] == 2) {
        warpCursor(window);
    }

    uint8_t mode = 0;
    if ([window isZoomed])
        mode = 1;
    else if ([window styleMask] & NSWindowStyleMaskFullScreen)
        mode = 2;
    wioSize(ptr, mode, rect.size.width, rect.size.height, framebuffer.size.width, framebuffer.size.height);

    [context update];
}

@end

@implementation View
{
    void *ptr;
    NSTrackingArea *area;
    NSCursor *cursor;
    uint8_t cursorMode;
    BOOL cursorInside;
}

- (instancetype)initWithPointer:(void*)value {
    self = [super init];
    ptr = value;
    return self;
}

- (void)setCursor:value {
    cursor = value;
    [self updateTrackingAreas];
}

- (void)setCursorMode:(uint8_t)value {
    if (!!value != !!cursorMode) {
        if (cursorInside) value ? [NSCursor hide] : [NSCursor unhide];
    }
    cursorMode = value;
}

- (uint8_t)cursorMode {
    return cursorMode;
}

- (void)updateTrackingAreas {
    [self removeTrackingArea:area];
    area = [[NSTrackingArea alloc]
        initWithRect:[self frame]
        options:NSTrackingActiveInKeyWindow | NSTrackingCursorUpdate | NSTrackingMouseEnteredAndExited
        owner:self
        userInfo:nil];
    [self addTrackingArea:area];
    [super updateTrackingAreas];
}

- (void)cursorUpdate:event {
    [cursor set];
}

- (void)mouseEntered:event {
    if (!cursorInside && cursorMode != 0) [NSCursor hide];
    cursorInside = true;
}

- (void)mouseExited:event {
    if (cursorInside && cursorMode != 0) [NSCursor unhide];
    cursorInside = false;
}

- (void)keyDown:event {
    wioKey(ptr, [event keyCode], [event isARepeat]);
    wioChars(ptr, [[event characters] UTF8String]);
}

- (void)keyUp:event {
    wioKey(ptr, [event keyCode], 2);
}

- (void)flagsChanged:event {
    UInt16 key = [event keyCode];
    NSUInteger flag;
    switch (key) {
        case 0x36: flag = NX_DEVICERCMDKEYMASK; break;
        case 0x37: flag = NX_DEVICELCMDKEYMASK; break;
        case 0x38: flag = NX_DEVICELSHIFTKEYMASK; break;
        case 0x3A: flag = NX_DEVICELALTKEYMASK; break;
        case 0x3B: flag = NX_DEVICELCTLKEYMASK; break;
        case 0x3C: flag = NX_DEVICERSHIFTKEYMASK; break;
        case 0x3D: flag = NX_DEVICERALTKEYMASK; break;
        case 0x3E: flag = NX_DEVICERCTLKEYMASK; break;
        case 0x39:
            wioKey(ptr, key, 0);
            wioKey(ptr, key, 2);
            return;
        default: return;
    }
    wioKey(ptr, key, [event modifierFlags] & flag ? 0 : 2);
}

- (void)mouseDown:event {
    wioButtonPress(ptr, 0);
}

- (void)mouseUp:event {
    wioButtonRelease(ptr, 0);
}

- (void)rightMouseDown:event {
    wioButtonPress(ptr, 1);
}

- (void)rightMouseUp:event {
    wioButtonRelease(ptr, 1);
}

- (void)otherMouseDown:event {
    NSInteger button = [event buttonNumber];
    if (button < 5) wioButtonPress(ptr, button);
}

- (void)otherMouseUp:event {
    NSInteger button = [event buttonNumber];
    if (button < 5) wioButtonRelease(ptr, button);
}

- (void)mouseMoved:event {
    if (cursorMode == 2) {
        wioMouseRelative(ptr, [event deltaX], [event deltaY]);
        return;
    }
    NSPoint location = [event locationInWindow];
    NSRect frame = [self frame];
    location.y = frame.size.height - location.y - 1;
    if (location.x < 0 || location.y < 0 || location.x > frame.size.width || location.y > frame.size.height) return;
    wioMouse(ptr, location.x, location.y);
}

- (void)mouseDragged:event {
    [self mouseMoved:event];
}

- (void)rightMouseDragged:event {
    [self mouseMoved:event];
}

- (void)otherMouseDragged:event {
    [self mouseMoved:event];
}

- (void)scrollWheel:event {
    wioScroll(ptr, [event scrollingDeltaX], [event scrollingDeltaY]);
}

@end

void wioInit() {
    [NSApplication sharedApplication];
    [NSApp setDelegate:[[ApplicationDelegate alloc] init]];
    [[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:nil];
}

void wioRun(void) {
    [NSApp run];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];
}

void wioLoop(void) {
    NSEvent *event;
    do {
        event = [NSApp nextEventMatchingMask:NSEventMaskAny
            untilDate:nil
            inMode:NSDefaultRunLoopMode
            dequeue:YES];
        [NSApp sendEvent:event];

        // keyUp is not called when cmd is held
        if ([event type] == NSEventTypeKeyUp && ([event modifierFlags] & NSEventModifierFlagCommand)) {
            [[NSApp keyWindow] sendEvent:event];
        }
    } while (event);
    [NSApp updateWindows];
}

void wioMessageBox(uint8_t style, const char *ptr, size_t len) {
    NSAlertStyle styles[] = {NSAlertStyleInformational, NSAlertStyleWarning, NSAlertStyleCritical};
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:string(ptr, len)];
    [alert setAlertStyle:styles[style]];
    [alert runModal];
}

void *wioCreateWindow(void *ptr, uint16_t width, uint16_t height) {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setDelegate:[[WindowDelegate alloc] initWithPointer:ptr]];

    View *view = [[View alloc] initWithPointer:ptr];
    [window setContentView:view];
    [window makeFirstResponder:view];

    [window setAcceptsMouseMovedEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [window setTabbingMode:NSWindowTabbingModeDisallowed];
    [window makeKeyAndOrderFront:nil];
    [window center];

    NSRect rect = [view frame];
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioSize(ptr, false, rect.size.width, rect.size.height, framebuffer.size.width, framebuffer.size.height);
    wioScale(ptr, [window backingScaleFactor]);

    return (void*)CFBridgingRetain(window);
}

void wioDestroyWindow(void *ptr, void *context) {
    CFBridgingRelease(context);
    NSWindow *window = CFBridgingRelease(ptr);
    [window close];
}

void wioSetTitle(NSWindow *window, const char *ptr, size_t len) {
    [window setTitle:string(ptr, len)];
}

void wioSetMode(NSWindow *window, uint8_t mode) {
    if (!!([window styleMask] & NSWindowStyleMaskFullScreen) != (mode == 2)) [window toggleFullScreen:nil];
    if (mode != 2 && mode != [window isZoomed]) [window performZoom:nil];
}

void wioSetCursor(NSWindow *window, uint8_t shape) {
    NSCursor *cursor;
    switch (shape) {
        case 3: cursor = [NSCursor IBeamCursor]; break;
        case 4: cursor = [NSCursor pointingHandCursor]; break;
        case 5: cursor = [NSCursor crosshairCursor]; break;
        case 6: cursor = [NSCursor operationNotAllowedCursor]; break;
        case 8: cursor = [NSCursor resizeUpDownCursor]; break;
        case 9: cursor = [NSCursor resizeLeftRightCursor]; break;
        default: cursor = [NSCursor arrowCursor]; break;
    }
    [[window contentView] setCursor:cursor];
}

void wioSetCursorMode(NSWindow *window, uint8_t mode) {
    [[window contentView] setCursorMode:mode];
    if (mode == 2) {
        warpCursor(window);
        CGAssociateMouseAndMouseCursorPosition(NO);
    } else {
        CGAssociateMouseAndMouseCursorPosition(YES);
    }
}

void wioRequestAttention(void) {
    [NSApp requestUserAttention:NSCriticalRequest];
}

void wioSetClipboardText(const char *ptr, size_t len) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[NSPasteboardTypeString] owner:nil];
    [pasteboard setString:string(ptr, len) forType:NSPasteboardTypeString];
}

char *wioGetClipboardText(const void *ptr, size_t *len) {
    NSString *string = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    if (!string) return NULL;
    return wioDupeClipboardText(ptr, [string UTF8String], len);
}

void *wioCreateContext(NSWindow *window, NSOpenGLPixelFormatAttribute *attributes) {
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    [context setView:[window contentView]];
    WindowDelegate *delegate = [window delegate];
    [delegate setContext:context];
    return (void*)CFBridgingRetain(context);
}

void wioMakeContextCurrent(NSOpenGLContext *context) {
    [context makeCurrentContext];
}

void wioSwapBuffers(NSWindow *window, NSOpenGLContext *context) {
    if ([window occlusionState] & NSApplicationOcclusionStateVisible) {
        [context flushBuffer];
    } else {
        // vsync does not apply to occluded windows
        struct timespec time = {0, 33333333};
        nanosleep(&time, NULL);
    }
}

void wioSwapInterval(NSOpenGLContext *context, int32_t interval) {
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
}
