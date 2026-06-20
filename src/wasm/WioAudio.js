class WioAudio extends AudioWorkletProcessor {
    constructor(options) {
        super(options);

        /** @type {WebAssembly.Instance} */
        this.instance = undefined;

        this.callback = undefined;

        /** @type {Float32Array} */
        this.buffer = undefined;

        this.port.onmessage = (event) => {
            this.memory = event.data.memory;
            this.callback = event.data.callback;
            this.buffer = new Float32Array(event.data.memory.buffer, event.data.buffer, 128 * event.data.channels);

            let imports = {};
            for (const info of WebAssembly.Module.imports(event.data.module)) {
                imports[info.module] ??= {};
                imports[info.module][info.name] = () => { throw new Error("javascript call on audio thread"); };
            }
            imports.env.memory = event.data.memory;

            WebAssembly.instantiate(event.data.module, imports).then((instance) => { this.instance = instance });
        };

        if (options.numberOfOutputs === 1) {
            this.process = (inputs, outputs, parameters) => {
                if (this.instance === undefined) return true;

                this.instance.exports.wioAudioCallback(this.callback, this.buffer.byteOffset, this.buffer.length);

                const channels = outputs[0].length;
                for (let channel = 0; channel < channels; channel++) {
                    for (let sample = 0; sample < 128; sample++) {
                        outputs[0][channel][sample] = this.buffer[sample * channels + channel];
                    }
                }

                return true;
            };
        } else {
            this.process = (inputs, outputs, parameters) => {
                if (this.instance === undefined) return true;

                const channels = this.buffer.length / 128;
                for (let channel = 0; channel < channels && channel < inputs[0].length; channel++) {
                    for (let sample = 0; sample < 128; sample++) {
                        this.buffer[sample * channels + channel] = inputs[0][channel][sample];
                    }
                }

                this.instance.exports.wioAudioCallback(this.callback, this.buffer.byteOffset, this.buffer.length);

                return true;
            };
        }
    }
}

registerProcessor("wio", WioAudio);
