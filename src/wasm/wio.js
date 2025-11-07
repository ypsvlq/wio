const wio = {
    module: undefined,
    canvases: undefined,
    windows: [],
    gamepads: navigator.getGamepads(),

    run(module, canvases) {
        wio.module = module;
        wio.canvases = canvases;

        module.exports._start();
        requestAnimationFrame(wio.loop);

        addEventListener("pointerlockchange", () => {
            for (const window of wio.windows) {
                if (window.cursor_mode === 2) {
                    window.canvas.style.cursor = (window.canvas === document.pointerLockElement) ? "none" : window.cursor;
                }
            }
        });

        addEventListener("gamepadconnected", event => {
            wio.gamepads = navigator.getGamepads();
            wio.module.exports.wioJoystick(event.gamepad.index)
        });
    },

    loop() {
        if (wio.module.exports.wioLoop()) {
            requestAnimationFrame(wio.loop);
        }
    },

    shift(id) {
        return wio.windows[id].events.shift();
    },

    shiftFloat(id) {
        return wio.windows[id].events.shift();
    },

    messageBox(ptr, len) {
        alert(wio.getString(ptr, len));
    },

    createWindow() {
        const canvas = wio.canvases.shift();
        if (canvas === undefined) throw new Error("no canvas available");

        const events = [3];
        const window = {
            canvas: canvas,
            events: events,
            text: false,
            cursor: undefined,
            cursor_mode: undefined,
        };

        new ResizeObserver(() => {
            const width = parseInt(canvas.scrollWidth);
            const height = parseInt(canvas.scrollHeight);
            canvas.width = width * devicePixelRatio;
            canvas.height = height * devicePixelRatio;
            events.push(
                9, (document.fullscreenElement === canvas) ? 2 : 0,
                6, width, height,
                7, canvas.width, canvas.height,
                8, devicePixelRatio,
                5,
            );
        }).observe(canvas);
        canvas.addEventListener("contextmenu", event => event.preventDefault());
        canvas.addEventListener("focus", () => events.push(1));
        canvas.addEventListener("blur", () => events.push(2));
        canvas.addEventListener("keydown", event => {
            event.preventDefault();
            const key = wio.keys[event.code];
            if (key) events.push(event.repeat ? 12 : 11, key);
            if (window.text && [...event.key].length === 1) events.push(10, event.key.codePointAt(0));
        });
        canvas.addEventListener("keyup", event => {
            const key = wio.keys[event.code];
            if (key) events.push(13, key);
        });
        canvas.addEventListener("mousedown", event => {
            const button = wio.buttons[event.button];
            if (button !== undefined) events.push(11, button);
            if (window.cursor_mode === 2) canvas.requestPointerLock({ unadjustedMovement: true });
        });
        canvas.addEventListener("mouseup", event => {
            const button = wio.buttons[event.button];
            if (button !== undefined) events.push(13, button);
        });
        canvas.addEventListener("mousemove", event => {
            if (window.cursor_mode !== 2) {
                events.push(14, event.offsetX, event.offsetY);
            } else {
                events.push(15, event.movementX, event.movementY);
            }
        });
        canvas.addEventListener("wheel", event => {
            if (event.deltaY !== 0) events.push(16, event.deltaY);
            if (event.deltaX !== 0) events.push(17, event.deltaX);
        });

        wio.windows.push(window);
        return wio.windows.length - 1;
    },

    setTextInput(id, enabled) {
        wio.windows[id].text = enabled;
    },

    setFullscreen(id, fullscreen) {
        if (fullscreen) {
            wio.windows[id].canvas.requestFullscreen().catch(() => { });
        } else {
            document.exitFullscreen().catch(() => { });
        }
    },

    setCursor(id, cursor) {
        wio.windows[id].cursor = {
            0: "default",
            1: "progress",
            2: "wait",
            3: "text",
            4: "pointer",
            5: "crosshair",
            6: "not-allowed",
            7: "move",
            8: "ns-resize",
            9: "ew-resize",
            10: "nesw-resize",
            11: "nwse-resize",
        }[cursor];

        if (wio.windows[id].cursor_mode === 0) {
            wio.windows[id].canvas.style.cursor = wio.windows[id].cursor;
        }
    },

    setCursorMode(id, mode) {
        wio.windows[id].cursor_mode = mode;

        if (mode === 0) {
            wio.windows[id].canvas.style.cursor = wio.windows[id].cursor;
        } else {
            wio.windows[id].canvas.style.cursor = "none";
        }

        if (mode === 2) {
            wio.windows[id].canvas.requestPointerLock({ unadjustedMovement: true });
        } else {
            document.exitPointerLock();
        }
    },

    setSize(id, width, height) {
        wio.windows[id].canvas.style.width = `${width}px`;
        wio.windows[id].canvas.style.height = `${height}px`;
    },

    setClipboardText(ptr, len) {
        navigator.clipboard.writeText(wio.getString(ptr, len));
    },

    getJoystickCount() {
        return wio.gamepads.length;
    },

    getJoystickIdLen(i) {
        return (wio.gamepads[i] !== null) ? new TextEncoder().encode(wio.gamepads[i].id).length : 0;
    },

    getJoystickId(i, ptr) {
        new TextEncoder().encodeInto(wio.gamepads[i].id, new Uint8Array(wio.module.exports.memory.buffer, ptr));
    },

    openJoystick(i, ptr) {
        if (wio.gamepads[i] === null || !wio.gamepads[i].connected) return false;
        const lengths = new Uint32Array(wio.module.exports.memory.buffer, ptr, 2);
        lengths[0] = wio.gamepads[i].axes.length;
        lengths[1] = wio.gamepads[i].buttons.length;
        return true;
    },

    getJoystickState(index, axes_ptr, axes_len, buttons_ptr, buttons_len) {
        if (wio.gamepads[index] === null || !wio.gamepads[index].connected) return false;
        const axes = new Uint16Array(wio.module.exports.memory.buffer, axes_ptr, axes_len);
        const buttons = new Uint8Array(wio.module.exports.memory.buffer, buttons_ptr, buttons_len);
        for (let i = 0; i < axes_len; i++) {
            axes[i] = (wio.gamepads[index].axes[i] + 1) * 32767.5;
        }
        for (let i = 0; i < buttons_len; i++) {
            buttons[i] = wio.gamepads[index].buttons[i].pressed;
        }
        return true;
    },

    getString(ptr, len) {
        return new TextDecoder().decode(new Uint8Array(wio.module.exports.memory.buffer, ptr, len));
    },

    keys: {
        KeyA: 5,
        KeyB: 6,
        KeyC: 7,
        KeyD: 8,
        KeyE: 9,
        KeyF: 10,
        KeyG: 11,
        KeyH: 12,
        KeyI: 13,
        KeyJ: 14,
        KeyK: 15,
        KeyL: 16,
        KeyM: 17,
        KeyN: 18,
        KeyO: 19,
        KeyP: 20,
        KeyQ: 21,
        KeyR: 22,
        KeyS: 23,
        KeyT: 24,
        KeyU: 25,
        KeyV: 26,
        KeyW: 27,
        KeyX: 28,
        KeyY: 29,
        KeyZ: 30,
        Digit1: 31,
        Digit2: 32,
        Digit3: 33,
        Digit4: 34,
        Digit5: 35,
        Digit6: 36,
        Digit7: 37,
        Digit8: 38,
        Digit9: 39,
        Digit0: 40,
        Enter: 41,
        Escape: 42,
        Backspace: 43,
        Tab: 44,
        Space: 45,
        Minus: 46,
        Equal: 47,
        BracketLeft: 48,
        BracketRight: 49,
        Backslash: 50,
        Semicolon: 51,
        Quote: 52,
        Backquote: 53,
        Comma: 54,
        Period: 55,
        Slash: 56,
        CapsLock: 57,
        F1: 58,
        F2: 59,
        F3: 60,
        F4: 61,
        F5: 62,
        F6: 63,
        F7: 64,
        F8: 65,
        F9: 66,
        F10: 67,
        F11: 68,
        F12: 69,
        PrintScreen: 70,
        ScrollLock: 71,
        Pause: 72,
        Insert: 73,
        Home: 74,
        PageUp: 75,
        Delete: 76,
        End: 77,
        PageDown: 78,
        ArrowRight: 79,
        ArrowLeft: 80,
        ArrowDown: 81,
        ArrowUp: 82,
        NumLock: 83,
        NumpadDivide: 84,
        NumpadMultiply: 85,
        NumpadSubtract: 86,
        NumpadAdd: 87,
        NumpadEnter: 88,
        Numpad1: 89,
        Numpad2: 90,
        Numpad3: 91,
        Numpad4: 92,
        Numpad5: 93,
        Numpad6: 94,
        Numpad7: 95,
        Numpad8: 96,
        Numpad9: 97,
        Numpad0: 98,
        NumpadDecimal: 99,
        IntlBackslash: 100,
        ContextMenu: 101,
        NumpadEqual: 102,
        F13: 103,
        F14: 104,
        F15: 105,
        F16: 106,
        F17: 107,
        F18: 108,
        F19: 109,
        F20: 110,
        F21: 111,
        F22: 112,
        F23: 113,
        F24: 114,
        NumpadComma: 115,
        IntlRo: 116,
        KanaMode: 117,
        IntlYen: 118,
        Convert: 119,
        NonConvert: 120,
        Lang1: 121,
        Lang2: 122,
        ControlLeft: 123,
        ShiftLeft: 124,
        AltLeft: 125,
        MetaLeft: 126,
        ControlRight: 127,
        ShiftRight: 128,
        AltRight: 129,
        MetaRight: 130,
    },

    buttons: {
        0: 0,
        1: 2,
        2: 1,
        3: 3,
        4: 4,
    },
};

export default wio;
