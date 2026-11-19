local U = {}
function U.copy(v)
    if type(v) ~= "table" then return v end
    local r = {}; for k, x in pairs(v) do r[k] = U.copy(x) end; return r
end
function U.clamp(v, a, b) return math.max(a, math.min(b, v)) end
function U.round(v) return math.floor(v + 0.5) end
function U.read(path, limit)
    local f = io.open(path, "rb"); if not f then return nil end
    local b = f:read((limit or 16777216) + 1); f:close()
    if b and #b <= (limit or 16777216) then return b end
end
function U.write(path, data)
    local f, e = io.open(path, "wb"); if not f then return nil, e end
    local ok, err = f:write(data); local closed, cerr = f:close()
    return ok and closed, err or cerr
end
function U.mkdir(path)
    local lfs = require("libs/libkoreader-lfs")
    local cur = path:sub(1, 1) == "/" and "/" or ""
    for part in path:gmatch("[^/]+") do
        cur = cur .. part
        if not lfs.attributes(cur) then
            local ok, err = lfs.mkdir(cur); if not ok then return nil, err end
        elseif lfs.attributes(cur, "mode") ~= "directory" then return nil, "Chemin occupé : " .. cur end
        cur = cur .. "/"
    end
    return true
end
function U.get(t, path)
    for key in path:gmatch("[^.]+") do if type(t) ~= "table" then return nil end; t = t[key] end
    return t
end
function U.set(t, path, value)
    local keys = {}; for k in path:gmatch("[^.]+") do keys[#keys+1] = k end
    for i = 1, #keys-1 do t[keys[i]] = t[keys[i]] or {}; t = t[keys[i]] end
    t[keys[#keys]] = value
end
function U.safePath(path)
    if type(path) ~= "string" or #path < 1 or #path > 200 then return false end
    if path:find("[^%w%._%-%/]") or path:sub(1,1) == "/" or path:sub(-1) == "/" or path:find("//",1,true) then return false end
    for part in path:gmatch("[^/]+") do if part == "." or part == ".." then return false end end
    return true
end
return U
