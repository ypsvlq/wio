const wio = {
    module: undefined,
    canvas: undefined,
    log: "",
    events: [],
    cursor: undefined,

    run(module, canvas) {
        wio.module = module;
        wio.canvas = canvas;

        module.exports._start();
        requestAnimationFrame(wio.loop);

        canvas.style.width = `${canvas.width}px`;
        canvas.style.height = `${canvas.height}px`;
        canvas.width *= devicePixelRatio;
        canvas.height *= devicePixelRatio;

        wio.events.push(
            5, parseInt(canvas.style.width), parseInt(canvas.style.height),
            7, canvas.width, canvas.height,
            8, devicePixelRatio,
            1,
        );

        new ResizeObserver(() => wio.events.push(
            5, parseInt(canvas.style.width), parseInt(canvas.style.height),
            7, canvas.width, canvas.height,
            8, devicePixelRatio,
        )).observe(canvas);

        canvas.addEventListener("contextmenu", event => event.preventDefault());
        canvas.addEventListener("keydown", event => {
            event.preventDefault();
            const key = wio.keys[event.code];
            if (key) wio.events.push(event.repeat ? 11 : 10, key);
            if ([...event.key].length == 1) wio.events.push(9, event.key.codePointAt(0));
        });
        canvas.addEventListener("keyup", event => {
            const key = wio.keys[event.code];
            if (key) wio.events.push(12, key);
        });
        canvas.addEventListener("mousedown", event => {
            const button = wio.buttons[event.button];
            if (button != undefined) wio.events.push(10, button);
        });
        canvas.addEventListener("mouseup", event => {
            const button = wio.buttons[event.button];
            if (button != undefined) wio.events.push(12, button);
        });
        canvas.addEventListener("mousemove", event => {
            wio.events.push(13, event.offsetX, event.offsetY);
        });
    },

    loop() {
        if (wio.module.exports.wioLoop()) {
            requestAnimationFrame(wio.loop);
        }
    },

    write(ptr, len) {
        wio.log += wio.getString(ptr, len);
    },

    flush() {
        console.log(wio.log);
        wio.log = "";
    },

    shift() {
        return wio.events.shift();
    },

    shiftFloat() {
        return wio.events.shift();
    },

    jsCursor(cursor) {
        wio.cursor = {
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
        wio.canvas.style.cursor = wio.cursor;
    },

    jsCursorMode(mode) {
        switch (mode) {
            case 0:
                wio.canvas.style.cursor = wio.cursor;
                break;
            case 1:
                wio.cursor = wio.canvas.style.cursor;
                wio.canvas.style.cursor = "none";
                break;
        }
    },

    jsMessageBox(ptr, len) {
        alert(wio.getString(ptr, len));
    },

    jsSetClipboard(ptr, len) {
        navigator.clipboard.writeText(wio.getString(ptr, len));
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
