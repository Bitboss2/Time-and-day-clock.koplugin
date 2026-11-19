-- SPDX-License-Identifier: GPL-3.0-or-later
local ffi = require("ffi")

local ntx = {id=1, name="Kobo NTX", update="struct mxcfb_update_data_v1_ntx",
    size=68, wait=0x4004462f, wide_marker=false, temp=4096}
local mk7 = {id=2, name="Kobo Mk7", update="struct mxcfb_update_data",
    size=72, wait=0xc008462f, wide_marker=true, temp=4096}
local carta = {id=3, name="Kindle Carta", update="struct mxcfb_update_data",
    size=72, wait=0xc008462f, wide_marker=true, temp=4097}

local models = {
    Kobo_alyssum=ntx, Kobo_daylight=ntx, Kobo_snow=ntx,
    Kobo_star_r2=mk7, Kobo_snow_r2=mk7, Kobo_nova=mk7,
    KindlePaperWhite2=carta, KindlePaperWhite3=carta, KindleVoyage=carta,
}

local function istype(kind, value)
    if not value then return false end
    local ok, match = pcall(ffi.istype, kind, value)
    return ok and match
end

return function(device, screen)
    local model = device.model
    local profile = model == "Kobo_star" and ntx or models[model]
    assert(profile, "Modèle hors liste de compatibilité : "..tostring(model))
    assert(screen and screen.bb and type(screen.fd) == "number" and screen.fd >= 0,
        "Framebuffer mxcfb indisponible")
    assert(not screen.full_bb and (screen.bb:getType() == 1 or screen.bb:getType() == 3),
        "Framebuffer plein écran 8 ou 16 bits requis")
    if model == "Kobo_star" then
        assert(screen.update_data and ffi.sizeof(screen.update_data) == ntx.size,
            "Structure Kobo NTX de 68 octets requise")
        return {id=0, name=ntx.name, wait=ntx.wait, custom=true}
    end
    assert(istype(profile.update, screen.update_data) and ffi.sizeof(screen.update_data) == profile.size
        and ffi.offsetof(profile.update,"update_marker") == 24
        and ffi.offsetof(profile.update,"temp") == (profile == carta and 36 or 28)
        and ffi.offsetof(profile.update,"flags") == (profile == carta and 40 or 32),
        "Structure de mise à jour différente de celle attendue")
    local marker = profile.wide_marker and "struct mxcfb_update_marker_data" or "uint32_t[1]"
    assert(istype(marker, screen.marker_data) and type(screen.mech_wait_update_complete) == "function",
        "Attente des marqueurs incompatible ou désactivée dans KOReader")
    assert(screen.update_data.temp == profile.temp and screen.waveform_a2 == 4
        and screen.waveform_fast == 1 and screen.waveform_full == 2,
        "Modes constructeur ou température incompatibles")
    assert(not screen.night_mode and screen.bb:getInverse() == 0,
        "Désactiver le mode nuit avant le test constructeur")
    return {id=profile.id, name=profile.name, wait=profile.wait, custom=false,
        collect_ntx=profile==ntx,
        wake_epdc=profile ~= carta and type(screen.mech_poweron) == "function"}
end
