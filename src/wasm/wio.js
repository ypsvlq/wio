class Wio {
    constructor(canvases) {
        /** @type {WebAssembly.Instance} */
        this.instance = undefined;

        /** @type {HTMLCanvasElement[]} */
        this.canvases = canvases;

        /** @type {{canvas: HTMLCanvasElement, events: number[], input: HTMLInputElement, text: boolean, cursor: string, cursor_mode: number}[]} */
        this.windows = [];

        this.gamepads = navigator.getGamepads();
    }

    run(instance) {
        this.instance = instance;
        this.instance.exports._start();
        this.loop();

        addEventListener("pointerlockchange", () => {
            for (const window of this.windows) {
                if (window.cursor_mode === 2) {
                    window.canvas.style.cursor = (window.canvas === document.pointerLockElement) ? "none" : window.cursor;
                }
            }
        });

        addEventListener("gamepadconnected", (event) => {
            this.gamepads = navigator.getGamepads();
            this.instance.exports.wioJoystick(event.gamepad.index);
        });
    }

    loop() {
        if (this.instance.exports.wioLoop()) {
            requestAnimationFrame(() => this.loop());
        }
    }

    getString(ptr, len) {
        return new TextDecoder().decode(new Uint8Array(this.instance.exports.memory.buffer, ptr, len));
    }

    imports = {
        shift: (id) => this.windows[id].events.shift(),

        shiftFloat: (id) => this.windows[id].events.shift(),

        messageBox: (ptr, len) => alert(this.getString(ptr, len)),

        createWindow: (width, height) => {
            const canvas = this.canvases.shift();
            if (canvas === undefined) throw new Error("no canvas available");

            if (canvas.style.width === "") canvas.style.width = `${width}px`;
            if (canvas.style.height === "") canvas.style.height = `${height}px`;

            const events = [3];

            const input = document.createElement("input");
            input.tabIndex = -1;
            input.style.display = "none";
            input.style.opacity = "0";
            input.style.position = "absolute";
            input.style.border = "0px";
            input.style.padding = "0px";
            input.addEventListener("input", (event) => {
                switch (event.inputType) {
                    case "insertText":
                    case "insertCompositionText":
                    case "insertFromPaste":
                    case "insertFromPasteAsQuotation":
                    case "insertFromDrop":
                    case "insertTranspose":
                    case "insertReplacementText":
                    case "insertFromYank":
                        if (event.inputType === "insertCompositionText") {
                            events.push(11);
                        }
                        for (const char of event.data) {
                            events.push((event.isComposing ? 12 : 10), char.codePointAt(0));
                        }
                        if (!event.isComposing) {
                            input.value = "";
                        }
                        break;
                }
            });
            input.addEventListener("keydown", (event) => canvas.dispatchEvent(new KeyboardEvent("keydown", event)));
            input.addEventListener("keyup", (event) => canvas.dispatchEvent(new KeyboardEvent("keyup", event)));
            canvas.parentElement.appendChild(input);

            const window = {
                canvas: canvas,
                events: events,
                input: input,
                text: false,
                cursor: "default",
                cursor_mode: 0,
            };

            new ResizeObserver(() => {
                canvas.width = canvas.scrollWidth * devicePixelRatio;
                canvas.height = canvas.scrollHeight * devicePixelRatio;
                events.push(
                    6, (document.fullscreenElement === canvas) ? 2 : 0,
                    7, canvas.scrollWidth, canvas.scrollHeight,
                    8, canvas.width, canvas.height,
                    9, devicePixelRatio,
                    5,
                );
            }).observe(canvas);
            canvas.addEventListener("contextmenu", (event) => event.preventDefault());
            canvas.addEventListener("focus", () => {
                events.push(1);
                if (window.text) {
                    input.focus();
                }
            });
            canvas.addEventListener("blur", () => {
                if (!window.text) {
                    events.push(2);
                }
            });
            canvas.addEventListener("keydown", (event) => {
                event.preventDefault();
                const key = Wio.keys[event.code];
                if (key) events.push(event.repeat ? 15 : 14, key);
            });
            canvas.addEventListener("keyup", (event) => {
                const key = Wio.keys[event.code];
                if (key) events.push(16, key);
            });
            canvas.addEventListener("mousedown", (event) => {
                const button = Wio.buttons[event.button];
                if (button !== undefined) events.push(14, button);
                if (window.cursor_mode === 2) canvas.requestPointerLock({ unadjustedMovement: true });
            });
            canvas.addEventListener("mouseup", (event) => {
                const button = Wio.buttons[event.button];
                if (button !== undefined) events.push(16, button);
            });
            canvas.addEventListener("mousemove", (event) => {
                if (window.cursor_mode !== 2) {
                    events.push(17, event.offsetX, event.offsetY);
                } else {
                    events.push(18, event.movementX, event.movementY);
                }
            });
            canvas.addEventListener("wheel", (event) => {
                if (event.deltaY !== 0) events.push(19, event.deltaY);
                if (event.deltaX !== 0) events.push(20, event.deltaX);
            });

            this.windows.push(window);
            return this.windows.length - 1;
        },

        enableTextInput: (id, x, y) => {
            this.windows[id].text = true;
            const rect = this.windows[id].canvas.getBoundingClientRect();
            this.windows[id].input.style.left = `${rect.x + x}px`;
            this.windows[id].input.style.top = `${rect.y + y}px`;
            this.windows[id].input.style.display = "unset";
            if (document.activeElement === this.windows[id].canvas) {
                this.windows[id].input.focus();
            }
        },

        disableTextInput: (id) => {
            this.windows[id].text = false;
            this.windows[id].input.style.display = "none";
            if (document.activeElement === this.windows[id].input) {
                this.windows[id].canvas.focus();
            }
        },

        setFullscreen: (id, fullscreen) => {
            if (fullscreen) {
                this.windows[id].canvas.requestFullscreen().catch(() => { });
            } else {
                document.exitFullscreen().catch(() => { });
            }
        },

        setSize: (id, width, height) => {
            this.windows[id].canvas.style.width = `${width}px`;
            this.windows[id].canvas.style.height = `${height}px`;
        },

        setCursor: (id, cursor) => {
            this.windows[id].cursor = {
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

            if (this.windows[id].cursor_mode === 0) {
                this.windows[id].canvas.style.cursor = this.windows[id].cursor;
            }
        },

        setCursorMode: (id, mode) => {
            this.windows[id].cursor_mode = mode;

            if (mode === 0) {
                this.windows[id].canvas.style.cursor = this.windows[id].cursor;
            } else {
                this.windows[id].canvas.style.cursor = "none";
            }

            if (mode === 2) {
                this.windows[id].canvas.requestPointerLock({ unadjustedMovement: true });
            } else {
                document.exitPointerLock();
            }
        },

        setClipboardText: (ptr, len) => {
            navigator.clipboard.writeText(this.getString(ptr, len)).catch(() => { })
        },

        getJoystickCount: () => this.gamepads.length,

        getJoystickIdLen: (i) => {
            return (this.gamepads[i] !== null) ? new TextEncoder().encode(this.gamepads[i].id).length : 0;
        },

        getJoystickId: (i, ptr) => {
            new TextEncoder().encodeInto(this.gamepads[i].id, new Uint8Array(this.instance.exports.memory.buffer, ptr));
        },

        openJoystick: (i, ptr) => {
            if (this.gamepads[i] === null || !this.gamepads[i].connected) return false;
            const lengths = new Uint32Array(this.instance.exports.memory.buffer, ptr, 2);
            lengths[0] = this.gamepads[i].axes.length;
            lengths[1] = this.gamepads[i].buttons.length;
            return true;
        },

        getJoystickState: (index, axes_ptr, axes_len, buttons_ptr, buttons_len) => {
            if (this.gamepads[index] === null || !this.gamepads[index].connected) return false;
            const axes = new Uint16Array(this.instance.exports.memory.buffer, axes_ptr, axes_len);
            const buttons = new Uint8Array(this.instance.exports.memory.buffer, buttons_ptr, buttons_len);
            for (let i = 0; i < axes_len; i++) {
                axes[i] = (this.gamepads[index].axes[i] + 1) * 32767.5;
            }
            for (let i = 0; i < buttons_len; i++) {
                buttons[i] = this.gamepads[index].buttons[i].pressed;
            }
            return true;
        },
    };

    static keys = {
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
    };

    static buttons = {
        0: 0,
        1: 2,
        2: 1,
        3: 3,
        4: 4,
    };
}

export default Wio;
