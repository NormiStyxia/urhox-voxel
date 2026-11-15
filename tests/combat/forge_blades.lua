-- Offline geometry checks. Shader compilation/pixels still require Web preview.
package.path='scripts/?.lua;'..package.path
local Blades=require('combat.ForgeShowroomBlades')
for _,route in ipairs({'A','B'}) do
    local d=Blades.Data(route)
    assert(d.triangles>0 and d.triangles<600 and #d.vertices%3==0)
    assert(d.bounds.min[2]==0 and math.abs(d.bounds.max[2]-1.7)<1e-10)
    assert(d.sockets.root[2]==0 and d.sockets.top[2]==1.7)
    local masks={}
    for i=1,#d.vertices,3 do
        local a,b,c=d.vertices[i],d.vertices[i+1],d.vertices[i+2]
        local u,v={},{}
        for k=1,3 do u[k]=b.p[k]-a.p[k];v[k]=c.p[k]-a.p[k] end
        local cross={u[2]*v[3]-u[3]*v[2],u[3]*v[1]-u[1]*v[3],u[1]*v[2]-u[2]*v[1]}
        local dot=0
        for k=1,3 do dot=dot+cross[k]*a.n[k] end
        assert(dot>1e-10,'degenerate or inverted triangle')
    end
    for _,v in ipairs(d.vertices) do
        local length,sum=0,0
        for k=1,3 do
            assert(v.p[k]==v.p[k] and math.abs(v.p[k])<2)
            length=length+v.n[k]^2;sum=sum+v.c[k]
            if route=='B' then assert(math.abs(v.p[k]*100-math.floor(v.p[k]*100+.5))<1e-8,'off 1cm grid') end
        end
        assert(math.abs(length-1)<1e-8 and math.abs(sum-1)<1e-8)
        assert(v.shade>0 and v.shade<=1 and v.glow>=0 and v.glow<=1)
        masks[v.glow]=true
    end
    assert(masks[0] and masks[1])
    if route=='B' then
        assert(#d.boxes<=40 and d.triangles==#d.boxes*12)
        for _,b in ipairs(d.boxes) do for k=1,3 do assert(b.to[k]>b.from[k]) end end
    end
    print(('forge_blades %s PASS triangles=%d vertices=%d boxes=%d vertex_bytes=%d bounds=%.2fx%.2fx%.2f'):format(
        route,d.triangles,#d.vertices,#d.boxes,#d.vertices*36,
        d.bounds.max[1]-d.bounds.min[1],d.bounds.max[2]-d.bounds.min[2],d.bounds.max[3]-d.bounds.min[3]))
end
assert(not pcall(Blades.Data,'C'))
