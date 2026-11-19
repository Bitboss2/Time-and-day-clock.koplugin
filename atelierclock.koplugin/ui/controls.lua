-- Declarative controls, all hosted by Atelier's fullscreen native canvas.
local C={}
function C.sections(element,units)
    element=element or "time"
    local limit=units=="px" and 2000 or 100
    local unit=units=="px" and "px" or "%"
    local r={
        Disposition={
            {"auto_layout","Disposition automatique","bool"},{"gap","Espacement",0,100,5,"px"},
            {"scale","Échelle du cadran",40,150,5,"%"},{"rotation","Orientation","choice"},
            {"units","Unité des positions","choice"},
            {element..".x","Position horizontale",-limit,limit,1,unit},{element..".y","Position verticale",-limit,limit,1,unit},
            {element..".z","Calque",0,20,1,""},{element..".visible","Élément visible","bool"},
        },
        Typographie={
            {element..".font","Police (nom KOReader ou chemin TTF)","text"},
            {element..".size",element=="time" and "Taille de l'heure (%)" or "Taille de l'élément",8,260,2,""},
            {"outline","Contour des chiffres",0,8,1,"px"},{"format","Format horaire","choice"},
            {"locale","Langue des dates et mots","choice"},{"date_format","Format de date","choice"},
        },
        Habillage={
            {"night","Clair / sombre","choice"},{"separator","Séparateur","choice"},{"border","Cadre","choice"},
            {"analog_numerals","Chiffres du cadran analogique","choice"},
            {"hour_width","Épaisseur de l'aiguille des heures",1,12,1,"px"},
            {"minute_width","Épaisseur de l'aiguille des minutes",1,12,1,"px"},
            {"brightness","Éclairage manuel (-1 = conserver)",-1,100,1,"%"},
        },
        Informations={
            {"show_date","Date","bool"},{"show_battery","Batterie","bool"},{"battery_format","Présentation batterie","choice"},
            {"show_wifi","État Wi-Fi (sans connexion)","bool"},{"show_memory","Mémoire Lua","bool"},
            {"show_world","Seconde horloge","bool"},{"world_zone","Fuseau IANA secondaire","text"},
        },
        Images={
            {"image_enabled","Fond personnalisé","bool"},{"image_mode","Image unique / diaporama","choice"},
            {"image_portrait","Image portrait : chemin PNG","text"},{"image_landscape","Image paysage : chemin PNG","text"},
            {"folder_portrait","Dossier portrait","text"},{"folder_landscape","Dossier paysage","text"},
            {"image_interval","Durée d'une image",1,1440,5,"min"},{"image_invert","Inverser le fond en mode sombre","bool"},
            {"image_full_refresh","Nettoyer l'écran au changement","bool"},{"per_image","Lire les réglages image.png.json","bool"},
        },
        Veille={
            {"interval","Profil d'actualisation","interval"},{"fast_rtc","RTC accéléré Aura 2 (expérimental)","bool"},
            {"wake_margin","Marge après fin d'affichage",0.1,5,0.1,"s"},
            {"reuse_suspend","Réutiliser la préparation Aura 2","bool"},
            {"full_refresh","Nettoyage complet (0 = désactivé)",0,1440,15,"min"},
            {"low_battery","Arrêter les réveils sous",0,40,1,"%"},
            {"quiet","Pause nocturne des mises à jour","bool"},
            {"quiet_start","Début de la pause",0,23,1,"h"},{"quiet_end","Fin de la pause",0,23,1,"h"},
        },
    }
    return r
end
C.labels={follow="Suivre KOReader",light="Clair",dark="Sombre",["24"]="24 heures",["12"]="12 heures",
    ["0"]="Portrait",["1"]="Paysage →",["2"]="Portrait inversé",["3"]="Paysage ←",
    none="Aucun",line="Ligne",dots="Points",diamond="Losange",ornament="Ornement",simple="Simple",double="Double",corner="Coins",
    arabic="Arabes",roman="Romains",both="Icône et %",percent="Pourcentage",icon="Icône",single="Image unique",cycle="Diaporama",
    px="Pixels",long="Date longue",short="Date courte",iso="AAAA-MM-JJ",fr="Français",en="English"}
return C
