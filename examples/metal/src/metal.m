#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

static id<MTLDevice> device;
static id<MTLCommandQueue> command_queue;
static id<MTLRenderPipelineState> render_pipeline_state;
static CAMetalLayer *layer;

void metalInit(NSWindow *window, const char *shaders_ptr, size_t shaders_len) {
    device = MTLCreateSystemDefaultDevice();

    command_queue = [device newCommandQueue];

    NSString *shaders = [[NSString alloc] initWithBytes:shaders_ptr length:shaders_len encoding:NSUTF8StringEncoding];
    id<MTLLibrary> library = [device newLibraryWithSource:shaders options:nil error:nil];

    MTLRenderPipelineDescriptor *render_pipeline_descriptor = [MTLRenderPipelineDescriptor new];
    [render_pipeline_descriptor setVertexFunction:[library newFunctionWithName:@"vertexShader"]];
    [render_pipeline_descriptor setFragmentFunction:[library newFunctionWithName:@"fragmentShader"]];
    [[[render_pipeline_descriptor colorAttachments] objectAtIndexedSubscript:0] setPixelFormat:MTLPixelFormatBGRA8Unorm];

    render_pipeline_state = [device newRenderPipelineStateWithDescriptor:render_pipeline_descriptor error:nil];

    layer = [CAMetalLayer layer];
    [layer setDevice:device];
    [layer setPixelFormat:MTLPixelFormatBGRA8Unorm];

    NSView *view = [window contentView];
    [view setLayer:layer];
    [view setWantsLayer:YES];
}

void metalResize(uint16_t width, uint16_t height) {
    [layer setDrawableSize:CGSizeMake(width, height)];
}

void metalDraw(void) {
    id<CAMetalDrawable> drawable = [layer nextDrawable];

    MTLRenderPassDescriptor *render_pass_descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    MTLRenderPassColorAttachmentDescriptor *color_attachment = [[render_pass_descriptor colorAttachments] objectAtIndexedSubscript:0];
    [color_attachment setTexture:drawable.texture];
    [color_attachment setLoadAction:MTLLoadActionClear];
    [color_attachment setStoreAction:MTLStoreActionStore];
    [color_attachment setClearColor:MTLClearColorMake(0, 0, 0, 1)];

    id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

    id<MTLRenderCommandEncoder> render_encoder = [command_buffer renderCommandEncoderWithDescriptor:render_pass_descriptor];
    [render_encoder setRenderPipelineState:render_pipeline_state];
    [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [render_encoder endEncoding];

    [command_buffer presentDrawable:drawable];
    [command_buffer commit];
}
