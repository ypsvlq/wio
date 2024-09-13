#import <Cocoa/Cocoa.h>

extern void wioClose(void *);
extern void wioCreate(void *);
extern void wioFocus(void *);
extern void wioUnfocus(void *);
extern void wioSize(void *, bool, UInt16, UInt16, UInt16, UInt16);
extern void wioScale(void *, Float32);
extern void wioChars(void *, const char *);
extern void wioKeyDown(void *, UInt16);
extern void wioKeyRepeat(void *, UInt16);
extern void wioKeyUp(void *, UInt16);
extern void wioButtonPress(void *, UInt8);
extern void wioButtonRelease(void *, UInt8);
extern void wioMouse(void *, UInt16, UInt16);
extern void wioScroll(void *, Float32, Float32);
extern char *wioDupeClipboardText(const void *, const char *, size_t *);

static NSString *string(const char *ptr, size_t len) {
    return [[NSString alloc] initWithBytes:ptr length:len encoding:NSUTF8StringEncoding];
}

@interface ApplicationDelegate : NSObject <NSApplicationDelegate>
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

@interface WindowDelegate : NSObject <NSWindowDelegate>
{
    void *ptr;
    NSOpenGLContext *context;
}
@end

@implementation WindowDelegate

- (instancetype)initWithPointer:(void*)value {
    self = [super init];
    ptr = value;
    return self;
}

- (void)setContext:value {
    context = value;
}

- (BOOL)windowShouldClose:sender {
    wioClose(ptr);
    return NO;
}

- (void)windowDidBecomeKey:notification {
    wioFocus(ptr);
}

- (void)windowDidResignKey:notification {
    wioUnfocus(ptr);
}

- (void)windowDidResize:notification {
    NSWindow *window = [notification object];
    NSView *view = [window contentView];
    NSRect rect = [view frame];
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioSize(ptr, [window isZoomed], rect.size.width, rect.size.height, framebuffer.size.width, framebuffer.size.height);
    [context update];
}

@end

@interface View : NSView
{
    void *ptr;
    NSTrackingArea *area;
    NSCursor *cursor;
    BOOL cursorhidden;
    BOOL cursorinside;
}
@end

@implementation View

- (instancetype)initWithPointer:(void*)value {
    self = [super init];
    ptr = value;
    return self;
}

- (void)setCursor:value {
    cursor = value;
    [self updateTrackingAreas];
}

- (void)setCursorHidden:(BOOL)value {
    if (value != cursorhidden) {
        cursorhidden = value;
        if (cursorinside) value ? [NSCursor hide] : [NSCursor unhide];
    }
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
    if (cursorhidden) [NSCursor hide];
    cursorinside = true;
}

- (void)mouseExited:event {
    if (cursorhidden) [NSCursor unhide];
    cursorinside = false;
}

- (void)keyDown:event {
    if ([event isARepeat]) {
        wioKeyRepeat(ptr, [event keyCode]);
    } else {
        wioKeyDown(ptr, [event keyCode]);
    }
    wioChars(ptr, [[event characters] UTF8String]);
}

- (void)keyUp:event {
    wioKeyUp(ptr, [event keyCode]);
}

- (void)flagsChanged:event {
    UInt16 key = [event keyCode];
    NSUInteger flag;
    switch (key) {
        case 0x36: flag = NX_DEVICERCMDKEYMASK; break;
        case 0x37: flag = NX_DEVICELCMDKEYMASK; break;
        case 0x38: flag = NX_DEVICELSHIFTKEYMASK; break;
        case 0x39: flag = NSEventModifierFlagCapsLock; break;
        case 0x3A: flag = NX_DEVICELALTKEYMASK; break;
        case 0x3B: flag = NX_DEVICELCTLKEYMASK; break;
        case 0x3C: flag = NX_DEVICERSHIFTKEYMASK; break;
        case 0x3D: flag = NX_DEVICERALTKEYMASK; break;
        case 0x3E: flag = NX_DEVICERCTLKEYMASK; break;
        default: return;
    }
    if ([event modifierFlags] & flag) {
        wioKeyDown(ptr, key);
    } else {
        wioKeyUp(ptr, key);
    }
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
    } while (event);
    [NSApp updateWindows];
}

void *wioCreateWindow(void *ptr, uint16_t width, uint16_t height) {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setDelegate:[[WindowDelegate alloc] initWithPointer:ptr]];

    View *view = [[View alloc] initWithPointer:ptr];
    [window setContentView:view];
    [window makeFirstResponder:view];

    [window setAcceptsMouseMovedEvents:YES];
    [window makeKeyAndOrderFront:nil];
    [window center];

    NSRect rect = [view frame];
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioSize(ptr, false, rect.size.width, rect.size.height, framebuffer.size.width, framebuffer.size.height);
    wioScale(ptr, [window backingScaleFactor]);
    wioCreate(ptr);

    return (__bridge_retained void *)window;
}

void wioDestroyWindow(void *ptr, void *context) {
    CFBridgingRelease(context);
    NSWindow *window = CFBridgingRelease(ptr);
    [window close];
}

void wioSetTitle(NSWindow *window, const char *ptr, size_t len) {
    [window setTitle:string(ptr, len)];
}

void wioSetSize(NSWindow *window, uint16_t width, uint16_t height) {
    [window setContentSize:NSMakeSize(width, height)];
}

void wioSetDisplayMode(NSWindow *window, uint8_t mode) {
    switch (mode) {
        case 0:
        case 1:
            [window setStyleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable];
            [window orderFront:nil];
            break;
        case 3:
            [window orderOut:nil];
            break;
    }
    if ((mode == 0 && [window isZoomed]) || (mode == 1 && ![window isZoomed])) {
        [window performZoom:nil];
    }
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
    [[window contentView] setCursorHidden:mode];
}

void *wioCreateContext(NSWindow *window) {
    NSOpenGLPixelFormatAttribute attributes[] = {NSOpenGLPFADoubleBuffer, 0};
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    [context setView:[window contentView]];
    WindowDelegate *delegate = [window delegate];
    [delegate setContext:context];
    return CFBridgingRetain(context);
}

void wioMakeContextCurrent(NSOpenGLContext *context) {
    [context makeCurrentContext];
}

void wioSwapBuffers(NSOpenGLContext *context) {
    [context flushBuffer];
}

void wioSwapInterval(NSOpenGLContext *context, int32_t interval) {
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
}

void wioMessageBox(uint8_t style, const char *ptr, size_t len) {
    NSAlertStyle styles[] = {NSAlertStyleInformational, NSAlertStyleWarning, NSAlertStyleCritical};
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:string(ptr, len)];
    [alert setAlertStyle:styles[style]];
    [alert runModal];
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
