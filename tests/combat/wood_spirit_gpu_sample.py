"""Draw the production fragment body offscreen with macOS CGL. Maker owns its own backend."""
import ctypes as c
from pathlib import Path

import numpy as np


class BrushGPU:
    def __init__(self, atlas):
        gl=self.gl=c.CDLL('/System/Library/Frameworks/OpenGL.framework/OpenGL')
        fmt=c.c_void_p(); count=c.c_int(); ctx=c.c_void_p()
        assert gl.CGLChoosePixelFormat((c.c_int*3)(99,0x3200,0),c.byref(fmt),c.byref(count))==0
        assert gl.CGLCreateContext(fmt,None,c.byref(ctx))==0 and gl.CGLSetCurrentContext(ctx)==0
        gl.CGLReleasePixelFormat(fmt); self.context=ctx
        gl.glGetString.restype=c.c_char_p
        print('Brush GPU:',gl.glGetString(0x1F01).decode(),gl.glGetString(0x1F02).decode())
        fragment=Path('assets/Shaders/BLGL/WoodSpiritBrush.shader').read_text().split('void fragment()',1)[1]
        vertex='''#version 150
out vec2 UV;
void main(){vec2 p=vec2((gl_VertexID<<1)&2, gl_VertexID&2); UV=p; gl_Position=vec4(p*2.0-1.0,0.0,1.0);}'''
        # Wrap the existing fragment entry point with BLGL's inputs and outputs.
        frag='''#version 150
in vec2 UV; out vec4 result; uniform sampler2D brush_atlas; uniform float phase,impact;
vec3 ALBEDO; float ALPHA; void paint()'''+fragment+'\nvoid main(){paint();result=vec4(ALBEDO,ALPHA);}'
        program=self.program=gl.glCreateProgram()
        for kind,source in ((0x8B31,vertex),(0x8B30,frag)):
            handle=gl.glCreateShader(kind); raw=c.c_char_p(source.encode()); status=c.c_int()
            gl.glShaderSource(handle,1,c.byref(raw),None); gl.glCompileShader(handle)
            gl.glGetShaderiv(handle,0x8B81,c.byref(status))
            if not status.value:
                buf=c.create_string_buffer(4096); gl.glGetShaderInfoLog(handle,4096,None,buf); raise RuntimeError(buf.value)
            gl.glAttachShader(program,handle); gl.glDeleteShader(handle)
        gl.glLinkProgram(program); gl.glGetProgramiv(program,0x8B82,c.byref(status)); assert status.value
        gl.glUseProgram(program)
        def texture(width,height,data):
            tex=c.c_uint(); gl.glGenTextures(1,c.byref(tex)); gl.glBindTexture(0x0DE1,tex)
            for param in (0x2800,0x2801): gl.glTexParameteri(0x0DE1,param,0x2600)
            gl.glTexImage2D(0x0DE1,0,0x8058,width,height,0,0x1908,0x1401,data)
            return tex
        self.target=texture(64,64,None); self.frame=c.c_uint(); gl.glGenFramebuffers(1,c.byref(self.frame))
        gl.glBindFramebuffer(0x8D40,self.frame);gl.glFramebufferTexture2D(0x8D40,0x8CE0,0x0DE1,self.target,0)
        assert gl.glCheckFramebufferStatus(0x8D40)==0x8CD5
        self.atlas=texture(64,128,atlas.ctypes.data_as(c.c_void_p));self.vao=c.c_uint()
        gl.glGenVertexArrays(1,c.byref(self.vao));gl.glBindVertexArray(self.vao);gl.glViewport(0,0,64,64)
        gl.glDisable(0x0BD0); gl.glUniform1i(gl.glGetUniformLocation(program,b'brush_atlas'),0)
        self.phase=gl.glGetUniformLocation(program,b'phase');self.impact=gl.glGetUniformLocation(program,b'impact')

    def render(self,impact,phase):
        gl=self.gl; gl.glUniform1f(self.impact,c.c_float(impact)); gl.glUniform1f(self.phase,c.c_float(phase))
        gl.glDrawArrays(4,0,3); pixels=np.empty((64,64,4),dtype=np.uint8)
        gl.glReadPixels(0,0,64,64,0x1908,0x1401,pixels.ctypes.data_as(c.c_void_p)); assert gl.glGetError()==0
        return pixels

    def close(self):
        self.gl.CGLSetCurrentContext(None); self.gl.CGLReleaseContext(self.context)
