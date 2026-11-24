// Standalone WebGL2 acceptance harness. Python supplies projected real actor vertices,
// the PNG pixel bytes, Lua material uniforms and both shipping fragment bodies.
const gl=document.querySelector('canvas').getContext('webgl2',{alpha:false,antialias:true,preserveDrawingBuffer:true});
if (!gl) throw Error('WebGL2 unavailable');
function shader(stage,src) {
    const sh=gl.createShader(stage);gl.shaderSource(sh,src);gl.compileShader(sh);
    if(!gl.getShaderParameter(sh,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(sh));return sh;
}
function program(src) {
    const vs=shader(gl.VERTEX_SHADER,'#version 300 es\nlayout(location=0) in vec3 point;layout(location=1) in vec3 normal;layout(location=2) in vec2 uv;layout(location=3) in vec3 color;out vec3 N;out vec2 UV;out vec3 colorIn;void main(){gl_Position=vec4(point,1.);N=normal;UV=uv;colorIn=color;}');
    let body=src.replace(/^shader_type.*$/gm,'').replace(/^render_mode.*$/gm,'').replace(/ : filter_nearest, repeat_disable/g,'').replace(/(uniform float \w+) = [^;]+;/g,'$1;');
    const common='#version 300 es\nprecision highp float;in vec2 UV;in vec3 N;in vec3 colorIn;out vec4 result;vec3 ALBEDO,EMISSION;float ALPHA,ROUGHNESS,METALLIC,SPECULAR;\n';
    const unlit=src.includes('shading_model_unlit');
    const fs=shader(gl.FRAGMENT_SHADER,common+body+'\nvoid main(){ALPHA=1.;EMISSION=vec3(0.);fragment();float light='+(unlit?'1.':'(.60+.48*max(0.,dot(normalize(N),normalize(vec3(.48,.85,.49)))))')+';result=vec4(sqrt(clamp(ALBEDO*light+EMISSION,0.,1.)),ALPHA);}');
    const p=gl.createProgram();gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(p));return p;
}
function bytes(b64){return Uint8Array.from(atob(b64),c=>c.charCodeAt(0));}
const programs=inputs.sources.map(program),tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,tex);
gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,192,160,0,gl.RGBA,gl.UNSIGNED_BYTE,bytes(inputs.atlas));
for(const param of [gl.TEXTURE_MIN_FILTER,gl.TEXTURE_MAG_FILTER])gl.texParameteri(gl.TEXTURE_2D,param,gl.NEAREST);
for(const param of [gl.TEXTURE_WRAP_S,gl.TEXTURE_WRAP_T])gl.texParameteri(gl.TEXTURE_2D,param,gl.CLAMP_TO_EDGE);
const canvas=gl.canvas,buf=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buf);
[3,3,2,3].forEach((n,i)=>{gl.enableVertexAttribArray(i);gl.vertexAttribPointer(i,n,gl.FLOAT,false,44,[0,12,24,32][i]);});
gl.viewport(0,0,canvas.width,canvas.height);gl.enable(gl.DEPTH_TEST);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);
const frames=[];
for(const frame of inputs.frames){
    gl.depthMask(true);gl.clearColor(.17,.19,.21,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
    for(const batch of frame){const p=programs[batch.program];gl.useProgram(p);
        if(batch.program===1){gl.enable(gl.BLEND);gl.depthMask(false);}else{gl.disable(gl.BLEND);gl.depthMask(true);}
        for(const [k,v] of Object.entries(batch.uniforms))gl.uniform1f(gl.getUniformLocation(p,k),v);
        gl.bufferData(gl.ARRAY_BUFFER,bytes(batch.vertices),gl.STREAM_DRAW);gl.drawArrays(gl.TRIANGLES,0,batch.count);
    }
    if(gl.getError()!==0)throw Error('WebGL draw failed');frames.push(canvas.toDataURL('image/png').split(',')[1]);
}
document.querySelector('pre').textContent=JSON.stringify(frames);
