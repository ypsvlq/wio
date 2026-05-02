#include <AppKit.h>
#include <InterfaceKit.h>
#include <NetworkKit.h>
#include <OpenGLKit.h>
#include <DeviceKit.h>
#include <MediaKit.h>
#include <StorageKit.h>
#include <app/Cursor.h>

extern "C" {
    void wioClose(void *);
    void wioFocused(void *);
    void wioUnfocused(void *);
    void wioVisible(void *);
    void wioHidden(void *);
    void wioSize(void *, uint8, uint16, uint16);
    void wioChars(void *, const char *);
    void wioKey(void *, int32, uint8);
    void wioButtons(void *, uint8);
    void wioMouse(void *, uint16, uint16);
    void wioMouseRelative(void *, int16, int16);
    void wioScroll(void *, float, float);
    void wioDropBegin(void *);
    void wioDropPosition(void *, uint16, uint16);
    void wioDropFile(void *, const char *);
    void wioDropText(void *, const char *, size_t);
    void wioDropComplete(void *);
    void wioAudioOutputWrite(void *, void *, size_t);

    extern float wio_scale;
}

class WioWindow : public BWindow {
public:
    void *zig;
    BRect normal_frame;
    bool relative_mouse;
    uint8 mode;
#ifdef WIO_DROP
    bool dropping;
#endif

    WioWindow(void *zig, BRect frame, const char *title) : BWindow(frame, title, B_TITLED_WINDOW, 0) {
        this->zig = zig;
        this->normal_frame = Frame();
        this->relative_mouse = false;
        this->mode = 0;
#ifdef WIO_DROP
        this->dropping = false;
#endif
#ifdef WIO_FRAMEBUFFER
        AddChild(new BView(Bounds(), "wio", B_FOLLOW_ALL_SIDES, 0));
#endif
    }

    void DispatchMessage(BMessage *message, BHandler *target) {
        bool dispatch_parent = true;

        switch (message->what) {
            case B_QUIT_REQUESTED:
                wioClose(zig);
                dispatch_parent = false;
                break;
            case B_WINDOW_ACTIVATED: {
                bool active;
                if (message->FindBool("active", &active) == B_OK) {
                    active ? wioFocused(zig) : wioUnfocused(zig);
                }
                break;
            }
            case B_MINIMIZE: {
                bool minimize;
                if (message->FindBool("minimize", &minimize) == B_OK) {
                    minimize ? wioHidden(zig) : wioVisible(zig);
                }
                break;
            }
            case B_WINDOW_RESIZED: {
                int32 width, height;
                if (message->FindInt32("width", &width) == B_OK && message->FindInt32("height", &height) == B_OK) {
                    wioSize(zig, mode, width, height);
                    mode = 0;
                }
                break;
            }
            case B_KEY_DOWN:
            case B_UNMAPPED_KEY_DOWN: {
                int32 key;
                if (message->FindInt32("key", &key) == B_OK) {
                    int32 repeat;
                    wioKey(zig, key, (message->FindInt32("be:key_repeat", &repeat) == B_OK) ? 1 : 0);
                }
                const char *bytes;
                if (message->FindString("bytes", &bytes) == B_OK) {
                    wioChars(zig, bytes);
                }
                break;
            }
            case B_KEY_UP:
            case B_UNMAPPED_KEY_UP: {
                int32 key;
                if (message->FindInt32("key", &key) == B_OK) {
                    wioKey(zig, key, 2);
                }
                break;
            }
            case B_MOUSE_DOWN:
            case B_MOUSE_UP: {
                int32 buttons;
                if (message->FindInt32("buttons", &buttons) == B_OK) {
                    wioButtons(zig, buttons);
                }
                break;
            }
            case B_MOUSE_MOVED: {
                BPoint where;
                if (message->FindPoint("where", &where) == B_OK) {
                    if (relative_mouse) {
                        BRect bounds = Bounds();
                        int16 dx = where.x - (bounds.right / 2);
                        int16 dy = where.y - (bounds.bottom / 2);
                        if (dx != 0 || dy != 0) {
                            wioMouseRelative(zig, dx, dy);
                            WarpCursor();
                        }
                    } else {
                        if (where.x > 0 && where.y > 0) {
                            wioMouse(zig, where.x, where.y);
                        }
                    }
                }

#ifdef WIO_DROP

                BMessage drag_msg;
                if (message->FindMessage("be:drag_message", &drag_msg) == B_OK) {
                    if (!dropping) {
                        dropping = true;
                        wioDropBegin(zig);
                    }
                    if (where.x > 0 && where.y > 0) {
                        wioDropPosition(zig, (uint16)where.x, (uint16)where.y);
                    }
                }

#endif

                break;
            }
            case B_MOUSE_WHEEL_CHANGED: {
                float y, x;
                message->FindFloat("be:wheel_delta_y", &y); // sets to 0 on failure
                message->FindFloat("be:wheel_delta_x", &x); // sets to 0 on failure
                wioScroll(zig, y, x);
                break;
            }
        }

#ifdef WIO_DROP

        if (message->WasDropped()) {
            dropping = false;
            entry_ref ref;
            for (int32 i = 0; message->FindRef("refs", i, &ref) == B_OK; i++) {
                wioDropFile(zig, BPath(&ref).Path());
            }
            const void *text;
            ssize_t len;
            if (message->FindData("text/plain", B_MIME_TYPE, &text, &len) == B_OK) {
                wioDropText(zig, (const char *)text, (size_t)len);
            }
            wioDropComplete(zig);
            dispatch_parent = false;
        }

#endif

        if (dispatch_parent) {
            BWindow::DispatchMessage(message, target);
        }
    }

