local T = {}
function T.next(now, settings)
    local interval=settings.interval
    if interval==0 then return nil end
    local n=math.floor(now/interval)*interval+interval
    if settings.quiet then
        local d=os.date("*t",n);local h=d.hour
        local a,b=settings.quiet_start,settings.quiet_end
        local quiet=a~=b and ((a<b and h>=a and h<b) or (a>b and (h>=a or h<b)))
        if quiet then
            -- os.time normalizes local calendar fields; this handles DST and midnight.
            if a>b and h>=a then d.day=d.day+1 end
            d.hour=b;d.min=0;d.sec=0;d.isdst=nil
            n=os.time(d)
            if n<=now then n=now+interval end
        end
    end
    return n
end
local frdays={"dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"}
local frmonths={"janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"}
function T.date(now,s)
    if s.date_format=="iso" then return os.date("%Y-%m-%d",now) end
    if s.date_format=="short" then return os.date("%d / %m / %Y",now) end
    local d=os.date("*t",now)
    if s.locale=="fr" then return frdays[d.wday].." "..d.day.." "..frmonths[d.month] end
    return os.date("%A %d %B",now)
end
function T.digital(now,s)
    local fmt=s.format
    if fmt=="follow" then fmt=G_reader_settings and G_reader_settings:isTrue("twelve_hour_clock") and "12" or "24" end
    if fmt=="12" then return os.date("%I:%M",now),os.date("%p",now) end
    return os.date("%H:%M",now),""
end
local nums={[0]="zéro","un","deux","trois","quatre","cinq","six","sept","huit","neuf","dix","onze","douze","treize","quatorze","quinze","seize","dix-sept","dix-huit","dix-neuf"}
local function number(n)
    if nums[n] then return nums[n] end
    local tens=n<30 and "vingt" or n<40 and "trente" or n<50 and "quarante" or "cinquante"
    local a=n%10;return tens..(a==0 and "" or a==1 and " et un" or "-"..nums[a])
end
function T.words(now,s)
    local d=os.date("*t",now)
    if s.locale~="fr" then return os.date("%H",now).." hours",os.date("%M",now).." minutes" end
    local h=d.hour%12
    local hour=h==0 and (d.hour==0 and "minuit" or "midi") or number(h)..(h==1 and " heure" or " heures")
    local m=d.min
    return hour,m==0 and "pile" or m==15 and "et quart" or m==30 and "et demie" or number(m)
end
return T
