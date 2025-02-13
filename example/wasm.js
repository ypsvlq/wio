const log = {
    buffer: "",

    write(ptr, len) {
        log.buffer += wio.getString(ptr, len);
    },

    flush() {
        console.log(log.buffer);
        log.buffer = "";
    },
};

const gl = {
    context: undefined,
    objects: [,],

    init() {
        gl.context = wio.canvas.getContext("webgl");
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
        const index = gl.objects.indexOf(null);
        if (index != -1) {
            gl.objects[index] = object;
            return index;
        } else {
            return gl.objects.push(object) - 1;
        }
    },

    deleteObjects(n, ptr) {
        const list = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            gl.objects[list[i]] = null;
        }
    },

    activeTexture(texture) {
        gl.context.activeTexture(texture);
    },

    attachShader(program, shader) {
        gl.context.attachShader(gl.objects[program], gl.objects[shader]);
    },

    bindAttribLocation(program, index, name) {
        gl.context.bindAttribLocation(gl.objects[program], index, gl.getStringZ(name));
    },

    bindBuffer(target, buffer) {
        gl.context.bindBuffer(target, gl.objects[buffer]);
    },

    bindFramebuffer(target, framebuffer) {
        gl.context.bindFramebuffer(target, framebuffer ? gl.objects[framebuffer] : null);
    },

    bindRenderbuffer(target, renderbuffer) {
        gl.context.bindRenderbuffer(target, gl.objects[renderbuffer]);
    },

    bindTexture(target, texture) {
        gl.context.bindTexture(target, gl.objects[texture]);
    },

    blendColor(red, green, blue, alpha) {
        gl.context.blendColor(red, green, blue, alpha);
    },

    blendEquation(mode) {
        gl.context.blendEquation(mode);
    },

    blendEquationSeparate(modeRGB, modeAlpha) {
        gl.context.blendEquationSeparate(modeRGB, modeAlpha);
    },

    blendFunc(sfactor, dfactor) {
        gl.context.blendFunc(sfactor, dfactor);
    },

    blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha) {
        gl.context.blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha);
    },

    bufferData(target, size, data, usage) {
        gl.context.bufferData(target, new Uint8Array(wio.module.exports.memory.buffer, data, size), usage);
    },

    bufferSubData(target, offset, size, data) {
        gl.context.bufferSubData(target, offset, new Uint8Array(wio.module.exports.memory.buffer, data, size));
    },

    checkFramebufferStatus(target) {
        return gl.context.checkFramebufferStatus(target);
    },

    clear(mask) {
        gl.context.clear(mask);
    },

    clearColor(red, green, blue, alpha) {
        gl.context.clearColor(red, green, blue, alpha);
    },

    clearDepthf(depth) {
        gl.context.clearDepth(depth);
    },

    clearStencil(s) {
        gl.context.clearStencil(s);
    },

    colorMask(red, green, blue, alpha) {
        gl.context.colorMask(red, green, blue, alpha);
    },

    compileShader(shader) {
        gl.context.compileShader(gl.objects[shader]);
    },

    compressedTexImage2D(target, level, internalformat, width, height, border, imageSize, data) {
        gl.context.compressedTexImage2D(target, level, internalformat, width, height, border, new Uint8Array(wio.module.exports.memory.buffer, data, imageSize));
    },

    compressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, imageSize, data) {
        gl.context.compressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, new Uint8Array(wio.module.exports.memory.buffer, data, imageSize));
    },

    copyTexImage2D(target, level, internalformat, x, y, width, height, border) {
        gl.context.copyTexImage2D(target, level, internalformat, x, y, width, height, border);
    },

    copyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height) {
        gl.context.copyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height);
    },

    createProgram() {
        const program = gl.context.createProgram();
        return gl.pushObject(program);
    },

    createShader(type) {
        const shader = gl.context.createShader(type);
        return gl.pushObject(shader);
    },

    cullFace(mode) {
        gl.context.cullFace(mode);
    },

    deleteBuffers(n, buffers) {
        gl.deleteObjects(n, buffers);
    },

    deleteFramebuffers(n, framebuffers) {
        gl.deleteObjects(n, framebuffers);
    },

    deleteProgram(program) {
        gl.objects[program] = null;
    },

    deleteRenderbuffers(n, renderbuffers) {
        gl.deleteObjects(n, renderbuffers);
    },

    deleteShader(shader) {
        gl.objects[shader] = null;
    },

    deleteTextures(n, textures) {
        gl.deleteObjects(n, textures);
    },

    depthFunc(func) {
        gl.context.depthFunc(func);
    },

    depthMask(flag) {
        gl.context.depthMask(flag);
    },

    depthRangef(n, f) {
        gl.context.depthRange(n, f);
    },

    detachShader(program, shader) {
        gl.context.detachShader(gl.objects[program], gl.objects[shader]);
    },

    disable(cap) {
        gl.context.disable(cap);
    },

    disableVertexAttribArray(index) {
        gl.context.disableVertexAttribArray(index);
    },

    drawArrays(mode, first, count) {
        gl.context.drawArrays(mode, first, count);
    },

    drawElements(mode, count, type, offset) {
        gl.context.drawElements(mode, count, type, offset);
    },

    enable(cap) {
        gl.context.enable(cap);
    },

    enableVertexAttribArray(index) {
        gl.context.enableVertexAttribArray(index);
    },

    finish() {
        gl.context.finish();
    },

    flush() {
        gl.context.flush();
    },

    framebufferRenderbuffer(target, attachment, renderbuffertarget, renderbuffer) {
        gl.context.framebufferRenderbuffer(target, attachment, renderbuffertarget, gl.objects[renderbuffer]);
    },

    framebufferTexture2D(target, attachment, textarget, texture, level) {
        gl.context.framebufferTexture2D(target, attachment, textarget, gl.objects[texture], level);
    },

    frontFace(mode) {
        gl.context.frontFace(mode);
    },

    genBuffers(n, ptr) {
        const buffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            buffers[i] = gl.pushObject(gl.context.createBuffer());
        }
    },

    generateMipmap(target) {
        gl.context.generateMipmap(target);
    },

    genFramebuffers(n, ptr) {
        const framebuffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            framebuffers[i] = gl.pushObject(gl.context.createFramebuffer());
        }
    },

    genRenderbuffers(n, ptr) {
        const renderbuffers = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            renderbuffers[i] = gl.pushObject(gl.context.createRenderbuffer());
        }
    },

    genTextures(n, ptr) {
        const textures = new Uint32Array(wio.module.exports.memory.buffer, ptr, n);
        for (let i = 0; i < n; i++) {
            textures[i] = gl.pushObject(gl.context.createTexture());
        }
    },

    getActiveAttrib(program, index, bufSize, length, size, type, name) {
        const info = gl.context.getActiveAttrib(gl.objects[program], index);
        if (info == null) return;
        new Int32Array(wio.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(wio.module.exports.memory.buffer, type)[0] = info.type;
        gl.setStringZ(name, bufSize, length, info.name);
    },

    getActiveUniform(program, index, bufSize, length, size, type, name) {
        const info = gl.context.getActiveUniform(gl.objects[program], index);
        if (info == null) return;
        new Int32Array(wio.module.exports.memory.buffer, size)[0] = info.size;
        new Uint32Array(wio.module.exports.memory.buffer, type)[0] = info.type;
        gl.setStringZ(name, bufSize, length, info.name);
    },

    getAttachedShaders(program, maxCount, count, shaders) {
        const indices = gl.context.getAttachedShaders(gl.objects[program]).map(shader => gl.objects.indexOf(shader));
        const buffer = new Uint32Array(wio.module.exports.memory.buffer, shaders);
        for (var i = 0; i < maxCount && i < indices.length; i++) {
            buffer[i] = indices[i];
        }
        if (count != 0) {
            new Int32Array(wio.module.exports.memory.buffer, count)[0] = i;
        }
    },

    getAttribLocation(program, name) {
        return gl.context.getAttribLocation(gl.objects[program], gl.getStringZ(name));
    },

    getBooleanv(pname, params) {
        gl.setParams(Uint8Array, params, gl.context.getParameter(pname));
    },

    getBufferParameteriv(target, value, data) {
        gl.setParams(Int32Array, data, gl.context.getBufferParameter(target, value));
    },

    getError() {
        return gl.context.getError();
    },

    getFloatv(pname, params) {
        gl.setParams(Float32Array, params, gl.context.getParameter(pname));
    },

    getFramebufferAttachmentParameteriv(target, attachment, pname, params) {
        const value = gl.context.getFramebufferAttachmentParameter(target, attachment, pname);
        if (typeof value == "object") {
            value = gl.objects.indexOf(value);
        }
        new Int32Array(wio.module.exports.memory.buffer, params)[0] = value;
    },

    getIntegerv(pname, params) {
        gl.setParams(Int32Array, params, gl.context.getParameter(pname));
    },

    getProgramiv(program, pname, params) {
        gl.setParams(Int32Array, params, gl.context.getProgramParameter(gl.objects[program], pname));
    },

    getProgramInfoLog(program, maxLength, length, infoLog) {
        gl.setStringZ(infoLog, maxLength, length, gl.context.getProgramInfoLog(gl.objects[program]));
    },

    getRenderbufferParameteriv(target, pname, params) {
        gl.setParams(Int32Array, params, gl.context.getRenderbufferParameter(target, pname));
    },

    getShaderiv(shader, pname, params) {
        gl.setParams(Int32Array, params, gl.context.getShaderParameter(gl.objects[shader], pname));
    },

    getShaderInfoLog(shader, maxLength, length, infoLog) {
        gl.setStringZ(infoLog, maxLength, length, gl.context.getShaderInfoLog(gl.objects[shader]));
    },

    getShaderPrecisionFormat(shaderType, precisionType, range, precision) {
        const format = gl.context.getShaderPrecisionFormat(shaderType, precisionType);
        new Int32Array(wio.module.exports.memory.buffer, range, 2).set([format.rangeMin, format.rangeMax]);
        new Int32Array(wio.module.exports.memory.buffer, precision)[0] = format.precision;
    },

    getShaderSource(shader, bufSize, length, source) {
        gl.setStringZ(source, bufSize, length, gl.context.getShaderSource(gl.objects[shader]));
    },

    getString() { },

    getTexParameterfv(target, pname, params) {
        gl.setParams(Float32Array, params, gl.context.getTexParameter(target, pname));
    },

    getTexParameteriv(target, pname, params) {
        gl.setParams(Int32Array, params, gl.context.getTexParameter(target, pname));
    },

    getUniformfv(program, location, params) {
        gl.setParams(Float32Array, params, gl.context.getUniform(gl.objects[program], location));
    },

    getUniformiv(program, location, params) {
        gl.setParams(Int32Array, params, gl.context.getUniform(gl.objects[program], location));
    },

    getUniformLocation(program, name) {
        return gl.context.getUniformLocation(gl.objects[program], gl.getStringZ(name));
    },

    getVertexAttribfv(index, pname, params) {
        gl.setParams(Float32Array, params, gl.context.getVertexAttrib(index, pname));
    },

    getVertexAttribiv(index, pname, params) {
        gl.setParams(Int32Array, params, gl.context.getVertexAttrib(index, pname));
    },

    getVertexAttribPointerv(index, pname, pointer) {
        new Uint32Array(wio.module.exports.memory.buffer, pointer)[0] = gl.context.getVertexAttribOffset(index, pname);
    },

    hint(target, mode) {
        gl.context.hint(target, mode);
    },

    isBuffer(buffer) {
        return gl.context.isBuffer(gl.objects[buffer]);
    },

    isEnabled(cap) {
        return gl.context.isEnabled(cap);
    },

    isFramebuffer(framebuffer) {
        return gl.context.isFramebuffer(gl.objects[framebuffer]);
    },

    isProgram(program) {
        return gl.context.isProgram(gl.objects[program]);
    },

    isRenderbuffer(renderbuffer) {
        return gl.context.isRenderbuffer(gl.objects[renderbuffer]);
    },

    isShader(shader) {
        return gl.context.isShader(gl.objects[shader]);
    },

    isTexture(texture) {
        return gl.context.isTexture(gl.objects[texture]);
    },

    lineWidth(width) {
        gl.context.lineWidth(width);
    },

    linkProgram(program) {
        gl.context.linkProgram(gl.objects[program]);
    },

    pixelStorei(pname, param) {
        gl.context.pixelStorei(pname, param);
    },

    polygonOffset(factor, units) {
        gl.context.polygonOffset(factor, units);
    },

    readPixels(x, y, width, height, format, type, pixels) {
        gl.context.readPixels(x, y, width, height, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    renderbufferStorage(target, internalformat, width, height) {
        gl.context.renderbufferStorage(target, internalformat, width, height);
    },

    sampleCoverage(value, invert) {
        gl.context.sampleCoverage(value, invert);
    },

    scissor(x, y, width, height) {
        gl.context.scissor(x, y, width, height);
    },

    shaderSource(shader, count, strings_ptr, lengths_ptr) {
        const strings = new Uint32Array(wio.module.exports.memory.buffer, strings_ptr, count);
        const lengths = new Int32Array(wio.module.exports.memory.buffer, lengths_ptr, count);
        var string = "";
        for (let i = 0; i < count; i++) {
            string += (lengths_ptr != 0 && lengths[i] >= 0) ? wio.getString(strings[i], lengths[i]) : gl.getStringZ(strings[i]);
        }
        gl.context.shaderSource(gl.objects[shader], string);
    },

    stencilFunc(func, ref, mask) {
        gl.context.stencilFunc(func, ref, mask);
    },

    stencilFuncSeparate(face, func, ref, mask) {
        gl.context.stencilFuncSeparate(face, func, ref, mask);
    },

    stencilMask(mask) {
        gl.context.stencilMask(mask);
    },

    stencilMaskSeparate(face, mask) {
        gl.context.stencilMaskSeparate(face, mask);
    },

    stencilOp(fail, zfail, zpass) {
        gl.context.stencilOp(fail, zfail, zpass);
    },

    stencilOpSeparate(face, sfail, dpfail, dppass) {
        gl.context.stencilOpSeparate(face, sfail, dpfail, dppass);
    },

    texImage2D(target, level, internalformat, width, height, border, format, type, pixels) {
        gl.context.texImage2D(target, level, internalformat, width, height, border, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    texParameterf(target, pname, param) {
        gl.context.texParameterf(target, pname, param);
    },

    texParameteri(target, pname, param) {
        gl.context.texParameteri(target, pname, param);
    },

    texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, pixels) {
        gl.context.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, new Uint8Array(wio.module.exports.memory.buffer, pixels));
    },

    uniform1f(location, v0) {
        gl.context.uniform1f(location, v0);
    },

    uniform1fv(location, count, value) {
        gl.context.uniform1fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform1i(location, v0) {
        gl.context.uniform1i(location, v0);
    },

    uniform1iv(location, count, value) {
        gl.context.uniform1iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform2f(location, v0, v1) {
        gl.context.uniform2f(location, v0, v1);
    },

    uniform2fv(location, count, value) {
        gl.context.uniform2fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform2i(location, v0, v1) {
        gl.context.uniform2i(location, v0, v1);
    },

    uniform2iv(location, count, value) {
        gl.context.uniform2iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform3f(location, v0, v1, v2) {
        gl.context.uniform3f(location, v0, v1, v2);
    },

    uniform3fv(location, count, value) {
        gl.context.uniform3fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform3i(location, v0, v1, v2) {
        gl.context.uniformif(location, v0, v1, v2);
    },

    uniform3iv(location, count, value) {
        gl.context.uniform3iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform4f(location, v0, v1, v2, v3) {
        gl.context.uniform4f(location, v0, v1, v2, v3);
    },

    uniform4fv(location, count, value) {
        gl.context.uniform4fv(location, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniform4i(location, v0, v1, v2, v3) {
        gl.context.uniform4i(location, v0, v1, v2, v3);
    },

    uniform4iv(location, count, value) {
        gl.context.uniform4iv(location, new Int32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniformMatrix2fv(location, count, transpose, value) {
        gl.context.uniformMatrix2fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniformMatrix3fv(location, count, transpose, value) {
        gl.context.uniformMatrix3fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    uniformMatrix4fv(location, count, transpose, value) {
        gl.context.uniformMatrix4fv(location, transpose, new Float32Array(wio.module.exports.memory.buffer, value, count));
    },

    useProgram(program) {
        gl.context.useProgram(gl.objects[program]);
    },

    validateProgram(program) {
        gl.context.validateProgram(gl.objects[program]);
    },

    vertexAttrib1f(index, x) {
        gl.context.vertexAttrib1f(index, x);
    },

    vertexAttrib1fv(index, v) {
        gl.context.vertexAttrib1fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    vertexAttrib2f(index, x, y) {
        gl.context.vertexAttrib2f(index, x, y);
    },

    vertexAttrib2fv(index, v) {
        gl.context.vertexAttrib2fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    vertexAttrib3f(index, x, y, z) {
        gl.context.vertexAttrib3f(index, x, y, z);
    },

    vertexAttrib3fv(index, v) {
        gl.context.vertexAttrib3fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    vertexAttrib4f(index, x, y, z, w) {
        gl.context.vertexAttrib4f(index, x, y, z, w);
    },

    vertexAttrib4fv(index, v) {
        gl.context.vertexAttrib4fv(index, new Float32Array(wio.module.exports.memory.buffer, v));
    },

    vertexAttribPointer(index, size, type, normalized, stride, offset) {
        gl.context.vertexAttribPointer(index, size, type, normalized, stride, offset);
    },

    viewport(x, y, width, height) {
        gl.context.viewport(x, y, width, height);
    },
};
