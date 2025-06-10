#include <AppKit.h>
#include <InterfaceKit.h>
#include <OpenGLKit.h>
#include <DeviceKit.h>
#include <MediaKit.h>

extern "C" {
    void wioClose(void *);
    void wioFocused(void *);
    void wioUnfocused(void *);
    void wioVisible(void *);
    void wioHidden(void *);
    void wioSize(void *, uint16, uint16);
    void wioChars(void *, const char *);
    void wioKey(void *, int32, uint8);
    void wioButtons(void *, uint8);
    void wioMouse(void *, uint16, uint16);
    void wioScroll(void *, float, float);
    void wioAudioOutputWrite(void *, void *, size_t);
}

class WioWindow : public BWindow {
private:
    void *zig;

public:
    WioWindow(void *zig, BRect frame, const char *title) : BWindow(frame, title, B_TITLED_WINDOW, 0) {
        this->zig = zig;
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
                    if (active) {
                        wioFocused(zig);
                    } else {
                        wioUnfocused(zig);
                    }
                }
                break;
            }
            case B_MINIMIZE: {
                bool minimize;
                if (message->FindBool("minimize", &minimize) == B_OK) {
                    if (minimize) {
                        wioHidden(zig);
                    } else {
                        wioVisible(zig);
                    }
                }
            }
            case B_WINDOW_RESIZED: {
                int32 width, height;
                if (message->FindInt32("width", &width) == B_OK) {
                    if (message->FindInt32("height", &height) == B_OK) {
                        wioSize(zig, width, height);
                    }
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
            }
            case B_MOUSE_MOVED: {
                BPoint where;
                if (message->FindPoint("where", &where) == B_OK) {
                    if (where.x > 0 && where.y > 0) {
                        wioMouse(zig, where.x, where.y);
                    }
                }
                break;
            }
            case B_MOUSE_WHEEL_CHANGED: {
                float y, x;
                message->FindFloat("be:wheel_delta_y", &y);
                message->FindFloat("be:wheel_delta_x", &x);
                wioScroll(zig, y, x);
                break;
            }
        }

        if (dispatch_parent) {
            BWindow::DispatchMessage(message, target);
        }
    }
};

extern "C" {
    void wioInit(void) {
        new BApplication("application/x-vnd.wio");
    }

    void wioMessageBox(uint8 type, const char *title, const char *message) {
        alert_type types[] = { B_INFO_ALERT, B_WARNING_ALERT, B_STOP_ALERT };
        BAlert *alert = new BAlert(title, message, "OK", NULL, NULL, B_WIDTH_AS_USUAL, types[type]);
        alert->Go();
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

    void wioSetTitle(WioWindow *window, const char *title) {
        window->SetTitle(title);
    }

    void wioSetSize(WioWindow *window, float width, float height) {
        window->ResizeTo(width, height);
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

#ifdef WIO_OPENGL

    BGLView *wioCreateContext(WioWindow *window, bool doublebuffer, bool alpha, bool depth, bool stencil) {
        BGLView *view = new BGLView(window->Bounds(), "OpenGL", B_FOLLOW_ALL_SIDES, 0, (doublebuffer ? BGL_DOUBLE : 0) | (alpha ? BGL_ALPHA : 0) | (depth ? BGL_DEPTH : 0) | (stencil ? BGL_STENCIL : 0));
        window->AddChild(view);
        return view;
    }

    static BGLView *current;

    void wioMakeContextCurrent(BGLView *view) {
        if (current != NULL) current->UnlockGL();
        view->LockGL();
        current = view;
    }

    void wioSwapBuffers(bool vsync) {
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
