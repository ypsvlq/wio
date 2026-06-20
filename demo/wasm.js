class GL {
    constructor(wio) {
        this.contexts = [];

        /** @type {WebGLRenderingContext} */
        this.context = undefined;

        this.uniforms = undefined;

        this.getStringZ = (ptr) => {
            const array = new Uint8Array(wio.memory.buffer, ptr);
            let len = 0;
            while (array[len]) len++;
            return new TextDecoder().decode(array.slice(0, len));
        };

        this.setStringZ = (ptr, max, length, string) => {
            const buffer = new Uint8Array(wio.memory.buffer, ptr);
            const encoded = new TextEncoder().encode(string);
            buffer.set(encoded);
            buffer[encoded.length] = 0;
            if (length !== 0) {
                new Int32Array(wio.memory.buffer, length)[0] = encoded.length;
            }
        };

        this.setParams = (Array, ptr, value) => {
            const buffer = new Array(wio.memory.buffer, ptr);
            if (typeof value[Symbol.iterator] === "function") {
                buffer.set(value);
            } else {
                buffer[0] = value;
            }
        };

        this.deleteObjects = (n, ptr) => {
            const list = new Uint32Array(wio.memory.buffer, ptr, n);
            for (let i = 0; i < n; i++) {
                wio.objects[list[i]] = null;
            }
        };

        this.imports = {
            createContext: (id) => {
                this.contexts[id] = wio.objects[id].canvas.getContext("webgl");
            },

            makeContextCurrent: (id) => {
                this.context = this.contexts[id];
            },

            activeTexture: (texture) => this.context.activeTexture(texture),

            attachShader: (program, shader) => this.context.attachShader(wio.objects[program].program, wio.objects[shader]),

            bindAttribLocation: (program, index, name) => this.context.bindAttribLocation(wio.objects[program].program, index, this.getStringZ(name)),

            bindBuffer: (target, buffer) => this.context.bindBuffer(target, wio.objects[buffer]),

            bindFramebuffer: (target, framebuffer) => this.context.bindFramebuffer(target, framebuffer ? wio.objects[framebuffer] : null),

            bindRenderbuffer: (target, renderbuffer) => this.context.bindRenderbuffer(target, wio.objects[renderbuffer]),

            bindTexture: (target, texture) => this.context.bindTexture(target, wio.objects[texture]),

            blendColor: (red, green, blue, alpha) => this.context.blendColor(red, green, blue, alpha),

            blendEquation: (mode) => this.context.blendEquation(mode),

            blendEquationSeparate: (modeRGB, modeAlpha) => this.context.blendEquationSeparate(modeRGB, modeAlpha),

            blendFunc: (sfactor, dfactor) => this.context.blendFunc(sfactor, dfactor),

            blendFuncSeparate: (srcRGB, dstRGB, srcAlpha, dstAlpha) => this.context.blendFuncSeparate(srcRGB, dstRGB, srcAlpha, dstAlpha),

            bufferData: (target, size, data, usage) => this.context.bufferData(target, new Uint8Array(wio.memory.buffer, data, size), usage),

            bufferSubData: (target, offset, size, data) => this.context.bufferSubData(target, offset, new Uint8Array(wio.memory.buffer, data, size)),

            checkFramebufferStatus: (target) => this.context.checkFramebufferStatus(target),

            clear: (mask) => this.context.clear(mask),

            clearColor: (red, green, blue, alpha) => this.context.clearColor(red, green, blue, alpha),

            clearDepthf: (depth) => this.context.clearDepth(depth),

            clearStencil: (s) => this.context.clearStencil(s),

            colorMask: (red, green, blue, alpha) => this.context.colorMask(red, green, blue, alpha),

            compileShader: (shader) => this.context.compileShader(wio.objects[shader]),

            compressedTexImage2D: (target, level, internalformat, width, height, border, imageSize, data) => this.context.compressedTexImage2D(target, level, internalformat, width, height, border, new Uint8Array(wio.memory.buffer, data, imageSize)),

            compressedTexSubImage2D: (target, level, xoffset, yoffset, width, height, format, imageSize, data) => this.context.compressedTexSubImage2D(target, level, xoffset, yoffset, width, height, format, new Uint8Array(wio.memory.buffer, data, imageSize)),

            copyTexImage2D: (target, level, internalformat, x, y, width, height, border) => this.context.copyTexImage2D(target, level, internalformat, x, y, width, height, border),

            copyTexSubImage2D: (target, level, xoffset, yoffset, x, y, width, height) => this.context.copyTexSubImage2D(target, level, xoffset, yoffset, x, y, width, height),

            createProgram: () => wio.pushObject({ program: this.context.createProgram(), uniforms: { list: [], name: {} } }),

            createShader: (type) => wio.pushObject(this.context.createShader(type)),

            cullFace: (mode) => this.context.cullFace(mode),

            deleteBuffers: (n, buffers) => this.deleteObjects(n, buffers),

            deleteFramebuffers: (n, framebuffers) => this.deleteObjects(n, framebuffers),

            deleteProgram: (program) => wio.objects[program] = null,

            deleteRenderbuffers: (n, renderbuffers) => this.deleteObjects(n, renderbuffers),

            deleteShader: (shader) => wio.objects[shader] = null,

            deleteTextures: (n, textures) => this.deleteObjects(n, textures),

            depthFunc: (func) => this.context.depthFunc(func),

            depthMask: (flag) => this.context.depthMask(flag),

            depthRangef: (n, f) => this.context.depthRange(n, f),

            detachShader: (program, shader) => this.context.detachShader(wio.objects[program].program, wio.objects[shader]),

            disable: (cap) => this.context.disable(cap),

            disableVertexAttribArray: (index) => this.context.disableVertexAttribArray(index),

            drawArrays: (mode, first, count) => this.context.drawArrays(mode, first, count),

            drawElements: (mode, count, type, offset) => this.context.drawElements(mode, count, type, offset),

            enable: (cap) => this.context.enable(cap),

            enableVertexAttribArray: (index) => this.context.enableVertexAttribArray(index),

            finish: () => this.context.finish(),

            flush: () => this.context.flush(),

            framebufferRenderbuffer: (target, attachment, renderbuffertarget, renderbuffer) => this.context.framebufferRenderbuffer(target, attachment, renderbuffertarget, wio.objects[renderbuffer]),

            framebufferTexture2D: (target, attachment, textarget, texture, level) => this.context.framebufferTexture2D(target, attachment, textarget, wio.objects[texture], level),

            frontFace: (mode) => this.context.frontFace(mode),

            genBuffers: (n, ptr) => {
                const buffers = new Uint32Array(wio.memory.buffer, ptr, n);
                for (let i = 0; i < n; i++) {
                    buffers[i] = wio.pushObject(this.context.createBuffer());
                }
            },

            generateMipmap: (target) => this.context.generateMipmap(target),

            genFramebuffers: (n, ptr) => {
                const framebuffers = new Uint32Array(wio.memory.buffer, ptr, n);
                for (let i = 0; i < n; i++) {
                    framebuffers[i] = wio.pushObject(this.context.createFramebuffer());
                }
            },

            genRenderbuffers: (n, ptr) => {
                const renderbuffers = new Uint32Array(wio.memory.buffer, ptr, n);
                for (let i = 0; i < n; i++) {
                    renderbuffers[i] = wio.pushObject(this.context.createRenderbuffer());
                }
            },

            genTextures: (n, ptr) => {
                const textures = new Uint32Array(wio.memory.buffer, ptr, n);
                for (let i = 0; i < n; i++) {
                    textures[i] = wio.pushObject(this.context.createTexture());
                }
            },

            getActiveAttrib: (program, index, bufSize, length, size, type, name) => {
                const info = this.context.getActiveAttrib(wio.objects[program].program, index);
                if (info === null) return;
                new Int32Array(wio.memory.buffer, size)[0] = info.size;
                new Uint32Array(wio.memory.buffer, type)[0] = info.type;
                this.setStringZ(name, bufSize, length, info.name);
            },

            getActiveUniform: (program, index, bufSize, length, size, type, name) => {
                const info = this.context.getActiveUniform(wio.objects[program].program, index);
                if (info === null) return;
                new Int32Array(wio.memory.buffer, size)[0] = info.size;
                new Uint32Array(wio.memory.buffer, type)[0] = info.type;
                this.setStringZ(name, bufSize, length, info.name);
            },

            getAttachedShaders: (program, maxCount, count, shaders) => {
                const indices = this.context.getAttachedShaders(wio.objects[program].program).map(shader => wio.objects.indexOf(shader));
                const buffer = new Uint32Array(wio.memory.buffer, shaders);
                for (let i = 0; i < maxCount && i < indices.length; i++) {
                    buffer[i] = indices[i];
                }
                if (count !== 0) {
                    new Int32Array(wio.memory.buffer, count)[0] = i;
                }
            },

            getAttribLocation: (program, name) => this.context.getAttribLocation(wio.objects[program].program, this.getStringZ(name)),

            getBooleanv: (pname, params) => this.setParams(Uint8Array, params, this.context.getParameter(pname)),

            getBufferParameteriv: (target, value, data) => this.setParams(Int32Array, data, this.context.getBufferParameter(target, value)),

            getError: () => this.context.getError(),

            getFloatv: (pname, params) => this.setParams(Float32Array, params, this.context.getParameter(pname)),

            getFramebufferAttachmentParameteriv: (target, attachment, pname, params) => {
                const value = this.context.getFramebufferAttachmentParameter(target, attachment, pname);
                if (typeof value === "object") {
                    value = wio.objects.indexOf(value);
                }
                new Int32Array(wio.memory.buffer, params)[0] = value;
            },

            getIntegerv: (pname, params) => this.setParams(Int32Array, params, this.context.getParameter(pname)),

            getProgramiv: (program, pname, params) => this.setParams(Int32Array, params, this.context.getProgramParameter(wio.objects[program].program, pname)),

            getProgramInfoLog: (program, maxLength, length, infoLog) => this.setStringZ(infoLog, maxLength, length, this.context.getProgramInfoLog(wio.objects[program].program)),

            getRenderbufferParameteriv: (target, pname, params) => this.setParams(Int32Array, params, this.context.getRenderbufferParameter(target, pname)),

            getShaderiv: (shader, pname, params) => this.setParams(Int32Array, params, this.context.getShaderParameter(wio.objects[shader], pname)),

            getShaderInfoLog: (shader, maxLength, length, infoLog) => this.setStringZ(infoLog, maxLength, length, this.context.getShaderInfoLog(wio.objects[shader])),

            getShaderPrecisionFormat: (shaderType, precisionType, range, precision) => {
                const format = this.context.getShaderPrecisionFormat(shaderType, precisionType);
                new Int32Array(wio.memory.buffer, range, 2).set([format.rangeMin, format.rangeMax]);
                new Int32Array(wio.memory.buffer, precision)[0] = format.precision;
            },

            getShaderSource: (shader, bufSize, length, source) => this.setStringZ(source, bufSize, length, this.context.getShaderSource(wio.objects[shader])),

            getString: () => 0,

            getTexParameterfv: (target, pname, params) => this.setParams(Float32Array, params, this.context.getTexParameter(target, pname)),

            getTexParameteriv: (target, pname, params) => this.setParams(Int32Array, params, this.context.getTexParameter(target, pname)),

            getUniformfv: (program, location, params) => this.setParams(Float32Array, params, this.context.getUniform(wio.objects[program].program, location)),

            getUniformiv: (program, location, params) => this.setParams(Int32Array, params, this.context.getUniform(wio.objects[program].program, location)),

            getUniformLocation: (program, name) => {
                if (wio.objects[program].uniforms.name[name] === undefined) {
                    const uniform = this.context.getUniformLocation(wio.objects[program].program, this.getStringZ(name));
                    if (uniform === null) return -1;
                    wio.objects[program].uniforms.list.push(uniform);
                    wio.objects[program].uniforms.name[name] = wio.objects[program].uniforms.list - 1;
                }
                return wio.objects[program].uniforms.name[name];
            },

            getVertexAttribfv: (index, pname, params) => this.setParams(Float32Array, params, this.context.getVertexAttrib(index, pname)),

            getVertexAttribiv: (index, pname, params) => this.setParams(Int32Array, params, this.context.getVertexAttrib(index, pname)),

            getVertexAttribPointerv: (index, pname, pointer) => new Uint32Array(wio.memory.buffer, pointer)[0] = this.context.getVertexAttribOffset(index, pname),

            hint: (target, mode) => this.context.hint(target, mode),

            isBuffer: (buffer) => this.context.isBuffer(wio.objects[buffer]),

            isEnabled: (cap) => this.context.isEnabled(cap),

            isFramebuffer: (framebuffer) => this.context.isFramebuffer(wio.objects[framebuffer]),

            isProgram: (program) => this.context.isProgram(wio.objects[program].program),

            isRenderbuffer: (renderbuffer) => this.context.isRenderbuffer(wio.objects[renderbuffer]),

            isShader: (shader) => this.context.isShader(wio.objects[shader]),

            isTexture: (texture) => this.context.isTexture(wio.objects[texture]),

            lineWidth: (width) => this.context.lineWidth(width),

            linkProgram: (program) => this.context.linkProgram(wio.objects[program].program),

            pixelStorei: (pname, param) => this.context.pixelStorei(pname, param),

            polygonOffset: (factor, units) => this.context.polygonOffset(factor, units),

            readPixels: (x, y, width, height, format, type, pixels) => this.context.readPixels(x, y, width, height, format, type, new Uint8Array(wio.memory.buffer, pixels)),

            releaseShaderCompiler: () => { },

            renderbufferStorage: (target, internalformat, width, height) => this.context.renderbufferStorage(target, internalformat, width, height),

            sampleCoverage: (value, invert) => this.context.sampleCoverage(value, invert),

            scissor: (x, y, width, height) => this.context.scissor(x, y, width, height),

            shaderBinary: () => { },

            shaderSource: (shader, count, strings_ptr, lengths_ptr) => {
                const strings = new Uint32Array(wio.memory.buffer, strings_ptr, count);
                const lengths = new Int32Array(wio.memory.buffer, lengths_ptr, count);
                let string = "";
                for (let i = 0; i < count; i++) {
                    string += (lengths_ptr !== 0 && lengths[i] >= 0) ? wio.getString(strings[i], lengths[i]) : this.getStringZ(strings[i]);
                }
                this.context.shaderSource(wio.objects[shader], string);
            },

            stencilFunc: (func, ref, mask) => this.context.stencilFunc(func, ref, mask),

            stencilFuncSeparate: (face, func, ref, mask) => this.context.stencilFuncSeparate(face, func, ref, mask),

            stencilMask: (mask) => this.context.stencilMask(mask),

            stencilMaskSeparate: (face, mask) => this.context.stencilMaskSeparate(face, mask),

            stencilOp: (fail, zfail, zpass) => this.context.stencilOp(fail, zfail, zpass),

            stencilOpSeparate: (face, sfail, dpfail, dppass) => this.context.stencilOpSeparate(face, sfail, dpfail, dppass),

            texImage2D: (target, level, internalformat, width, height, border, format, type, pixels) => this.context.texImage2D(target, level, internalformat, width, height, border, format, type, new Uint8Array(wio.memory.buffer, pixels)),

            texParameterf: (target, pname, param) => this.context.texParameterf(target, pname, param),

            texParameterfv: (target, pname, params) => this.context.texParameterf(target, pname, new Float32Array(wio.memory.buffer, params)),

            texParameteri: (target, pname, param) => this.context.texParameteri(target, pname, param),

            texParameteriv: (target, pname, params) => this.context.texParameteri(target, pname, new Int32Array(wio.memory.buffer, params)),

            texSubImage2D: (target, level, xoffset, yoffset, width, height, format, type, pixels) => this.context.texSubImage2D(target, level, xoffset, yoffset, width, height, format, type, new Uint8Array(wio.memory.buffer, pixels)),

            uniform1f: (location, v0) => this.context.uniform1f(this.uniforms[location], v0),

            uniform1fv: (location, count, value) => this.context.uniform1fv(this.uniforms[location], new Float32Array(wio.memory.buffer, value, count)),

            uniform1i: (location, v0) => this.context.uniform1i(this.uniforms[location], v0),

            uniform1iv: (location, count, value) => this.context.uniform1iv(this.uniforms[location], new Int32Array(wio.memory.buffer, value, count)),

            uniform2f: (location, v0, v1) => this.context.uniform2f(this.uniforms[location], v0, v1),

            uniform2fv: (location, count, value) => this.context.uniform2fv(this.uniforms[location], new Float32Array(wio.memory.buffer, value, count * 2)),

            uniform2i: (location, v0, v1) => this.context.uniform2i(this.uniforms[location], v0, v1),

            uniform2iv: (location, count, value) => this.context.uniform2iv(this.uniforms[location], new Int32Array(wio.memory.buffer, value, count * 2)),

            uniform3f: (location, v0, v1, v2) => this.context.uniform3f(this.uniforms[location], v0, v1, v2),

            uniform3fv: (location, count, value) => this.context.uniform3fv(this.uniforms[location], new Float32Array(wio.memory.buffer, value, count * 3)),

            uniform3i: (location, v0, v1, v2) => this.context.uniformif(this.uniforms[location], v0, v1, v2),

            uniform3iv: (location, count, value) => this.context.uniform3iv(this.uniforms[location], new Int32Array(wio.memory.buffer, value, count * 3)),

            uniform4f: (location, v0, v1, v2, v3) => this.context.uniform4f(this.uniforms[location], v0, v1, v2, v3),

            uniform4fv: (location, count, value) => this.context.uniform4fv(this.uniforms[location], new Float32Array(wio.memory.buffer, value, count * 4)),

            uniform4i: (location, v0, v1, v2, v3) => this.context.uniform4i(this.uniforms[location], v0, v1, v2, v3),

            uniform4iv: (location, count, value) => this.context.uniform4iv(this.uniforms[location], new Int32Array(wio.memory.buffer, value, count * 4)),

            uniformMatrix2fv: (location, count, transpose, value) => this.context.uniformMatrix2fv(this.uniforms[location], transpose, new Float32Array(wio.memory.buffer, value, count * 4)),

            uniformMatrix3fv: (location, count, transpose, value) => this.context.uniformMatrix3fv(this.uniforms[location], transpose, new Float32Array(wio.memory.buffer, value, count * 9)),

            uniformMatrix4fv: (location, count, transpose, value) => this.context.uniformMatrix4fv(this.uniforms[location], transpose, new Float32Array(wio.memory.buffer, value, count * 16)),

            useProgram: (program) => {
                this.context.useProgram(wio.objects[program].program);
                this.uniforms = wio.objects[program].uniforms.list;
            },

            validateProgram: (program) => this.context.validateProgram(wio.objects[program].program),

            vertexAttrib1f: (index, x) => this.context.vertexAttrib1f(index, x),

            vertexAttrib1fv: (index, v) => this.context.vertexAttrib1fv(index, new Float32Array(wio.memory.buffer, v)),

            vertexAttrib2f: (index, x, y) => this.context.vertexAttrib2f(index, x, y),

            vertexAttrib2fv: (index, v) => this.context.vertexAttrib2fv(index, new Float32Array(wio.memory.buffer, v)),

            vertexAttrib3f: (index, x, y, z) => this.context.vertexAttrib3f(index, x, y, z),

            vertexAttrib3fv: (index, v) => this.context.vertexAttrib3fv(index, new Float32Array(wio.memory.buffer, v)),

            vertexAttrib4f: (index, x, y, z, w) => this.context.vertexAttrib4f(index, x, y, z, w),

            vertexAttrib4fv: (index, v) => this.context.vertexAttrib4fv(index, new Float32Array(wio.memory.buffer, v)),

            vertexAttribPointer: (index, size, type, normalized, stride, offset) => this.context.vertexAttribPointer(index, size, type, normalized, stride, offset),

            viewport: (x, y, width, height) => this.context.viewport(x, y, width, height),
        };
    }
}

export { GL };
