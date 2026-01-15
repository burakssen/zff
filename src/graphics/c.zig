const builtin = @import("builtin");

pub const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("rlgl.h");
    @cInclude("raymath.h");

    if (builtin.os.tag == .emscripten) {
        // REQUIRED: Exposes glDrawArrays and other GL functions for WebGL
        @cInclude("GLES2/gl2.h");
        @cInclude("emscripten/emscripten.h");
    } else if (builtin.os.tag == .macos) {
        // macOS Desktop
        @cDefine("GL_SILENCE_DEPRECATION", "");
        @cInclude("OpenGL/gl.h");
    } else {
        // Linux/Windows Desktop
        @cInclude("GL/gl.h");
    }

    // Fallback definition if headers miss it
    @cDefine("GL_LINES", "0x0001");
});
