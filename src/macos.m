#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include <IOKit/hid/IOHIDKeys.h>

extern void wioClose(void *);
extern void wioFocused(void *);
extern void wioUnfocused(void *);
extern void wioVisible(void *);
extern void wioHidden(void *);
extern void wioSize(void *, UInt8, UInt16, UInt16);
extern void wioFramebuffer(void *, UInt16, UInt16);
extern void wioScale(void *, Float32);
extern void wioChars(void *, const char *);
extern void wioPreviewChars(void *, const char *, uint16_t, uint16_t);
extern void wioPreviewReset(void *);
extern void wioKey(void *, UInt16, UInt8);
extern void wioButtonPress(void *, UInt8);
extern void wioButtonRelease(void *, UInt8);
extern void wioMouse(void *, UInt16, UInt16);
extern void wioMouseRelative(void *, SInt16, SInt16);
extern void wioScroll(void *, Float32, Float32);
extern char *wioDupeClipboardText(const void *, const char *, size_t *);

static NSString *string(const char *ptr, size_t len) {
    return [[NSString alloc] initWithBytes:ptr length:len encoding:NSUTF8StringEncoding];
}

static void warpCursor(NSWindow *window) {
    NSRect frame = [window frame];
    NSRect screen = [[NSScreen mainScreen] frame];
    CGWarpMouseCursorPosition(CGPointMake(CGRectGetMidX(frame), CGRectGetMaxY(screen) - CGRectGetMidY(frame)));
}

@interface WioApplicationDelegate : NSObject <NSApplicationDelegate>
@end

@interface WioWindowDelegate : NSObject <NSWindowDelegate>
@end

@interface WioView : NSView <NSTextInputClient>
- (uint8_t)cursorMode;
@end

@implementation WioApplicationDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp stop:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    for (NSWindow *window in [NSApp windows]) {
        id delegate = [window delegate];
        if ([delegate respondsToSelector:@selector(windowShouldClose:)]) {
            [delegate windowShouldClose:window];
        }
    }
    return NSTerminateCancel;
}

@end

@implementation WioWindowDelegate {
    void *zig;
#ifdef WIO_OPENGL
    NSOpenGLContext *context;
#endif
}

- (instancetype)initWithZigWindow:(void *)value {
    self = [super init];
    zig = value;
    return self;
}

#ifdef WIO_OPENGL
- (void)setContext:(NSOpenGLContext *)value {
    context = value;
}
#endif

- (void)windowDidEnterFullScreen:(NSNotification *)notification {
    [[[notification object] contentView] updateTrackingAreas];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    wioClose(zig);
    return NO;
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    wioFocused(zig);

    NSWindow *window = [notification object];
    WioView *view = [window contentView];
    if ([view cursorMode] == 2) {
        warpCursor(window);
    }
}

- (void)windowDidResignKey:(NSNotification *)notification {
    wioUnfocused(zig);
}

- (void)windowDidChangeOcclusionState:(NSNotification *)notification {
    if ([[notification object] occlusionState] & NSWindowOcclusionStateVisible) {
        wioVisible(zig);
    } else {
        wioHidden(zig);
    }
}

- (void)windowDidResize:(NSNotification *)notification {
    NSWindow *window = [notification object];
    WioView *view = [window contentView];

    if ([view cursorMode] == 2) {
        warpCursor(window);
    }

    uint8_t mode = 0;
    if ([window isZoomed])
        mode = 1;
    else if ([window styleMask] & NSWindowStyleMaskFullScreen)
        mode = 2;

    NSRect rect = [view frame];
    wioSize(zig, mode, rect.size.width, rect.size.height);
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioFramebuffer(zig, framebuffer.size.width, framebuffer.size.height);

#ifdef WIO_OPENGL
    [context update];
#endif
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    NSWindow *window = [notification object];
    NSView *view = [window contentView];
    CGFloat scale = [window backingScaleFactor];

    NSRect rect = [view frame];
    wioScale(zig, scale);
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioFramebuffer(zig, framebuffer.size.width, framebuffer.size.height);

#ifdef WIO_OPENGL
    [context update];
#endif
#ifdef WIO_VULKAN
    [[view layer] setContentsScale:scale];
#endif
}

@end

@implementation WioView {
    void *zig;
    NSString *marked;
    NSTrackingArea *area;
    NSCursor *cursor;
    uint16_t textX, textY;
    BOOL textInput;
    uint8_t cursorMode;
    BOOL cursorInside;
}

