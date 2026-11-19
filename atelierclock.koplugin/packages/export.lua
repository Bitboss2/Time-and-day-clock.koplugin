local load=...
local U=load("core/util")
local C=load("core/collection")
local E={}
function E.write(app,s,path)
    local item=C.current(s);local face=app:face(s.face)
    if not item or face.schema_version~=2 then return nil,"Export a face in v2 format."end
    if type(path)~="string"or not path:match("%.clock$")then return nil,"The extension must be .clock."end
    local existing=io.open(path,"rb");if existing then existing:close();return nil,"This file already exists. Choose another name."end
    local archive=require("ffi/archiver").Writer:new();local scene
    local preview=path..".preview.png";local temp=path..".tmp"
    local ok,result=pcall(function()
        local manifest=U.copy(face);manifest.dir=nil;manifest.path=nil
        manifest.id=face.id:sub(1,30).."-"..item.uid.."-"..os.time()
        manifest.name=item.title;manifest.order=100;manifest.preset={style=item.style,appearance=item.appearance,slots=U.copy(item.slots)}
        scene=load("render/scene").new(app,face,s,379,512);scene:render(os.time())
        assert(scene.frame:writePNG(preview),"Cannot write the preview")
        assert(archive:open(temp,"zip"),archive.err);assert(archive:setZipCompression("deflate"),archive.err)
        assert(archive:addFileFromMemory("manifest.json",require("json").encode(manifest)),archive.err)
        local paths={[face.preview]=true};for _,p in pairs(face.assets)do paths[p]=true end
        for name in pairs(paths)do
            local bytes=assert(U.read(name==face.preview and preview or face.dir.."/"..name,8*1024*1024),"Missing resource")
            assert(archive:addFileFromMemory(name,bytes),archive.err)
        end
        archive:close()
        -- Validate the bytes we actually wrote before publishing the file.
        load("packages/reader").open(temp,app.data_dir.."/cache")
        assert(os.rename(temp,path));return path
    end)
    if scene then scene:free()end;archive:close();os.remove(preview)
    if not ok then os.remove(temp);return nil,tostring(result)end
    return result
end
return E
