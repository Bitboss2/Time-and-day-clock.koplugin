-- Hand-drawn icon set on a 24-unit grid: 2-unit strokes, round caps, soft
-- corners. Every icon is drawn once into a cached layer, never per frame.
local load=...
local D=load("render/draw")
local I={}
local pi=math.pi
function I.draw(bb,name,x,y,size,ink)
    local s=size/24;local t=math.max(1.6,size/12.5);ink=ink or 0
    local function L(a,b,c,d)D.stroke(bb,x+a*s,y+b*s,x+c*s,y+d*s,ink,t)end
    local function P(points)for i=1,#points-1 do local a,b=points[i],points[i+1];L(a[1],a[2],b[1],b[2])end end
    local function O(cx,cy,r,from,to)D.ring(bb,x+cx*s,y+cy*s,r*s,ink,t,from,to)end
    local function R(a,b,w,h,r)D.roundBorder(bb,x+a*s,y+b*s,w*s,h*s,(r or 3)*s,ink,t)end
    local function F(a,b,w,h,r)D.round(bb,x+a*s,y+b*s,w*s,h*s,(r or 3)*s,ink)end
    local function dot(cx,cy,r)D.circle(bb,x+cx*s,y+cy*s,(r or 1.4)*s,ink)end
    if name=="gallery"then R(3,3,8,8,2.5);R(13,3,8,8,2.5);R(3,13,8,8,2.5);R(13,13,8,8,2.5)
    elseif name=="edit"then P{{5,19},{6,14.5},{16,4.5},{19.5,8},{9.5,18},{5,19}};L(13.5,7,17,10.5)
    elseif name=="moon"then O(12,12,8.2,pi*.85,pi*2.15);O(17.6,12,7.4,pi*1.083,pi*1.917);dot(19.5,5,1.1)
    elseif name=="pulse"then P{{2.5,12.5},{7,12.5},{9.5,6},{13.5,18.5},{16,10},{17.5,12.5},{21.5,12.5}}
    elseif name=="clock"then O(12,12,8.5);P{{12,7},{12,12},{15.5,14}}
    elseif name=="move"then L(12,3,12,21);L(3,12,21,12);P{{9,6},{12,3},{15,6}};P{{9,18},{12,21},{15,18}};P{{6,9},{3,12},{6,15}};P{{18,9},{21,12},{18,15}}
    elseif name=="text"then P{{5,7},{5,5},{19,5},{19,7}};L(12,5,12,19);L(9,19,15,19)
    elseif name=="image"then R(3,4.5,18,15,3);dot(15.5,9.5,1.8);P{{4,17.5},{9,12},{13,16},{15.5,13.5},{20,17.5}}
    elseif name=="style"then O(12,12,8.5);dot(8.3,10,1.2);dot(12,7.6,1.2);dot(15.7,10,1.2);O(12.5,16.5,2.4)
    elseif name=="info"then O(12,12,8.5);dot(12,8,1.5);L(12,11.5,12,16.5)
    elseif name=="battery"then R(2.5,7,17,10,2.5);F(20.5,10,2,4,1);F(5,9.5,8,5,1)
    elseif name=="check"then P{{5,12.5},{10,17.5},{19,7}}
    elseif name=="close"then L(6.5,6.5,17.5,17.5);L(6.5,17.5,17.5,6.5)
    elseif name=="left"then P{{15,5},{8,12},{15,19}}
    elseif name=="right"then P{{9,5},{16,12},{9,19}}
    elseif name=="down"then P{{5,9},{12,16},{19,9}}
    elseif name=="up"then P{{5,15},{12,8},{19,15}}
    elseif name=="plus"then L(12,5,12,19);L(5,12,19,12)
    elseif name=="minus"then L(5,12,19,12)
    elseif name=="more"then dot(5.5,12,1.9);dot(12,12,1.9);dot(18.5,12,1.9)
    elseif name=="play"then P{{8,5},{18.5,12},{8,19},{8,5}}
    elseif name=="import"then L(12,3.5,12,14.5);P{{7.5,10},{12,14.5},{16.5,10}};P{{4,15},{4,20},{20,20},{20,15}}
    elseif name=="export"then L(12,14.5,12,3.5);P{{7.5,8},{12,3.5},{16.5,8}};P{{4,15},{4,20},{20,20},{20,15}}
    elseif name=="star"then
        local pts={};for n=0,10 do local a=-pi/2+n*pi/5;local r=n%2==0 and 9 or 4;pts[#pts+1]={12+math.cos(a)*r,12.6+math.sin(a)*r}end;P(pts)
    elseif name=="copy"then R(8,8,12.5,12.5,3);P{{5,15.5},{3.5,15.5},{3.5,3.5},{15.5,3.5},{15.5,5}}
    elseif name=="trash"then L(4,6.5,20,6.5);P{{9,6.5},{9.5,3.5},{14.5,3.5},{15,6.5}};P{{6,6.5},{7,20.5},{17,20.5},{18,6.5}};L(10.5,10,10.5,17);L(13.5,10,13.5,17)
    elseif name=="sliders"then L(4,7,20,7);L(4,12,20,12);L(4,17,20,17);F(13,5,3,4,1.5);F(7,10,3,4,1.5);F(15,15,3,4,1.5)
    elseif name=="layers"then P{{12,4},{20.5,8.5},{12,13},{3.5,8.5},{12,4}};P{{3.5,14},{12,18.5},{20.5,14}}
    elseif name=="sun"then O(12,12,4.8);for n=0,7 do local a=n*pi/4;L(12+math.cos(a)*8,12+math.sin(a)*8,12+math.cos(a)*9.8,12+math.sin(a)*9.8)end
    elseif name=="drop"then P{{12,3},{17.5,11.5}};O(12,14.5,6,pi*.62,pi*2.38);P{{12,3},{6.5,11.5}}
    elseif name=="auto"then O(12,12,8.5);D.circle(bb,x+12*s,y+12*s,5.6*s,ink);D.rect(bb,x+12*s,y+5*s,7*s,14*s,255-ink)
    elseif name=="spark"then P{{12,2.5},{13.6,10.4},{21.5,12},{13.6,13.6},{12,21.5},{10.4,13.6},{2.5,12},{10.4,10.4},{12,2.5}};dot(19,5,1.2)
    elseif name=="frame"then R(4,3,16,18,3);R(7.5,6.5,9,11,1.5)
    elseif name=="wave"then P{{2.5,12},{5,8},{8,8},{11,16},{14,16},{17,8},{19.5,8},{21.5,12}}
    elseif name=="rename"then P{{4,20},{4.6,16.6},{14,7.2},{16.8,10},{7.4,19.4},{4,20}};L(13,20,20,20)
    elseif name=="globe"then O(12,12,8.5);L(3.5,12,20.5,12);O(12,12,4,0,pi);O(12,12,4,pi,pi*2);L(12,3.5,12,20.5)
    elseif name=="rotate"then O(12,12,7.5,.5,pi*1.8);P{{4.5,4.5},{5.4,9.4},{10.2,8.4}}
    elseif name=="file"then P{{14,3},{6,3},{6,21},{18,21},{18,7},{14,3},{14,7},{18,7}}
    else R(4,4,16,16,3)end
end
return I
