-- Display profile selection for the Atelier interface.
-- Pure function of the device model, the verified Fluid Ink platform and the
-- user's display settings. Never touches the framebuffer.
local P={}

-- Models accepted by Fluid Ink 6.5 platform.lua (vendor A2/DU ports) plus the
-- Aura 2 v1 custom pulse path. Kept here only for the user-facing explanation;
-- the authoritative check is engine/fluidink/platform.lua itself.
P.models={
    Kobo_star="Kobo Aura Edition 2 v1",
    Kobo_star_r2="Kobo Aura Edition 2 v2",
    Kobo_snow="Kobo Aura H2O Edition 2 v1",
    Kobo_snow_r2="Kobo Aura H2O Edition 2 v2",
    Kobo_alyssum="Kobo Glo HD",
    Kobo_daylight="Kobo Aura One",
    Kobo_nova="Kobo Clara HD",
    KindlePaperWhite2="Kindle Paperwhite 2",
    KindlePaperWhite3="Kindle Paperwhite 3",
    KindleVoyage="Kindle Voyage",
}

-- Fluid Ink drive policies (see scene.lua of Fluid Ink 6.5):
-- 12 = « Fluid Ink v6 », 2 = « Conduite Rapide » (vendor A2/DU path).
P.FLUID_V6=12
P.VENDOR_FAST=2
-- « Débit » profile of Fluid Ink: queue 1, Bayer 8×8, no gamma.
P.DEBIT={window=1,dither="bayer",gamma=false}

local function fps(settings)
    local v=tonumber(settings and settings.display_fps)or 30
    if v>=60 then return 60 elseif v>=45 then return 45 end
    return 30
end

-- platform: result table of engine/fluidink/platform.lua, or nil plus reason.
function P.select(model,platform,settings,reason)
    settings=settings or {}
    local wanted=settings.display_engine or "auto"
    local classic={engine="classic",fps=fps(settings),label="Classique KOReader",
        detail=reason or "Moteur fluide non disponible sur ce modèle"}
    if wanted=="classic"then classic.detail="Choisi dans les réglages";return classic end
    if not platform then return classic end
    local p={engine="fluid",fps=fps(settings),window=P.DEBIT.window,dither=P.DEBIT.dither,gamma=P.DEBIT.gamma,
        model=model,model_name=P.models[model]or tostring(model)}
    if platform.custom and model=="Kobo_star"then
        -- Aura 2 v1: Fluid Ink v6 with « Impulsions 2 », Débit, 30 Hz target.
        p.name="pulses";p.label="Fluide 30 Hz · Impulsions 2"
        p.drive_policy=P.FLUID_V6;p.phase=2;p.capture=true
        p.wave="a2";p.wave_still="a2"
        p.detail="Fluid Ink v6 · Impulsions 2 · Débit"
    else
        -- Other compatible readers: v6 fallback without the pulse profile.
        p.name="fallback";p.label="Fluide v6 · sans impulsions"
        p.drive_policy=platform.custom and P.FLUID_V6 or P.VENDOR_FAST;p.phase=0
        p.capture=platform.custom and true or false
        p.wave="a2";p.wave_still=platform.custom and "a2"or "du"
        p.detail=(platform.custom and "Fluid Ink v6"or "Fluid Ink v6 · mode constructeur "..tostring(platform.name)).." · Débit"
    end
    return p
end

-- Pulses refused by the kernel/reference: keep Fluid Ink v6, without pulses.
function P.withoutPulses(p,errno)
    local r={};for k,v in pairs(p)do r[k]=v end
    r.name="fallback";r.phase=0;r.label="Fluide v6 · sans impulsions"
    r.detail="Impulsions refusées"..(errno and(" (errno "..errno..")")or "").." · Fluid Ink v6 · Débit"
    return r
end

function P.reduced(settings)return settings and settings.motion=="reduced"end
return P
