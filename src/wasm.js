"use strict";

const wio = {
    module: undefined,
    canvas: undefined,
    log: "",
    events: [],
    cursor: undefined,
    cursor_mode: undefined,
    gamepads: undefined,
    gamepad_ids: undefined,
    gl: undefined,
    objects: [,],

    run(module, canvas) {
        wio.module = module;
        wio.canvas = canvas;

        module.exports._start();
        requestAnimationFrame(wio.loop);

        new ResizeObserver(wio.resize).observe(canvas);
        wio.resize();
        wio.events.push(1);

        canvas.addEventListener("contextmenu", event => event.preventDefault());
        canvas.addEventListener("focus", () => wio.events.push(2));
        canvas.addEventListener("blur", () => wio.events.push(3));
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
            if (wio.cursor_mode != 2) {
                wio.events.push(13, event.offsetX, event.offsetY);
            } else {
                wio.events.push(14, event.movementX, event.movementY);
            }
        });
        canvas.addEventListener("wheel", event => {
            if (event.deltaY != 0) wio.events.push(15, event.deltaY * 0.01);
            if (event.deltaX != 0) wio.events.push(16, event.deltaX * 0.01);
        });

        addEventListener("gamepadconnected", event => wio.module.exports.wioJoystick(event.gamepad.index));
    },

    loop() {
        if (wio.module.exports.wioLoop()) {
            requestAnimationFrame(wio.loop);
        }
    },

    resize() {
        const width = parseInt(canvas.scrollWidth);
        const height = parseInt(canvas.scrollHeight);
        canvas.width = width * devicePixelRatio;
        canvas.height = height * devicePixelRatio;
        wio.events.push(
            8, (document.fullscreenElement == wio.canvas) ? 2 : 0,
            5, width, height,
            6, canvas.width, canvas.height,
            7, devicePixelRatio,
        );
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

    setFullscreen(fullscreen) {
        if (fullscreen) {
            wio.canvas.requestFullscreen().catch(() => { });
        } else {
            document.exitFullscreen().catch(() => { });
        }
    },

    setCursor(cursor) {
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

        if (wio.cursor_mode == 0) {
            wio.canvas.style.cursor = wio.cursor;
        }
    },

    setCursorMode(mode) {
        wio.cursor_mode = mode;

        if (mode == 0) {
            wio.canvas.style.cursor = wio.cursor;
        } else {
            wio.canvas.style.cursor = "none";
        }

        if (mode == 2) {
            wio.canvas.requestPointerLock({ unadjustedMovement: true });
        } else {
            document.exitPointerLock();
        }
    },

    createContext() {
        wio.gl = wio.canvas.getContext("webgl");
    },

    getJoysticks() {
        wio.gamepads = navigator.getGamepads();
        wio.gamepad_ids = [];
        const encoder = new TextEncoder();
        for (let i = 0; i < wio.gamepads.length; i++) {
            if (wio.gamepads[i] != null) {
                wio.gamepad_ids[i] = encoder.encode(wio.gamepads[i].id);
            } else {
                wio.gamepad_ids[i] = { length: 0 };
            }
        }
        return wio.gamepads.length;
    },

    getJoystickIdLen(i) {
        return wio.gamepad_ids[i].length;
    },

    getJoystickId(i, ptr) {
        new Uint8Array(wio.module.exports.memory.buffer, ptr).set(wio.gamepad_ids[i]);
    },

    openJoystick(i, ptr) {
        if (wio.gamepads[i] == null || !wio.gamepads[i].connected) return false;
        const lengths = new Uint32Array(wio.module.exports.memory.buffer, ptr, 2);
        lengths[0] = wio.gamepads[i].axes.length;
        lengths[1] = wio.gamepads[i].buttons.length;
        return true;
    },

    getJoystickState(index, axes_ptr, axes_len, buttons_ptr, buttons_len) {
        if (wio.gamepads[index] == null || !wio.gamepads[index].connected) return false;
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

    messageBox(ptr, len) {
        alert(wio.getString(ptr, len));
    },

    setClipboardText(ptr, len) {
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

    getStringZ(ptr) {
        const array = new Uint8Array(wio.module.exports.memory.buffer, ptr);
        let len = 0;
        while (array[len]) len++;
        return new TextDecoder().decode(array.subarray(0, len));
    },

    setStringZ(ptr, max, length, string) {
        const buffer = new Uint8Array(wio.module.exports.memory.buffer, ptr);
        const result = new TextEncoder().encodeInto(string, buffer.subarray(0, max - 1));
        buffer[result.written] = 0;
        if (length != 0) {
            new Int32Array(wio.module.exports.memory.buffer, length)[0] = result.written;
        }
    },

    setParams(Array, ptr, value) {
        const buffer = new Array(wio.module.exports.memory.buffer, ptr);
        if (typeof value[Symbol.iterator] == "function") {
            buffer.set(value);
        } else {
            buffer[0] = value;
        }
    },

    pushObject(object) {
        const index = wio.objects.indexOf(null);
        if (index != -1) {
            wio.objects[index] = object;
            return index;
        } else {
            return wio.objects.push(object) - 1;
        }
    },

    glActiveTexture(texture) {
        wio.gl.activeTexture(texture);
    },

    glAttachShader(program, shader) {
        wio.gl.attachShader(wio.objects[program], wio.objects[shader]);
    },

    glBindAttribLocation(program, index, name) {
        wio.gl.bindAttribLocation(wio.objects[program], index, wio.getStringZ(name));
    },

    glBindBuffer(target, buffer) {
        wio.gl.bindBuffer(target, wio.objects[buffer]);
    },

    glBindFramebuffer(target, framebuffer) {
        wio.gl.bindFramebuffer(target, framebuffer ? wio.objects[framebuffer] : null);
    },

    glBindRenderbuffer(target, renderbuffer) {
        wio.gl.bindRenderbuffer(target, wio.objects[renderbuffer]);
    },

    glBindTexture(target, texture) {
        wio.gl.bindTexture(target, wio.objects[texture]);
    },

    glBlendColor(red, green, blue, alpha) {
        wio.gl.blendColor(red, green, blue, alpha);
    },

    glBlendEquation(mode) {
        wio.gl.blendEquation(mode);
    },

    glBlendEquationSeparate(modeRGB, modeAlpha) {
        wio.gl.blendEquationSeparate(modeRGB, modeAlpha);
    },

    glBlendFunc(sfactor, dfactor) {
        wio.gl.blendFunc(sfactor, dfactor);
    },

    glBlendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha) {
        wio.gl.blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha);
    },

    glBufferData(target, size, data, usage) {
        wio.gl.bufferData(target, new Uint8Array(wio.module.exports.memory.buffer, data, size), usage);
    },

    glBufferSubData(target, offset, size, data) {
        wio.gl.bufferSubData(target, offset, new Uint8Array(wio.module.exports.memory.buffer, data, size));
    },

    glCheckFramebufferStatus(target) {
        return wio.gl.checkFramebufferStatus(target);
    },

    glClear(mask) {
        wio.gl.clear(mask);
    },

    glClearColor(red, green, blue, alpha) {
        wio.gl.clearColor(red, green, blue, alpha);
    },

    glClearDepthf(depth) {
        wio.gl.clearDepth(depth);
    },

    glClearStencil(s) {
        wio.gl.clearStencil(s);
    },

    glColorMask(red, green, blue, alpha) {
        wio.gl.colorMask(red, green, blue, alpha);
    },

    glCompileShader(shader) {
        wio.gl.compileShader(wio.objects[shader]);
    },

    glCompressedTexImage2D(target, level, internalformat, width, height, border, imageSize, data) {
        wio.gl.compressedTexImage2D(target, level, internalformat, width, height, border, new Uint8Array(wio.module.exports.memory.buffer, data, imageSize));
    },

    glCompressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, imageSize, data) {
        wio.gl.compressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, new Uint8Array(wio.module.exports.memory.buffer, data, imageSize));
    },

    glCopyTexImage2D(target, level, internalformat, x, y, width, height, border) {
        wio.gl.copyTexImage2D(target, level, internalformat, x, y, width, height, border);
    },

    glCopyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height) {
        wio.gl.copyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height);
    },

    glCreateProgram() {
        const program = wio.gl.createProgram();
        return wio.pushObject(program);
    },

    glCreateShader(type) {
        const shader = wio.gl.createShader(type);
        return wio.pushObject(shader);
    },

    glCullFace(mode) {
        wio.gl.cullFace(mode);
    },

    glDeleteBuffers(n, ptr) {
        const buffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            wio.objects[buffers[i]] = null;
        }
    },

    glDeleteFramebuffers(n, framebuffers) {
        wio.glDeleteBuffers(n, framebuffers);
    },

    glDeleteProgram(program) {
        wio.objects[program] = null;
    },

    glDeleteRenderbuffers(n, renderbuffers) {
        wio.glDeleteBuffers(n, renderbuffers);
    },

    glDeleteShader(shader) {
        wio.objects[shader] = null;
    },

    glDeleteTextures(n, textures) {
        wio.glDeleteBuffers(n, textures);
    },

    glDepthFunc(func) {
        wio.gl.depthFunc(func);
    },

    glDepthMask(flag) {
        wio.gl.depthMask(flag);
    },

    glDepthRangef(n, f) {
        wio.gl.depthRange(n, f);
    },

    glDetachShader(program, shader) {
        wio.gl.detachShader(wio.objects[program], wio.objects[shader]);
    },

    glDisable(cap) {
        wio.gl.disable(cap);
    },

    glDisableVertexAttribArray(index) {
        wio.gl.disableVertexAttribArray(index);
    },

    glDrawArrays(mode, first, count) {
        wio.gl.drawArrays(mode, first, count);
    },

    glDrawElements(mode, count, type, offset) {
        wio.gl.drawElements(mode, count, type, offset);
    },

    glEnable(cap) {
        wio.gl.enable(cap);
    },

    glEnableVertexAttribArray(index) {
        wio.gl.enableVertexAttribArray(index);
    },

    glFinish() {
        wio.gl.finish();
    },

    glFlush() {
        wio.gl.flush();
    },

    glFramebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer) {
        wio.gl.framebufferRenderbuffer(target, attachment, renderbuffertarget, wio.objects[renderbuffer]);
    },

    glFramebufferTexture2D(target, attachment, textarget, texture, level) {
        wio.gl.framebufferTexture2D(target, attachment, textarget, wio.objects[texture], level);
    },

    glFrontFace(mode) {
        wio.gl.frontFace(mode);
    },

    glGenBuffers(n, ptr) {
        const buffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            buffers[i] = wio.pushObject(wio.gl.createBuffer());
        }
    },

    glGenerateMipmap(target) {
        wio.gl.generateMipmap(target);
    },

    glGenFramebuffers(n, ptr) {
        const framebuffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            framebuffers[i] = wio.pushObject(wio.gl.createFramebuffer());
        }
    },

    glGenRenderbuffers(n, ptr) {
        const renderbuffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            renderbuffers[i] = wio.pushObject(wio.gl.createRenderbuffer());
        }
    },

    glGenTextures(n, ptr) {
        const textures = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            textures[i] = wio.pushObject(wio.gl.createTexture());
        }
    },

    glGetActiveAttrib(program, index, bufSize, length, size, type, name) {
        const info = wio.gl.getActiveAttrib(wio.objects[program], index);
        if (info == null) return;
        new Int32Array(wio.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(wio.module.exports.memory.buffer, type)[0] = info.type;
        wio.setStringZ(name, bufSize, length, info.name);
    },

    glGetActiveUniform(program, index, bufSize, length, size, type, name) {
        const info = wio.gl.getActiveUniform(wio.objects[program], index);
        if (info == null) return;
        new Int32Array(wio.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(wio.module.exports.memory.buffer, type)[0] = info.type;
        wio.setStringZ(name, bufSize, length, info.name);
    },

    glGetAttachedShaders(program, maxCount, count, shaders) {
        const indices = wio.gl.getAttachedShaders(wio.objects[program]).map(shader => wio.objects.indexOf(shader));
        const buffer = new Uint32Array(wio.module.exports.memory.buffer, shaders);
        for (var i = 0; i < maxCount && i < indices.length; i++) {
            buffer[i] = indices[i];
        }
        if (count != 0) {
            new Int32Array(wio.module.exports.memory.buffer, count)[0] = i;
        }
    },

    glGetAttribLocation(program, name) {
        return wio.gl.getAttribLocation(wio.objects[program], wio.getStringZ(name));
    },

    glGetBooleanv(pname, params) {
        wio.setParams(Uint8Array, params, wio.gl.getParameter(pname));
    },

    glGetBufferParameteriv(target, value, data) {
        wio.setParams(Int32Array, data, wio.gl.getBufferParameter(target, value));
    },

    glGetError() {
        return wio.gl.getError();
    },

    glGetFloatv(pname, params) {
        wio.setParams(Float32Array, params, wio.gl.getParameter(pname));
    },

    glGetFramebufferAttachmentParameteriv(target, attachment, pname, params) {
        const value = wio.gl.getFramebufferAttachmentParameter(target, attachment, pname);
        if (typeof value == "object") {
            value = wio.objects.indexOf(value);
        }
        new Int32Array(wio.module.exports.memory.buffer, params)[0] = value;
    },

    glGetIntegerv(pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getParameter(pname));
    },

    glGetProgramiv(program, pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getProgramParameter(wio.objects[program], pname));
    },

    glGetProgramInfoLog(program, maxLength, length, infoLog) {
        wio.setStringZ(infoLog, maxLength, length, wio.gl.getProgramInfoLog(wio.objects[program]));
    },

    glGetRenderbufferParameteriv(target, pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getRenderbufferParameter(target, pname));
    },

    glGetShaderiv(shader, pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getShaderParameter(wio.objects[shader], pname));
    },

    glGetShaderInfoLog(shader, maxLength, length, infoLog) {
        wio.setStringZ(infoLog, maxLength, length, wio.gl.getShaderInfoLog(wio.objects[shader]));
    },

    glGetShaderPrecisionFormat(shaderType, precisionType, range, precision) {
        const format = wio.gl.getShaderPrecisionFormat(shaderType, precisionType);
        new Int32Array(wio.module.exports.memory.buffer, range, 2).set([format.rangeMin, format.rangeMax]);
        new Int32Array(wio.module.exports.memory.buffer, precision)[0] = format.precision;
    },

    glGetShaderSource(shader, bufSize, length, source) {
        wio.setStringZ(source, bufSize, length, wio.gl.getShaderSource(wio.objects[shader]));
    },

    glGetString() { },

    glGetTexParameterfv(target, pname, params) {
        wio.setParams(Float32Array, params, wio.gl.getTexParameter(target, pname));
    },

    glGetTexParameteriv(target, pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getTexParameter(target, pname));
    },

    glGetUniformfv(program, location, params) {
        wio.setParams(Float32Array, params, wio.gl.getUniform(wio.objects[program], location));
    },

    glGetUniformiv(program, location, params) {
        wio.setParams(Int32Array, params, wio.gl.getUniform(wio.objects[program], location));
    },

    glGetUniformLocation(program, name) {
        return wio.gl.getUniformLocation(wio.objects[program], wio.getStringZ(name));
    },

    glGetVertexAttribfv(index, pname, params) {
        wio.setParams(Float32Array, params, wio.gl.getVertexAttrib(index, pname));
    },

    glGetVertexAttribiv(index, pname, params) {
        wio.setParams(Int32Array, params, wio.gl.getVertexAttrib(index, pname));
    },

    glGetVertexAttribPointerv(index, pname, pointer) {
        new Uint32Array(wio.module.exports.memory.buffer, pointer)[0] = wio.gl.getVertexAttribOffset(index, pname);
    },

    glHint(target, mode) {
        wio.gl.hint(target, mode);
    },

    glIsBuffer(buffer) {
        return wio.gl.isBuffer(wio.objects[buffer]);
    },

    glIsEnabled(cap) {
        return wio.gl.isEnabled(cap);
    },

    glIsFramebuffer(framebuffer) {
        return wio.gl.isFramebuffer(wio.objects[framebuffer]);
    },

    glIsProgram(program) {
        return wio.gl.isProgram(wio.objects[program]);
    },

    glIsRenderbuffer(renderbuffer) {
        return wio.gl.isRenderbuffer(wio.objects[renderbuffer]);
    },

    glIsShader(shader) {
        return wio.gl.isShader(wio.objects[shader]);
    },

    glIsTexture(texture) {
        return wio.gl.isTexture(wio.objects[texture]);
    },

    glLineWidth(width) {
        wio.gl.lineWidth(width);
    },

    glLinkProgram(program) {
        wio.gl.linkProgram(wio.objects[program]);
    },

    glPixelStorei(pname, param) {
        wio.gl.pixelStorei(pname, param);
    },

    glPolygonOffset(factor, units) {
        wio.gl.polygonOffset(factor, units);
    },

    glReadPixels(x, y, width, height, format, type, pixels) {
        wio.gl.readPixels(x, y, width, height, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    glRenderbufferStorage(target, internalformat, width, height) {
        wio.gl.renderbufferStorage(target, internalformat, width, height);
    },

    glSampleCoverage(value, invert) {
        wio.gl.sampleCoverage(value, invert);
    },

    glScissor(x, y, width, height) {
        wio.gl.scissor(x, y, width, height);
    },

    glShaderSource(shader, count, strings_ptr, lengths_ptr) {
        const strings = new Uint32Array(wio.module.exports.memory.buffer, strings_ptr, count);
        const lengths = new Int32Array(wio.module.exports.memory.buffer, lengths_ptr, count);
        var string = "";
        for (let i = 0; i < count; i++) {
            string += (lengths_ptr != 0 && lengths[i] >= 0) ? wio.getString(strings[i], lengths[i]) : wio.getStringZ(strings[i]);
        }
        wio.gl.shaderSource(wio.objects[shader], string);
    },

    glStencilFunc(func, ref, mask) {
        wio.gl.stencilFunc(func, ref, mask);
    },

    glStencilFuncSeparate(face, func, ref, mask) {
        wio.gl.stencilFuncSeparate(face, func, ref, mask);
    },

    glStencilMask(mask) {
        wio.gl.stencilMask(mask);
    },

    glStencilMaskSeparate(face, mask) {
        wio.gl.stencilMaskSeparate(face, mask);
    },

    glStencilOp(fail, zfail, zpass) {
        wio.gl.stencilOp(fail, zfail, zpass);
    },

    glStencilOpSeparate(face, sfail, dpfail, dppass) {
        wio.gl.stencilOpSeparate(face, sfail, dpfail, dppass);
    },

    glTexImage2D(target, level, internalformat, width, height, border, format, type, pixels) {
        wio.gl.texImage2D(target, level, internalformat, width, height, border, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    glTexParameterf(target, pname, param) {
        wio.gl.texParameterf(target, pname, param);
    },

    glTexParameteri(target, pname, param) {
        wio.gl.texParameteri(target, pname, param);
    },

    glTexSubImage2D(target, level, xoffset, yoffset, width, height, format, type, pixels) {
        wio.gl.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    glUniform1f(location, v0) {
        wio.gl.uniform1f(location, v0);
    },

    glUniform1fv(location, count, value) {
        wio.gl.uniform1fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform1i(location, v0) {
        wio.gl.uniform1i(location, v0);
    },

    glUniform1iv(location, count, value) {
        wio.gl.uniform1iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform2f(location, v0, v1) {
        wio.gl.uniform2f(location, v0, v1);
    },

    glUniform2fv(location, count, value) {
        wio.gl.uniform2fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform2i(location, v0, v1) {
        wio.gl.uniform2i(location, v0, v1);
    },

    glUniform2iv(location, count, value) {
        wio.gl.uniform2iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform3f(location, v0, v1, v2) {
        wio.gl.uniform3f(location, v0, v1, v2);
    },

    glUniform3fv(location, count, value) {
        wio.gl.uniform3fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform3i(location, v0, v1, v2) {
        wio.gl.uniformif(location, v0, v1, v2);
    },

    glUniform3iv(location, count, value) {
        wio.gl.uniform3iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform4f(location, v0, v1, v2, v3) {
        wio.gl.uniform4f(location, v0, v1, v2, v3);
    },

    glUniform4fv(location, count, value) {
        wio.gl.uniform4fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniform4i(location, v0, v1, v2, v3) {
        wio.gl.uniform4i(location, v0, v1, v2, v3);
    },

    glUniform4iv(location, count, value) {
        wio.gl.uniform4iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix2fv(location, count, transpose, value) {
        wio.gl.uniformMatrix2fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix3fv(location, count, transpose, value) {
        wio.gl.uniformMatrix3fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUniformMatrix4fv(location, count, transpose, value) {
        wio.gl.uniformMatrix4fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    glUseProgram(program) {
        wio.gl.useProgram(wio.objects[program]);
    },

    glValidateProgram(program) {
        wio.gl.validateProgram(wio.objects[program]);
    },

    glVertexAttrib1f(index, x) {
        wio.gl.vertexAttrib1f(index, x);
    },

    glVertexAttrib1fv(index, v) {
        wio.gl.vertexAttrib1fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    glVertexAttrib2f(index, x, y) {
        wio.gl.vertexAttrib2f(index, x, y);
    },

    glVertexAttrib2fv(index, v) {
        wio.gl.vertexAttrib2fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    glVertexAttrib3f(index, x, y, z) {
        wio.gl.vertexAttrib3f(index, x, y, z);
    },

    glVertexAttrib3fv(index, v) {
        wio.gl.vertexAttrib3fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    glVertexAttrib4f(index, x, y, z, w) {
        wio.gl.vertexAttrib4f(index, x, y, z, w);
    },

    glVertexAttrib4fv(index, v) {
        wio.gl.vertexAttrib4fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    glVertexAttribPointer(index, size, type, normalized, stride, offset) {
        wio.gl.vertexAttribPointer(index, size, type, normalized, stride, offset);
    },

    glViewport(x, y, width, height) {
        wio.gl.viewport(x, y, width, height);
    },
};