- (instancetype)initWithZigWindow:(void *)value {
    self = [super init];
    zig = value;
    return self;
}

- (void)setTextInput:(BOOL)value x:(uint16_t)x y:(uint16_t)y {
    textInput = value;
    textX = x;
    textY = y;
    if (!value && marked != nil) {
        [[NSTextInputContext currentInputContext] discardMarkedText];
        marked = nil;
    }
}

- (void)setCursor:(NSCursor *)value {
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

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    if (marked) {
        wioPreviewReset(zig);
        marked = nil;
    }
    NSString *s = [string isKindOfClass:[NSString class]] ? string : [string string];
    wioChars(zig, [s UTF8String]);
}

- (void)doCommandBySelector:(SEL)selector {}

- (void)setMarkedText:(id)string selectedRange:(NSRange)selectedRange replacementRange:(NSRange)replacementRange {
    marked = [string isKindOfClass:[NSString class]] ? string : [string string];
    if ([marked length] == 0) {
        wioPreviewReset(zig);
        marked = nil;
        return;
    }
    wioPreviewChars(zig, [marked UTF8String], selectedRange.location, selectedRange.length);
}

- (void)unmarkText {
    if (marked) {
        wioPreviewReset(zig);
        wioChars(zig, [marked UTF8String]);
        marked = nil;
    }
}

- (NSRange)selectedRange {
    return NSMakeRange(NSNotFound, 0);
}

- (NSRange)markedRange {
    return (marked != nil) ? NSMakeRange(0, [marked length]) : NSMakeRange(NSNotFound, 0);
}

- (BOOL)hasMarkedText {
    return (marked != nil);
}

- (NSAttributedString *)attributedSubstringForProposedRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    return nil;
}

- (NSArray<NSAttributedStringKey> *)validAttributesForMarkedText {
    return @[];
}

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    return [[self window] convertRectToScreen:NSMakeRect(textX, [self frame].size.height - textY, 0, 0)];
}

- (NSUInteger)characterIndexForPoint:(NSPoint)point {
    return 0;
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

- (void)cursorUpdate:(NSEvent *)event {
    [cursor set];
}

- (void)mouseEntered:(NSEvent *)event {
    if (!cursorInside && cursorMode != 0) [NSCursor hide];
    cursorInside = YES;
}

- (void)mouseExited:(NSEvent *)event {
    if (cursorInside && cursorMode != 0) [NSCursor unhide];
    cursorInside = NO;
}

- (void)keyDown:(NSEvent *)event {
    wioKey(zig, [event keyCode], [event isARepeat]);
    if (textInput) {
        [[NSTextInputContext currentInputContext] handleEvent:event];
    }
}

- (void)keyUp:(NSEvent *)event {
    wioKey(zig, [event keyCode], 2);
}

- (void)flagsChanged:(NSEvent *)event {
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
            wioKey(zig, key, 0);
            wioKey(zig, key, 2);
            return;
        default: return;
    }
    wioKey(zig, key, [event modifierFlags] & flag ? 0 : 2);
}

- (void)mouseDown:(NSEvent *)event {
    wioButtonPress(zig, 0);
}

- (void)mouseUp:(NSEvent *)event {
    wioButtonRelease(zig, 0);
}

- (void)rightMouseDown:(NSEvent *)event {
    wioButtonPress(zig, 1);
}

- (void)rightMouseUp:(NSEvent *)event {
    wioButtonRelease(zig, 1);
}

- (void)otherMouseDown:(NSEvent *)event {
    NSInteger button = [event buttonNumber];
    if (button < 5) wioButtonPress(zig, button);
}

- (void)otherMouseUp:(NSEvent *)event {
    NSInteger button = [event buttonNumber];
    if (button < 5) wioButtonRelease(zig, button);
}

- (void)mouseMoved:(NSEvent *)event {
    if (cursorMode == 2) {
        wioMouseRelative(zig, [event deltaX], [event deltaY]);
        return;
    }
    NSPoint location = [event locationInWindow];
    NSRect frame = [self frame];
    location.y = frame.size.height - location.y - 1;
    if (location.x < 0 || location.y < 0 || location.x > frame.size.width || location.y > frame.size.height) return;
    wioMouse(zig, location.x, location.y);
}

- (void)mouseDragged:(NSEvent *)event {
    [self mouseMoved:event];
}

- (void)rightMouseDragged:(NSEvent *)event {
    [self mouseMoved:event];
}

- (void)otherMouseDragged:(NSEvent *)event {
    [self mouseMoved:event];
}

