-- Offline checks for the generated whole-weapon anime sword (tools/weapon_gen/wingsword.py).
-- Shader compilation/pixels/lighting still require Web preview.
package.path='scripts/?.lua;'..package.path
local Blades=require('combat.ForgeShowroomBlades')
local Parts=require('combat.WeaponParts')
local d=Blades.Data('W')
assert(d.route=='W' and d.triangles>200 and d.triangles<700 and #d.vertices==d.triangles*3)
assert(Blades.Data('W')==d,'expanded model is cached read-only')
-- model space: origin = grip centre, tip +Y
assert(math.abs(d.displayHeight-1.855)<2e-3)
assert(d.sockets.grip[2]==0 and math.abs(d.sockets.tip[2]-1.62)<1e-6 and d.sockets.pommel[2]<-.2)
assert(d.bounds.min[2]<-.2 and math.abs(d.bounds.max[2]-1.62)<1e-3)
local function Cross(a,b,c)
    local u,v={},{}
    for k=1,3 do u[k]=b.p[k]-a.p[k];v[k]=c.p[k]-a.p[k] end
    return {u[2]*v[3]-u[3]*v[2],u[3]*v[1]-u[1]*v[3],u[1]*v[2]-u[2]*v[1]}
end
local seen,gripTris,metalTris,coreTris,gemTris,bladeTris={},0,0,0,0,0
local leftReach,rightReach=0,0
for i=1,#d.vertices,3 do
    local a,b,c=d.vertices[i],d.vertices[i+1],d.vertices[i+2]
    local x=Cross(a,b,c)
    local dot=x[1]*a.n[1]+x[2]*a.n[2]+x[3]*a.n[3]
    assert(dot>1e-9,'degenerate or inverted triangle')
    -- same normal on all 3 vertices (flat shading), unit length, finite
    for k=1,3 do
        assert(a.n[k]==b.n[k] and b.n[k]==c.n[k])
        for _,v in ipairs({a,b,c}) do assert(v.p[k]==v.p[k] and math.abs(v.p[k])<2.2) end
    end
    assert(math.abs(a.n[1]^2+a.n[2]^2+a.n[3]^2-1)<1e-8)
    -- duplicated triangle = z-fighting
    local keys={}
    for _,v in ipairs({a,b,c}) do keys[#keys+1]=('%.4f,%.4f,%.4f'):format(v.p[1],v.p[2],v.p[3]) end
    table.sort(keys);local key=table.concat(keys,'|')
    assert(not seen[key],'duplicate triangle');seen[key]=true
    -- material channel weights: 0..1, sum<=1, remainder is the grip
    local w=a.c;local sum=w[1]+w[2]+w[3]
    assert(w[1]>=0 and w[2]>=0 and w[3]>=0 and sum<=1+1e-9)
    assert(a.shade>0 and a.shade<=1 and a.glow>=0 and a.glow<=1)
    if sum<.5 then
        gripTris=gripTris+1
        -- grip triangles outward from the Y axis and inside the grip volume
        local cx=(a.p[1]+b.p[1]+c.p[1])/3;local cz=(a.p[3]+b.p[3]+c.p[3])/3
        assert(a.n[2]==a.n[2] and math.abs(cx)<.03 and math.abs(cz)<.03)
    end
    if w[2]>.9 then metalTris=metalTris+1;assert(a.glow==0)
        for _,v in ipairs({a,b,c}) do
            if v.p[2]>.215-.17 and v.p[2]<.215+.32 then
                if v.p[1]<leftReach then leftReach=v.p[1] end
                if v.p[1]>rightReach then rightReach=v.p[1] end
            end
        end
    end
    if w[3]>.9 and a.glow>.3 and a.glow<.4 then coreTris=coreTris+1 end
    if w[3]>.9 and a.glow==1 then gemTris=gemTris+1 end
    if w[1]>.5 then
        bladeTris=bladeTris+1
        -- blade: normals face away from the blade axis
        local cx=(a.p[1]+b.p[1]+c.p[1])/3;local cz=(a.p[3]+b.p[3]+c.p[3])/3
        assert(a.n[1]*cx+a.n[3]*cz>=-1e-9,'blade normal points inward')
    end
end
assert(gripTris>=40 and metalTris>150 and coreTris>=8 and gemTris>=16 and bladeTris>=24)
-- design brief: asymmetric wings (left taller/wider than right)
assert(-leftReach>rightReach+.015,'wing guard must stay asymmetric')
-- UV mask values the shader relies on
local masks={}
for _,v in ipairs(d.vertices) do masks[v.glow]=true end
assert(masks[0] and masks[.35] and masks[1])
-- palette: default grip is deep navy, preset index overrides it, keys complete
local pal=Blades.Palette({primary=3,secondary=1,accent=2})
assert(pal.primary and pal.secondary and pal.accent and pal.grip)
assert(pal.grip[3]>pal.grip[1] and pal.grip[3]<.5,'default grip stays dark navy')
local custom=Blades.Palette({primary=3,secondary=1,accent=2,grip=#Parts.ColorPresets})
assert(custom.grip[1]~=pal.grip[1] or custom.grip[2]~=pal.grip[2] or custom.grip[3]~=pal.grip[3])
-- A/B routes unaffected: weights sum to 1 so grip weight stays zero in the shader
for _,route in ipairs({'A','B'}) do
    for _,v in ipairs(Blades.Data(route).vertices) do assert(math.abs(v.c[1]+v.c[2]+v.c[3]-1)<1e-8) end
end
print(('forge_wing_sword PASS triangles=%d vertex_bytes=%d grip=%d metal=%d core=%d gem=%d blade=%d wingReach L%.3f R%.3f'):format(
    d.triangles,#d.vertices*36,gripTris,metalTris,coreTris,gemTris,bladeTris,-leftReach,rightReach))