    void WarpCursor(void) {
        BRect bounds = Bounds();
        BPoint centre = ConvertToScreen(BPoint(bounds.right / 2, bounds.bottom / 2));
        set_mouse_position(centre.x, centre.y);
    }
};

extern "C" {
    void wioInit(void) {
        new BApplication("application/x-vnd.wio");
        wio_scale = be_plain_font->Size() / 12.0f;
    }

    void wioMessageBox(uint8 type, const char *title, const char *message) {
        alert_type types[] = { B_INFO_ALERT, B_WARNING_ALERT, B_STOP_ALERT };
        BAlert *alert = new BAlert(title, message, "OK", NULL, NULL, B_WIDTH_AS_USUAL, types[type]);
        alert->Go();
    }

    void wioOpenUri(const char *uri) {
        BUrl(uri, false).OpenWithPreferredApplication();
    }

    uint32 wioGetModifiers(void) {
        return modifiers();
    }

    WioWindow *wioCreateWindow(void *zig, const char *title, uint16 width, uint16 height) {
        WioWindow *window = new WioWindow(zig, BRect(370, 70, 370 + width, 70 + height), title);
        window->Show();
        return window;
    }

    void wioDestroyWindow(WioWindow *window) {
        window->Lock();
        window->Quit();
    }

    void wioEnableRelativeMouse(WioWindow *window) {
        window->relative_mouse = true;
        be_app->HideCursor();
        window->WarpCursor();
    }

    void wioDisableRelativeMouse(WioWindow *window) {
        window->relative_mouse = false;
        be_app->ShowCursor();
    }

    void wioSetTitle(WioWindow *window, const char *title) {
        window->SetTitle(title);
    }

    void wioSetMode(WioWindow *window, uint8 mode) {
        BRect frame;
        switch (mode) {
            case 0:
                frame = window->normal_frame;
                break;
            case 1:
                return;
            case 2:
                frame = BScreen(window).Frame();
                frame.right += 1;
                frame.bottom += 1;
                if (frame == window->Frame()) {
                    return;
                }
                window->mode = 2;
                break;
        }
        window->MoveTo(frame.left, frame.top);
        window->ResizeTo(frame.right - frame.left, frame.bottom - frame.top);
    }

    void wioSetSize(WioWindow *window, float width, float height) {
        window->ResizeTo(width, height);
    }

    void wioSetCursor(uint8 shape) {
        static const BCursorID ids[] = {
            B_CURSOR_ID_SYSTEM_DEFAULT,
            B_CURSOR_ID_NO_CURSOR,
            B_CURSOR_ID_CONTEXT_MENU,
            B_CURSOR_ID_HELP,
            B_CURSOR_ID_FOLLOW_LINK,
            B_CURSOR_ID_PROGRESS,
            B_CURSOR_ID_PROGRESS,
            B_CURSOR_ID_CROSS_HAIR,
            B_CURSOR_ID_CROSS_HAIR,
            B_CURSOR_ID_I_BEAM,
            B_CURSOR_ID_I_BEAM_HORIZONTAL,
            B_CURSOR_ID_CREATE_LINK,
            B_CURSOR_ID_COPY,
            B_CURSOR_ID_MOVE,
            B_CURSOR_ID_NOT_ALLOWED,
            B_CURSOR_ID_NOT_ALLOWED,
            B_CURSOR_ID_GRAB,
            B_CURSOR_ID_GRABBING,
            B_CURSOR_ID_RESIZE_EAST,
            B_CURSOR_ID_RESIZE_NORTH,
            B_CURSOR_ID_RESIZE_NORTH_EAST,
            B_CURSOR_ID_RESIZE_NORTH_WEST,
            B_CURSOR_ID_RESIZE_SOUTH,
            B_CURSOR_ID_RESIZE_SOUTH_EAST,
            B_CURSOR_ID_RESIZE_SOUTH_WEST,
            B_CURSOR_ID_RESIZE_WEST,
            B_CURSOR_ID_RESIZE_EAST_WEST,
            B_CURSOR_ID_RESIZE_NORTH_SOUTH,
            B_CURSOR_ID_RESIZE_NORTH_EAST_SOUTH_WEST,
            B_CURSOR_ID_RESIZE_NORTH_WEST_SOUTH_EAST,
            B_CURSOR_ID_RESIZE_EAST_WEST,
            B_CURSOR_ID_RESIZE_NORTH_SOUTH,
            B_CURSOR_ID_MOVE,
            B_CURSOR_ID_ZOOM_IN,
            B_CURSOR_ID_ZOOM_OUT,
        };
        BCursor cursor = BCursor(ids[shape]);
        be_app->SetCursor(&cursor);
    }

    void wioSetClipboardText(const char *text, size_t len) {
        if (be_clipboard->Lock()) {
            be_clipboard->Clear();
            be_clipboard->Data()->AddData("text/plain", B_MIME_TYPE, text, len);
            be_clipboard->Commit();
            be_clipboard->Unlock();
        }
    }

    const char *wioGetClipboardText(size_t *len) {
        static BMessage *data;
        if (be_clipboard->Lock()) {
            data = be_clipboard->Data();
            be_clipboard->Unlock();
        } else {
            return NULL;
        }
        const char *text;
        data->FindData("text/plain", B_MIME_TYPE, (const void **)&text, (ssize_t *)len);
        return text;
    }

#ifdef WIO_FRAMEBUFFER

    struct WioFramebuffer {
        BBitmap *bitmap;
        uint8 *bits;
        uint32 bytes_per_row;
    };

    WioFramebuffer wioCreateFramebuffer(uint16 width, uint16 height) {
        BBitmap *bitmap = new BBitmap(BRect(0, 0, width, height), B_RGB32);
        WioFramebuffer result = { bitmap, (uint8 *)bitmap->Bits(), (uint32)bitmap->BytesPerRow() };
        return result;
    }

    void wioFramebufferDestroy(BBitmap *bitmap) {
        delete bitmap;
    }

    void wioPresentFramebuffer(WioWindow *window, BBitmap *bitmap) {
        if (window->Lock()) {
            window->ChildAt(0)->SetViewBitmap(bitmap);
            window->Unlock();
        }
    }

#endif

#ifdef WIO_OPENGL

    BGLView *wioGlCreateContext(WioWindow *window, bool doublebuffer, bool alpha, bool depth, bool stencil) {
        BGLView *view = new BGLView(window->Bounds(), "OpenGL", B_FOLLOW_ALL_SIDES, 0, (doublebuffer ? BGL_DOUBLE : 0) | (alpha ? BGL_ALPHA : 0) | (depth ? BGL_DEPTH : 0) | (stencil ? BGL_STENCIL : 0));
        window->AddChild(view);
        return view;
    }

    static BGLView *current;

    void wioGlMakeContextCurrent(BGLView *view) {
        if (current != NULL) current->UnlockGL();
        view->LockGL();
        current = view;
    }

    void wioGlSwapBuffers(bool vsync) {
        current->SwapBuffers(vsync);
    }

#endif

#ifdef WIO_JOYSTICK

    BJoystick *wioJoystickIteratorInit(int32 *count) {
        BJoystick *joystick = new BJoystick();
        *count = joystick->CountDevices();
        return joystick;
    }

    void wioJoystickIteratorDeinit(BJoystick *joystick) {
        delete joystick;
    }

    void wioJoystickIteratorNext(BJoystick *joystick, int32 index, char *name) {
        joystick->GetDeviceName(index, name);
    }

    BJoystick *wioJoystickOpen(const char *name, int32 *axis_count, int32 *hat_count, int32 *button_count) {
        BJoystick *joystick = new BJoystick();
        if (joystick->Open(name) == B_ERROR) {
            delete joystick;
            return NULL;
        }
        *axis_count = joystick->CountAxes();
        *hat_count = joystick->CountHats();
        *button_count = joystick->CountButtons();
        return joystick;
    }

    void wioJoystickClose(BJoystick *joystick) {
        joystick->Close();
        delete joystick;
    }

    bool wioJoystickPoll(BJoystick *joystick, int16 *axes, uint8 *hats, uint32 *buttons) {
        if (joystick->Update() != B_OK) return false;
        if (joystick->GetAxisValues(axes) != B_OK) return false;
        if (joystick->GetHatValues(hats) != B_OK) return false;
        *buttons = joystick->ButtonValues();
        return true;
    }

#endif

#ifdef WIO_AUDIO

    static void writeFn(void *data, void *buffer, size_t size, const media_raw_audio_format &format) {
        (void)format;
        wioAudioOutputWrite(data, buffer, size);
    }

    BSoundPlayer *wioAudioOutputOpen(uint32 rate, uint8 channels, void *data) {
        media_raw_audio_format format = {
            .frame_rate = (float)rate,
            .channel_count = channels,
            .format = media_raw_audio_format::B_AUDIO_FLOAT,
            .byte_order = B_MEDIA_HOST_ENDIAN,
            .buffer_size = 0,
        };
        BSoundPlayer *player = new BSoundPlayer(&format, NULL, writeFn, NULL, data);
        if (player->InitCheck() != B_OK) {
            delete player;
            return NULL;
        }
        player->Start();
        return player;
    }

    void wioAudioOutputClose(BSoundPlayer *player) {
        delete player;
    }

#endif
}