- (void)scrollWheel:(NSEvent *)event {
    wioScroll(zig, [event scrollingDeltaX], [event scrollingDeltaY]);
}

@end

void wioInit() {
    [NSApplication sharedApplication];
    [[NSBundle mainBundle] loadNibNamed:@"MainMenu" owner:NSApp topLevelObjects:nil];
    [NSApp setDelegate:[[WioApplicationDelegate alloc] init]];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp run];
}

void wioUpdate(void) {
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

void wioWait(void) {
    NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
        untilDate:[NSDate distantFuture]
        inMode:NSDefaultRunLoopMode
        dequeue:YES];
    [NSApp sendEvent:event];
}

void wioMessageBox(uint8_t style, const char *ptr, size_t len) {
    NSAlertStyle styles[] = { NSAlertStyleInformational, NSAlertStyleWarning, NSAlertStyleCritical };
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:string(ptr, len)];
    [alert setAlertStyle:styles[style]];
    [alert runModal];
}

void *wioCreateWindow(void *zig, uint16_t width, uint16_t height) {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered
        defer:NO];
    [window setDelegate:[[WioWindowDelegate alloc] initWithZigWindow:zig]];

    WioView *view = [[WioView alloc] initWithZigWindow:zig];
    [window setContentView:view];
    [window makeFirstResponder:view];

    [window setAcceptsMouseMovedEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    [window setTabbingMode:NSWindowTabbingModeDisallowed];
    [window makeKeyAndOrderFront:nil];
    [window center];

    wioVisible(zig);
    wioScale(zig, [window backingScaleFactor]);

    NSRect rect = [view frame];
    wioSize(zig, 0, rect.size.width, rect.size.height);
    NSRect framebuffer = [view convertRectToBacking:rect];
    wioFramebuffer(zig, framebuffer.size.width, framebuffer.size.height);

    return (void *)CFBridgingRetain(window);
}

void wioDestroyWindow(void *ptr) {
    NSWindow *window = CFBridgingRelease(ptr);
    [window close];
}

void wioEnableTextInput(NSWindow *window, uint16_t x, uint16_t y) {
    [[window contentView] setTextInput:YES x:x y:y];
}

void wioDisableTextInput(NSWindow *window) {
    [[window contentView] setTextInput:NO x:0 y:0];
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

void wioSetSize(NSWindow *window, uint16_t width, uint16_t height) {
    [window setContentSize:NSMakeSize(width, height)];
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

#ifdef WIO_OPENGL

void *wioCreateContext(NSWindow *window, const NSOpenGLPixelFormatAttribute *attributes) {
    NSView *view = [window contentView];
    [view setWantsBestResolutionOpenGLSurface:YES];
    NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:format shareContext:nil];
    [context setView:view];
    WioWindowDelegate *delegate = [window delegate];
    [delegate setContext:context];
    return (void *)CFBridgingRetain(context);
}

void wioDestroyContext(void *context) {
    CFBridgingRelease(context);
}

void wioMakeContextCurrent(NSOpenGLContext *context) {
    [context makeCurrentContext];
}

void wioSwapBuffers(NSWindow *window, NSOpenGLContext *context) {
    [context flushBuffer];
}

void wioSwapInterval(NSOpenGLContext *context, int32_t interval) {
    [context setValues:&interval forParameter:NSOpenGLCPSwapInterval];
}

#endif

#ifdef WIO_VULKAN

void *wioCreateMetalLayer(NSWindow *window) {
    CAMetalLayer *layer = [CAMetalLayer layer];
    [layer setContentsScale:[window backingScaleFactor]];
    NSView *view = [window contentView];
    [view setWantsLayer:YES];
    [view setLayer:layer];
    return (__bridge void *)layer;
}

#endif

#ifdef WIO_JOYSTICK

const CFStringRef wioHIDDeviceUsagePageKey = CFSTR(kIOHIDDeviceUsagePageKey);
const CFStringRef wioHIDDeviceUsageKey = CFSTR(kIOHIDDeviceUsageKey);
const CFStringRef wioHIDVendorIDKey = CFSTR(kIOHIDVendorIDKey);
const CFStringRef wioHIDProductIDKey = CFSTR(kIOHIDProductIDKey);
const CFStringRef wioHIDVersionNumberKey = CFSTR(kIOHIDVersionNumberKey);
const CFStringRef wioHIDSerialNumberKey = CFSTR(kIOHIDSerialNumberKey);
const CFStringRef wioHIDProductKey = CFSTR(kIOHIDProductKey);

#endif
