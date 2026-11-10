-- TTS-SELFUPDATE:mundane-importer
--
if __nqs_mundane_bus == nil then
__nqs_mundane_bus = { __seq = 0 }
function __nqs_mundane_bus.publish(json_string)
for _, obj in ipairs(getObjectsWithTag("gamerecorder")) do
pcall(obj.call, "bus_publish", json_string)
end
end
function __nqs_mundane_bus.nextSeq()
__nqs_mundane_bus.__seq = __nqs_mundane_bus.__seq + 1
return __nqs_mundane_bus.__seq
end
function __nqs_mundane_bus.faceOf(kind, value)
local R, n = __nqs_mundane_bus.rules, tonumber(value)
if type(R) == "table" and n ~= nil then
if kind == "FIREPOWER" and type(R.firepower) == "table" and type(R.firepower[n]) == "table" then
local fp, hits = R.firepower[n], tonumber(R.firepower[n].hits) or 1
local word = hits == 1 and "1 hit" or (tostring(hits) .. " hits")
if fp.ammo then return hits == 1 and "Ammo Check" or (word .. ", Ammo Check") end
return word
elseif kind == "INJURY" and type(R.injuryDice) == "table" and R.injuryDice[n] ~= nil then
local key = R.injuryDice[n]
local res = type(R.injury) == "table" and R.injury[key] or nil
return type(res) == "table" and res.label or tostring(key)
end
end
return tostring(value)
end
function __nqs_mundane_bus.diceArray(faces, kind)
local out = {}
for i, f in ipairs(faces) do
out[i] = { type = kind or "D6", value = f, face = __nqs_mundane_bus.faceOf(kind, f) }
end
return out
end
function __nqs_mundane_bus.emit(event)
event.seq = __nqs_mundane_bus.nextSeq()
event.t = Time.time
if __nqs_mundane_bus.stamp_guid and event.guid == nil then event.guid = self.getGUID() end
__nqs_mundane_bus.publish(JSON.encode(event))
end
end
function __nqs_mundane_bus.stampOf(obj)
local ok, v = pcall(function() return obj.getVar("MUNDA_STAMP") end)
return ok and v or nil
end
__nqs_mundane_bus.STAMPLESS = 3
function __nqs_mundane_bus.whenLoaded(objs, before, done)
local guids, bare = {}, {}
for i, o in ipairs(objs) do
local ok, g = pcall(function() return o.getGUID() end)
guids[i] = ok and g or nil
end
local function clock()
local ok, t = pcall(function() return Time.time end)
return ok and tonumber(t) or os.time()
end
local function loaded()
for i = 1, #objs do
local g = guids[i]
local ok, o = pcall(function() return g and getObjectFromGUID(g) end)
if ok and o then
local now = __nqs_mundane_bus.stampOf(o)
if now == nil then
bare[i] = bare[i] or clock()
if clock() - bare[i] < __nqs_mundane_bus.STAMPLESS then return false end
else
bare[i] = nil
if now == before[i] then return false end
end
end
end
return true
end
Wait.condition(function() done(guids, false) end, loaded, 20, function() done(guids, true) end)
end
function __nqs_mundane_bus.refreshed(objs, before, cards)
if #objs == 0 then
if cards then __nqs_mundane_bus.emit({ kind = "mundane_ready", cards = cards }) end
return
end
__nqs_mundane_bus.whenLoaded(objs, before, function(guids, timeout)
__nqs_mundane_bus.emit({ kind = "models_refreshed", guids = guids, timeout = timeout or nil })
if cards then __nqs_mundane_bus.emit({ kind = "mundane_ready", cards = cards, timeout = timeout or nil }) end
end)
end
local IMPORTER_NAME = "Mundane Importer"
local VERSION = "?"
local CHAT_PREFIX = "[Info] "
local IMPORT_TAG = "Mundane Import"
local IMPORTER_TAG = "Mundane Importer"
local CONTROLLER_TAG = "Mundane Controller"
local GANG_TAG = "Mundane Gang_"
local OLD_TAGS = { "Mundane Gang - ", "Mundane Controller_", "Mundane Gang: ", "Mundane Owner: " }
local function trim(s)
s = (s or ""):gsub("^%s+", "")
return (s:gsub("%s+$", ""))
end
local function gangOf(obj)
local ok, tags = pcall(function() return obj.getTags() end)
for _, pre in ipairs({ GANG_TAG, OLD_TAGS[1], OLD_TAGS[2] }) do
for _, t in ipairs(ok and tags or {}) do
if t:sub(1, #pre) == pre and #t > #pre then return t end
end
end
end
MUNDA_STAMP = table.concat({ os.time(), os.clock(), math.random(1, 999999999) }, "-")
local KNOWN, SAME_CARDS = {}, {}
local function hasFunction(obj, fn)
local okG, guid = pcall(function() return obj.getGUID() end)
guid = okG and type(guid) == "string" and guid or nil
local known, has = guid and KNOWN[guid], nil
if known then
local ok, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if ok and stamp ~= nil and stamp == known.stamp then has = known.fns[fn] == true else KNOWN[guid] = nil end
end
if has == nil then
local ok, script = pcall(function() return obj.getLuaScript() end)
local stamp = nil
if ok and type(script) == "string" and guid and script:find("MUNDA_STAMP", 1, true) then
local okV, v = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if okV then stamp = v end
end
if stamp ~= nil then
local a = script:find("local IMPORTED" .. " = ", 1, true)
local _, b = script:find("--@@MUNDA_" .. "IMPORT@@", a or 1, true)
local pre, post = a and b and script:sub(1, a - 1), a and b and script:sub(b + 1)
local key = pre and (#pre .. ":" .. #post)
local same = key and SAME_CARDS[key]
local fns = same and same.pre == pre and same.post == post and same.fns
if not fns then
fns = {}
for name in script:gmatch("function ([%w_]+)%(") do fns[name] = true end
if key then SAME_CARDS[key] = { pre = pre, post = post, fns = fns } end
end
KNOWN[guid] = { stamp = stamp, fns = fns }
has = fns[fn] == true
else
has = not (ok and type(script) == "string") or script:find("function " .. fn .. "(", 1, true) ~= nil
end
end
return has
end
local function callIfHas(obj, fn, arg)
if not hasFunction(obj, fn) then return false end
return pcall(function() return obj.call(fn, arg) end)
end
local PANEL_DETAIL = 2
local PANEL_BG = "https://steamusercontent-a.akamaihd.net/ugc/12352082712112839381/58ABA6CE8570F5CB9E72C7E53BE4BE3A2CD8C9F7/"
local BG_RATIO = 1847 / 1337
local INK, PALE, PAPER = "#293133", "#F2F1EC", "#E6E5E1"
local WASH = "#FFFFFF40|#FFFFFF73|#FFFFFF26|#FFFFFF26"
local LIT = "#293133E6|#3A4447E6|#1C2224E6|#29313366"
local RED = "#7A2020D9|#963030D9|#5A1515D9|#7A202066"
local BEVEL = ' outline="#29313366" outlineSize="2 2"'
local function colors(c) return string.format("%s|%s|%s|%s", c, c, c, c) end
local function xmlEsc(s)
return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end
local function setLabel(id, text)
self.UI.setAttribute(id, "text", text)
self.UI.setValue(id, text)
end
local function panelLocal(panel, x, y)
local function nums(str)
local t = {}
for v in tostring(str):gmatch("%-?[%d%.]+") do t[#t + 1] = tonumber(v) end
return t
end
local pos, rot, sc = nums(panel.position), nums(panel.rotation), nums(panel.scale)
local px, py = x * (sc[1] or 1), y * (sc[2] or 1)
local a = math.rad(rot[3] or 0)
local ux = (pos[1] or 0) + px * math.cos(a) - py * math.sin(a)
local uy = (pos[2] or 0) + px * math.sin(a) + py * math.cos(a)
return ux / 100, uy / 100
end
local FEEDBACK = {
MARK = "✉︎", TEXT = "Feedback",
W = 124, H = 30, MARK_W = 22,
URL = "https://docs.google.com/forms/d/e/1FAIpQLSdOTHX_jjUigf9HpH9mRPav5yBvyKPLSV9g1Q09N9dnUHUU7g/viewform?usp=publish-editor",
NAME = "Mundane Feedback",
INFO_URL = "https://antaresx101.github.io/TTS_tools/mundane-ui-reference/",
INFO_NAME = "Mundane Supported Mechanics",
TAG = "Mundane Feedback",
OLD = { "Mundane Feedback_Mundane Importer", "Mundane Feedback_Mundane Controller" },
PAST = -4.5,
LIFT = 2,
TILT = 30,
TURN = 0,
}
function FEEDBACK.tablets()
local out = {}
local tags = { FEEDBACK.TAG }
for _, tag in ipairs(FEEDBACK.OLD) do tags[#tags + 1] = tag end
for _, tag in ipairs(tags) do
local ok, list = pcall(function() return getObjectsWithTag(tag) end)
for _, o in ipairs(ok and type(list) == "table" and list or {}) do
local okD, gone = pcall(function() return o.isDestroyed() end)
if not (okD and gone) then out[#out + 1] = o end
end
end
return out
end
function FEEDBACK.tablet()
return FEEDBACK.tablets()[1]
end
function FEEDBACK.showing()
local tab = FEEDBACK.tablet()
if not tab then return nil end
local ok, name = pcall(function() return tab.getName() end)
return (ok and name == FEEDBACK.INFO_NAME) and "info" or "feedback"
end
function FEEDBACK.page(what)
if what == "info" then return FEEDBACK.INFO_NAME, FEEDBACK.INFO_URL end
return FEEDBACK.NAME, FEEDBACK.URL
end
function FEEDBACK.xml()
local w, h, m = FEEDBACK.W, FEEDBACK.H, FEEDBACK.MARK_W
local left = -w / 2 + 8
local on = FEEDBACK.showing() == "feedback"
local ink = on and PALE or INK
return string.format([[
        <Panel id="feedbackBox" rectAlignment="MiddleRight" width="%d" height="%d" color="#00000000">
          <Button id="feedbackBtn" width="%d" height="%d" colors="%s" onClick="onFeedback"></Button>
          <Text id="feedbackMark" offsetXY="%g 0" width="%d" height="%d" fontSize="16" fontStyle="Bold"
                color="%s" raycastTarget="false">%s</Text>
          <Text id="feedbackText" offsetXY="%g 0" width="%d" height="%d" fontSize="16" fontStyle="Bold"
                color="%s" alignment="MiddleLeft" raycastTarget="false">%s</Text>
        </Panel>]], w, h, w, h, on and LIT or WASH, left + m / 2, m, h, ink, FEEDBACK.MARK,
left + m + 4 + (w - 8 - m - 4 - 8) / 2, w - 8 - m - 4 - 8, h, ink, FEEDBACK.TEXT)
end
function FEEDBACK.draw(on)
on = on == true or on == "feedback"
pcall(function()
self.UI.setAttribute("feedbackBtn", "colors", on and LIT or WASH)
self.UI.setAttribute("feedbackMark", "color", on and PALE or INK)
self.UI.setAttribute("feedbackText", "color", on and PALE or INK)
end)
end
function feedbackLit(on)
FEEDBACK.draw(on)
end
function FEEDBACK.drawAll(what)
FEEDBACK.draw(what)
local pass = what == "feedback" or what or false
for _, tag in ipairs({ IMPORTER_TAG, CONTROLLER_TAG }) do
local ok, list = pcall(function() return getObjectsWithTag(tag) end)
for _, o in ipairs(ok and type(list) == "table" and list or {}) do
if o ~= self then callIfHas(o, "feedbackLit", pass) end
end
end
end
function FEEDBACK.spot(panel, h)
local x, z = panelLocal(panel, 0, h / 2)
local ux, uz = panelLocal(panel, 0, h / 2 + 100)
local ok, a, b = pcall(function()
return self.positionToWorld({ -x, 0, -z }), self.positionToWorld({ -ux, 0, -uz })
end)
if not (ok and a and b) then return nil end
local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
local dx, dz = (b.x or b[1]) - ax, (b.z or b[3]) - az
local len = math.sqrt(dx * dx + dz * dz)
if len < 1e-6 then dx, dz, len = 0, 1, 1 end
dx, dz = dx / len, dz / len
return { ax + dx * FEEDBACK.PAST, ay + FEEDBACK.LIFT, az + dz * FEEDBACK.PAST },
{ FEEDBACK.TILT, math.deg((math.atan2 or math.atan)(dx, dz)) + FEEDBACK.TURN, 0 }
end
function FEEDBACK.show(tab, url)
local ok, cur = pcall(function() return tab.Browser.url end)
if not (ok and cur) then ok, cur = pcall(function() return tab.getValue() end) end
if ok and cur == url then return end
if not pcall(function() tab.Browser.url = url end) then pcall(function() tab.setValue(url) end) end
end
function FEEDBACK.open(panel, h, what)
what = what or "feedback"
if FEEDBACK.spawning then return end
local tag = FEEDBACK.TAG
local name, url = FEEDBACK.page(what)
local up = FEEDBACK.tablets()
if #up > 0 then
if FEEDBACK.showing() == what then
for _, o in ipairs(up) do pcall(function() o.destruct() end) end
return FEEDBACK.drawAll(false)
end
for k = 2, #up do pcall(function() up[k].destruct() end) end
local tab = up[1]
pcall(function() tab.setName(name) end)
pcall(function() if not tab.hasTag(tag) then tab.addTag(tag) end end)
FEEDBACK.show(tab, url)
return FEEDBACK.drawAll(what)
end
local at, rot = FEEDBACK.spot(panel, h)
if not at then return end
FEEDBACK.spawning = true
local ok = pcall(function()
spawnObject({ type = "Tablet", position = at, rotation = rot, sound = false,
callback_function = function(o)
FEEDBACK.spawning = nil
o.setLock(true)
o.setName(name)
o.addTag(tag)
o.setPosition(at)
o.setRotation(rot)
FEEDBACK.show(o, url)
end })
end)
if not ok then FEEDBACK.spawning = nil; return end
pcall(function() Wait.time(function() FEEDBACK.spawning = nil end, 5) end)
FEEDBACK.drawAll(what)
end
local function panelShell(t)
return string.format([[
<Defaults>
  <Text color="%s" fontSize="16" alignment="MiddleCenter"/>
  <Button colors="%s" textColor="%s" fontSize="16" fontStyle="Bold" outline="#29313366" outlineSize="2 2"/>
  <InputField fontStyle="Bold" textColor="%s" colors="#FFFFFF40|#FFFFFF73|#FFFFFF26|#FFFFFF26"
              outline="#29313366" outlineSize="2 2"/>
</Defaults>
<Panel id="%s" position="%s" rotation="%s" scale="%s" width="%d" height="%d"
       color="%s" padding="3 3 3 3">
  <Panel id="panelField" color="%s">
    <Mask id="bgMask">
      <Image id="bgImage" image="mundanePanelBg" raycastTarget="false"
             rectAlignment="UpperCenter" width="%d" height="%d"/>
    </Mask>
    <VerticalLayout padding="9 9 9 9" spacing="6" childForceExpandHeight="false">
      <Panel id="headerPanel" preferredHeight="40" color="#00000000">
        <Text id="titleText" width="%d" height="40" fontSize="22" fontStyle="Bold">%s</Text>
        <Text id="versionText" rectAlignment="UpperLeft" offsetXY="0 -2" width="120" height="20" fontSize="15"
              fontStyle="Bold" alignment="MiddleLeft">v%s</Text>
        <Text rectAlignment="UpperLeft" offsetXY="0 -22" width="140" height="16" fontSize="11"
              alignment="MiddleLeft">Made by Antares77</Text>
%s
      </Panel>
%s
    </VerticalLayout>
%s
  </Panel>
</Panel>]], INK, WASH, INK, INK,
t.id, t.position, t.rotation, t.scale, t.width, t.height, INK, PAPER,
t.width - 6, math.floor((t.width - 6) * BG_RATIO),
t.width - 24, xmlEsc(t.title), xmlEsc(t.version), FEEDBACK.xml(), t.body, t.over or "")
end
local SIZE_ATTRS = { "fontSize", "preferredHeight", "preferredWidth", "spacing", "width", "height",
"padding", "outlineSize", "offsetXY" }
local function detailed(xml, root)
local k = PANEL_DETAIL
if k == 1 then return xml end
for _, a in ipairs(SIZE_ATTRS) do
xml = xml:gsub("(%s" .. a .. '=")([^"]*)(")', function(pre, v, post)
v = v:gsub("%-?[%d%.]+", function(n)
n = tonumber(n) * k
return a == "fontSize" and string.format("%d", math.floor(n + 0.5)) or string.format("%g", n)
end)
return pre .. v .. post
end)
end
return (xml:gsub('(<Panel id="' .. root .. '"[^>]-scale=")([^"]*)(")', function(pre, v, post)
return pre .. v:gsub("[%d%.]+", function(n) return string.format("%g", tonumber(n) / k) end) .. post
end))
end
local MODEL = {
BASE_SIZES = { 25, 28.5, 32, 40, 50, 60 },
BASE_SNAP = 2.5,
MM_PER_INCH = 25.4,
LOOKS_DEFAULT = {
background = "#1D2027",
headers = "#9AA3AE",
text = "#F2F2F2",
accent = "#E8C97A",
edges = "#6B5B33",
frame = "none", trim = "", tint = "yes",
},
LOOKS_COLORS = {
{ key = "background", label = "Background" },
{ key = "headers", label = "Headers" },
{ key = "text", label = "Text" },
{ key = "accent", label = "Accent" },
{ key = "edges", label = "Edges" },
},
LOOKS_KEYS = { "background", "headers", "text", "accent", "edges", "frame", "trim", "tint" },
LOOKS_OPEN = "[Mundane Appearance]",
LOOKS_CLOSE = "[/Mundane Appearance]",
}
do
local MM_PER_INCH = MODEL.MM_PER_INCH
local function trim(s)
s = tostring(s or ""):gsub("^%s+", "")
return (s:gsub("%s+$", ""))
end
function MODEL.baseRecord(mm, source, raw, how, guess)
return { diameter = mm / MM_PER_INCH, mm = mm, source = source,
raw = raw, how = how, guess = guess or nil }
end
function MODEL.footprint(b)
if b == nil then return nil end
local s, k = b.size, 1
if s == nil then s, k = b.extents, 2 end
if s == nil then return nil end
local x, z = tonumber(s.x or s[1]), tonumber(s.z or s[3])
if not (x and z) or x <= 0 or z <= 0 then return nil end
return math.min(x, z) * k
end
function MODEL.measureRaw(obj)
local footprint = MODEL.footprint
local function try(fn)
local ok, v = pcall(fn)
return ok and tonumber(v) or nil
end
local d = try(function() return footprint(obj.getComponent("MeshRenderer").get("bounds")) end)
if d then return d, "renderer" end
d = try(function()
local widest = nil
for _, c in ipairs(obj.getComponents()) do
if tostring(c.name):find("Collider", 1, true) then
local ok, w = pcall(function() return footprint(c.get("bounds")) end)
if ok and w and w > (widest or 0) then widest = w end
end
end
return widest
end)
if d then return d, "collider" end
d = try(function() return footprint(obj.getBoundsNormalized()) end)
or try(function() return footprint(obj.getBounds()) end)
if d then return d, "bounds" end
end
function MODEL.snapBase(mm)
local near, under = nil, nil
for _, s in ipairs(MODEL.BASE_SIZES) do
if not near or math.abs(s - mm) < math.abs(near - mm) then near = s end
if s <= mm and (not under or s > under) then under = s end
end
if not near or math.abs(near - mm) <= MODEL.BASE_SNAP then return near or mm, false end
return under or near, true
end
function MODEL.measureBase(obj)
local d, how = MODEL.measureRaw(obj)
if not d then return nil end
local raw = d * MM_PER_INCH
local mm, guess = MODEL.snapBase(raw)
return MODEL.baseRecord(mm, "measured", math.floor(raw * 10 + 0.5) / 10, how, guess)
end
function MODEL.baseLine(desc)
for raw in (tostring(desc or "") .. "\n"):gmatch("([^\n]*)\n") do
local line = raw:gsub("\r", "")
local bare = line:gsub("%[/?[%w%-]*%]", "")
local n = tonumber(bare:match("^%s*[Bb][Aa][Ss][Ee]%s*:%s*(%d+%.?%d*)%s*[Mm]?[Mm]?%s*$"))
if n and n > 0 then return n, line end
end
end
function MODEL.height(obj)
local okP, p = pcall(function() return obj.getPosition() end)
local y = okP and p and tonumber(p.y or p[2])
if not y then return nil end
local okS, s = pcall(function() return obj.getScale() end)
local sy = math.max(0.01, math.abs(okS and s and tonumber(s.y or s[2]) or 1))
local function up(v)
local ok, n = pcall(function() return tonumber(v.y or v[2]) end)
return ok and n or nil
end
local function topOf(b)
local ok, t = pcall(function()
local c, z, e = up(b.center), up(b.size), up(b.extents)
return up(b.max) or (c and z and c + z / 2) or (c and e and c + e)
end)
return ok and tonumber(t) or nil
end
local best = nil
local function take(b)
local t = topOf(b)
if t and t > y and (not best or t > best) then best = t end
end
for _, get in ipairs({ "getVisualBoundsNormalized", "getBoundsNormalized", "getBounds" }) do
local ok, b = pcall(function() return obj[get]() end)
if ok then take(b) end
end
for _, kind in ipairs({ "MeshRenderer", "SkinnedMeshRenderer" }) do
local ok, list = pcall(function() return obj.getComponentsInChildren(kind) end)
if ok and type(list) == "table" then
for _, c in ipairs(list) do
local okE, on = pcall(function() return c.get("enabled") end)
if not (okE and on == false) then
local okB, b = pcall(function() return c.get("bounds") end)
if okB then take(b) end
end
end
end
end
if best then return (best - y) / sy, best - y end
end
function MODEL.hexColor(v)
local h = tostring(v or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
return h and ("#" .. h:upper()) or nil
end
function MODEL.fullLooks(t)
t = type(t) == "table" and t or {}
local out = {}
for _, c in ipairs(MODEL.LOOKS_COLORS) do
out[c.key] = MODEL.hexColor(t[c.key]) or MODEL.LOOKS_DEFAULT[c.key]
end
out.frame = trim(t.frame)
out.trim = trim(t.trim)
out.tint = tostring(t.tint or "yes"):lower():match("^%s*n") and "no" or "yes"
return out
end
function MODEL.parseLooks(notes)
local OPEN, CLOSE = MODEL.LOOKS_OPEN, MODEL.LOOKS_CLOSE
notes = tostring(notes or "")
local a = notes:find(OPEN, 1, true)
if not a then return nil end
local b = notes:find(CLOSE, a, true) or #notes + 1
local t = {}
for line in notes:sub(a + #OPEN, b - 1):gmatch("[^\r\n]+") do
local eq = line:find("=", 1, true)
local k = eq and trim(line:sub(1, eq - 1)):lower()
if k and k ~= "" and not k:find("%A") then t[k] = trim(line:sub(eq + 1)) end
end
return t
end
function MODEL.formatLooks(t)
local lines = { MODEL.LOOKS_OPEN }
for _, k in ipairs(MODEL.LOOKS_KEYS) do
lines[#lines + 1] = string.format("%-10s = %s", k, tostring(t[k] or ""))
end
lines[#lines + 1] = MODEL.LOOKS_CLOSE
return table.concat(lines, "\n")
end
function MODEL.notesWithLooks(notes, block)
notes = tostring(notes or "")
local a = notes:find(MODEL.LOOKS_OPEN, 1, true)
if a then
local _, b = notes:find(MODEL.LOOKS_CLOSE, a, true)
notes = (notes:sub(1, a - 1) .. notes:sub((b or #notes) + 1)):gsub("^%s+", ""):gsub("%s+$", "")
end
if not block then return notes end
return notes == "" and block or (notes .. "\n\n" .. block)
end
end
local IMPORT_PREFIX = "[Mundane Importer] "
local CARD_SCRIPT
local PANEL = { position = "0 450 -5", rotation = "0 0 180", scale = "1 1 1" }
local TEMPLATES_URL = ""
local TEMPLATES_SOON = "...coming soon"
local CHANGELOG = {
{ version = "3.1.0", note = "Major Update", changes = {
"Loading and performance improvements",
"Spectating works correctly now",
"- Seat as Grey for performance",
"- Seat as a Color for the full experience",
"1v1, 1v2, 2v2 is supported now. Move another fighter to the scoreboard to initialize a team"
} },
{ version = "3.0.0", note = "Huge Update", changes = {
"Full Template, Blast and Unstable attacks support (+Homebrew option for unstable)",
"Dice effect tags (Shred, Blaze, Rending...) and much better chat messages",
"99% of skills, wargear and weapon traits are now fully integrated. All gang rules supported",
"Custom backgrounds for the UI: PNGs with transparency, any image height (they work now)",
"Online reference page for all supported abilities, rules, skills and traits (also on the Controller)",
"Many smaller fixes and readability improvements"
} },
{ version = "2.2.1", note = "Minor Update", changes = {"UI-Overhaul for the Mundane Controller"
} },
{ version = "2.2.0", note = "Major Update", changes = {"Improvements and accessibility for various actions and rolls", "Added deployment zones / setup helper"
} },
{ version = "2.1.2", note = "Minor Update", changes = {"Cover save fix"
} },
{ version = "2.1.1", note = "Minor Update", changes = {"Added Knockback(X+) and Bio-Booster support"
} },
{ version = "2.1.0", note = "Major Update", changes = {"Added auto-update feature (use !update in the chat)."
} },
{ version = "2.0.0", note = "Mundane Importer (N26) release", changes = {
} },
{ version = "1.0.0", note = "Mundane Importer (N23) release", changes = {
} },
}
local C = {
role = "[FFAA44]",
weap = "[C6C930]",
mode = "[888888]",
skey = "[56F442]",
trait = "[7BC596]",
skill = "[DC61ED]",
rule = "[BBBBBB]",
gear = "[00aeff]",
}
local R = "[-]"
local HEADER_SPACING = { M = 3, WS = 3, BS = 3, S = 3, T = 3, W = 3, I = 3, A = 3,
Sv = 3, Ld = 3, Cl = 3, Wil = 3, Int = 3 }
local STAT_SPACING = { M = 3, WS = 3, BS = 3, S = 3, T = 4, W = 3, I = 2, A = 3,
Sv = 3, Ld = 4, Cl = 4, Wil = 5, Int = 5 }
local SPACING_DEFAULT = 3
local STAT_PER_ROW = 8
local LOOKS_SPOT_CENTER = { 0, 0.25, 0 }
local LOOKS_SPOT_GAP = 2.25
local LOOKS_SPOT_COUNT = 3
local SPOT_POLL = 2
local LOOKS_SPOT_SIZE = 1.5
local LOOKS_SPOT_TURN = 0
local function looksSpots()
local spots, c = {}, LOOKS_SPOT_CENTER
for i = 1, LOOKS_SPOT_COUNT do
local dx = ((LOOKS_SPOT_COUNT + 1) / 2 - i) * LOOKS_SPOT_GAP
spots[i] = { c[1] + dx, c[2], c[3] }
end
return spots
end
local THEME_PRESETS = {
{ name = "Classic", background = "#1D2027", headers = "#9AA3AE", text = "#F2F2F2", accent = "#E8C97A", edges = "#6B5B33" },
{ name = "Ash", background = "#1E2124", headers = "#8F979F", text = "#F4F6F8", accent = "#C8D0D8", edges = "#56606A" },
{ name = "Blood", background = "#1F1515", headers = "#A38F8F", text = "#F5EDED", accent = "#E0574A", edges = "#6E2B25" },
{ name = "Toxin", background = "#141B15", headers = "#8FA795", text = "#EEF6EF", accent = "#A6E05A", edges = "#3F6B2B" },
{ name = "Azure", background = "#121923", headers = "#8B9BB1", text = "#EEF3FA", accent = "#6FB5F5", edges = "#2C4F76" },
{ name = "Wyrd", background = "#1A1522", headers = "#9A90A8", text = "#F3EFF8", accent = "#C08CF2", edges = "#54336E" },
{ name = "Brass", background = "#1E1A12", headers = "#A89A7C", text = "#F7F0E0", accent = "#D9A441", edges = "#7A5A26" },
{ name = "Ember", background = "#20140E", headers = "#B39A88", text = "#FBF1E8", accent = "#FF8A3D", edges = "#8A3A12" },
{ name = "Frost", background = "#0F1C22", headers = "#8FB3BF", text = "#EAF8FC", accent = "#7FE3F0", edges = "#2D6572" },
{ name = "Neon", background = "#150F1C", headers = "#A58FB5", text = "#FFF0FB", accent = "#FF4FD8", edges = "#1F9DA3" },
}
local THEMES_PER_ROW = 5
local SWATCH_HUES = {
{ 0, 0 },
{ 4, 1.0 },
{ 16, 0.85 },
{ 28, 1.0 },
{ 42, 1.0 },
{ 54, 1.0 },
{ 72, 0.75 },
{ 100, 0.85 },
{ 172, 0.9 },
{ 212, 1.0 },
{ 238, 0.9 },
{ 275, 0.9 },
{ 322, 0.9 },
}
local SWATCH_ROWS = {
background = { l = 0.14, s = 0.55 },
headers = { l = 0.64, s = 0.40 },
text = { l = 0.93, s = 1.00 },
accent = { l = 0.62, s = 0.95 },
edges = { l = 0.46, s = 0.62 },
}
local function hsl(hue, sat, light)
local c = (1 - math.abs(2 * light - 1)) * sat
local hp = (hue % 360) / 60
local x = c * (1 - math.abs(hp % 2 - 1))
local r, g, b = 0, 0, 0
if hp < 1 then r, g = c, x elseif hp < 2 then r, g = x, c elseif hp < 3 then g, b = c, x
elseif hp < 4 then g, b = x, c elseif hp < 5 then r, b = x, c else r, b = c, x end
local m = light - c / 2
return string.format("#%02X%02X%02X", math.floor((r + m) * 255 + 0.5),
math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5))
end
local SWATCHES = {}
for key, row in pairs(SWATCH_ROWS) do
SWATCHES[key] = {}
for n, hue in ipairs(SWATCH_HUES) do
SWATCHES[key][n] = (key == "text" and hue[2] == 0) and "#FFFFFF" or hsl(hue[1], row.s * hue[2], row.l)
end
end
local FRAME_PRESETS = {
{ name = "None", frame = "none", trim = "" },
{ name = "Hexagon", frame = "", trim = "", upload = true },
{ name = "Plate", frame = "", trim = "", upload = true },
{ name = "Bracket", frame = "", trim = "", upload = true },
{ name = "Riveted", frame = "", trim = "", upload = true },
}
local FIELD_LABELS = {
{ label = "Rating", key = "rating" },
{ label = "Skills", key = "skills" },
{ label = "Wargear", key = "wargear" },
{ label = "Rules", key = "rules" },
}
local STAT_HEADER = "^M%s+WS%s+BS%s+S%s+T%s+W%s+I%s+A%s+Sv%s+Ld"
local WEAP_HEADER = "^Weapon%s+SR"
local COL = { sr = 1, lr = 2, str = 3, ap = 4, l = 5, traits = 6 }
local rosterText = ""
local function splitTab(line)
local parts = {}
for part in ((line or "") .. "\t"):gmatch("([^\t]*)\t") do
parts[#parts + 1] = trim(part)
end
return parts
end
local function extractField(t, label)
return t:match("^" .. label .. ":%s*(.*)")
end
local MAX_COPIES = 6
local function splitCount(str)
str = str or ""
local a, b, n = str:find("%s*%(%s*[xX]%s*(%d+)%s*%)")
n = tonumber(n)
if not n or n < 1 then return str, 1 end
return trim(str:sub(1, a - 1) .. " " .. str:sub(b + 1)), math.min(n, MAX_COPIES)
end
local function cleanItemName(str, removeInfo)
if not str or str == "" then return "" end
if removeInfo then str = str:gsub("%s*%b()%s*", "") end
str = trim(str)
return (str:lower():gsub("(%a)([%w_']*)", function(f, r) return f:upper() .. r end))
end
local function parseProfile(mode, raw)
local p = splitTab((raw or ""):gsub("^\t+", ""))
local function col(key, fallback)
local v = p[COL[key]]
if v == nil or v == "" then return fallback end
return v
end
return {
mode = mode or "",
sr = col("sr", "-"), lr = col("lr", "-"), str = col("str", "-"),
ap = col("ap", "-"), l = col("l", "-"), traits = col("traits", ""),
}
end
local function isEmptyProfile(p)
if p.traits ~= "" and p.traits ~= "-" then return false end
for _, k in ipairs({ "sr", "lr", "str", "ap", "l" }) do
if p[k] ~= "" and p[k] ~= "-" then return false end
end
return true
end
local function findBlockStarts(lines)
local starts = {}
for i, line in ipairs(lines) do
if line:match("^%d+\t%s*$") then
starts[#starts + 1] = i
elseif trim(line):match("^%d+$") then
for j = i + 1, math.min(i + 3, #lines) do
if trim(lines[j]):match("^Rating:%s*%d") then
starts[#starts + 1] = i
break
end
end
end
end
return starts
end
local WARGEAR_GRANTS = {
conduitofozostium = { subtype = "Wyrd", power = "Force Blast" },
glovesofozostium = { subtype = "Wyrd", power = "Flaming Weapon" },
}
local function grantKey(name) return (tostring(name or ""):lower():gsub("[^%w]", "")) end
local function listNames(s)
local out, depth, cur = {}, 0, {}
for c in (tostring(s or "") .. ","):gmatch(".") do
if c == "(" then depth = depth + 1 elseif c == ")" and depth > 0 then depth = depth - 1 end
if c == "," and depth == 0 then
local name = trim(table.concat(cur))
if name ~= "" then out[#out + 1] = name end
cur = {}
else
cur[#cur + 1] = c
end
end
return out
end
local function applyGrants(f)
for _, item in ipairs(listNames(f.wargear)) do
local g = WARGEAR_GRANTS[grantKey(item)]
if g and g.subtype then
local parts = {}
for p in (f.role .. "•"):gmatch("(.-)•") do parts[#parts + 1] = trim(p) end
local has = false
for tag in ((parts[2] or "") .. ","):gmatch("([^,]*),") do
has = has or grantKey(tag) == grantKey(g.subtype)
end
if not has then
if #parts < 2 or parts[2] == "" then parts[2] = g.subtype
else parts[2] = parts[2] .. ", " .. g.subtype end
f.role = table.concat(parts, " • ")
end
end
if g and g.power then
local has = false
for _, s in ipairs(listNames(f.skills)) do has = has or grantKey(s) == grantKey(g.power) end
if not has then
local s = trim(f.skills or "")
f.skills = (s ~= "" and s ~= "-" and s ~= "—") and (s .. ", " .. g.power) or g.power
end
end
end
end
local function parseBlock(lines)
local f = { name = "", role = "", statKeys = {}, statVals = {}, weapons = {} }
local statValIdx = nil
local i = 2
while i <= #lines do
local raw, t = lines[i], trim(lines[i])
i = i + 1
if t == "" then
elseif f.name == "" then
f.name = t
elseif t:match("%s•%s") then
f.role = t
else
local matched = false
for _, lbl in ipairs(FIELD_LABELS) do
local v = extractField(t, lbl.label)
if v then f[lbl.key] = trim(v); matched = true; break end
end
if not matched and t:match(STAT_HEADER) then
f.statKeys = splitTab(raw)
if i <= #lines then
f.statVals, statValIdx = splitTab(lines[i]), i
i = i + 1
end
end
end
end
local cur = nil
local function flush()
if cur and #cur.profiles > 0 then f.weapons[#f.weapons + 1] = cur end
cur = nil
end
local function isMeta(t, idx)
if idx == statValIdx or t == f.name or t:match("%s•%s") or t:match(STAT_HEADER) then
return true
end
for _, lbl in ipairs(FIELD_LABELS) do
if t:match("^" .. lbl.label .. ":") then return true end
end
return false
end
local function add(p) if not isEmptyProfile(p) then cur.profiles[#cur.profiles + 1] = p end end
local group = nil
i = 2
while i <= #lines do
local raw, t, idx = lines[i], trim(lines[i]), i
i = i + 1
if t == "" or isMeta(t, idx) then
elseif t:match(WEAP_HEADER) then
flush()
elseif t:match("^%- %a") then
if cur and i <= #lines then
group = t:match("^%- (.*)")
add(parseProfile(group, lines[i]))
i = i + 1
end
elseif t:match("^%-%-+ %a") then
if cur and i <= #lines then
local p = parseProfile(t:match("^%-%-+ (.*)"), lines[i])
p.group = group
add(p)
i = i + 1
end
elseif raw:find("\t") then
if cur then add(parseProfile("", raw)) end
else
flush()
cur, group = { name = t, profiles = {} }, nil
local nr = lines[i]
if nr and nr:find("\t") and not trim(nr):match("^%- %a") and trim(nr) ~= "" then
add(parseProfile("", nr))
i = i + 1
end
end
end
flush()
applyGrants(f)
return f
end
local function parseExport(raw)
local text = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
local lines = {}
for ln in (text .. "\n"):gmatch("([^\n]*)\n") do
if trim(ln) ~= "" then lines[#lines + 1] = ln end
end
local starts, fighters = findBlockStarts(lines), {}
local gang = (starts[1] or 1) > 1 and trim(lines[1]) or nil
local kind = gang and (starts[1] or 1) > 2 and trim(lines[2]) or nil
if kind and (kind:find(":%s*$") or kind:find("^%d")) then kind = nil end
for bi, si in ipairs(starts) do
local block = {}
for k = si, (starts[bi + 1] or (#lines + 1)) - 1 do block[#block + 1] = lines[k] end
local f = parseBlock(block)
if f.name ~= "" then fighters[#fighters + 1] = f end
end
return fighters, gang, kind
end
local function fmtRange(sr, lr)
if sr == "T" or lr == "T" then return "T" end
if sr == "E" or lr == "E" then return "Melee" end
local hasS, hasL = sr ~= "-" and sr ~= "", lr ~= "-" and lr ~= ""
if hasS and hasL then return sr .. "/" .. lr end
if hasS then return sr end
if hasL then return lr end
return nil
end
local function buildDesc(f)
local out = {}
local function ln(s) out[#out + 1] = s or "" end
if f.role ~= "" then ln(C.role .. f.role .. R) end
if #f.statKeys > 0 and #f.statVals > 0 then
ln("")
local k1, v1, k2, v2, n = {}, {}, {}, {}, 0
for k, key in ipairs(f.statKeys) do
if key ~= "" then
n = n + 1
local pk = key .. string.rep(" ", math.max(1, HEADER_SPACING[key] or SPACING_DEFAULT))
local pv = (f.statVals[k] or "?") ..
string.rep(" ", math.max(1, STAT_SPACING[key] or SPACING_DEFAULT))
if n <= STAT_PER_ROW then k1[#k1 + 1], v1[#v1 + 1] = pk, pv
else k2[#k2 + 1], v2[#v2 + 1] = pk, pv end
end
end
if #k1 > 0 then ln(C.skey .. table.concat(k1) .. R); ln(table.concat(v1)) end
if #k2 > 0 then ln(""); ln(C.skey .. table.concat(k2) .. R); ln(table.concat(v2)) end
end
if #f.weapons > 0 then
ln("")
for _, w in ipairs(f.weapons) do
ln(C.weap .. cleanItemName(w.name) .. R)
for _, p in ipairs(w.profiles) do
local parts = {}
if p.mode ~= "" then
local mode = cleanItemName(p.mode, true)
if p.group then mode = cleanItemName(p.group, true) .. ": " .. mode end
parts[#parts + 1] = C.mode .. "> [" .. mode .. "]\n" .. R
end
local rng = fmtRange(p.sr, p.lr)
if rng then parts[#parts + 1] = rng end
parts[#parts + 1] = "S:" .. p.str .. " "
parts[#parts + 1] = "AP:" .. p.ap .. " "
parts[#parts + 1] = "L:" .. p.l .. " "
local row = table.concat(parts, " ") .. "\n"
if p.traits ~= "" and p.traits ~= "-" then
row = row .. " " .. C.trait .. p.traits .. R .. "\n"
end
ln(row)
end
end
end
if f.skills then ln(C.skill .. f.skills .. R) end
if f.wargear then ln(C.gear .. f.wargear .. R) end
if f.rules then ln(C.rule .. f.rules .. R) end
return table.concat(out, "\n")
end
local function traitValue(traits, pattern)
for t in ((traits or "") .. ","):gmatch("([^,]*),") do
local v = trim(t):lower():match("^" .. pattern .. "$")
if v then return v end
end
end
local RANKS = { leader = "Leader", champion = "Champion", ganger = "Ganger", prospect = "Prospect", brute = "Brute" }
local SPECIALISMS = { medic = "medic", tech = "tech", brawler = "melee",
heavy = "ranged", gunner = "ranged", gunslinger = "ranged", scout = "ranged", sniper = "ranged" }
local CATEGORY_ORDER = { "wyrd", "loner", "medic", "tech", "melee", "ranged", "beast" }
local function splitRole(role)
local parts = {}
for p in ((role or "") .. "•"):gmatch("(.-)•") do parts[#parts + 1] = trim(p) end
if #parts < 2 then return trim(role), nil, nil end
local rank, has = nil, {}
for tag in (parts[2] .. ","):gmatch("([^,]*),") do
local t = trim(tag):lower()
rank = rank or RANKS[t]
has[t] = true
end
if has.specialist then
local spec = SPECIALISMS[(parts[3] or ""):lower()]
if spec then has[spec] = true end
end
for _, c in ipairs(CATEGORY_ORDER) do
if has[c] then return parts[1], rank, c end
end
return parts[1], rank, nil
end
local function meleeProfile(p)
for t in ((p.traits or "") .. ","):gmatch("([^,]*),") do
if trim(t):lower() == "melee" then return true end
end
return false
end
local function splitMixed(name, profiles)
local melee, ranged = {}, {}
for _, p in ipairs(profiles) do
if meleeProfile(p) then melee[#melee + 1] = p else ranged[#ranged + 1] = p end
end
if #melee == 0 or #ranged == 0 then return { { name = name, profiles = profiles } } end
local parts = {}
for part in (name .. "/"):gmatch("([^/]*)/") do
if trim(part) ~= "" then parts[#parts + 1] = trim(part) end
end
local function key(s) return trim((tostring(s or ""):lower():gsub("%b()", ""):gsub("%*", ""))) end
local function named(list)
local own = list[1].group or (#list == 1 and list[1].mode ~= "" and list[1].mode) or nil
if own and #parts >= 2 then
for _, part in ipairs(parts) do
if key(own) ~= "" and key(part):find(key(own), 1, true) then return part end
end
end
return own or name
end
return { { name = named(melee), profiles = melee, single = #melee == 1 },
{ name = named(ranged), profiles = ranged, single = #ranged == 1 } }
end
local function toCardFighter(f)
local stats = {}
for k, key in ipairs(f.statKeys) do
if key ~= "" then stats[key] = f.statVals[k] or "-" end
end
local weapons = {}
for wi = 1, #f.weapons do
local w = f.weapons[wi]
local name, copies = splitCount(w.name)
for _ = 1, copies do
for _, part in ipairs(splitMixed(name, w.profiles)) do
local profiles = {}
for _, p in ipairs(part.profiles) do
profiles[#profiles + 1] = {
name = not part.single and p.mode ~= "" and cleanItemName(p.mode, true) or nil,
SR = p.sr, LR = p.lr, S = p.str, AP = p.ap, L = p.l,
D = traitValue(p.traits, "damage%s*%(%s*(%d+)%s*%)") or "-",
Am = traitValue(p.traits, "ammo%s*%(%s*(%d%+?)%s*%)") or "-",
traits = p.traits,
}
end
weapons[#weapons + 1] = { name = cleanItemName(part.name), profiles = profiles }
end
end
end
local ftype, rank, category = splitRole(f.role)
return {
name = f.name, rank = rank or "None", ftype = ftype ~= "" and ftype or "None", category = category,
role = f.role, rating = f.rating,
skills = f.skills or "", wargear = f.wargear or "",
rules = f.rules,
stats = stats, weapons = weapons,
}
end
local function baseFor(obj, desc)
local mm = MODEL.baseLine(desc)
if mm then return MODEL.baseRecord(mm, "description") end
local ok, b = callIfHas(obj, "getBase")
if ok and type(b) == "table" and b.source == "manual" and tonumber(b.diameter) then
return { diameter = tonumber(b.diameter),
mm = tonumber(b.mm) or tonumber(b.diameter) * MODEL.MM_PER_INCH, source = "manual" }
end
return MODEL.measureBase(obj)
end
local function baseText(b)
if not b then return "not measured (the card assumes its default)" end
local t = string.format("%gmm", b.mm)
if b.source ~= "measured" then return t .. " (" .. (b.source == "manual" and "set by hand" or "in description") .. ")" end
if b.guess then return t .. string.format(" (measured %gmm -- check it)", b.raw) end
return t
end
local function luaString(s)
return '"' .. s:gsub('[\1-\31\127"\\]', function(c)
if c == "\n" then return "\\n" elseif c == "\r" then return "\\r"
elseif c == "\t" then return "\\t" elseif c == '"' then return '\\"'
elseif c == "\\" then return "\\\\" end
local b = c:byte()
if b < 32 or b == 127 then return string.format("\\%03d", b) end
return c
end) .. '"'
end
local function toLua(v)
local t = type(v)
if t == "string" then return luaString(v) end
if t == "number" or t == "boolean" then return tostring(v) end
if t ~= "table" then return "nil" end
local keys = {}
for k in pairs(v) do keys[#keys + 1] = k end
table.sort(keys, function(a, b)
if type(a) == type(b) then return a < b end
return type(a) == "number"
end)
local parts = {}
for _, k in ipairs(keys) do
local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. luaString(k) .. "]")
parts[#parts + 1] = key .. " = " .. toLua(v[k])
end
return "{ " .. table.concat(parts, ", ") .. " }"
end
local IMPORT_MARKER = "local IMPORTED = nil --@@MUNDA_IMPORT@@"
local function cardScriptFor(fighter, id)
local a, b = CARD_SCRIPT:find(IMPORT_MARKER, 1, true)
if not a then error("the embedded card script has no import line -- rebuild the importer") end
return CARD_SCRIPT:sub(1, a - 1)
.. "local IMPORTED = " .. toLua({ id = id, fighter = fighter }) .. " --@@MUNDA_IMPORT@@"
.. CARD_SCRIPT:sub(b + 1)
end
local function sameLooks(a, b)
for _, k in ipairs(MODEL.LOOKS_KEYS) do if (a[k] or "") ~= (b[k] or "") then return false end end
return true
end
local upgradeCard, cardIsCurrent
local function writeLooks(obj, t)
obj.setGMNotes(MODEL.notesWithLooks(obj.getGMNotes(), t and MODEL.formatLooks(t) or nil))
local ok, script = pcall(function() return obj.getLuaScript() end)
script = ok and tostring(script or "") or ""
if not script:find("@@MUNDA_IMPORT@@", 1, true) then return end
if cardIsCurrent(script) then
pcall(function() obj.call("reloadLooks") end)
else
upgradeCard(obj, script)
end
end
local function gangTag(name)
name = trim((tostring(name or ""):gsub("[^%w%s_%-%.']", ""):gsub("%s+", " ")))
return name ~= "" and (GANG_TAG .. name:sub(1, 60)) or nil
end
local function setGang(obj, tag)
local ok, tags = pcall(function() return obj.getTags() end)
for _, t in ipairs(ok and tags or {}) do
local old = t:sub(1, #GANG_TAG) == GANG_TAG
for _, o in ipairs(OLD_TAGS) do old = old or t:sub(1, #o) == o end
if old and t ~= tag then obj.removeTag(t) end
end
if tag and not obj.hasTag(tag) then obj.addTag(tag) end
end
local function cardModels(tag)
local out = {}
for _, obj in ipairs(getAllObjects()) do
if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) and obj.hasTag(tag) then out[#out + 1] = obj end
end
return out
end
local lastGang = nil
local edit = MODEL.fullLooks(nil)
local targets = {}
local target = nil
local function installCard(obj, script)
if IMPORT_TAG ~= "" and not obj.hasTag(IMPORT_TAG) then obj.addTag(IMPORT_TAG) end
obj.setLuaScript("")
Wait.time(function()
if obj and not obj.isDestroyed() then
obj.setLuaScript(script)
Wait.time(function()
if obj and not obj.isDestroyed() then obj.reload() end
end, 0.1)
end
end, 0.1)
end
local function findUnused(name, used)
local low = name:lower()
for _, obj in ipairs(getAllObjects()) do
if obj.getName():lower() == low and not used[obj.getGUID()] then return obj end
end
end
local importCount = 0
local function splitCard(script)
local a = script:find("local IMPORTED = ", 1, true)
local _, b = script:find("--@@MUNDA_IMPORT@@", a or 1, true)
if not (a and b) then return nil end
return script:sub(1, a - 1), script:sub(a, b), script:sub(b + 1)
end
local CARD_PARTS = {}
cardIsCurrent = function(script)
if not CARD_PARTS.pre then
local a, b = CARD_SCRIPT:find(IMPORT_MARKER, 1, true)
if not a then return false end
CARD_PARTS.pre, CARD_PARTS.post = CARD_SCRIPT:sub(1, a - 1), CARD_SCRIPT:sub(b + 1)
end
local pre, _, post = splitCard(script)
return pre ~= nil and #pre == #CARD_PARTS.pre and #post == #CARD_PARTS.post
and pre == CARD_PARTS.pre and post == CARD_PARTS.post
end
upgradeCard = function(obj, script)
local _, line = splitCard(script)
local a, b = CARD_SCRIPT:find(IMPORT_MARKER, 1, true)
if not (line and a) then return end
installCard(obj, CARD_SCRIPT:sub(1, a - 1) .. line .. CARD_SCRIPT:sub(b + 1))
end
local function runImport(rawText, player)
local ok, fighters, gang, gangType = pcall(parseExport, rawText)
if not ok then
printToAll(IMPORT_PREFIX .. "Parse error: " .. tostring(fighters), { 1, 0.2, 0.2 })
return nil, "Parse error: " .. tostring(fighters)
end
importCount = importCount + 1
local batch = string.format("%s-%d-%d", self.getGUID(), os.time(), importCount)
local applied, notFound, used, bases = 0, {}, {}, {}
local busObjs, busStamps = {}, {}
local tag = gangTag(gang)
if tag then lastGang = tag end
for fi, f in ipairs(fighters) do
local obj = findUnused(f.name, used)
if obj then
used[obj.getGUID()] = true
local okD, oldDesc = pcall(function() return obj.getDescription() end)
oldDesc = okD and oldDesc or ""
local base, kept = baseFor(obj, oldDesc), select(2, MODEL.baseLine(oldDesc))
obj.setDescription(buildDesc(f) .. (kept and ("\n\n" .. kept) or ""))
setGang(obj, tag)
if not MODEL.parseLooks(obj.getGMNotes()) then
obj.setGMNotes(MODEL.notesWithLooks(obj.getGMNotes(), MODEL.formatLooks(MODEL.fullLooks(nil))))
end
local cf = toCardFighter(f)
local height, tall = MODEL.height(obj)
cf.base, cf.height = base, height
cf.gangType = gangType
local okL, lift = callIfHas(obj, "getLift")
cf.lift = okL and tonumber(lift) or nil
busStamps[#busObjs + 1] = __nqs_mundane_bus.stampOf(obj)
busObjs[#busObjs + 1] = obj
installCard(obj, cardScriptFor(cf, batch .. "-" .. fi))
obj.highlightOn({ 0, 1, 0 }, 0.8)
applied = applied + 1
bases[#bases + 1] = f.name .. ": " .. baseText(base)
.. (tall and string.format(', %.1f" tall', tall) or ", height not measured")
else
notFound[#notFound + 1] = f.name
end
end
printToAll(string.format(IMPORT_PREFIX .. "Imported %d fighter(s) onto their models.", applied),
{ 0.3, 1, 0.4 })
if #notFound > 0 then
printToAll(IMPORT_PREFIX .. "No model named:", { 1, 0.7, 0.2 })
for _, n in ipairs(notFound) do printToAll(IMPORT_PREFIX .. "    * " .. n, { 1, 0.85, 0.5 }) end
end
if #bases > 0 then
printToAll(IMPORT_PREFIX .. "Bases / Heights (put \"Base: XXmm\" in descriptions before import, if it is not recognized correctly):",
{ 0.6, 0.85, 1 })
for _, n in ipairs(bases) do printToAll(IMPORT_PREFIX .. "    * " .. n, { 0.8, 0.92, 1 }) end
end
__nqs_mundane_bus.refreshed(busObjs, busStamps, applied)
return applied, notFound
end
local function framePresets()
local out = {}
for _, f in ipairs(FRAME_PRESETS) do
if not f.upload or f.frame ~= "" then out[#out + 1] = f end
end
return out
end
local function currentFrame()
for i, f in ipairs(framePresets()) do
if edit.frame == f.frame and edit.trim == (f.trim or "") then return i end
end
end
local ROSTER_HINT = "Paste the roster here (Print Options -> Roster -> Copy the table)..."
local FRAME_URL_HINT = "...or paste your own image URL (PNG or JPG, fixed width, any height)"
local function frameUrlText()
if currentFrame() or not tostring(edit.frame or ""):match("^https?://") then return FRAME_URL_HINT end
return edit.frame
end
local SWATCH_W = 25
local ROW_W = 92 + 28 + 86 + #SWATCH_HUES * SWATCH_W + (2 + #SWATCH_HUES) * 3
local PANEL_W = ROW_W + 2 * 9 + 2 * 3
local SECTION_H = 426
local IMPORT_H = 162
local PANEL_H = 664
local EDIT_H = SECTION_H + 2 * 9 + 2 * 3
local function looksXml()
local rows = {}
local function add(s) rows[#rows + 1] = s end
add(string.format('<VerticalLayout id="appearanceSection" preferredHeight="%d" spacing="6" childForceExpandHeight="false">',
SECTION_H))
add('<Text preferredHeight="28" fontSize="20" fontStyle="Bold">UI Appearance</Text>')
for _, c in ipairs(MODEL.LOOKS_COLORS) do
local sw = {}
for n, hex in ipairs(SWATCHES[c.key]) do
sw[#sw + 1] = string.format('<Button id="pre_%s_%d" preferredWidth="%d" colors="%s"%s onClick="onSwatch" />',
c.key, n, SWATCH_W, colors(hex), BEVEL)
end
add(string.format(
'<HorizontalLayout preferredHeight="32" spacing="3" childForceExpandWidth="false">' ..
'<Text preferredWidth="92" fontSize="15" fontStyle="Bold" alignment="MiddleLeft">%s</Text>' ..
'<Image id="sw_%s" preferredWidth="28" color="%s"%s />' ..
'<InputField id="hex_%s" preferredWidth="86" fontSize="13" characterLimit="7" textAlignment="MiddleCenter" text="%s" onEndEdit="onHexEdit" />' ..
'%s</HorizontalLayout>', c.label, c.key, edit[c.key], BEVEL, c.key, edit[c.key], table.concat(sw)))
end
for first = 1, #THEME_PRESETS, THEMES_PER_ROW do
local th = {}
for n = first, first + THEMES_PER_ROW - 1 do
local t = THEME_PRESETS[n]
th[#th + 1] = t and string.format('<Button id="theme_%d" fontSize="14" onClick="onTheme">%s</Button>', n, t.name)
or '<Panel color="#00000000" />'
end
add('<HorizontalLayout preferredHeight="28" spacing="4">' .. table.concat(th) .. '</HorizontalLayout>')
end
local fr, cur = {}, currentFrame()
for n, f in ipairs(framePresets()) do
fr[#fr + 1] = string.format('<Button id="frame_%d" fontSize="14" colors="%s" textColor="%s" onClick="onFramePreset">%s</Button>',
n, n == cur and LIT or WASH, n == cur and PALE or INK, f.name)
end
add('<HorizontalLayout preferredHeight="28" spacing="4">' ..
'<Text preferredWidth="92" fontSize="15" fontStyle="Bold" alignment="MiddleLeft">Background</Text>' ..
table.concat(fr) .. '</HorizontalLayout>')
add(string.format('<HorizontalLayout preferredHeight="28" spacing="4" childForceExpandWidth="false">' ..
'<Text preferredWidth="92" fontSize="15" fontStyle="Bold" alignment="MiddleLeft">Templates</Text>' ..
'<InputField id="templatesUrl" preferredWidth="%d" fontSize="12" readOnly="true" textAlignment="MiddleLeft"' ..
' text="%s" />' ..
'</HorizontalLayout>', ROW_W - 96, xmlEsc(TEMPLATES_URL ~= "" and TEMPLATES_URL or TEMPLATES_SOON)))
add(string.format('<InputField id="frameUrl" preferredHeight="32" fontSize="13" textAlignment="MiddleLeft" text="%s"' ..
' onEndEdit="onFrameUrl" />', xmlEsc(frameUrlText())))
add(string.format(
'<HorizontalLayout preferredHeight="28" spacing="6">' ..
'<Button id="applyAll" fontSize="15" colors="%s" textColor="%s" onClick="onApplyAll">Apply UI to the whole Gang</Button>' ..
'<Button id="resetAll" fontSize="15" colors="%s" textColor="%s" onClick="onResetAll">Reset UI for the whole Gang</Button>' ..
'</HorizontalLayout>', LIT, PALE, RED, PALE))
add('</VerticalLayout>')
return table.concat(rows)
end
local HISTORY_BTN_W = 150
local function historyXml()
local lines = {}
for _, v in ipairs(CHANGELOG) do
lines[#lines + 1] = "v" .. v.version .. (v.note and ("  --  " .. v.note) or "")
for _, c in ipairs(v.changes) do lines[#lines + 1] = "   - " .. c end
lines[#lines + 1] = ""
end
return string.format([[
    <Panel id="historyPopup" active="false" rectAlignment="MiddleCenter" width="%d" height="%d"
           color="#1C2224F5" padding="14 14 12 12" outline="%s" outlineSize="2 2">
      <VerticalLayout spacing="8" childForceExpandHeight="false">
        <Text preferredHeight="30" fontSize="22" fontStyle="Bold" color="%s">Update History</Text>
        <Text preferredHeight="%d" fontSize="14" color="%s" alignment="UpperLeft">%s</Text>
        <Button preferredHeight="34" fontSize="16" colors="#FFFFFF26|#FFFFFF40|#FFFFFF1A|#FFFFFF1A"
                textColor="%s" outline="#E6E5E14D" onClick="onHistory">Close</Button>
      </VerticalLayout>
    </Panel>]], PANEL_W - 6, PANEL_H - 6, PAPER, PAPER, PANEL_H - 6 - 26 - 30 - 34 - 16, PAPER,
xmlEsc(table.concat(lines, "\n")), PAPER)
end
local function panelXml()
local body = string.format([[
      <VerticalLayout id="importSection" preferredHeight="%d" spacing="6" childForceExpandHeight="false">
      <Text preferredHeight="18" fontSize="14" fontStyle="Bold" verticalOverflow="Overflow">Paste a MundaManager roster export and press Import.</Text>
      <Text preferredHeight="18" fontSize="14" fontStyle="Bold" verticalOverflow="Overflow">Fighter info goes onto the models with the same name as the Fighter.</Text>
      <Text preferredHeight="18" fontSize="14" fontStyle="Bold" verticalOverflow="Overflow">You can edit the UI of the Fighters by putting them on the pedestal.</Text>
      <Panel id="rosterBox" preferredHeight="47" color="#00000000">
        <InputField id="rosterInput" width="%d" height="47" lineType="MultiLineNewline" fontSize="13"
                    textAlignment="MiddleLeft" text="%s" onValueChanged="onRosterInputChanged"
                    onEndEdit="onRosterInputDone" />
      </Panel>
      <HorizontalLayout preferredHeight="28" spacing="6" childForceExpandWidth="false">
        <Button id="importBtn" preferredWidth="%d" fontSize="17" colors="%s" textColor="%s" onClick="confirmImport">Import</Button>
        <Button id="historyBtn" preferredWidth="%d" fontSize="15" onClick="onHistory">Update History</Button>
      </HorizontalLayout>
      <Image preferredHeight="3" color="#29313399" />
      </VerticalLayout>
      %s]], IMPORT_H, ROW_W, xmlEsc(ROSTER_HINT), ROW_W - HISTORY_BTN_W - 6, LIT, PALE, HISTORY_BTN_W, looksXml())
return panelShell({ id = "importPanel", position = PANEL.position, rotation = PANEL.rotation, scale = PANEL.scale,
width = PANEL_W, height = PANEL_H, title = IMPORTER_NAME .. " (N26)", version = VERSION,
body = body, over = historyXml() })
end
local function panelAssets()
return { { name = "mundanePanelBg", url = PANEL_BG } }
end
local function currentGang()
return (target and gangOf(target)) or lastGang
end
local function drawEditor()
for _, c in ipairs(MODEL.LOOKS_COLORS) do
self.UI.setAttribute("sw_" .. c.key, "color", edit[c.key])
self.UI.setAttribute("hex_" .. c.key, "text", edit[c.key])
end
local cur = currentFrame()
for n in ipairs(framePresets()) do
self.UI.setAttribute("frame_" .. n, "colors", n == cur and LIT or WASH)
self.UI.setAttribute("frame_" .. n, "textColor", n == cur and PALE or INK)
end
self.UI.setAttribute("frameUrl", "text", frameUrlText())
end
local function editChanged()
drawEditor()
for _, o in ipairs(targets) do
if not o.isDestroyed() then writeLooks(o, edit) end
end
end
local function modelsOnSpots()
local found, seen = {}, {}
if not (Physics and Physics.cast and self.positionToWorld) then return found end
for _, spot in ipairs(looksSpots()) do
local p = self.positionToWorld(spot)
local hits = Physics.cast({ origin = { p.x, p.y + 1.5, p.z }, direction = { 0, 1, 0 }, type = 3,
size = { LOOKS_SPOT_SIZE, 3, LOOKS_SPOT_SIZE }, max_distance = 0 }) or {}
for _, h in ipairs(hits) do
local o = h.hit_object
if o and o ~= self and o.type ~= "Surface" and o.tag ~= "Surface" then
if not seen[o] then seen[o] = true; found[#found + 1] = o end
break
end
end
end
return found
end
local function panelPosition(h)
local function nums(str)
local t = {}
for n in tostring(str):gmatch("%-?[%d%.]+") do t[#t + 1] = tonumber(n) end
return t
end
local pos, rot, sc = nums(PANEL.position), nums(PANEL.rotation), nums(PANEL.scale)
local d = (PANEL_H - h) / 2 * (sc[2] or 1)
local rx, ry, rz = math.rad(rot[1] or 0), math.rad(rot[2] or 0), math.rad(rot[3] or 0)
local x, y, z = -d * math.sin(rz), d * math.cos(rz), 0
y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
local function f(v) return (string.format("%.2f", v):gsub("%.?0+$", "")) end
return f((pos[1] or 0) + x) .. " " .. f((pos[2] or 0) + y) .. " " .. f((pos[3] or 0) + z)
end
local function showSections()
local function show(id, on) self.UI.setAttribute(id, "active", on and "true" or "false") end
local editing = target ~= nil
show("headerPanel", not editing)
show("importSection", not editing)
local h = editing and EDIT_H or PANEL_H
self.UI.setAttribute("importPanel", "height", tostring(h * PANEL_DETAIL))
self.UI.setAttribute("importPanel", "position", panelPosition(h))
end
local function checkSpot()
local now = modelsOnSpots()
local same = #now == #targets
for i = 1, #now do same = same and now[i] == targets[i] end
if same then return end
local was, newcomer = {}, nil
for _, o in ipairs(targets) do was[o] = true end
for _, o in ipairs(now) do
if not was[o] then
newcomer = newcomer or o
pcall(function() o.highlightOn({ 0.9, 0.8, 0.4 }, 1) end)
end
end
local changed = (#now == 0) ~= (#targets == 0)
targets, target = now, now[1]
if newcomer then edit = MODEL.fullLooks(MODEL.parseLooks(newcomer.getGMNotes())) end
drawEditor()
if changed then showSections() end
end
local function addSnapPoint(old)
if not (self.getSnapPoints and self.setSnapPoints) then return end
local c = LOOKS_SPOT_CENTER
local reach = (LOOKS_SPOT_COUNT + 1) / 2 * LOOKS_SPOT_GAP + LOOKS_SPOT_GAP
local function ours(q)
local x, z = q.x or q[1] or 0, q.z or q[3] or 0
for _, s in ipairs(old or {}) do
if math.abs(x - (s[1] or 0)) < 0.01 and math.abs(z - (s[3] or 0)) < 0.01 then return true end
end
return math.abs(z - c[3]) < 0.01 and math.abs(x - c[1]) <= reach
end
local pts = {}
for _, sp in ipairs(self.getSnapPoints() or {}) do
if not ours(sp.position or {}) then pts[#pts + 1] = sp end
end
for _, spot in ipairs(looksSpots()) do
pts[#pts + 1] = { position = spot, rotation = { 0, LOOKS_SPOT_TURN, 0 }, rotation_snap = true }
end
self.setSnapPoints(pts)
end
function onSave()
return JSON.encode({ version = VERSION, looks = edit, gang = lastGang, spots = looksSpots() })
end
function onLoad(saved)
if Updater_stateVersion then
local _ = nil
_, VERSION = Updater_stateVersion(saved)
end
local ok, data = pcall(function() return JSON.decode(saved or "") end)
if ok and type(data) == "table" then
if data.looks then edit = MODEL.fullLooks(data.looks) end
lastGang = data.gang
end
pcall(function()
if self.hasTag(CONTROLLER_TAG) then self.removeTag(CONTROLLER_TAG) end
if not self.hasTag(IMPORTER_TAG) then self.addTag(IMPORTER_TAG) end
end)
self.UI.setXml(detailed(panelXml(), "importPanel"), panelAssets())
addSnapPoint(ok and type(data) == "table" and data.spots or nil)
Wait.frames(drawEditor, 2)
Wait.time(checkSpot, SPOT_POLL, -1)
end
local spotToken = 0
local function spotSoon()
spotToken = spotToken + 1
local token = spotToken
Wait.time(function() if token == spotToken then checkSpot() end end, 0.5)
end
function onObjectDrop() spotSoon() end
function onObjectPickUp() spotSoon() end
function onObjectDestroy() spotSoon() end
function onRosterInputChanged(player, value, id)
rosterText = value or ""
if rosterText == ROSTER_HINT then rosterText = "" end
end
function onRosterInputDone(player, value, id)
local text = value or rosterText
if text == nil or text == "" or text == ROSTER_HINT then return end
self.UI.setAttribute("rosterInput", "text", "")
self.UI.setAttribute("rosterInput", "text", text)
rosterText = text
end
function onFeedback(player, value, id)
FEEDBACK.open(PANEL, PANEL_H)
end
function confirmImport(player, value, id)
if (rosterText or ""):match("^%s*$") then
printToAll(IMPORT_PREFIX .. "Nothing to import -- paste a roster export first.", { 1, 0.5, 0.1 })
return
end
runImport(rosterText, player)
end
function importRoster(args)
local text = type(args) == "table" and (args.text or args[1]) or args
if type(text) ~= "string" or text:match("^%s*$") then
return { ok = false, error = "importRoster: expected a non-empty roster text" }
end
local applied, extra = runImport(text, nil)
if applied == nil then return { ok = false, error = tostring(extra) } end
return { ok = true, applied = applied, notFound = extra }
end
local historyOpen = false
function onHistory(player, value, id)
historyOpen = not historyOpen
self.UI.setAttribute("historyPopup", "active", historyOpen and "true" or "false")
end
function onHexEdit(player, value, id)
local key = tostring(id or ""):match("^hex_(%a+)$")
local c = MODEL.hexColor(value)
if key and c then edit[key] = c end
editChanged()
end
function onSwatch(player, value, id)
local key, n = tostring(id or ""):match("^pre_(%a+)_(%d+)$")
local hex = key and SWATCHES[key] and SWATCHES[key][tonumber(n) or 0]
if hex then edit[key] = hex; editChanged() end
end
function onTheme(player, value, id)
local th = THEME_PRESETS[tonumber(tostring(id or ""):match("^theme_(%d+)$")) or 0]
if not th then return end
for _, c in ipairs(MODEL.LOOKS_COLORS) do edit[c.key] = th[c.key] end
editChanged()
end
function onFramePreset(player, value, id)
local f = framePresets()[tonumber(tostring(id or ""):match("^frame_(%d+)$")) or 0]
if not f then return end
edit.frame, edit.trim, edit.tint = f.frame, f.trim or "", "yes"
editChanged()
end
function onFrameUrl(player, value, id)
local url = trim(tostring(value or ""))
if url == FRAME_URL_HINT then url = "" end
if url == "" then edit.frame, edit.trim, edit.tint = "none", "", "yes"
else edit.frame, edit.trim, edit.tint = url, "", "no" end
editChanged()
end
local function wholeGang(looks, done, colour)
local gang = currentGang()
if not gang then
printToAll(CHAT_PREFIX .. "No gang yet: import one, or put one of its models on the appearance spot.",
{ 1, 0.7, 0.2 })
return
end
local n = 0
for _, obj in ipairs(cardModels(gang)) do writeLooks(obj, looks); n = n + 1 end
local name = gang
for _, pre in ipairs({ GANG_TAG, OLD_TAGS[1], OLD_TAGS[2] }) do
if name:sub(1, #pre) == pre then name = name:sub(#pre + 1) end
end
printToAll(string.format("[%s] %s on %d model(s) of %s.", name, done, n, name), colour)
end
function onApplyAll(player, value, id)
wholeGang(edit, "This appearance is now", { 0.3, 1, 0.4 })
end
function onResetAll(player, value, id)
wholeGang(nil, "Appearance reset to the default", { 1, 0.7, 0.2 })
end
local CURRENT = {}
function upgradeCards()
local out = {}
local busObjs, busStamps = {}, {}
for _, obj in ipairs(getAllObjects()) do
if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) then
local guid = obj.getGUID()
local seen, same = CURRENT[guid], false
if seen then
local okV, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
same = okV and stamp ~= nil and stamp == seen
end
if not same then
CURRENT[guid] = nil
local ok, script = pcall(function() return obj.getLuaScript() end)
script = ok and tostring(script or "") or ""
if script:find("@@MUNDA_IMPORT@@", 1, true) then
if not cardIsCurrent(script) then
busStamps[#busObjs + 1] = __nqs_mundane_bus.stampOf(obj)
busObjs[#busObjs + 1] = obj
upgradeCard(obj, script)
out[#out + 1] = guid
elseif script:find("MUNDA_STAMP", 1, true) then
local okV, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if okV and stamp ~= nil then CURRENT[guid] = stamp end
end
end
end
end
end
__nqs_mundane_bus.refreshed(busObjs, busStamps)
return out
end
CARD_SCRIPT = [=[
if __nqs_mundane_bus == nil then
__nqs_mundane_bus = { __seq = 0, stamp_guid = true }
function __nqs_mundane_bus.publish(json_string)
for _, obj in ipairs(getObjectsWithTag("gamerecorder")) do
pcall(obj.call, "bus_publish", json_string)
end
end
function __nqs_mundane_bus.nextSeq()
__nqs_mundane_bus.__seq = __nqs_mundane_bus.__seq + 1
return __nqs_mundane_bus.__seq
end
function __nqs_mundane_bus.faceOf(kind, value)
local R, n = __nqs_mundane_bus.rules, tonumber(value)
if type(R) == "table" and n ~= nil then
if kind == "FIREPOWER" and type(R.firepower) == "table" and type(R.firepower[n]) == "table" then
local fp, hits = R.firepower[n], tonumber(R.firepower[n].hits) or 1
local word = hits == 1 and "1 hit" or (tostring(hits) .. " hits")
if fp.ammo then return hits == 1 and "Ammo Check" or (word .. ", Ammo Check") end
return word
elseif kind == "INJURY" and type(R.injuryDice) == "table" and R.injuryDice[n] ~= nil then
local key = R.injuryDice[n]
local res = type(R.injury) == "table" and R.injury[key] or nil
return type(res) == "table" and res.label or tostring(key)
end
end
return tostring(value)
end
function __nqs_mundane_bus.diceArray(faces, kind)
local out = {}
for i, f in ipairs(faces) do
out[i] = { type = kind or "D6", value = f, face = __nqs_mundane_bus.faceOf(kind, f) }
end
return out
end
function __nqs_mundane_bus.emit(event)
event.seq = __nqs_mundane_bus.nextSeq()
event.t = Time.time
if __nqs_mundane_bus.stamp_guid and event.guid == nil then event.guid = self.getGUID() end
__nqs_mundane_bus.publish(JSON.encode(event))
end
end
local MODEL = {
BASE_SIZES = { 25, 28.5, 32, 40, 50, 60 },
BASE_SNAP = 2.5,
MM_PER_INCH = 25.4,
LOOKS_DEFAULT = {
background = "#1D2027",
headers = "#9AA3AE",
text = "#F2F2F2",
accent = "#E8C97A",
edges = "#6B5B33",
frame = "none", trim = "", tint = "yes",
},
LOOKS_COLORS = {
{ key = "background", label = "Background" },
{ key = "headers", label = "Headers" },
{ key = "text", label = "Text" },
{ key = "accent", label = "Accent" },
{ key = "edges", label = "Edges" },
},
LOOKS_KEYS = { "background", "headers", "text", "accent", "edges", "frame", "trim", "tint" },
LOOKS_OPEN = "[Mundane Appearance]",
LOOKS_CLOSE = "[/Mundane Appearance]",
}
do
local MM_PER_INCH = MODEL.MM_PER_INCH
local function trim(s)
s = tostring(s or ""):gsub("^%s+", "")
return (s:gsub("%s+$", ""))
end
function MODEL.baseRecord(mm, source, raw, how, guess)
return { diameter = mm / MM_PER_INCH, mm = mm, source = source,
raw = raw, how = how, guess = guess or nil }
end
function MODEL.footprint(b)
if b == nil then return nil end
local s, k = b.size, 1
if s == nil then s, k = b.extents, 2 end
if s == nil then return nil end
local x, z = tonumber(s.x or s[1]), tonumber(s.z or s[3])
if not (x and z) or x <= 0 or z <= 0 then return nil end
return math.min(x, z) * k
end
function MODEL.measureRaw(obj)
local footprint = MODEL.footprint
local function try(fn)
local ok, v = pcall(fn)
return ok and tonumber(v) or nil
end
local d = try(function() return footprint(obj.getComponent("MeshRenderer").get("bounds")) end)
if d then return d, "renderer" end
d = try(function()
local widest = nil
for _, c in ipairs(obj.getComponents()) do
if tostring(c.name):find("Collider", 1, true) then
local ok, w = pcall(function() return footprint(c.get("bounds")) end)
if ok and w and w > (widest or 0) then widest = w end
end
end
return widest
end)
if d then return d, "collider" end
d = try(function() return footprint(obj.getBoundsNormalized()) end)
or try(function() return footprint(obj.getBounds()) end)
if d then return d, "bounds" end
end
function MODEL.snapBase(mm)
local near, under = nil, nil
for _, s in ipairs(MODEL.BASE_SIZES) do
if not near or math.abs(s - mm) < math.abs(near - mm) then near = s end
if s <= mm and (not under or s > under) then under = s end
end
if not near or math.abs(near - mm) <= MODEL.BASE_SNAP then return near or mm, false end
return under or near, true
end
function MODEL.measureBase(obj)
local d, how = MODEL.measureRaw(obj)
if not d then return nil end
local raw = d * MM_PER_INCH
local mm, guess = MODEL.snapBase(raw)
return MODEL.baseRecord(mm, "measured", math.floor(raw * 10 + 0.5) / 10, how, guess)
end
function MODEL.baseLine(desc)
for raw in (tostring(desc or "") .. "\n"):gmatch("([^\n]*)\n") do
local line = raw:gsub("\r", "")
local bare = line:gsub("%[/?[%w%-]*%]", "")
local n = tonumber(bare:match("^%s*[Bb][Aa][Ss][Ee]%s*:%s*(%d+%.?%d*)%s*[Mm]?[Mm]?%s*$"))
if n and n > 0 then return n, line end
end
end
function MODEL.height(obj)
local okP, p = pcall(function() return obj.getPosition() end)
local y = okP and p and tonumber(p.y or p[2])
if not y then return nil end
local okS, s = pcall(function() return obj.getScale() end)
local sy = math.max(0.01, math.abs(okS and s and tonumber(s.y or s[2]) or 1))
local function up(v)
local ok, n = pcall(function() return tonumber(v.y or v[2]) end)
return ok and n or nil
end
local function topOf(b)
local ok, t = pcall(function()
local c, z, e = up(b.center), up(b.size), up(b.extents)
return up(b.max) or (c and z and c + z / 2) or (c and e and c + e)
end)
return ok and tonumber(t) or nil
end
local best = nil
local function take(b)
local t = topOf(b)
if t and t > y and (not best or t > best) then best = t end
end
for _, get in ipairs({ "getVisualBoundsNormalized", "getBoundsNormalized", "getBounds" }) do
local ok, b = pcall(function() return obj[get]() end)
if ok then take(b) end
end
for _, kind in ipairs({ "MeshRenderer", "SkinnedMeshRenderer" }) do
local ok, list = pcall(function() return obj.getComponentsInChildren(kind) end)
if ok and type(list) == "table" then
for _, c in ipairs(list) do
local okE, on = pcall(function() return c.get("enabled") end)
if not (okE and on == false) then
local okB, b = pcall(function() return c.get("bounds") end)
if okB then take(b) end
end
end
end
end
if best then return (best - y) / sy, best - y end
end
function MODEL.hexColor(v)
local h = tostring(v or ""):match("^%s*#?(%x%x%x%x%x%x)%s*$")
return h and ("#" .. h:upper()) or nil
end
function MODEL.fullLooks(t)
t = type(t) == "table" and t or {}
local out = {}
for _, c in ipairs(MODEL.LOOKS_COLORS) do
out[c.key] = MODEL.hexColor(t[c.key]) or MODEL.LOOKS_DEFAULT[c.key]
end
out.frame = trim(t.frame)
out.trim = trim(t.trim)
out.tint = tostring(t.tint or "yes"):lower():match("^%s*n") and "no" or "yes"
return out
end
function MODEL.parseLooks(notes)
local OPEN, CLOSE = MODEL.LOOKS_OPEN, MODEL.LOOKS_CLOSE
notes = tostring(notes or "")
local a = notes:find(OPEN, 1, true)
if not a then return nil end
local b = notes:find(CLOSE, a, true) or #notes + 1
local t = {}
for line in notes:sub(a + #OPEN, b - 1):gmatch("[^\r\n]+") do
local eq = line:find("=", 1, true)
local k = eq and trim(line:sub(1, eq - 1)):lower()
if k and k ~= "" and not k:find("%A") then t[k] = trim(line:sub(eq + 1)) end
end
return t
end
function MODEL.formatLooks(t)
local lines = { MODEL.LOOKS_OPEN }
for _, k in ipairs(MODEL.LOOKS_KEYS) do
lines[#lines + 1] = string.format("%-10s = %s", k, tostring(t[k] or ""))
end
lines[#lines + 1] = MODEL.LOOKS_CLOSE
return table.concat(lines, "\n")
end
function MODEL.notesWithLooks(notes, block)
notes = tostring(notes or "")
local a = notes:find(MODEL.LOOKS_OPEN, 1, true)
if a then
local _, b = notes:find(MODEL.LOOKS_CLOSE, a, true)
notes = (notes:sub(1, a - 1) .. notes:sub((b or #notes) + 1)):gsub("^%s+", ""):gsub("%s+$", "")
end
if not block then return notes end
return notes == "" and block or (notes .. "\n\n" .. block)
end
end
local CFG = {
position = "0 0 -260",
scale = "0.15 0.15 0.15",
headGap = 0.25,
nameArrows = { down = "▼", up = "▲" },
liftStep = 0.1,
liftMax = 5,
billboard = true,
unseatedCopy = false,
standAngle = -60,
faceOffset = 180,
faceSmooth = 0.05,
faceIdle = 0.1,
faceEvery = 0.04,
faceStep = 1,
yaw = 0,
seatDelay = 0.5,
joinDelay = 3,
seatStagger = 0.5,
buildStagger = 0.65,
seatRecheck = 30,
watchSettle = 0.3,
watchEase = 0.6,
watchStep = 5,
snapSettle = 0.15,
watchHint = 5,
lighterXml = true,
timingLog = false,
textDetail = 0.425,
startVisible = true,
visibility = "",
rankSymbols = { leader = "♛", champion = "♚", ganger = "♞", prospect = "♟", brute = "♜" },
rankScale = 0.75,
groupMark = "🗲",
wyrdMark = "⏳",
knockMark = "↔",
seqRule = "-----",
seqStale = 120,
targetName = "[%s]",
targetMulti = "[%d Targets]",
targetIcon = 0.9,
targetGap = 0.3,
targetPoll = 0.25,
targetFill = 1.0,
blastCount = "[%d Targets selected]",
blastOne = "[1 Target selected]",
blastHit = "Blast: Select Targets",
blastScatter = 'Scatter Distance: %d"',
blastMisfire = "MISFIRE!",
smokeShow = 4.5,
twinAsk = "Twin-Linked: Re-roll?",
cloakAsk = "Did the target move?",
jumpAsk = "Activate Jump Booster?",
jumpDownAsk = "Jumping down?",
flyAsk = "Flying, continue?",
voidAsk = "Target has Void Soul",
disruptAsk = "Disrupt Power?",
disruptWait = "Awaiting Disruption",
disruptSkip = "Skip",
enrageGap = 3,
coverYes = "✔",
statOrder ={ "M", "I", "T", "Sv", "BS", "WS", "S", "A" },
statOrderHover = { "M", "I", "T", "Sv", "Ld", "Wil", "Int", "Cl" },
artRetry = 1.5,
popupLinger = 0.25,
tabLinger = 1,
diceShow = 4.5,
unstableShow = 1.5,
diceLeave = 1,
diceWait = 45,
diceJoin = 1,
diceArea = 3,
diceGap = 0.5,
diceKeep = 6,
diceSpin = 14,
dicePush = 1.5,
infoPrefix = "[Info] ",
statusFlash = 0.5,
weaponFlash = 1.5,
statusGlow = 0.9,
activeMark = 1,
diamondDepth = 1.35,
spendShade = 0.55,
baseDefault = 32,
autoEngage = true,
engageSlack = 0.005,
engageLevel = 1,
engageSettle = 3,
importTag = "Mundane Import",
gangTag = "Mundane Gang_",
oldGangTags = { "Mundane Gang - ", "Mundane Controller_" },
teamTag = "Mundane Team_",
wyrdTag = "Mundane Wyrd Power",
nerveRays = 3,
nerveSpread = 0.35,
controllerTag = "Mundane Controller",
}
local COL, looks, trimText, applyLooks
do
COL = {
frame = "#14161Af2",
frameTrim = "#B08C40ff",
diamond = "#20242Bff",
ready = "#62F384ff",
iconText = "#E8C97Aff",
statusInk = "#15171Bff",
hover = "#FFFFFF33",
press = "#FFFFFF55",
clear = "#00000000",
hpFull = "#C0392Bff",
hpEmpty = "#4B515Cff",
hpHover = "#E05A4Bff",
hpOut = "#FF5A1Fff",
hpBack = "#000000ff",
label = "#9AA3AE",
value = "#F2F2F2",
valueMod = "#F0916E",
valueUp = "#6EE07A",
valueBoth = "#F2D24B",
valueUser = "#7FD6FF",
valuePending = "#E9A6FF",
statPlate = "#0C0E12f2",
accent = "#E8C97A",
nameShadow = "#000000FF",
popupBg = "#0C0E12f2",
popupHead = "#8A93A0",
popupText = "#EDEDED",
popupTraits = "#B9A46A",
profileFill = "#171A20ff",
profileEdge = "#6B5B33",
profileOut = "#5A2E96ff",
profileJam = "#8A2020ff",
ammoOut = "#B48CF0",
ammoJam = "#E06B6B",
ammoSpent = "#E06B6B",
ammoCombi = "#F2D24B",
wyrdInk = "#B47AFF",
traitOn = "#4CFF6A",
traitUsed = "#FF4A4A",
itemSpent = "#5C6168",
ammoSpared = "#7CC8FF",
marksman = "#7CC8FF",
weaponBlocked = "#E35049ff",
actionBg = "#262B35ff",
toggleOff = "#1D2027ff",
toggleOn = "#6B5B33ff",
toggleTextOff = "#FFFFFFff",
toggleTextOn = "#FFFFFFff",
ammoFine = "#9AA3AE",
iconPlate = "#2B303Bff",
actMovement = "#4E3F0Cff",
actClose = "#5A1A1Aff",
actShooting = "#1A2C52ff",
actUtility = "#12494Aff",
actWyrd = "#4A2A6Eff",
actCost = "#FFFFFFff",
actDimInk = "#80868Fff",
badge = "#0C0E12e6",
dicePanel = "#000000ff",
skillBack = "#262A31ff",
diceFace = "#1D2027ff",
diceInk = "#E8C97A",
diceFire = "#4A1616ff",
diceFireInk = "#F2EAD8",
diceAmmo = "#FF8C3A",
diceUnstable = "#F2C230ff",
diceUnstableInk = "#1F5BFF",
diceHurt = "#141416ff",
diceInjured = "#F2D24B",
diceSerious = "#FF8C3A",
diceOut = "#FF4040",
diceShock = "#6FC3FF",
diceKnock = "#EDE6D6",
dicePrecise = "#B58CFF",
diceRend = "#3DE3E8",
diceShred = "#FF6EC7",
diceConc = "#4A78D8",
diceBlaze = "#FFD54A",
diceBreach = "#3B5BFF",
diceWasted = "#C9B037",
diceTagInk = "#141210",
}
local LOOKS_SHADES = {
frame = "background", diamond = "background", popupBg = "background",
profileFill = "background", actionBg = "background", toggleOff = "background",
iconPlate = "background", badge = "background", statPlate = "background",
diceFace = "background",
label = "headers", popupHead = "headers", ammoFine = "headers", actDimInk = "headers",
value = "text", popupText = "text", toggleTextOff = "text", toggleTextOn = "text",
actCost = "text",
accent = "accent", iconText = "accent", popupTraits = "accent", diceInk = "accent",
profileEdge = "edges", toggleOn = "edges", frameTrim = "edges",
}
looks = {}
for k, v in pairs(MODEL.LOOKS_DEFAULT) do looks[k] = v end
function trimText(s)
s = tostring(s or ""):gsub("^%s+", "")
return (s:gsub("%s+$", ""))
end
do
local COL_BASE = {}
for k, v in pairs(COL) do COL_BASE[k] = v end
function applyLooks(t)
for k, v in pairs(MODEL.fullLooks(t)) do looks[k] = v end
local function ch(hex, i) return tonumber(hex:sub(i, i + 1), 16) end
for key, base in pairs(LOOKS_SHADES) do
local from, to, c = MODEL.LOOKS_DEFAULT[base], looks[base], COL_BASE[key]
local out = "#"
for i = 2, 6, 2 do
out = out .. string.format("%02X", math.max(0, math.min(255, ch(c, i) + ch(to, i) - ch(from, i))))
end
COL[key] = out .. c:sub(8, 9)
end
end
end
end
local ASSETS = {
diamond = "https://steamusercontent-a.akamaihd.net/ugc/16547195976271425103/49D2C958CA710AA5E444E2D02E739373CA6CFED6/",
edge_line = "https://steamusercontent-a.akamaihd.net/ugc/13432909356284909624/B129FFCF81BACF983676DFEE7F7E71473280818C/",
diamond_frame = "https://steamusercontent-a.akamaihd.net/ugc/14782607483565015523/5A66DA23DFB6BD38FFD1692D8E5F435717D1134D/",
action_bg = "",
stat_die = "https://steamusercontent-a.akamaihd.net/ugc/12001738551517573707/F2E806437431BEE65DD78832C9C5A286D327A301/",
active_mark = "https://steamusercontent-a.akamaihd.net/ugc/9281115089520461063/F53E226583EE872913D80FBF0C8F7B4628221C57/",
target_mark = "https://steamusercontent-a.akamaihd.net/ugc/17880169358078946793/330D69EC1DDBF1DC38A417466667044005079BEC/",
status_glow = "https://steamusercontent-a.akamaihd.net/ugc/11856102754185019043/36BA8FF309C1B7B07526BA0D1184035FE72C620D/",
hp_segment = "https://steamusercontent-a.akamaihd.net/ugc/11541277657115134292/5B419CCE6C18B70D7A5D406D2000B5EFD8783580/",
status_active = "",
status_suppressed = "",
status_engaged = "",
status_seriously_injured = "",
cond_intoxicated = "https://steamusercontent-a.akamaihd.net/ugc/12427786278172164376/AA173745B2A38A177D61660DBFAB78228C24D88F/",
cond_radphage = "https://steamusercontent-a.akamaihd.net/ugc/11283545823330145507/00AF00B8C681D41AC21C1645D4D3333C3FF324E6/",
cond_concussion = "https://steamusercontent-a.akamaihd.net/ugc/16460778255637512568/815E86C426D99F2AB9A3A39FBE9F7ED67EEDAD7C/",
cond_shackled = "https://steamusercontent-a.akamaihd.net/ugc/11680554426613227028/7641F82C42A1B8070CF6A1C2303284BD63E885D0/",
cond_webbed = "https://steamusercontent-a.akamaihd.net/ugc/9237916920720992997/255FB43CED5FBECDDD141DA6FBB6A52362F8E38A/",
cond_insanity = "https://steamusercontent-a.akamaihd.net/ugc/14280399364781883923/6F84C7AC372740F5B30A9BFA4F1BFD60823CEA8D/",
cond_blind = "https://steamusercontent-a.akamaihd.net/ugc/12149855709979826673/013CB13F42E3144D863E36F64AB61D890D240B70/",
cond_feared = "https://steamusercontent-a.akamaihd.net/ugc/11151711576388475026/5CF74011F69D348EC17DDE57B18E82F26501266F/",
cond_maintaining_power = "https://steamusercontent-a.akamaihd.net/ugc/13568058608364494798/6E01547915A468E0DF55AE722FF1DECC72111E24/",
cond_special = "https://steamusercontent-a.akamaihd.net/ugc/16116723763441808920/A54859B6D2FA77FE9B9B61FFF8C7F91B8E6B5C28/",
cond_frenzy = "https://steamusercontent-a.akamaihd.net/ugc/18439163337286278787/F21DA356144992D2E4AF78DA6747BC234955AE92/",
cond_fearsome = "https://steamusercontent-a.akamaihd.net/ugc/18299705223356920427/C7B3F095D440FF3D5B1985EADB7DAB3BDA7EE8A1/",
menu_actions = "",
menu_conditions = "",
wpn_gun = "",
wpn_heavy = "",
wpn_sidearm = "",
wpn_melee = "",
wpn_melee_heavy = "",
wpn_grenade = "",
type_wyrd = "",
type_loner = "",
type_medic = "",
type_tech = "",
type_melee = "",
type_ranged = "",
type_beast = "",
dice_half = "https://steamusercontent-a.akamaihd.net/ugc/10983465679628948206/E524B4434A8F8B44E4893AC7E14879EAE1E846B1/",
dice_ammo = "https://steamusercontent-a.akamaihd.net/ugc/11665480591323161820/4F28BC74E0066C560A47499AB8AA53F03DE6EA92/",
dice_injured = "https://steamusercontent-a.akamaihd.net/ugc/17020447175444252033/0056BCF18973FB6173680CDE23D66B3B77A6330A/",
dice_serious = "https://steamusercontent-a.akamaihd.net/ugc/10099668034452400088/BB4C08CA9320F632D2C594299F3E9F7D0D2ED658/",
dice_out = "https://steamusercontent-a.akamaihd.net/ugc/17529322079219295649/569C26E282F3EE462E95EDF52DE2058C62063133/",
}
local RULES = {}
if __nqs_mundane_bus ~= nil then __nqs_mundane_bus.rules = RULES end
RULES.actionTypes = {
movement = "actMovement",
close = "actClose",
shooting = "actShooting",
utility = "actUtility",
wyrd = "actWyrd",
}
RULES.actions = {
{ key = "move", label = "Move", cost = "S", type = "movement", desc = "",
distance = { { "M", 1 } } },
{ key = "dash", label = "Dash", cost = "D", type = "movement", desc = "",
distance = { { "M", 1 }, { "I", 1 } } },
{ key = "engage", label = "Engage", cost = "S", type = "close", desc = "",
distance = { { "D6", 1 } } },
{ key = "charge", label = "Charge", cost = "D", type = "close", desc = "",
distance = { { "M", 1 }, { "D6", 1 } } },
{ key = "coup_de_grace", label = "Coup de Grace", cost = "S", type = "close", desc = "" },
{ key = "interact", label = "Interact", cost = "S", type = "utility", desc = "" },
{ key = "shoot", label = "Shoot", cost = "S", type = "shooting", desc = "" },
{ key = "braced_shot", label = "Braced Shot", cost = "D", type = "shooting", desc = "" },
{ key = "aimed_shot", label = "Aimed Shot", cost = "D", type = "shooting", desc = "" },
{ key = "reload", label = "Reload", cost = "S", type = "shooting", desc = "" },
{ key = "treat_ally", label = "Treat Ally", cost = "S", type = "utility", desc = "" },
{ key = "group_activation", label = "Group Activation", cost = "S", type = "utility", desc = "" },
{ key = "fight", label = "Fight", cost = "D", type = "close", desc = "" },
{ key = "retreat", label = "Retreat", cost = "D", type = "movement", desc = "",
distance = { { "I", 1 } } },
{ key = "crawl", label = "Crawl", cost = "D", type = "movement", desc = "",
distance = { { "S", 1 } } },
{ key = "desperate_escape", label = "Desperate Escape", cost = "D", type = "movement", desc = "",
escape = 3 },
{ key = "tend_wounds", label = "Tend Wounds", cost = "D", type = "utility", desc = "" },
{ key = "recovery_test", label = "Recovery Test", cost = "RT", type = "utility", always = true, desc = "" },
{ key = "maintain_control_f", label = "Maintain Control", cost = "F", type = "wyrd", wyrd = true, desc = "" },
{ key = "maintain_control_s", label = "Maintain Control", cost = "S", type = "wyrd", wyrd = true, desc = "" },
{ key = "concentrate", label = "Concentrate", cost = "S", type = "wyrd", wyrd = true, desc = "" },
}
RULES.statusActions = {
active = {
left = { "move", "dash", "engage", "charge", "coup_de_grace", "interact" },
right = { "shoot", "braced_shot", "aimed_shot", "reload", "treat_ally", "group_activation" },
},
suppressed = {
left = { "move", "engage", "coup_de_grace", "interact" },
right = { "shoot", "reload", "treat_ally", "group_activation" },
},
engaged = {
right = { "fight", "retreat" },
},
seriously_injured = {
right = { "crawl", "desperate_escape", "tend_wounds", "recovery_test" },
},
}
RULES.conditions = {
{ key = "intoxicated", label = "Intoxicated", short = "ITX", desc = "" },
{ key = "radphage", label = "Radphage", short = "RAD", desc = "",
mods = { T = -1 } },
{ key = "concussion", label = "Concussion", short = "CON", desc = "", stacks = true,
mods = { I = -1 } },
{ key = "shackled", label = "Shackled", short = "SHK", desc = "" },
{ key = "webbed", label = "Webbed", short = "WEB", desc = "" },
{ key = "insanity", label = "Insanity", short = "INS", desc = "" },
{ key = "blind", label = "Blind", short = "BLD", desc = "",
set = { WS = 6 }, hitOnly = { melee = 6 } },
{ key = "feared", label = "Feared", short = "FEA", desc = "",
set = { WS = 6 } },
{ key = "maintaining_power", label = "Maintaining Power", short = "PWR", desc = "" },
{ key = "special", label = "Special", short = "SPC", desc = "" },
{ key = "frenzy", label = "Frenzy", short = "FRZ", desc = "", auto = true,
mods = { A = 1 } },
{ key = "fearsome", label = "Fearsome", short = "FSM", desc = "", auto = true },
}
RULES.skills = {
{ name = "Counter-Attack", desc = "", counterAttack = true },
{ name = "Inspiring", desc = "", costs = { group_activation = "F" } },
{ name = "Juggernaut", desc = "", juggernaut = true },
{ name = "Fast Reload", desc = "", fastReload = true },
{ name = "Iron Will", desc = "", ironWill = 1 },
{ name = "Medicate", desc = "", action = "S", type = "utility", label = "Heal Ally", heal = 1,
statuses = { "active", "suppressed" } },
{ name = "Munitioneer", desc = "", action = "S", type = "utility",
label = "Distribute Ammo", distribute = 6, statuses = { "active", "suppressed" } },
{ name = "Catfall", desc = "", catfall = true },
{ name = "Dodge", desc = "", dodge = 6 },
{ name = "Spring Up", desc = "", springUp = true },
{ name = "Sprint", desc = "", action = "D", type = "movement", statuses = { "active" },
distance = { { "M", 1 }, { "I", 2 } } },
{ name = "Bull Charge", desc = "", bullCharge = true },
{ name = "Bulging Biceps", desc = "", biceps = true },
{ name = "Berserker", desc = "", condition = "frenzy" },
{ name = "Combat Master", desc = "", master = true },
{ name = "Headbutt", desc = "", weapon = { name = "Headbutt", profiles = {
{ SR = "E", LR = "-", S = "S+1", AP = "-", L = "1", traits = "Additional Attack (1), Melee" } } } },
{ name = "Heavy Blows", desc = "", meleeS = { heavy = 1 } },
{ name = "Rain Of Blows", desc = "", rainOfBlows = true },
{ name = "Two-Weapon Fighter", desc = "", secondary = 2 },
{ name = "Fearsome", desc = "", condition = "fearsome" },
{ name = "Iron Jaw", desc = "", ironJaw = 2 },
{ name = "Nerves Of Steel", desc = "", steel = true },
{ name = "Unstoppable", desc = "", unstoppable = true },
{ name = "Backstab", desc = "", backstab = true },
{ name = "Cut-Throat", desc = "", cutThroat = true },
{ name = "Lie Low", desc = "", lieLow = true },
{ name = "Fast Shot", desc = "", shoots = 2 },
{ name = "Gunfighter", desc = "", gunfighter = true },
{ name = "Hip-Shooting", desc = "", hipShooting = true },
{ name = "Marksman", desc = "", marksman = 1 },
{ name = "Sharpshooter", desc = "", aimed = 2 },
{ name = "Precision Shot", desc = "", precise = true },
{ name = "Force Blast", desc = "", action = "F/C", type = "wyrd",
weapon = { name = "Force Blast", profiles = {
{ SR = '8"', LR = '12"', S = "2", AP = "-1", L = "1", traits = "Knockback (3+)" } } } },
{ name = "Flaming Weapon", desc = "", action = "F/C", type = "wyrd", flaming = "Blaze (5+)" },
{ name = "Freeze Time", desc = "", action = "D", type = "wyrd",
area = { range = 12, side = "all", oneAction = true } },
{ name = "Weapon Jinx", desc = "", action = "S", type = "wyrd" },
{ name = "Terrify", desc = "", action = "D", type = "wyrd",
target = { range = 18, suppress = true, test = "Cl", ifReady = true, fail = "unready" } },
{ name = "Quickening", desc = "", action = "S/C", type = "wyrd",
maintained = { M = 3, I = 2 }, overLimit = true },
{ name = "Hypnosis", desc = "", action = "S", type = "wyrd" },
{ name = "Unbreakable Will", desc = "", action = "F/C", type = "wyrd",
aura = { range = 9, side = "friends", lend = { "Wil", "Cl" } } },
{ name = "Zealot", desc = "", action = "S/C", type = "wyrd" },
{ name = "Mind Control", desc = "", action = "S", type = "wyrd" },
{ name = "Assail", desc = "", action = "S", type = "wyrd",
target = { roll = "BS", suppress = true } },
{ name = "Force Wave", desc = "", action = "S", type = "wyrd" },
{ name = "Catalyst", desc = "", action = "F/C", type = "wyrd" },
{ name = "Hypnotic Gaze", desc = "", action = "D", type = "wyrd",
target = { range = 9, needReady = true, test = "agility", fail = "unready" } },
{ name = "The Horror", desc = "", action = "S", type = "wyrd",
target = { range = 12, test = "nerve" } },
{ name = "Leech Essence", desc = "", action = "S", type = "wyrd",
target = { range = 12, hit = { S = 3, AP = -1, L = 1 } } },
{ name = "Paroxysm", desc = "", action = "S/C", type = "wyrd",
target = { range = 9, base = { BS = 6, WS = 6 } } },
{ name = "Aura Of Despair", desc = "", action = "F/C", type = "wyrd",
aura = { side = "enemies", mods = { Cl = -1 } } },
{ name = "Hallucinations", desc = "", action = "S", type = "wyrd",
target = { range = 12, test = "Wil", fail = "insanity" } },
{ name = "Crush", desc = "", action = "F", type = "wyrd" },
{ name = "Force Field", desc = "", action = "S/C", type = "wyrd" },
{ name = "Terrible Truths", desc = "", action = "S", type = "wyrd",
target = { range = 6, test = "Wil", fail = "insanity" } },
{ name = "Psychotic Lure", desc = "", action = "S", type = "wyrd" },
{ name = "Deceitful Thoughts", desc = "", action = "D", type = "wyrd",
target = { range = 6, test = "Wil" } },
{ name = "Cacophony Of Silence", desc = "", action = "S/C", type = "wyrd", rerollHits = true },
{ name = "A Perfect Void", desc = "", action = "F/C", type = "wyrd", void = 10 },
{ name = "Eternal Slumber", desc = "", action = "S", type = "wyrd",
target = { range = 3, needStatus = "seriously_injured", out = true } },
{ name = "Scouring", desc = "", action = "F/C", type = "wyrd",
weapon = { name = "Scouring", profiles = {
{ SR = "T", LR = "-", S = "2", AP = "-", L = "1", traits = "Blaze (5+), Template" } } } },
{ name = "Levitation", desc = "", action = "F/C", type = "wyrd", maintained = { M = 3 } },
{ name = "Warp Strength", desc = "", action = "F/C", type = "wyrd", maintained = { S = 2 }, meleeL = 1 },
{ name = "Warp Shield", desc = "", action = "S", type = "wyrd",
area = { range = 3, side = "friends", self = true, mods = { Sv = -1 } } },
{ name = "Maddening Visions", desc = "", action = "S", type = "wyrd",
visions = { range = 3, condition = "insanity" } },
}
RULES.wargear = {
{ name = "Bio-Booster", desc = "", aka = { "Bio Booster", "Biobooster" },
bioBooster = 1, burns = true },
{ name = "Bomb Delivery Rats", desc = "" },
{ name = "Cult Icon", desc = "", groupReroll = true },
{ name = "Carapace Armour - Heavy", desc = "", aka = { "Heavy Carapace Armour", "Heavy Carapace", "Carapace Armour (Heavy)" },
agility = -1 },
{ name = "Chaos Familiar", desc = "" },
{ name = "Dirt Bike", desc = "" },
{ name = "Drop Rig", desc = "", action = "S", type = "utility", label = "Descend",
lines = { '3" horizontally', '12" vertically' } },
{ name = "Grapnel Launcher", desc = "", action = "D", type = "utility", label = "Grapnel",
lines = { '12" straight', "end on higher level" } },
{ name = "Grav Chute", desc = "", noFall = true },
{ name = "Hazard Suit", desc = "", immune = { "blaze", "radphage" } },
{ name = "Medicae Kit", desc = "", assist = 1 },
{ name = "Mesh Armour", desc = "", aka = { "Mesh Armor" },
mods = { Sv = -1 }, when = "engaged" },
{ name = "Reflec Shroud", desc = "", noAp = { "Las", "Plasma", "Melta" } },
{ name = "Photo-Goggles", desc = "", aka = { "Photo Goggles" }, flashMod = -2 },
{ name = "Refractor Field", desc = "", aka = { "Refractor Shield" }, inv = 5, burns = true },
{ name = "Respirator", desc = "", gasInv = 5 },
{ name = "Stimm-Slug Stash", desc = "", aka = { "Stim-Slug Stash" },
action = "F", type = "utility", label = "Stimm-Slug", once = true,
boost = { M = 2, S = 2, T = 2 }, reaction = { roll = 1, wounds = 1 } },
{ name = "Seven-Pointed Breastplate", desc = "" },
{ name = "Conduit Of Ozostium", desc = "", wyrdPower = "Force Blast" },
{ name = "Gloves Of Ozostium", desc = "", wyrdPower = "Flaming Weapon" },
{ name = "Seven-Pointed Talisman", desc = "", mods = { Cl = 1 },
aura = { range = 6, side = "all", mods = { Cl = 1 } } },
{ name = "Void Soul", desc = "", voidSoul = true },
{ name = "Extra Appendage", desc = "" },
{ name = "Horrific Appearance", desc = "", condition = "fearsome" },
{ name = "Massive Claws", desc = "" },
{ name = "Needle Spines", desc = "", mods = { Sv = -1 }, when = "engaged",
action = "S", type = "utility", label = "Fire Spines", once = true, spends = true,
statuses = { "active", "suppressed" },
burst = { range = 3, profile = { S = "-", AP = "-", L = "1", traits = "Toxin (3+)" } } },
{ name = "Tentacles", desc = "", agilityReroll = "all" },
{ name = "Toxic Blood", desc = "",
toxicBlood = { range = 1, profile = { S = "-", AP = "-", L = "1", traits = "Toxin (3+)" } } },
{ name = "Wing Membranes", desc = "", jumpDown = true },
{ name = "Exo Suit", desc = "", aka = { "Exo-Suit" }, immune = { "blaze", "radphage" } },
{ name = "Book Of The Redemption", desc = "" },
{ name = "Pyromantic Mantle", desc = "", activeMelee = "Blaze (5+)" },
{ name = "Psychomancer's Harness", desc = "", aka = { "Psychomancers Harness" } },
{ name = "Jump Booster", desc = "", aka = { "Jump-Booster" },
booster = { mods = { M = 3 }, flying = true, charge = { hit = 1, S = 1 }, unstable = true } },
{ name = "Augurspex", desc = "" },
{ name = "Refraction Cloak", desc = "", refraction = { moved = -1, still = -2 } },
{ name = "Servo-Medicae", desc = "", aka = { "Servo Medicae" },
action = "F", type = "utility", label = "Auto-Medicate", check = "Int", heal = 1,
statuses = { "active", "suppressed" } },
{ name = "Vox Array", desc = "", costs = { group_activation = "F" } },
{ name = "Magnacles", desc = "", action = "D", type = "close", label = "Restrain",
statuses = { "engaged" }, restrain = { test = "agility", fail = "webbed", freeBy = "S" } },
{ name = "Corpse Grinder Cult Icon", desc = "", action = "S", type = "utility", label = "Enrage",
statuses = { "active" },
enrage = { range = 6, dice = 3, stat = "M", needReady = true, needStatus = "active" } },
}
RULES.accessories = {
{ name = "Focusing Crystal" },
{ name = "Hotshot Las Pack" },
{ name = "Infra-Sight" },
{ name = "Las-Projector", coverShort = -1 },
{ name = "Mono-Sight", aimed = 2 },
{ name = "Suspensors" },
{ name = "Telescopic Sight", coverLong = -1 },
}
RULES.statRolls = {
I = { dice = 1, under = true },
T = { dice = 1, under = true },
S = { dice = 1, under = true },
Ld = { dice = 2, under = true },
Wil = { dice = 2, under = true },
Int = { dice = 2, under = true },
Cl = { dice = 2, under = true },
BS = { dice = 1, under = false },
WS = { dice = 1, under = false },
Sv = { dice = 1, under = false },
}
RULES.limits = {
M = { 1, 12 },
WS = { 2, 6 }, BS = { 2, 6 }, Sv = { 3, 6 },
S = { 1, 10 }, T = { 1, 10 }, I = { 1, 10 }, A = { 1, 10 },
Ld = { 4, 10 }, Cl = { 4, 10 }, Wil = { 4, 10 }, Int = { 4, 10 },
default = { 1, 10 },
}
RULES.traits = {
melee = "melee",
smoke = "smoke",
unstable = "unstable",
unwieldy = "unwieldy",
light = "light",
rapidFire = "rapid fire%s*%(%s*%d%+?%s*%)",
paired = "paired",
additional = "additional attacks?",
backstab = "backstab",
combi = "combi",
limited = "limited",
singleShot = "single shot",
shield = "shield",
parry = "parry",
reliable = "reliable",
ammo = "ammo",
scarce = "scarce",
heavy = "heavy",
assault = "assault",
toxin = "toxin",
shock = "shock",
knockback = "knockback",
blast = "blast[^,]*",
cursed = "cursed",
flash = "flash",
graviton = "graviton pulse",
lance = "lance",
lanceBomb = "lance%-bomb",
template = "template",
drag = "drag",
twinLinked = "twin%-linked",
blaze = "blaze",
damage = "damage",
rending = "rending",
breaching = "breaching",
shred = "shred",
concussive = "concussive",
gas = "gas",
web = "web",
radphage = "rad%-?phage",
}
RULES.injuryDice = { "injured", "injured", "serious", "serious", "serious", "out" }
RULES.injury = {
out = { label = "Out of Action", rank = 1, short = "OOA" },
serious = { label = "Serious Injury", rank = 2, short = "S. Inj" },
injured = { label = "Injury", rank = 3, short = "Inj" },
}
RULES.firepower = { { hits = 1, ammo = true }, { hits = 1 }, { hits = 1 }, { hits = 2 }, { hits = 2 }, { hits = 3 } }
RULES.cfg = {
engageRange = 1,
nerveRanges = { leader = 12, champion = 6 },
nerveOutRange = 3,
nerveOutNone = { "pet" },
nerveOutFoes = false,
groupRange = 3,
preMeasure = false,
agility = 4,
escherGang = { type = "House Escher", agility = "ones",
unless = { "Chaos Corrupted", "Genestealer Corrupted", "Genestealer Infected",
"Malstrain Corrupted" },
variants = { { type = "Wyld Hunt", agility = "all" },
{ type = "Chymist Cult", toxinShred = 6 } } },
coupGang = { type = "Genestealer Cults", mod = 1 },
corrupted = { "Chaos Corrupted", "Genestealer Corrupted", "Genestealer Infected", "Malstrain Corrupted" },
noGangRule = { "hanger-on" },
delaqueGang = { type = "House Delaque", range = 3, friends = 2, mods = { Ld = 1, Wil = 1 } },
goliathGang = { type = "House Goliath", charge = { S = 1 } },
palaniteGang = { type = "Palanite Enforcers", costs = { group_activation = "F" }, status = "active" },
outcastGang = { type = "Outcasts", range = 6, nerve = true, fearsome = true },
readyMarks = { spyrer = 2 },
extraArm = { rule = "Extra Arm", cost = "S" },
fixedMove = { "mounted" },
fallSave = 3,
fallLevels = { 3, 6 },
disruptRange = 18,
disruptMod = -2,
concentrateMod = 1,
maintainMod = 3,
powersLastNext = false,
shockNatural = false,
knockback = 1,
rapidOneHit = false,
unstableAll = true,
saveFails = 2,
coverShort = 1,
coverLong = 2,
coverTemplate = 1,
dicePause = 3,
performanceMode = false,
performanceFor = {},
qualityFor = {},
handWeapon = { light = true, name = "Hand Weapon", profiles = {
{ SR = "E", LR = "-", S = "S", AP = "-", L = "1", traits = "Melee" } } },
}
RULES.PARTS = {
actionTypes = "map", actions = "key", statusActions = "map", conditions = "key",
skills = "name", wargear = "name", statRolls = "map", limits = "map",
traits = "map", injury = "map", injuryDice = "list", firepower = "list",
cfg = "values", accessories = "name",
}
function RULES.copy(v)
if type(v) ~= "table" then return v end
local t = {}
for k, x in pairs(v) do t[k] = RULES.copy(x) end
return t
end
function RULES.same(a, b)
if type(a) ~= "table" or type(b) ~= "table" then return a == b end
for k, v in pairs(a) do if not RULES.same(v, b[k]) then return false end end
for k in pairs(b) do if a[k] == nil then return false end end
return true
end
function RULES.isList(t) return t[1] ~= nil or next(t) == nil end
function RULES.lay(into, over)
for k, v in pairs(over) do
if v == false then into[k] = nil else into[k] = RULES.copy(v) end
end
return into
end
function RULES.id(kind, e)
if type(e) ~= "table" then return nil end
if kind == "name" then return e.name ~= nil and tostring(e.name):lower() or nil end
return e.key
end
function RULES.merge(over)
local out = RULES.copy(RULES.DEFAULT)
if type(over) ~= "table" then return out end
for part, kind in pairs(RULES.PARTS) do
local o, t = over[part], out[part]
if type(o) ~= "table" then
elseif kind == "list" then
out[part] = RULES.copy(o)
elseif kind == "map" or kind == "values" then
for k, v in pairs(o) do
if kind == "values" and t[k] == nil then
elseif v == false and kind == "map" then
t[k] = nil
elseif type(v) == "table" and type(t[k]) == "table" and not RULES.isList(v)
and not RULES.isList(t[k]) then
RULES.lay(t[k], v)
else
t[k] = RULES.copy(v)
end
end
else
for _, e in ipairs(o) do
local id = RULES.id(kind, e)
local at = nil
for i, x in ipairs(id ~= nil and t or {}) do
if RULES.id(kind, x) == id then at = i break end
end
if id == nil then
elseif e.disabled then
if at then table.remove(t, at) end
else
local entry = RULES.lay((at and not e.replace) and t[at] or {}, e)
entry.replace, entry.disabled = nil, nil
t[at or #t + 1] = entry
end
end
end
end
return out
end
RULES.followers = {}
function RULES.follow(fn)
RULES.followers[#RULES.followers + 1] = fn
fn()
end
function RULES.use(over)
local merged, changed = RULES.merge(over), false
for part in pairs(RULES.PARTS) do
local live = RULES[part]
if not RULES.same(live, merged[part]) then
for k in pairs(live) do live[k] = nil end
for k, v in pairs(merged[part]) do live[k] = v end
changed = true
end
end
if changed then
for _, fn in ipairs(RULES.followers) do fn() end
end
return changed
end
RULES.DEFAULT = {}
for part in pairs(RULES.PARTS) do RULES.DEFAULT[part] = RULES.copy(RULES[part]) end
local STATUSES = {
{ key = "active", label = "Active", short = "ACT", color = "#5CD65C" },
{ key = "suppressed", label = "Suppressed", short = "SUP", color = "#7CC8FF" },
{ key = "engaged", label = "Engaged", short = "ENG", color = "#FFB366" },
{ key = "seriously_injured", label = "Seriously Injured", short = "S.I.", color = "#FF4040" },
}
local ACTION_TYPES = {}
RULES.follow(function()
for k in pairs(ACTION_TYPES) do ACTION_TYPES[k] = nil end
for k, v in pairs(RULES.actionTypes) do ACTION_TYPES[k] = COL[v] or v end
end)
local ACTIONS, STATUS_ACTIONS = RULES.actions, RULES.statusActions
RULES.follow(function() for k, v in pairs(RULES.cfg) do CFG[k] = v end end)
local ACTIVATION = {
INJURY_DICE = RULES.injuryDice,
INJURY = RULES.injury,
FIREPOWER = RULES.firepower,
MAX_DICE = 6,
MAX_SHOWN = 10,
FALL_MAX = 24,
}
local CONDITIONS, SKILLS, WARGEAR = RULES.conditions, RULES.skills, RULES.wargear
local SKILL = {}
local PROFILE_COLS = {
{ key = "Hit", fit = "+0" },
{ key = "SR", fit = '24"' },
{ key = "LR", fit = '48"' },
{ key = "S", fit = "S+2" },
{ key = "AP", fit = "-2" },
{ key = "L", fit = "10" },
{ key = "D", fit = "D3" },
{ key = "Am", fit = "6+" },
}
local STAT_ROLLS = RULES.statRolls
local STAT = {
LIMITS = RULES.limits,
NAMES = {
M = "Movement", WS = "Weapon Skill", BS = "Ballistic Skill", S = "Strength", T = "Toughness",
W = "Wounds", I = "Initiative", A = "Attacks", Ld = "Leadership", Cl = "Cool",
Wil = "Willpower", Int = "Intelligence", Sv = "Save", Inv = "Invulnerable Save",
},
}
local PROFILE_MODES = {
{ key = "attack", short = "ATK" },
{ key = "rapid_fire", short = "RF" },
}
local LAY = {
cardW = 1240, cardH = 340,
frameW = 1240, frameX = 0, frameY = 0, frameTall = 4,
glowPad = 61,
activeGap = 44, activeReach = 0.82, activeLine = 22,
activeEcho = 34, activeEchoLine = 0.55,
frameArt = 1.25,
statusD = 150,
sideD = 120,
readySplit = 6,
sideX = 370,
iconPad = 0.62,
dieIcon = 0.78,
labelFill = 0.72,
colW = 650,
statGap = 1,
statSignScale = 0.6,
statY = 10, statRowH = 75,
statIconPad = 0.8,
condPad = 4, condGap = 0, condFont = 18, condCountFont = 48, condScale = 1.5,
skillPad = 4, skillScale = 0.85, skillRows = 3, skillLeading = 1.1, skillEven = false,
skillSpace = 1.1, skillMark = 0.24,
skillInfoFont = 26, skillInfoPad = 12,
midTitleFont = 52, midBtnFont = 44, midBtnH = 64, midGap = 16,
midDiamond = 66, midReviveW = 240,
midStatFont = 44,
coverFill = 0.92,
diceD = 136, diceSpace = 12, dicePip = 0.22, diceEdge = 6, diceWaitFont = 44,
diceSumFont = 62, diceSumGap = 20, dicePad = 10,
diceAmmoSize = 1.25, diceAmmoPad = 0.035,
diceTagH = 26, diceTagGap = 4, diceTagSplit = 3, diceTagClear = 3, diceTagPad = 2, diceTagStretch = 1.5,
diceHalf = 0.45,
hpY = 125,
hpH = 81,
hpGap = 0.1,
hpOutW = 7, hpOutFont = 50, hpOutText = "Skills disabled",
compactEdge = 6,
nameFont = 96, nameGap = 10, nameShadow = 0.1, nameOutline = 0.035,
nameArrow = 0.6, nameArrowGap = 16,
labelFont = 50, valueFont = 60, diamondFont = 26,
pop = {
scale = 2,
gap = 0,
pad = 6,
colGap = 16,
headH = 26,
headTop = 3,
headGap = 3,
rowH = 34,
boxGap = 6,
border = 2,
aimEdge = 3,
boxPad = 3,
traitFit = 0.96,
traitPad = 1,
btnW = 62,
iconPad = 0.8,
condIconPad = 1.15,
costPad = 0.7,
entryW = 150,
actionW = 170,
entryGap = 3,
tabH = 24, tabFont = 20,
panelRows = 4,
condRows = 5,
specialRows = 6,
titleFont = 28, headFont = 18, valueFont = 22, traitFont = 17, btnFont = 20,
nameLeading = 0.95,
nameFit = 0.96,
},
}
local function halfDiag(side) return side * math.sqrt(2) / 2 end
LAY.sideY = halfDiag(LAY.sideD)
LAY.statusX = LAY.sideX + halfDiag(LAY.statusD)
LAY.statusRestX = LAY.sideX + halfDiag(LAY.sideD)
LAY.weaponX = LAY.sideX + halfDiag(LAY.sideD)
LAY.glowL = -(LAY.statusRestX + halfDiag(LAY.sideD)) - LAY.glowPad
LAY.glowR = LAY.weaponX + halfDiag(LAY.sideD) + LAY.glowPad
LAY.glowH = 2 * (LAY.sideY + halfDiag(LAY.sideD) + LAY.glowPad)
LAY.activeTip = LAY.weaponX + halfDiag(LAY.sideD) + LAY.activeGap
LAY.activeArm = LAY.activeReach * (LAY.sideY + halfDiag(LAY.sideD))
LAY.activePad = 16
LAY.activeArtL = LAY.activeTip - LAY.activeArm - LAY.activeLine - LAY.activePad
LAY.activeArtR = LAY.activeTip + LAY.activeEcho + LAY.activeLine + LAY.activePad
LAY.activeArtH = 2 * (LAY.activeArm + LAY.activeLine + LAY.activePad)
LAY.skillY = -(LAY.sideY + halfDiag(LAY.sideD) / 2)
LAY.skillBand = halfDiag(LAY.sideD) - 2 * LAY.skillPad
LAY.condD = (halfDiag(LAY.sideD) - 2 * LAY.condPad) * LAY.condScale
LAY.condY = -(LAY.sideY + halfDiag(LAY.sideD) + LAY.condPad + LAY.condD / 2)
LAY.weaponSpots = {
{ x = LAY.weaponX, y = 0 },
{ x = LAY.sideX, y = LAY.sideY },
{ x = LAY.sideX, y = -LAY.sideY },
}
function LAY.weaponSpot(i)
local n = #LAY.weaponSpots
if i <= n then return LAY.weaponSpots[i] end
return { x = LAY.weaponX, y = -2 * halfDiag(LAY.sideD) * (i - n) }
end
LAY.hpW = 2 * LAY.sideX
LAY.nameW = 2 * LAY.sideX
LAY.blockW = 2 * LAY.sideX
LAY.blockH = 2 * (LAY.sideY + halfDiag(LAY.sideD))
LAY.compactDrop = -LAY.blockH / 2 - (LAY.hpY - LAY.hpH / 2 - LAY.compactEdge)
LAY.frameH = LAY.frameW * LAY.frameTall
LAY.popS = {}
for k, v in pairs(LAY.pop) do
local fixed = (k == "scale" or k == "gap" or k == "iconPad" or k == "condIconPad" or k == "costPad" or k == "panelRows"
or k == "specialRows" or k == "condRows"
or k == "nameLeading" or k == "nameFit" or k == "traitFit")
LAY.popS[k] = fixed and v or v * LAY.pop.scale
end
local function defaultFighter()
return {
name = "Unnamed Ganger",
gang = "",
rank = "Ganger",
ftype = "None",
status = "active",
stats = {
M = '4"', WS = "5+", BS = "3+", S = "6", T = "4", W = "3",
I = "5", A = "2", Ld = "7", Cl = "6", Wil = "8", Int = "7",
Sv = "6+",
},
usedActions = {},
actionsLeft = 0,
activation = nil,
startedSI = false,
lostAction = nil,
outOfAction = false,
recovery = nil,
treated = nil,
grouped = nil,
readyMarks = nil,
statEdits = {},
wounds = { current = 3, max = 3 },
base = nil,
lift = nil,
conditions = {},
skills = { "Counter-attack", "Inspiring" },
wargear = {},
weapons = {
{
name = "Autogun",
profiles = {
{ SR = '8"', LR = '24"', S = "3", AP = "-", L = "-", D = "1", Am = "4+",
traits = "Rapid Fire (1)" },
},
},
{
name = "Stub Gun",
profiles = {
{ SR = '6"', LR = '12"', S = "3", AP = "-", L = "1", D = "-", Am = "4+",
traits = "Light" },
{ SR = '6"', LR = '12"', S = "3", AP = "-", L = "1",
D = "-", Am = "-", traits = "Light, Cursed, Limited" },
},
},
{
name = "Stilleto",
profiles = {
{ SR = "E", LR = "-", S = "-", AP = "-1", L = "1",
traits = "Melee, Toxin" },
{ SR = "E", LR = "-", S = "-", AP = "-1", L = "1",
traits = "Melee, Toxin" },
{ SR = "E", LR = "-", S = "-", AP = "-1", L = "1",
traits = "Melee, Toxin" },
{ SR = "E", LR = "-", S = "-", AP = "-1", L = "1",
traits = "Melee, Toxin" },
{ SR = "E", LR = "-", S = "-", AP = "-1", L = "1",
traits = "Melee, Toxin" },
},
},
},
}
end
local fighter = defaultFighter()
local IMPORTED = nil --@@MUNDA_IMPORT@@
local ui = {
visible = CFG.startVisible,
built = false,
viewers = { "all" },
view = {},
rawTexts = {},
}
local function view(key)
local v = ui.view[key]
if not v then
v = { hoverToken = 0, statsHover = false, yaw = CFG.yaw }
ui.view[key] = v
end
return v
end
local function weaponAt(i)
local n = #LAY.weaponSpots
if i <= n then return fighter.weapons[i] end
return (fighter.moreWeapons or {})[i - n]
end
local function weaponCount() return #LAY.weaponSpots + #(fighter.moreWeapons or {}) end
local function esc(s)
s = tostring(s == nil and "" or s)
s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
s = s:gsub('"', "&quot;"):gsub("'", "&apos;")
return s
end
local function clamp(n, lo, hi)
n = tonumber(n) or 0
if n < lo then return lo end
if n > hi then return hi end
return n
end
local function keyValue(a, b)
if type(a) == "table" and b == nil then return a.key, a.value end
return a, b
end
local dynamicAssets = {}
local function hasAsset(name)
if not name or name == "" then return false end
if dynamicAssets[name] and dynamicAssets[name] ~= "" then return true end
return ASSETS[name] ~= nil and ASSETS[name] ~= ""
end
local function imgAttr(name)
if hasAsset(name) then return string.format(' image="%s"', name) end
return ""
end
function ui.resolveIcon(value, autoName)
if type(value) ~= "string" or value == "" then return nil end
if value:match("^https?://") then
dynamicAssets[autoName] = value
return autoName
end
return value
end
function ui.buildAssetList()
local list = {}
for _, source in ipairs({ ASSETS, dynamicAssets }) do
for name, url in pairs(source) do
if type(url) == "string" and url ~= "" then list[#list + 1] = { name = name, url = url } end
end
end
return list
end
local function indexOf(list, key)
for i, e in ipairs(list) do
if e.key == key then return i end
end
end
local function statusDef(key) return STATUSES[indexOf(STATUSES, key) or 1] end
function ui.glowing() return hasAsset("status_glow") and (tonumber(CFG.statusGlow) or 0) > 0 end
function ui.glowColor()
local a = math.floor(clamp(CFG.statusGlow, 0, 1) * 255 + 0.5)
return statusDef(fighter.status).color:sub(1, 7) .. string.format("%02X", a)
end
function ui.activeColor()
local a = math.floor(clamp(tonumber(CFG.activeMark) or 0, 0, 1) * 255 + 0.5)
return statusDef(fighter.status).color:sub(1, 7) .. string.format("%02X", a)
end
function ui.activeShown()
return fighter.activation == "active" and (tonumber(CFG.activeMark) or 0) > 0
end
function ui.activeXml()
local x, n = {}, 0
local function add(fmt, ...)
n = n + 1
x[#x + 1] = string.format(fmt, n, ...)
end
local col = ui.activeColor()
x[#x + 1] = string.format('<Panel id="activeMark" active="%s" rectAlignment="MiddleCenter" width="%d"' ..
' height="%d" color="%s" raycastTarget="false">', tostring(ui.activeShown()), LAY.cardW, LAY.cardH, COL.clear)
for _, side in ipairs({ 1, -1 }) do
if hasAsset("active_mark") then
add('<Image id="activeMark_%d" rectAlignment="MiddleCenter" offsetXY="%g 0" width="%g" height="%g"' ..
' rotation="0 0 %d" color="%s" image="active_mark" raycastTarget="false" />',
side * (LAY.activeArtL + LAY.activeArtR) / 2, LAY.activeArtR - LAY.activeArtL, LAY.activeArtH,
side == 1 and 0 or 180, col)
else
local function chevron(tip, t, ink)
local len = LAY.activeArm * math.sqrt(2) + t / 2
for _, up in ipairs({ 1, -1 }) do
local d = (len / 2 - LAY.activeArm * math.sqrt(2)) / math.sqrt(2)
add('<Panel id="activeMark_%d" rectAlignment="MiddleCenter" offsetXY="%g %g" width="%g"' ..
' height="%g" rotation="0 0 %g" color="%s" raycastTarget="false" />',
side * (tip + d), -up * d, len, t, side * up * -45, ink)
end
end
chevron(LAY.activeTip, LAY.activeLine, col)
if LAY.activeEcho > 0 then
chevron(LAY.activeTip + LAY.activeEcho, LAY.activeLine * LAY.activeEchoLine, col)
end
end
end
x[#x + 1] = "</Panel>"
ui.activeParts = n
return table.concat(x)
end
local function rgbOf(hex)
local h = tostring(hex or ""):match("#?(%x%x%x%x%x%x)") or "E6E6E6"
return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end
function ui.gangOf(obj)
local ok, tags = pcall(function() return obj.getTags() end)
local prefixes = { CFG.gangTag }
for _, old in ipairs(CFG.oldGangTags or {}) do prefixes[#prefixes + 1] = old end
local teamPre = tostring(CFG.teamTag or "")
local gang, team = nil, nil
for _, t in ipairs(ok and type(tags) == "table" and tags or {}) do
if type(t) == "string" then
if teamPre ~= "" and t:sub(1, #teamPre) == teamPre and #t > #teamPre then
team = team or t:sub(#teamPre + 1)
elseif not gang then
for _, pre in ipairs(prefixes) do
if t:sub(1, #pre) == pre and #t > #pre then gang = t:sub(#pre + 1) break end
end
end
end
end
return gang, team
end
function ui.prefix()
local role = ACTIVATION.seqRole and ACTIVATION.seqRole()
if role then return "[" .. role .. "] " end
return ui.gangPrefix()
end
function ui.gangPrefix()
local gang = ui.gangOf(self)
if not gang or gang == "" then gang = trimText(fighter and fighter.gang or "") end
return gang ~= "" and ("[" .. gang .. "] ") or CFG.infoPrefix
end
local function chat(msg, rgb)
msg = ui.prefix() .. msg
if printToAll then pcall(printToAll, msg, rgb or { 0.9, 0.9, 0.9 }) else print(msg) end
end
local function flash(obj, rgb)
pcall(function() obj.highlightOn(rgb, CFG.statusFlash) end)
end
function ACTIVATION.actionGlow(key, kind)
local a = ACTIONS[indexOf(ACTIONS, key) or 0]
local c = rgbOf(ACTION_TYPES[kind or (a and a.type) or ""] or "#E6E6E6ff")
local top = math.max(c[1], c[2], c[3])
if top > 0 then for i = 1, 3 do c[i] = c[i] / top end end
return c
end
local function conditionCount(key)
local v = fighter.conditions[key]
local n = v == true and 1 or math.max(0, math.floor(tonumber(v) or 0))
if n == 0 and SKILL.grants then return SKILL.grants(key) end
return n
end
local function conditionLabel(c)
local n = conditionCount(c.key)
if c.stacks and n >= 2 then return string.format("%s x%d", c.label, n) end
return c.label
end
function STAT.range(key)
local r = STAT.LIMITS[key] or STAT.LIMITS.default
return r[1], r[2]
end
function STAT.clamp(key, n)
local lo, hi = STAT.range(key)
return math.max(lo, math.min(hi, n))
end
function STAT.better(key, d)
local roll = STAT_ROLLS[key]
if roll and not roll.under then return d < 0 end
return d > 0
end
function STAT.works(it, off)
if off == nil then off = SKILL.off() end
if it.kind ~= "skill" or not off then return true end
return it.type == "wyrd" and fighter.status ~= "seriously_injured" and fighter.outOfAction ~= true
end
function STAT.inv()
local best, from = nil, nil
for _, it in ipairs(SKILL.with("inv")) do
local n = tonumber(it.inv)
if n and not (fighter.burnt or {})[it.key] and not (best and best <= n) then best, from = n, it end
end
return best, from
end
function STAT.hoverOrder()
if not STAT.inv() then return CFG.statOrderHover end
local out = {}
for i, k in ipairs(CFG.statOrderHover) do out[i] = k == "Sv" and "Inv" or k end
return out
end
function STAT.gives(it, key, ctx)
if (it.kind == "wargear" or it.type == "wyrd") and STAT.fixed(key) then return 0 end
local n = 0
if it.mods and STAT.whenOn(it, ctx) and not SKILL.spent(it) then n = n + (tonumber(it.mods[key]) or 0) end
if it.boost and (fighter.boosted or {})[it.key] then n = n + (tonumber(it.boost[key]) or 0) end
local b = type(it.booster) == "table" and fighter.jumping == it.key and it.booster
if b then
n = n + (tonumber((b.mods or {})[key]) or 0)
if key == "S" and ACTIVATION.charged() then n = n + (tonumber((b.charge or {}).S) or 0) end
end
if it.maintained and SKILL.live(it) then n = n + (tonumber(it.maintained[key]) or 0) end
return n
end
function STAT.fixed(key)
if key ~= "M" then return false end
local tags = ACTIVATION.tags()
for _, t in ipairs(type(CFG.fixedMove) == "table" and CFG.fixedMove or {}) do
if tags[tostring(t):lower()] then return true end
end
return false
end
function STAT.whenOn(it, ctx)
if it.when == nil then return true end
if ctx and ctx.attack and it.when == "engaged" then return ctx.attack == "close" end
return it.when == fighter.status
end
function ACTIVATION.charged()
return fighter.activation == "active" and fighter.usedActions.charge == true
end
function STAT.over(key)
local n = 0
if not (type(fighter.wyrd) == "table" and fighter.wyrd.power) then return n end
for _, it in ipairs(SKILL.items()) do
if it.overLimit and STAT.works(it) then n = n + STAT.gives(it, key) end
end
return n
end
function STAT.hexed(key)
local m, base, lend = 0, nil, nil
if STAT.fixed(key) then return m, base, lend end
local group = {}
for _, h in pairs(fighter.hexes or {}) do
local n = tonumber(h.mods and h.mods[key]) or 0
if h.once then
local was = group[h.once]
if not was or math.abs(n) > math.abs(was) then group[h.once] = n end
else
m = m + n
end
local b = tonumber(h.base and h.base[key])
if b then base = b end
local l = tonumber(h.lend and h.lend[key])
if l and not (lend and not STAT.better(key, l - lend)) then lend = l end
end
for _, n in pairs(group) do m = m + n end
return m, base, lend
end
function STAT.hexWyrd(key)
for _, h in pairs(fighter.hexes or {}) do
if not h.gear and ((h.mods and (tonumber(h.mods[key]) or 0) ~= 0) or (h.base and h.base[key])
or (h.lend and h.lend[key])) then
return true
end
end
return false
end
local function statMod(key, ctx)
local m, off = 0, SKILL.off()
for _, c in ipairs(CONDITIONS) do
if c.mods and c.mods[key] then m = m + c.mods[key] * conditionCount(c.key) end
end
for _, it in ipairs(SKILL.items()) do
if STAT.works(it, off) then m = m + STAT.gives(it, key, ctx) end
end
return m + (STAT.hexed(key)) + (ACTIVATION.gangStat(key))
end
local pendingStats = {}
local function statOriginal(key) return tonumber(tostring(fighter.stats[key] or ""):match("%d+")) end
local function statEdited(key) return fighter.statEdits[key] ~= nil end
local function statPending(key) return pendingStats[key] ~= nil end
local function statKept(key)
if statOriginal(key) == nil then return nil end
return tonumber(fighter.statEdits[key]) or statOriginal(key)
end
local function statBase(key)
if statOriginal(key) == nil then return nil end
return pendingStats[key] and pendingStats[key].n or statKept(key)
end
local function statNumber(key, ctx, unset, nohex)
local base, m = statBase(key), statMod(key, ctx)
local hm, hbase, lend = STAT.hexed(key)
if nohex then m, hbase, lend = m - hm, nil, nil end
if base and hbase then base = hbase end
local over = STAT.over(key)
local function limit(n)
n = STAT.clamp(key, n - over) + over
if lend and STAT.better(key, lend - n) then n = lend end
return n
end
if key == "Sv" and ctx and ctx.save then
if not base then return limit(6 + over) end
return limit(base + m - 1)
end
if not base then return nil end
if key == "I" then
if ctx and ctx.unwieldy then base = 1 end
if ACTIVATION.charged() then m = m + 2 end
end
local n = base + m
if not unset then
for _, c in ipairs(CONDITIONS) do
if c.set and c.set[key] and conditionCount(c.key) > 0 then n = c.set[key] + over end
end
end
return limit(n)
end
local function statText(key, ctx)
local v = tostring(fighter.stats[key] or "-")
local roll = STAT_ROLLS[key]
if roll and roll.under then v = (v:gsub("%+$", "")) end
local n = statNumber(key, ctx)
if n and not v:find("%d") then return n .. (roll and roll.under and "" or "+") end
if n and n ~= statOriginal(key) then v = (v:gsub("%d+", tostring(n), 1)) end
return v
end
function STAT.effects(key, ctx)
local out = {}
if statNumber(key, ctx) == nil then return out end
local function add(kind, i, d)
if d == 0 then return end
local up = STAT.better(key, d)
out[#out + 1] = { kind = kind, i = i, up = up, down = not up }
end
for i, c in ipairs(CONDITIONS) do
if c.mods and c.mods[key] then add("condition", i, c.mods[key] * conditionCount(c.key)) end
end
local items, sum, off = {}, 0, SKILL.off()
for _, it in ipairs(SKILL.items()) do
local d = STAT.works(it, off) and STAT.gives(it, key, ctx) or 0
if d ~= 0 and it.type == "wyrd" then
add("item", it.bar, d)
out[#out].wyrd = true
elseif d ~= 0 then
items[#items + 1], sum = { bar = it.bar, d = d }, sum + d
end
end
local raw = statBase(key) and statBase(key) + statMod(key, ctx)
local capped = raw ~= nil and sum ~= 0 and STAT.better(key, sum)
and STAT.clamp(key, raw) == STAT.clamp(key, raw - sum)
for _, e in ipairs(items) do
if capped and STAT.better(key, e.d) then out[#out + 1] = { kind = "item", i = e.bar, capped = true }
else add("item", e.bar, e.d) end
end
local hexed = statNumber(key, ctx) - (statNumber(key, ctx, nil, true) or statNumber(key, ctx))
if hexed ~= 0 then
add("hex", nil, hexed)
out[#out].wyrd = STAT.hexWyrd(key)
end
for i, c in ipairs(CONDITIONS) do
if c.set and c.set[key] and conditionCount(c.key) > 0 then
add("condition", i, statNumber(key, ctx) - statNumber(key, ctx, true))
end
end
if key == "I" and ACTIVATION.charged() then add("action", nil, 2) end
add("gang", nil, (ACTIVATION.gangStat(key)))
if not ctx then return out end
if key == "I" and ctx.unwieldy then
out[#out + 1] = { kind = "weapon", i = ctx.melee, down = true }
elseif key == "BS" and ctx.combi then
out[#out + 1] = { kind = "weapon", i = tonumber(ctx.combi), down = true }
elseif key == "Sv" and ctx.save then
local plain = statNumber(key)
local up = not plain or statNumber(key, ctx) < plain
for _, i in ipairs(ctx.saveFrom or { false }) do
out[#out + 1] = { kind = "weapon", i = i or nil, up = up, capped = not up }
end
end
return out
end
function STAT.why(key, ctx, out)
out = out or {}
local function add(s)
if not s or s == "" then return end
for _, v in ipairs(out) do if v == s then return end end
out[#out + 1] = s
end
if statNumber(key, ctx) == nil then return out end
for _, c in ipairs(CONDITIONS) do
if conditionCount(c.key) > 0 and ((c.mods and (tonumber(c.mods[key]) or 0) ~= 0) or (c.set and c.set[key])) then
add(c.label)
end
end
local off = SKILL.off()
for _, it in ipairs(SKILL.items()) do
if STAT.works(it, off) and STAT.gives(it, key, ctx) ~= 0 then add(it.name) end
end
if key == "I" and ACTIVATION.charged() then add("Charge") end
add(select(2, ACTIVATION.gangStat(key)))
for _, h in pairs(fighter.hexes or {}) do
if (h.mods and (tonumber(h.mods[key]) or 0) ~= 0) or (h.base and h.base[key]) or (h.lend and h.lend[key]) then
add(tostring(h.label or "Wyrd power"))
end
end
if key == "Sv" and ctx and ctx.save then
for _, i in ipairs(ctx.saveFrom or {}) do
local w = weaponAt(i)
add(w and w.name)
end
end
if fighter.statEdits and fighter.statEdits[key] then add(key .. " set by hand") end
return out
end
function STAT.color(up, down, capped, wyrd)
if wyrd then return COL.wyrdInk end
if capped or (up and down) then return COL.valueBoth end
if up then return COL.valueUp end
if down then return COL.valueMod end
end
local function statColor(key, ctx)
if statPending(key) then return COL.valuePending end
local up, down, capped, wyrd = false, false, false, false
for _, e in ipairs(STAT.effects(key, ctx)) do
up, down, capped = up or e.up == true, down or e.down == true, capped or e.capped == true
wyrd = wyrd or e.wyrd == true
end
return STAT.color(up, down, capped, wyrd) or (statEdited(key) and COL.valueUser or COL.value)
end
local function idNum(id, prefix)
local n = tostring(id or ""):match("^" .. prefix .. "_(%d+)$")
return tonumber(n)
end
local function xyAttr(x, y) return string.format("%.1f %.1f", x, y) end
local textEm, textWidth, FIT, fitSize, textSize, textXml, iconXml,
layeredButton, diamond, edgeLineXml, edgeFrameXml, edgedBox
do
local GLYPH_EM = { default = 0.56 }
do
local function glyphs(chars, em) for c in chars:gmatch(".") do GLYPH_EM[c] = em end end
glyphs(" fijlrtI.,:;!|'/", 0.28)
glyphs("-()", 0.35)
glyphs('"', 0.42)
glyphs("ckszvxyJ", 0.50)
glyphs("ABEFKPSTVXYZ", 0.65)
glyphs("CDGHNOQRU", 0.75)
glyphs("mwM", 0.83)
glyphs("W", 0.94)
end
do
local known, count = {}, 0
function textEm(s)
s = tostring(s)
local hit = known[s]
if hit then return hit end
local w = 0
local key = s
s = s:gsub("⚠️", "W"):gsub("⚠", "W")
s = s:gsub("∑", "N")
s = s:gsub("↔", "W")
for _, sym in pairs(CFG.rankSymbols) do s = s:gsub(sym, "W") end
if (CFG.groupMark or "") ~= "" then s = s:gsub(CFG.groupMark, "W") end
if (CFG.wyrdMark or "") ~= "" then s = s:gsub(CFG.wyrdMark, "W") end
if (CFG.coverYes or "") ~= "" then s = s:gsub(CFG.coverYes, "W") end
if (CFG.knockMark or "") ~= "" then s = s:gsub(CFG.knockMark, "W") end
for c in s:gmatch(".") do w = w + (GLYPH_EM[c] or GLYPH_EM.default) end
if count > 4000 then known, count = {}, 0 end
known[key], count = w, count + 1
return w
end
end
function textWidth(s, size, bold)
return textEm(s) * size * (bold and 1.06 or 1)
end
FIT = 0.92
function fitSize(s, w, h, size, bold)
local wide = textWidth(s, size, bold)
if wide > w * FIT then size = size * w * FIT / wide end
return math.min(size, h / 1.2)
end
local TEXT_K = CFG.textDetail or 1
do
local known, count = {}, 0
function textSize(size, w, h)
local key = size .. "|" .. w .. "|" .. h
local hit = known[key]
if hit then return hit end
local fs = math.max(1, math.floor(size * TEXT_K))
local sc = size / fs
local function g(v) return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")) end
local t = { fontSize = string.format("%d", fs), scale = g(sc) .. " " .. g(sc) .. " 1",
width = string.format("%.2f", w / sc), height = string.format("%.2f", h / sc),
scaled = math.abs(sc - 1) > 1e-6 }
if count > 4000 then known, count = {}, 0 end
known[key], count = t, count + 1
return t
end
end
function textXml(o)
local t = textSize(o.size, o.w, o.h)
if tostring(o.text or ""):find("[&<>]") and ui.rawTexts then
local raw = ui.rawTexts
if not o.id then raw.n = (raw.n or 0) + 1; o.id = "rawTxt_" .. raw.n end
raw[#raw + 1] = { id = o.id, text = tostring(o.text) }
end
local style = o.style or "Bold"
if CFG.lighterXml then
return string.format(
'<Text%s rectAlignment="MiddleCenter" offsetXY="%s" width="%s" height="%s"%s' ..
' color="%s" fontSize="%s"%s%s>%s</Text>',
o.id and string.format(' id="%s"', o.id) or "", xyAttr(o.x or 0, o.y or 0),
t.width, t.height, t.scaled and string.format(' scale="%s"', t.scale) or "",
o.color, t.fontSize, style ~= "Bold" and string.format(' fontStyle="%s"', style) or "",
o.extra or "", esc(o.text))
end
return string.format(
'<Text%s rectAlignment="MiddleCenter" offsetXY="%s" width="%s" height="%s"%s' ..
' color="%s" fontSize="%s" fontStyle="%s" alignment="MiddleCenter"' ..
' horizontalOverflow="Overflow" verticalOverflow="Overflow"%s>%s</Text>',
o.id and string.format(' id="%s"', o.id) or "", xyAttr(o.x or 0, o.y or 0),
t.width, t.height, t.scaled and string.format(' scale="%s"', t.scale) or "",
o.color, t.fontSize, style, o.extra or "", esc(o.text))
end
function iconXml(o)
local act = o.active ~= nil and string.format(' active="%s"', tostring(o.active)) or ""
if hasAsset(o.icon) then
return string.format(
'<Image%s%s rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' image="%s" raycastTarget="false" />',
o.id and string.format(' id="%s"', o.id) or "", act, xyAttr(o.x, o.y), o.d, o.d, o.icon)
end
local plate = o.plate and string.format(
'<Image rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' color="%s" raycastTarget="false" />', xyAttr(o.x, o.y), o.d, o.d, o.plate) or ""
local s = o.labelD or (o.plate and o.d * 0.8 or o.d)
return plate .. textXml{ id = o.id, x = o.x, y = o.y, w = s, h = s, text = o.label,
size = fitSize(o.label, s, s, o.labelSize, true), color = o.labelColor or COL.iconText,
style = "Bold", extra = act }
end
function layeredButton(o)
local out = {}
local s = o.size
local w, h = o.w or s, o.h or s
local pos = string.format(' rectAlignment="MiddleCenter" offsetXY="%g %g"', o.x, o.y)
local rot = o.rotation and string.format(' rotation="0 0 %g"', o.rotation) or ""
if o.bgColor or hasAsset(o.bgAsset) then
out[#out + 1] = string.format(
'<Image%s width="%g" height="%g"%s color="%s"%s raycastTarget="false" />',
pos, w, h, rot, hasAsset(o.bgAsset) and (o.bgColor or "#FFFFFFff") or o.bgColor, imgAttr(o.bgAsset))
end
out[#out + 1] = o.under
if hasAsset(o.frame) then
out[#out + 1] = string.format(
'<Image%s width="%g" height="%g"%s image="%s" color="%s" raycastTarget="false" />',
pos, w * LAY.frameArt, h * LAY.frameArt, rot, o.frame, COL.accent)
end
if o.icon or o.label then
out[#out + 1] = iconXml{ id = o.iconId, x = o.x, y = o.y, d = math.min(w, h) * (o.iconPad or LAY.iconPad),
icon = o.icon, label = o.label or "", labelSize = o.labelSize, labelD = o.labelD, plate = o.plate,
labelColor = o.labelColor, active = o.iconActive }
end
out[#out + 1] = o.inner
local extra = ""
if o.onClick then extra = extra .. string.format(' onClick="%s"', o.onClick) end
if o.onEnter then extra = extra .. string.format(' onMouseEnter="%s"', o.onEnter) end
if o.onExit then extra = extra .. string.format(' onMouseExit="%s"', o.onExit) end
local tint = o.disabled and COL.clear or COL.hover
out[#out + 1] = string.format(
'<Button id="%s"%s width="%g" height="%g"%s%s colors="%s|%s|%s|%s"%s%s />',
o.id, pos, w, h, rot, imgAttr(o.hitImage), COL.clear, tint,
o.disabled and COL.clear or COL.press, COL.clear, extra,
o.disabled and ' interactable="false"' or "")
return table.concat(out)
end
function diamond(o)
o.rotation, o.bgAsset = 45, "diamond"
o.bgColor = o.bgColor or ui.gradTint(COL.diamond)
o.labelSize = o.labelSize or LAY.diamondFont
return layeredButton(o)
end
function LAY.diamondLabel(label, side, fill)
local reach = side / math.sqrt(2) * (fill or LAY.labelFill)
return math.floor(2 * reach / (textWidth(label, 1, true) + 0.72))
end
local BOX_FILL = {
profile = "profileFill", profile_out = "profileOut",
profile_jam = "profileJam",
tab_on = "toggleOn", tab_off = "toggleOff",
button = "actionBg",
}
function ui.boxColor(kind) return COL[BOX_FILL[kind]] end
local EDGE_ART = 2
function edgeLineXml(x, y, len, thick, rot, color)
local art = hasAsset("edge_line")
return string.format(
'<Image rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.2f"%s%s' ..
' color="%s" raycastTarget="false" />', xyAttr(x, y), len, art and thick * EDGE_ART or thick,
(rot or 0) ~= 0 and string.format(' rotation="0 0 %g"', rot) or "",
art and ' image="edge_line"' or "", color)
end
function edgeFrameXml(x, y, w, h, b, color, rot, skip)
local out = {}
if rot == 45 then
local d = (w / 2 - b / 2) / math.sqrt(2)
out[#out + 1] = edgeLineXml(x - d, y + d, w, b, 45, color)
out[#out + 1] = edgeLineXml(x + d, y + d, w, b, 135, color)
out[#out + 1] = edgeLineXml(x + d, y - d, w, b, 45, color)
out[#out + 1] = edgeLineXml(x - d, y - d, w, b, 135, color)
else
out[#out + 1] = edgeLineXml(x, y + h / 2 - b / 2, w, b, 0, color)
out[#out + 1] = edgeLineXml(x, y - h / 2 + b / 2, w, b, 0, color)
if skip ~= "left" then out[#out + 1] = edgeLineXml(x - w / 2 + b / 2, y, h, b, 90, color) end
if skip ~= "right" then out[#out + 1] = edgeLineXml(x + w / 2 - b / 2, y, h, b, 90, color) end
end
return table.concat(out)
end
function edgedBox(id, x, y, w, h, kind, inner, hover)
local b = LAY.popS.border
local lines = hasAsset("edge_line")
local grad = kind:match("^profile") and imgAttr("hp_segment") or ""
return string.format(
'<Panel id="%sEdge" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" color="%s"' .. (hover and ' onMouseEnter="onProfileEnter" onMouseExit="onProfileExit"'
or ' raycastTarget="false"') .. '><Image id="%s"' ..
' rectAlignment="MiddleCenter" width="%.1f" height="%.1f" color="%s"%s' ..
' raycastTarget="false" />%s%s</Panel>',
id, xyAttr(x, y), w, h, lines and COL.clear or COL.profileEdge, id,
w - 2 * b, h - 2 * b, ui.boxColor(kind), grad,
lines and edgeFrameXml(0, 0, w, h, b, COL.profileEdge) or "", inner or "")
end
end
do
function ui.hpMax() return math.max(1, math.floor(tonumber(fighter.wounds.max) or 1)) end
function ui.hpSegment(i, upTo)
local full = i <= clamp(fighter.wounds.current, 0, ui.hpMax())
local tint = full and COL.hpFull or COL.hpEmpty
local hover = full and COL.hpHover or COL.hpFull
local lit = i <= (upTo or 0)
return {
colors = table.concat(lit and { hover, hover, hover, hover } or { tint, hover, hover, tint }, "|"),
image = hasAsset("hp_segment") and "hp_segment" or "",
}
end
function ui.hpOut() return (tonumber(fighter.wounds.current) or 0) <= 0 end
local function hpOutXml()
local t, w, h = LAY.hpOutW, LAY.hpW, LAY.hpH
local parts = {
edgeLineXml(0, (h - t) / 2, w, t, 0, COL.hpOut),
edgeLineXml(0, -(h - t) / 2, w, t, 0, COL.hpOut),
}
local reach = halfDiag(LAY.sideD) - math.abs(LAY.hpY - LAY.sideY)
local textW = math.min(w, 2 * (LAY.sideX - math.max(0, reach)))
local textH = h - 2 * t
parts[#parts + 1] = textXml{ x = 0, y = 0, w = textW, h = textH, text = LAY.hpOutText,
color = COL.hpOut, size = fitSize(LAY.hpOutText, textW, textH, LAY.hpOutFont, true),
extra = ' raycastTarget="false"' }
return string.format(
'<Panel id="hpOut" active="%s" rectAlignment="MiddleCenter" offsetXY="0 %g"' ..
' width="%g" height="%g" color="%s" raycastTarget="false">%s</Panel>',
tostring(ui.hpOut()), LAY.hpY, w, h, COL.clear, table.concat(parts))
end
function ui.hpBarXml()
local segs = {}
for i = 1, ui.hpMax() do
local s = ui.hpSegment(i, 0)
segs[i] = string.format(
'<Button id="hpSeg_%d" flexibleWidth="1" minWidth="8"%s colors="%s"' ..
' onClick="onClickHpSegment" onMouseEnter="onHpEnter" onMouseExit="onHpExit" />',
i, s.image ~= "" and string.format(' image="%s"', s.image) or "", s.colors)
end
return string.format(
'<HorizontalLayout id="hpBar" rectAlignment="MiddleCenter" offsetXY="0 %g"' ..
' width="%g" height="%g" spacing="%g" childForceExpandWidth="true"' ..
' childForceExpandHeight="true">%s</HorizontalLayout>',
LAY.hpY, LAY.hpW, LAY.hpH, LAY.hpH * LAY.hpGap, table.concat(segs)) .. hpOutXml()
end
local function statColumns()
local n = math.max(1, #CFG.statOrder)
local pitch = LAY.colW / n + LAY.statGap
local cols = {}
for i = 1, n do cols[i] = { x = (i - (n + 1) / 2) * pitch, w = pitch } end
return cols
end
local function splitValue(text, x, size)
local num, sign = tostring(text):match("^(.-%d)(%D+)$")
if not num then num, sign = tostring(text), "" end
local signSize = size * LAY.statSignScale
local wn = textWidth(num, size, true)
local ws = sign ~= "" and textWidth(sign, signSize, true) or 0
local left = x - (wn + ws) / 2
local raise = sign:match("^[\"']") and 0.37 * (size - signSize) or 0
return { num = num, numX = left + wn / 2, numW = wn / FIT,
sign = sign, signX = left + wn + ws / 2, signW = math.max(ws, 1) / FIT,
signSize = signSize, signDy = raise }
end
function ui.statCells(hover, ctx)
local keys = hover and STAT.hoverOrder() or CFG.statOrder
local h = LAY.statRowH
local headSize, valSize = LAY.labelFont, LAY.valueFont
local cells = {}
for i, c in ipairs(statColumns()) do
local key = keys[i] or ""
cells[#cells + 1] = { id = "statHead_" .. i, text = key, x = c.x, y = h / 2,
w = c.w, h = h, color = COL.label, size = headSize }
local color = key == "Inv" and COL.value or statColor(key, ctx)
local v = splitValue(key == "Inv" and STAT.inv() .. "+" or statText(keys[i], ctx), c.x, valSize)
cells[#cells + 1] = { id = "statVal_" .. i, text = v.num, x = v.numX, y = -h / 2,
w = v.numW, h = h, color = color, size = valSize }
cells[#cells + 1] = { id = "statSign_" .. i, text = v.sign, x = v.signX,
y = -h / 2 + v.signDy, w = v.signW, h = h, color = color, size = v.signSize }
end
return cells
end
function ui.statTools(v)
local keys = v.statsHover and STAT.hoverOrder() or CFG.statOrder
local tools = {}
for i = 1, #statColumns() do
local stat = keys[i]
local open = v.statCol == i and stat ~= nil and statOriginal(stat) ~= nil
tools[i] = { set = open and statPending(stat) }
end
return tools
end
local function statPlateXml(id, btnId, x, y, w, label, onClick, active)
local h, k = LAY.statRowH, LAY.statIconPad
return string.format(
'<Panel id="%s" active="%s" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" color="%s" raycastTarget="false" onMouseEnter="onStatPlateEnter"' ..
' onMouseExit="onStatPlateExit">', id, tostring(active), xyAttr(x, y), w, h, COL.clear) ..
string.format('<Image rectAlignment="MiddleCenter" width="%.1f" height="%.1f" color="%s"' ..
' raycastTarget="false" />', w, h, COL.statPlate) ..
textXml{ w = w * k, h = h * k, text = label, size = fitSize(label, w * k, h * k, LAY.labelFont, true),
color = COL.value, extra = ' raycastTarget="false"' } ..
string.format('<Button id="%s" rectAlignment="MiddleCenter" width="%.1f" height="%.1f"' ..
' colors="%s|%s|%s|%s" onClick="%s" />', btnId, w, h, COL.clear, COL.hover, COL.press,
COL.clear, onClick) ..
'</Panel>'
end
function ui.statPlatesXml()
local parts, h = {}, LAY.statRowH
local tools = ui.statTools({ statsHover = false })
for i, c in ipairs(statColumns()) do
parts[#parts + 1] = statPlateXml("statSet_" .. i, "statSetBtn_" .. i, c.x, LAY.statY + h / 2, c.w,
"Set", "onStatSet", tools[i].set)
end
return table.concat(parts)
end
function ui.statBlockXml(ctx)
local parts = {}
for _, c in ipairs(ui.statCells(false, ctx)) do parts[#parts + 1] = textXml(c) end
local h = LAY.statRowH
parts[#parts + 1] = string.format(
'<Image id="statHeadRow" rectAlignment="MiddleCenter" offsetXY="0 %.1f" width="%g"' ..
' height="%.1f" color="%s" onMouseEnter="onStatsEnter" onMouseExit="onStatsHeadExit" />', h / 2, LAY.colW, h, COL.clear)
for i, c in ipairs(statColumns()) do
parts[#parts + 1] = string.format(
'<Panel id="statCol_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" color="%s" onMouseEnter="onStatColEnter" onMouseExit="onStatColExit">',
i, xyAttr(c.x, -h / 2), c.w, h, COL.clear) ..
string.format('<Button id="statValBtn_%d" rectAlignment="MiddleCenter" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="onStatClick" />',
i, c.w, h, COL.clear, COL.hover, COL.press, COL.clear) ..
'</Panel>'
end
return string.format(
'<Panel id="statBlock" rectAlignment="MiddleCenter" offsetXY="0 %g" width="%g"' ..
' height="%g" color="%s" onMouseExit="onStatsExit">%s</Panel>',
LAY.statY, LAY.colW, LAY.statRowH * 2, COL.clear, table.concat(parts))
end
end
function ACTIVATION.geometry(rowH)
local W, H = 2 * LAY.sideX, 2 * LAY.sideY
local titleH, seen = LAY.midTitleFont * 1.25, LAY.midTitleFont * 0.8
local pad = math.max(0, (H - seen - rowH) / 3)
return W, H, H / 2 - pad - seen / 2, titleH, -H / 2 + pad + rowH / 2
end
function ACTIVATION.button(id, x, y, w, label, onClick)
local h, pad = LAY.midBtnH, LAY.popS.boxPad
local inner = textXml{ id = id .. "Txt", w = w - 2 * pad, h = h, text = label, color = COL.value,
size = fitSize(label, w - 2 * pad, h, LAY.midBtnFont, true), extra = ' raycastTarget="false"' } ..
string.format('<Button id="%s" rectAlignment="MiddleCenter" width="%.1f" height="%.1f"' ..
' colors="%s|%s|%s|%s" onClick="%s" />', id, w, h, COL.clear, COL.hover, COL.press, COL.clear, onClick)
return edgedBox(id .. "Box", x, y, w, h, "button", inner)
end
function ACTIVATION.outTitle() return fighter.outCold and "Out Cold" or "Out of Action" end
function ACTIVATION.panelXml()
local d = LAY.midDiamond
local function panel(id, on, title, color, inner, rowH, titleId)
local W, H, titleY, titleH = ACTIVATION.geometry(rowH)
return string.format(
'<Panel id="%s" active="%s" rectAlignment="MiddleCenter" width="%g" height="%g" color="%s"' ..
' raycastTarget="true">', id, tostring(on), W, H, COL.statPlate:sub(1, 7) .. "ff") ..
textXml{ id = titleId, x = 0, y = titleY, w = W * 0.9, h = titleH, text = title, color = color,
size = fitSize(title, W * 0.9, titleH, LAY.midTitleFont, true), extra = ' raycastTarget="false"' } ..
inner .. '</Panel>'
end
local rowY = select(5, ACTIVATION.geometry(LAY.midBtnH))
local out = panel("outPanel", fighter.outOfAction == true, ACTIVATION.outTitle(), statusDef("seriously_injured").color,
ACTIVATION.button("reviveBtn", 0, rowY, LAY.midReviveW, "Revive", "onRevive"), LAY.midBtnH, "outTitle")
rowY = select(5, ACTIVATION.geometry(d * math.sqrt(2)))
local step = d * math.sqrt(2) + LAY.midGap
local rec = fighter.recovery
local function btn(id, i, label, onClick, icon, x, size, ink)
return diamond{ id = id, size = d, x = x or (i - 2) * step, y = rowY, icon = icon, label = label,
labelSize = size or LAY.midBtnFont, labelD = size and d or nil, iconId = id .. "Txt", labelColor = ink,
frame = "diamond_frame", onClick = onClick, iconPad = icon == "stat_die" and LAY.dieIcon or nil }
end
local W, H = ACTIVATION.geometry(d * math.sqrt(2))
local function group(id, on, inner)
return string.format('<Panel id="%s" active="%s" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' color="%s" raycastTarget="false">', id, tostring(on), W, H, COL.clear) .. inner .. '</Panel>'
end
local dagger = "†"
local row = group("recoveryRow", not ACTIVATION.doomed(),
btn("recoveryVal", 1, tostring(rec and rec.dice or 1), "onRecoveryValue")
.. btn("recoveryRoll", 2, "D", "onRecoveryRoll", "stat_die")
.. btn("recoveryClose", 3, "X", "onRecoveryClose"))
.. group("recoveryDoom", ACTIVATION.doomed(), btn("recoveryOut", 2, nil, "onRecoveryOut")
.. (hasAsset("dice_out") and string.format('<Image id="recoveryOutIcon" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%.1f" height="%.1f" image="dice_out" color="%s" raycastTarget="false" />',
xyAttr(0, rowY), d * 0.8, d * 0.8, statusDef("seriously_injured").color)
or textXml{ id = "recoveryOutTxt", x = 0, y = rowY, w = d, h = d * 1.3, text = dagger,
color = statusDef("seriously_injured").color,
size = fitSize(dagger, d, d * 1.3, LAY.midBtnFont * 1.6, true), extra = ' raycastTarget="false"' }))
out = out .. panel("recoveryPanel", ACTIVATION.isOpen(), "Recovery Test", COL.accent, row, d * math.sqrt(2))
local v, s = ACTIVATION.nerveValue(), d * LAY.iconPad
local head, stat = ACTIVATION.nerveTexts()
local asking = ACTIVATION.questioning()
local goW, noW = LAY.midReviveW, d * math.sqrt(2)
local left = -(goW + LAY.midGap + noW) / 2
local coverSize = LAY.diamondLabel("+" .. ACTIVATION.coverMax(), d, LAY.coverFill)
row = group("nerveRow", not asking, btn("nerveVal", 1, nil, "onNerveValue")
.. btn("nerveRoll", 2, "D", "onNerveRoll", "stat_die")
.. group("nerveConfirm", ACTIVATION.nerveAsks(), btn("nerveOk", 2, "OK", "onNerveOk"))
.. btn("nerveClose", 3, "X", "onNerveClose")
.. textXml{ id = "nerveValTxt", x = -step, y = rowY, w = s, h = s, text = v, color = ACTIVATION.nerveInk(),
size = fitSize(v, s, s, LAY.midBtnFont, true), extra = ' raycastTarget="false"' }
.. textXml{ id = "nerveStat", x = stat.x, y = stat.y, w = stat.w, h = stat.h,
text = stat.text, color = COL.value, size = stat.size, extra = ' raycastTarget="false"' })
.. group("nerveQuestion", asking,
group("nerveQGo", not (ACTIVATION.asksPair() or ACTIVATION.asksYes() or ACTIVATION.asksSkip()),
ACTIVATION.button("nerveGo", left + goW / 2, rowY, goW, "Continue", "onNerveGo")
.. btn("nerveNo", 3, "X", "onNerveClose", nil, left + goW + LAY.midGap + noW / 2))
.. group("nerveQPair", ACTIVATION.asksPair(),
btn("nerveCover", 1, ACTIVATION.coverText(), "onNerveCover", nil, nil, coverSize, ACTIVATION.coverInk())
.. btn("nerveYes", 2, CFG.coverYes, "onNerveGo")
.. btn("nerveX", 3, "X", "onNerveClose"))
.. group("nerveQYes", ACTIVATION.asksYes(),
btn("nerveOkYes", 2, CFG.coverYes, "onNerveGo", nil, -step / 2)
.. btn("nerveOkNo", 3, "X", "onNerveClose", nil, step / 2))
.. group("nerveQSkip", ACTIVATION.asksSkip(),
ACTIVATION.button("nerveSkip", 0, rowY, goW, CFG.disruptSkip or "Skip", "onNerveGo")))
return out .. panel("nervePanel", ACTIVATION.nerveOpen(), head.text, head.ink, row, d * math.sqrt(2), "nerveTitle")
end
function ACTIVATION.isOpen() return fighter.recovery ~= nil and not fighter.outOfAction end
function ACTIVATION.doomed() return fighter.recovery ~= nil and fighter.recovery.foes ~= nil end
function ACTIVATION.nerveOpen() return ACTIVATION.nerve ~= nil and not fighter.outOfAction end
function ACTIVATION.nerveAsks() return ACTIVATION.nerve ~= nil and ACTIVATION.nerve.test == "height" end
function ACTIVATION.questioning() return ACTIVATION.nerve ~= nil and ACTIVATION.nerve.test == "question" end
function ACTIVATION.asksPair() return ACTIVATION.questioning() and ACTIVATION.nerve.pair == true end
function ACTIVATION.asksYes() return ACTIVATION.questioning() and ACTIVATION.nerve.yes == true end
function ACTIVATION.asksSkip() return ACTIVATION.questioning() and ACTIVATION.nerve.skip == true end
function ACTIVATION.blasting() return ACTIVATION.questioning() and ACTIVATION.nerve.blast ~= nil end
function ACTIVATION.coverInk()
return ACTIVATION.asksPair() and ACTIVATION.nerve.coverBy and COL.valueMod or COL.iconText
end
function ACTIVATION.coverText()
local n = ACTIVATION.nerve
return string.format("+%d", ACTIVATION.asksPair() and tonumber(n.value) or 0)
end
function ACTIVATION.coverMax()
return math.max(tonumber(CFG.coverShort) or 0, tonumber(CFG.coverLong) or 0, tonumber(CFG.coverTemplate) or 0)
end
function ACTIVATION.nerveValue()
local n = ACTIVATION.nerve
if not (n and n.value) then return "-" end
if n.test == "height" then return n.value .. '"' end
return tostring(n.value)
end
function ACTIVATION.nerveInk()
local n = ACTIVATION.nerve
if n and n.test then return COL.iconText end
if n and n.hand then return COL.valueUser end
if n and n.group then return (n.minus or 0) > 0 and COL.valueMod or COL.iconText end
if n and n.from and n.value and (not n.own or n.value > n.own) then return COL.valueUp end
return COL.iconText
end
function ACTIVATION.nerveTexts()
local n = ACTIVATION.nerve
local title, stat = n and n.title or "Nerve Check", n and n.stat or "Cl"
local d = LAY.midDiamond * math.sqrt(2)
local W, _, _, titleH, rowY = ACTIVATION.geometry(d)
local size = LAY.midStatFont or LAY.midBtnFont
local tip = -(d + LAY.midGap) - d / 2
local edge = -LAY.sideX - math.min(0, rowY - 0.4 * size)
size = fitSize(stat, tip - LAY.midGap - edge, LAY.midDiamond, size, true)
local labelW = textWidth(stat, size, true)
return { text = title, w = W * 0.9, h = titleH, size = fitSize(title, W * 0.9, titleH, LAY.midTitleFont, true),
ink = n and n.titleInk or COL.accent },
{ text = stat, x = tip - LAY.midGap - labelW / 2, y = rowY, w = labelW * 1.2, h = LAY.midDiamond, size = size }
end
ACTIVATION.PIP_SPOTS = { { -1, 1 }, { 1, 1 }, { -1, 0 }, { 0, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 } }
ACTIVATION.PIPS = { { 4 }, { 2, 6 }, { 2, 4, 6 }, { 1, 2, 6, 7 }, { 1, 2, 4, 6, 7 }, { 1, 2, 3, 5, 6, 7 } }
ACTIVATION.STAND_IN = { injured = "INJ", serious = "S.I.", out = "†" }
function ACTIVATION.face(kind, v, D, hl, spared)
local f = { fill = COL.diceFace, ink = hl or COL.diceInk, pips = {} }
local ammoInk = spared and COL.ammoSpared or COL.diceAmmo
v = clamp(math.floor(tonumber(v) or 1), 1, 6)
local function text(t, ink, x, w, k)
f.num, f.numInk, f.numX, f.numY, f.numW, f.numH = t, ink, x, 0, w, D * 0.84
f.numSize = fitSize(t, w, D * 0.84, D * k, true)
end
if kind == "firepower" then
local fp = ACTIVATION.FIREPOWER[v]
f.fill = COL.diceFire
if fp.ammo then
text(tostring(fp.hits), COL.diceFireInk, -0.19 * D, 0.42 * D, 0.62)
if hasAsset("dice_ammo") then
f.icon, f.iconInk, f.iconX, f.iconD = "dice_ammo", ammoInk, 0.2 * D, 0.84 * D
else
f.mark, f.markInk, f.markX, f.markW = "!", ammoInk, 0.17 * D, 0.42 * D
f.markSize = fitSize("!", 0.42 * D, D * 0.84, D * 0.62, true)
end
else
text(tostring(fp.hits), COL.diceFireInk, 0, 0.84 * D, 0.72)
end
elseif kind == "injury" then
local r = ACTIVATION.INJURY_DICE[v] or "serious"
f.fill = COL.diceHurt
local art = ACTIVATION.injuryArt(r)
if art then
f.icon, f.iconInk, f.iconX, f.iconD = art, ACTIVATION.injuryInk(r), 0, 0.8 * D
else
text(ACTIVATION.STAND_IN[r], ACTIVATION.injuryInk(r), 0, 0.84 * D, 0.62)
end
else
if kind == "unstable" then f.fill, f.ink = COL.diceUnstable, hl or COL.diceUnstableInk end
for _, k in ipairs(ACTIVATION.PIPS[v]) do f.pips[k] = true end
end
return f
end
function ACTIVATION.injuryInk(r)
return r == "out" and COL.diceOut or r == "injured" and COL.diceInjured or COL.diceSerious
end
function ACTIVATION.injuryArt(r)
if hasAsset("dice_" .. r) then return "dice_" .. r end
return nil
end
function ACTIVATION.resultView(k)
local S1, b = LAY.diceSumFont, {}
b.ink, b.d = ACTIVATION.injuryInk(k), math.min(LAY.diceD * 0.8, S1 * 1.6)
local art = ACTIVATION.injuryArt(k)
if art then
b.icon, b.w, b.hh = art, b.d, b.d / 2
else
b.text, b.size = ACTIVATION.STAND_IN[k], S1
b.w, b.hh = textWidth(b.text, S1, true), S1 * 0.45
end
return b
end
function ACTIVATION.sumView(r)
if not r or r.rolling or not (r.sum or r.result) then return nil end
local S1, b = LAY.diceSumFont, {}
if r.result then return ACTIVATION.resultView(r.result) end
b.text, b.ink, b.size = r.sum, r.sumInk or COL.value, S1
b.w, b.hh = textWidth(b.text, b.size, true), b.size * 0.45
return b
end
function ACTIVATION.ammoView(r)
local st = r and not r.rolling and r.ammoState
if not st then return nil end
local S1 = LAY.diceSumFont
local b = { text = st:upper(), ink = COL["ammo" .. st:sub(1, 1):upper() .. st:sub(2)] or COL.diceAmmo, size = S1 }
b.w, b.hh = textWidth(b.text, S1, true), S1 * 0.45
return b
end
function ACTIVATION.ammoState(n, limited)
if (n or 0) < 1 then return nil end
return limited and "spent" or n >= 2 and "jam" or "out"
end
function ACTIVATION.leadView(r)
local text = r and not r.rolling and r.lead
if not text then return nil end
local size = LAY.diceSumFont
return { text = text, ink = r.leadInk or COL.value, size = size, w = textWidth(text, size, true), hh = size * 0.45 }
end
function ACTIVATION.linesView(r)
local list = r and not r.rolling and type(r.lines) == "table" and r.lines or nil
if not list or #list == 0 then return nil end
local n = math.min(2, #list)
local function y(k, sz) return n == 1 and 0 or (k == 1 and 0.6 or -0.6) * sz end
local function fits(sz)
if n * 1.2 * sz > 2 * LAY.sideY then return false end
for k = 1, n do
local half = LAY.sideX - LAY.dicePad - math.abs(y(k, sz)) - sz * 0.45
if textWidth(tostring(list[k]), sz, true) > 2 * half then return false end
end
return true
end
local size = LAY.diceSumFont
while size > 1 and not fits(size) do size = size - 1 end
local out = {}
for k = 1, 2 do
local text = k <= n and tostring(list[k]) or nil
out[k] = { text = text, ink = r.linesInk or COL.value, size = size, y = y(k, size),
w = text and textWidth(text, size, true) or 1 }
end
return out
end
function ACTIVATION.diceView()
local r = ACTIVATION.roll
local W, H = 2 * LAY.sideX, 2 * LAY.sideY
local rolling = r ~= nil and r.rolling == true
local v = { on = r ~= nil, rolling = rolling, W = W, H = H, slots = {}, rowY = 0 }
local faces = (r and not rolling) and r.faces or {}
local n = math.min(#faces, ACTIVATION.MAX_SHOWN)
local pad, gap = LAY.dicePad, LAY.diceSumGap
local tags = (r and not rolling and type(r.tags) == "table") and r.tags or {}
local half = (r and not rolling and type(r.half) == "table") and r.half or {}
local tagged = false
for i = 1, n do tagged = tagged or (type(tags[i]) == "table" and #tags[i] > 0) end
local D0 = tagged and math.min(LAY.diceD, ACTIVATION.tagRoom()) or LAY.diceD
local ex = tagged and math.max(0, ACTIVATION.markSide(D0) + LAY.diceTagGap + LAY.diceTagH - D0 / 2) or 0
local b = ACTIVATION.sumView(r)
local open = LAY.sideX - pad
local lead = ACTIVATION.leadView(r)
local after = r and not rolling and r.inline and b and b.text and b or nil
local l, D, step, w, x0 = nil, nil, nil, nil, nil
if lead or after then
if b and not after then b.x = open - b.hh - b.w / 2 end
local hh = LAY.diceSumFont * 0.45
local L = -open + hh
local R = (b and not after) and (b.x - b.w / 2 - gap) or open - hh
local function width()
local parts, total = 0, 0
for _, x in ipairs({ lead and lead.w or 0, w, after and after.w or 0 }) do
if x > 0 then parts, total = parts + 1, total + x end
end
return total + math.max(0, parts - 1) * gap
end
D, step = D0, D0 + LAY.diceSpace
w = n > 0 and (n * D + (n - 1) * (step - D)) or 0
local k = math.min(1, (R - L) / math.max(1, width()))
if k < 1 then
for _, t in ipairs({ lead or false, after or false }) do
if t then
t.size = math.max(1, math.floor(t.size * k))
t.w, t.hh = textWidth(t.text, t.size, true), t.size * 0.45
end
end
D, step = D0 * k, (D0 + LAY.diceSpace) * k
w = n > 0 and (n * D + (n - 1) * (step - D)) or 0
end
local x = (L + R) / 2 - width() / 2
if lead then lead.x, x = x + lead.w / 2, x + lead.w + gap end
x0 = x
if n > 0 then x = x + w + gap end
if after then after.x = x + after.w / 2 end
l = lead
else
if b then b.x = open - b.hh - b.w / 2 end
l = r and not rolling and r.best and ACTIVATION.resultView(r.best) or ACTIVATION.ammoView(r)
if l then l.x = -(open - l.hh - l.w / 2) end
local lo = l and (l.x + l.w / 2 + gap) or -open + ex
local hi = b and (b.x - b.w / 2 - gap) or open - ex
local k = (l and 0 or 1) + (b and 0 or 1)
local sp = math.max(0, n - 1) * LAY.diceSpace / D0
D = D0
if n > 0 then D = math.max(D0 * 0.3, math.min(D0, (hi - lo) / (n + sp + k * 0.5))) end
if not l then lo = lo + D / 2 end
if not b then hi = hi - D / 2 end
step = D + LAY.diceSpace * D / D0
w = n * D + math.max(0, n - 1) * (step - D)
local mid = lo + w / 2 > hi - w / 2 and (lo + hi) / 2 or clamp(0, lo + w / 2, hi - w / 2)
x0 = mid - w / 2
end
local ai = r and not rolling and r.ammoDie
for i = 1, ACTIVATION.MAX_SHOWN do
local kind = r and (r.kinds and r.kinds[i] or r.kind) or "d6"
local hl = r and (r.hls and r.hls[i] or r.hl)
local on = i <= n
local f = ACTIVATION.face(kind, faces[i] or 1, ACTIVATION.markSide(D), hl, r ~= nil and r.spare == i)
if on and half[i] then ACTIVATION.tint(f, half[i]) end
if on and ai == i then ACTIVATION.cartDie(f, faces[i], D, r.ammoGoal) end
v.slots[i] = { on = on, D = D, x = x0 + (i - 1) * step + D / 2, y = v.rowY, face = f,
tags = ACTIVATION.tagView(on and tags[i] or nil, D) }
end
v.sum = b
if r and r.best then v.best = l else v.ammo = l end
v.lines = ACTIVATION.linesView(r)
return v
end
ACTIVATION.EFFECTS = {
{ key = "shock", label = "SHOCK", short = "SHK", col = "diceShock" },
{ key = "knock", label = "KNOCK", short = "KB", col = "diceKnock" },
{ key = "precise", label = "PRECISE", short = "PRC", col = "dicePrecise" },
{ key = "rend", label = "REND", short = "RND", col = "diceRend" },
{ key = "shred", label = "SHRED", short = "SHR", col = "diceShred" },
{ key = "breach", label = "BREACH", short = "BRC", col = "diceBreach" },
{ key = "conc", label = "CONC", short = "CNC", col = "diceConc" },
{ key = "blaze", label = "BLAZE", short = "BLZ", col = "diceBlaze" },
}
function ACTIVATION.effect(key)
for _, e in ipairs(ACTIVATION.EFFECTS) do
if e.key == key then return e end
end
return nil
end
function ACTIVATION.effects(set)
local out = {}
for _, e in ipairs(ACTIVATION.EFFECTS) do
if set[e.key] then out[#out + 1] = e.key end
end
return #out > 0 and out or nil
end
function ACTIVATION.effectInk(e) return COL[e.col] or e.col end
function ACTIVATION.tagRoom()
local face = 2 * (LAY.sideY - LAY.diceTagClear - LAY.diceTagGap - LAY.diceTagH)
return face * (ACTIVATION.edgeArt() and LAY.frameArt or 1)
end
function ACTIVATION.tagView(list, D)
local W, h, g = ACTIVATION.markSide(D), LAY.diceTagH, LAY.diceTagSplit
local keys = {}
for _, key in ipairs(type(list) == "table" and list or {}) do
if ACTIVATION.effect(key) and #keys < 4 then keys[#keys + 1] = key end
end
local n = #keys
local spots = ({ { 1 }, { 1, 3 }, { 1, 3, 4 }, { 1, 2, 3, 4 } })[n] or {}
local shared = { n == 4, true, n >= 3, true }
local y = W / 2 + LAY.diceTagGap + h / 2
local out = {}
for k = 1, 4 do
out[k] = { on = false, text = "", ink = COL.diceShock, x = 0, y = 0, w = W, h = h, size = h / 2, sy = 1 }
end
for j, k in ipairs(spots) do
local e = ACTIVATION.effect(keys[j])
local w = shared[k] and (W - g) / 2 or W
local x = shared[k] and (k % 2 == 1 and -1 or 1) * (w + g) / 2 or 0
local text = shared[k] and e.short or e.label
local room, cap = h - 2 * LAY.diceTagPad, ACTIVATION.CART.cap
local size = fitSize(text, w - 2 * LAY.diceTagPad, math.huge, room / cap, true)
out[k] = { on = true, text = text, ink = ACTIVATION.effectInk(e), x = x, y = k <= 2 and y or -y, w = w, h = h,
size = size, sy = math.max(1, math.min(LAY.diceTagStretch, room / (cap * size))) }
end
return out
end
function ACTIVATION.tagText(g)
local t = textSize(g.size, g.w, g.h)
local sc = g.size / tonumber(t.fontSize)
local function f(v) return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")) end
return { fontSize = t.fontSize, scale = f(sc) .. " " .. f(sc * (g.sy or 1)) .. " 1", width = t.width,
height = string.format("%.2f", g.h / (sc * (g.sy or 1))) }
end
function ACTIVATION.mix(a, b, k)
local function ch(hex, i) return tonumber(hex:sub(i, i + 1), 16) end
local out = "#"
for i = 2, 6, 2 do out = out .. string.format("%02X", math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * k + 0.5)) end
return out .. (#a >= 9 and a:sub(8, 9) or "ff")
end
function ACTIVATION.tint(f, key)
local e = ACTIVATION.effect(key)
if not e then return end
local col = ACTIVATION.effectInk(e)
if hasAsset("dice_half") then f.half = col:sub(1, 7) .. string.format("%02X", math.floor(LAY.diceHalf * 255 + 0.5))
else f.fill = ACTIVATION.mix(f.fill, col, 0.3) end
end
ACTIVATION.CART = { tall = 0.88, caseY = 0.64, caseW = 0.32, caseH = 0.40, cap = 0.72,
goalY = 0.29, goalW = 0.25, goalH = 0.15 }
function ACTIVATION.cartDie(f, v, D, goal)
local t = tostring(clamp(math.floor(tonumber(v) or 1), 1, 6))
local side = ACTIVATION.markSide(D)
f.pips = {}
f.num, f.numInk, f.numX, f.numY, f.numW, f.numH = t, f.ink, 0, 0, side * 0.84, side * 0.84
f.numSize = fitSize(t, side * 0.84, side * 0.84, side * 0.62, true)
if not hasAsset("dice_ammo") then return end
local A, C = ACTIVATION.cartSize(D), ACTIVATION.CART
f.cart = A
f.cartInk = f.ink == COL.valueMod and COL.diceAmmo or f.ink
local w, h = (C.caseW - 2 * LAY.diceAmmoPad) * A, (C.caseH - 2 * LAY.diceAmmoPad) * A
local size = fitSize(t, w, math.huge, h / C.cap, true)
f.numY, f.numW, f.numH = (0.5 - C.caseY) * A, C.caseW * A, size * 1.3
f.numSize, f.numInk = math.floor(size), COL.diceTagInk
if goal then
local gs = math.floor(fitSize(goal, C.goalW * A, math.huge, C.goalH * A / C.cap, true))
f.goal = { text = goal, size = gs, y = (0.5 - C.goalY) * A, w = C.goalW * A + gs, h = gs * 1.3 }
end
end
function ACTIVATION.cartTexts(f)
local g = f.cart ~= nil and f.goal or nil
return {
{ id = "dieGoal", on = g ~= nil, text = g and g.text or "", ink = COL.diceTagInk, x = 0,
y = g and g.y or 0, w = g and g.w or 1, h = g and g.h or 1, size = g and g.size or LAY.diceTagH },
}
end
function ACTIVATION.cartSize(D)
return math.min(D * LAY.diceAmmoSize, 2 * (LAY.sideY - LAY.diceTagClear) / ACTIVATION.CART.tall)
end
function ACTIVATION.edgeArt() return hasAsset("diamond_frame") end
function ACTIVATION.faceSide(D) return ACTIVATION.edgeArt() and D / LAY.frameArt or D - 2 * LAY.diceEdge end
function ACTIVATION.markSide(D) return ACTIVATION.edgeArt() and D / LAY.frameArt or D end
function ACTIVATION.faceArt() return hasAsset("diamond") and "diamond" or nil end
function ACTIVATION.pipAt(k, D)
local spot = ACTIVATION.PIP_SPOTS[k]
return spot[1] * 0.27 * D, spot[2] * 0.27 * D, D * LAY.dicePip / math.sqrt(2)
end
function ACTIVATION.diceXml()
local v, e = ACTIVATION.diceView(), LAY.diceEdge
local function img(id, on, x, y, w, color, rot, image)
return string.format('<Image id="%s"%s rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"%s' ..
' color="%s"%s raycastTarget="false" />', id, on == nil and "" or string.format(' active="%s"', tostring(on)),
xyAttr(x, y), w, w, rot and ' rotation="0 0 45"' or "", color, image and string.format(' image="%s"', image) or "")
end
local out = {
string.format('<Panel id="dicePanel" active="%s" rectAlignment="MiddleCenter" width="%g" height="%g" color="%s"' ..
' raycastTarget="true" onMouseEnter="onDiceEnter" onMouseExit="onDiceExit">', tostring(v.on), v.W, v.H,
COL.dicePanel),
textXml{ id = "diceWait", x = 0, y = 0, w = v.W * 0.75, h = LAY.diceWaitFont * 1.25, text = "Rolling Dice...",
color = COL.accent, size = fitSize("Rolling Dice...", v.W * 0.75, LAY.diceWaitFont * 1.25,
LAY.diceWaitFont, true), extra = string.format(' active="%s" raycastTarget="false"', tostring(v.rolling)) },
}
for i, s in ipairs(v.slots) do
local f, D = s.face, s.D
out[#out + 1] = string.format('<Panel id="dieSlot_%d" active="%s" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%.1f" height="%.1f" color="%s" raycastTarget="false">', i, tostring(s.on), xyAttr(s.x, s.y), D, D, COL.clear)
local plain = f.cart == nil
local half = hasAsset("dice_half") and img("dieHalf_" .. i, f.half ~= nil, 0, 0, ACTIVATION.faceSide(D),
f.half or COL.clear, nil, "dice_half") or ""
if ACTIVATION.edgeArt() then
out[#out + 1] = img("dieFace_" .. i, plain, 0, 0, ACTIVATION.faceSide(D), ui.gradTint(f.fill), nil,
ACTIVATION.faceArt())
.. half .. img("dieEdge_" .. i, plain, 0, 0, D, f.ink, nil, "diamond_frame")
else
out[#out + 1] = img("dieEdge_" .. i, plain, 0, 0, D, f.ink)
.. img("dieFace_" .. i, plain, 0, 0, D - 2 * e, ui.gradTint(f.fill), nil, ACTIVATION.faceArt())
.. half
end
if hasAsset("dice_ammo") then
out[#out + 1] = img("dieAmmo_" .. i, not plain, 0, 0, f.cart or ACTIVATION.cartSize(D), f.cartInk or f.ink, nil,
"dice_ammo")
for _, part in ipairs(ACTIVATION.cartTexts(f)) do
out[#out + 1] = textXml{ id = part.id .. "_" .. i, x = part.x, y = part.y, w = part.w, h = part.h,
text = part.text, color = part.ink, size = part.size,
extra = string.format(' active="%s" raycastTarget="false"', tostring(part.on)) }
end
end
for k = 1, #ACTIVATION.PIP_SPOTS do
local px, py, pw = ACTIVATION.pipAt(k, ACTIVATION.markSide(D))
out[#out + 1] = img("diePip_" .. i .. "_" .. k, f.pips[k] == true, px, py, pw, f.ink, true)
end
out[#out + 1] = textXml{ id = "dieNum_" .. i, x = f.numX or 0, y = f.numY or 0, w = f.numW or D, h = f.numH or D,
text = f.num or "", color = f.numInk or COL.diceInk, size = f.numSize or LAY.diceSumFont,
extra = string.format(' active="%s" raycastTarget="false"', tostring(f.num ~= nil)) }
out[#out + 1] = img("dieIcon_" .. i, f.icon ~= nil, f.iconX or 0, 0, f.iconD or D * 0.66,
f.iconInk or COL.diceInk, nil, f.icon)
out[#out + 1] = textXml{ id = "dieMark_" .. i, x = f.markX or 0, y = 0, w = f.markW or D, h = ACTIVATION.markSide(D) * 0.84,
text = "!", color = f.markInk or COL.diceAmmo, size = f.markSize or LAY.diceSumFont,
extra = string.format(' active="%s" raycastTarget="false"', tostring(f.mark ~= nil)) }
for k, g in ipairs(s.tags) do
out[#out + 1] = string.format('<Image id="dieTag_%d_%d" active="%s" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%.1f" height="%.1f" color="%s" raycastTarget="false" />', i, k, tostring(g.on),
xyAttr(g.x, g.y), g.w, g.h, g.ink)
local t = ACTIVATION.tagText(g)
out[#out + 1] = string.format('<Text id="dieTagTxt_%d_%d" active="%s" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%s" height="%s" scale="%s" color="%s" fontSize="%s"%s' ..
' raycastTarget="false">%s</Text>', i, k, tostring(g.on), xyAttr(g.x, g.y), t.width, t.height, t.scale,
COL.diceTagInk, t.fontSize, CFG.lighterXml and "" or
' fontStyle="Bold" alignment="MiddleCenter" horizontalOverflow="Overflow" verticalOverflow="Overflow"',
g.text)
end
out[#out + 1] = '</Panel>'
end
local b = v.sum or {}
local sz = b.size or LAY.diceSumFont
out[#out + 1] = textXml{ id = "diceSum", x = b.x or 0, y = 0, w = (b.w or 1) / FIT + 2, h = sz * 1.25,
text = b.text or "", color = b.ink or COL.value, size = sz,
extra = string.format(' active="%s" raycastTarget="false"', tostring(b.text ~= nil)) }
out[#out + 1] = img("diceSumIcon", b.icon ~= nil, b.x or 0, 0, b.d or LAY.diceD * 0.8, b.ink or COL.value, nil, b.icon)
local a = v.ammo
local asz = a and a.size or LAY.diceSumFont
out[#out + 1] = textXml{ id = "ammoSum", x = a and a.x or 0, y = 0,
w = (a and a.w or textWidth("OUT", asz, true)) / FIT + 2, h = asz * 1.25,
text = a and a.text or "OUT", color = a and a.ink or COL.ammoOut,
size = asz, extra = string.format(' active="%s" raycastTarget="false"', tostring(a ~= nil)) }
local l = v.best or {}
local lsz = l.size or LAY.diceSumFont
out[#out + 1] = textXml{ id = "diceBest", x = l.x or 0, y = 0, w = (l.w or 1) / FIT + 2, h = lsz * 1.25,
text = l.text or "", color = l.ink or COL.value, size = lsz,
extra = string.format(' active="%s" raycastTarget="false"', tostring(l.text ~= nil)) }
out[#out + 1] = img("diceBestIcon", l.icon ~= nil, l.x or 0, 0, l.d or LAY.diceD * 0.8, l.ink or COL.value, nil, l.icon)
for k = 1, 2 do
local t = v.lines and v.lines[k] or {}
local tsz = t.size or LAY.diceSumFont
out[#out + 1] = textXml{ id = "diceLine_" .. k, x = 0, y = t.y or 0, w = (t.w or 1) / FIT + 2, h = tsz * 1.25,
text = t.text or "", color = t.ink or COL.value, size = tsz,
extra = string.format(' active="%s" raycastTarget="false"', tostring(t.text ~= nil)) }
end
return table.concat(out) .. '</Panel>'
end
MUNDA_STAMP = table.concat({ os.time(), os.clock(), math.random(1, 999999999) }, "-")
ACTIVATION.scripts = {}
function ACTIVATION.cutCard(script)
local a = script:find("local IMPORTED" .. " = ", 1, true)
local _, b = script:find("--@@MUNDA_" .. "IMPORT@@", a or 1, true)
if not (a and b) then return nil end
return script:sub(1, a - 1), script:sub(b + 1)
end
function ACTIVATION.sameCard(script)
local own = ACTIVATION.own
if own == nil then
own = false
local ok, mine = pcall(function() return self.getLuaScript() end)
if ok and type(mine) == "string" and type(_G) == "table" and _G.engageInfo == engageInfo then
local pre, post = ACTIVATION.cutCard(mine)
if pre then own = { pre = pre, post = post } end
end
ACTIVATION.own = own
end
if not own then return false end
local pre, post = ACTIVATION.cutCard(script)
return pre ~= nil and #pre == #own.pre and #post == #own.post and pre == own.pre and post == own.post
end
function ACTIVATION.has(obj, fn)
local okG, guid = pcall(function() return obj.getGUID() end)
guid = okG and type(guid) == "string" and guid or nil
local known = guid and ACTIVATION.scripts[guid]
if known then
local ok, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if ok and stamp ~= nil and stamp == known.stamp then
if known.same then return type(_G[fn]) == "function" end
return known.fns[fn] == true
end
ACTIVATION.scripts[guid] = nil
end
local ok, script = pcall(function() return obj.getLuaScript() end)
if not ok or type(script) ~= "string" then return true end
if ACTIVATION.sameCard(script) then
local okV, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if guid and okV and stamp ~= nil then ACTIVATION.scripts[guid] = { stamp = stamp, same = true } end
return type(_G[fn]) == "function"
end
if guid and script:find("MUNDA_STAMP", 1, true) then
local okV, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
if okV and stamp ~= nil then
local fns = {}
for name in script:gmatch("function ([%w_]+)%(") do fns[name] = true end
ACTIVATION.scripts[guid] = { stamp = stamp, fns = fns }
end
end
return script:find("function " .. fn .. "(", 1, true) ~= nil
end
function ACTIVATION.ask(obj, fn, arg)
if obj ~= nil and type(_G) == "table" and type(_G[fn]) == "function" then
local okS, me = pcall(function() return obj == self or obj.getGUID() == self.getGUID() end)
if okS and me then return pcall(_G[fn], arg) end
end
if not (obj and ACTIVATION.has(obj, fn)) then return false end
return pcall(function() return obj.call(fn, arg) end)
end
function ACTIVATION.tags(f)
f = f or fighter
local set, parts, role = {}, {}, tostring(f.role or "")
for part in (role .. "•"):gmatch("(.-)•") do parts[#parts + 1] = trimText(part):lower() end
if parts[1] and parts[1] ~= "" then set[parts[1]] = true end
for tag in ((parts[2] or "") .. ","):gmatch("([^,]*),") do
local t = trimText(tag)
if t ~= "" then set[t] = true end
end
for run in role:gmatch("[%w%s%-']+") do
local t = trimText(run):lower()
if t ~= "" then set[t] = true end
end
for _, v in ipairs({ f.category, f.rank, f.ftype }) do
if type(v) == "string" and v ~= "" then set[v:lower()] = true end
end
return set
end
function ui.conditionSlots()
local on = {}
for i, c in ipairs(CONDITIONS) do
if conditionCount(c.key) > 0 then on[#on + 1] = i end
end
local step = LAY.condD + LAY.condGap
if #on > 1 then step = math.min(step, (LAY.colW - LAY.condD) / (#on - 1)) end
local slots = {}
for k, i in ipairs(on) do
slots[i] = { x = (k - (#on + 1) / 2) * step, y = LAY.condY }
end
return slots
end
function ui.badgePlate()
local f = LAY.condCountFont
return textWidth("x9", f, true) / FIT + 0.2 * f, f * 1.25
end
function ui.stackBadge(n)
local text = "x" .. n
local w, h = ui.badgePlate()
return text, fitSize(text, w, h, LAY.condCountFont, true)
end
function ui.conditionBarXml()
local slots, parts, d = ui.conditionSlots(), {}, LAY.condD
local bw, bh = ui.badgePlate()
for i, c in ipairs(CONDITIONS) do
local s, n = slots[i], conditionCount(c.key)
local badge, badgeSize = ui.stackBadge(n)
local icon = "cond_" .. c.key
parts[#parts + 1] = string.format(
'<Panel id="condSlot_%d" active="%s" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%g" height="%g" color="%s" raycastTarget="false">',
i, tostring(s ~= nil), xyAttr(s and s.x or 0, s and s.y or LAY.condY), d, d, COL.clear)
parts[#parts + 1] = layeredButton{
id = "condBar_" .. i, size = d, x = 0, y = 0, icon = icon, iconPad = 1,
label = c.short, labelSize = LAY.condFont, plate = COL.iconPlate,
hitImage = icon, onClick = "onClearCondition", onEnter = "onInfoEnter", onExit = "onInfoExit",
inner = string.format(
'<Panel id="condBadge_%d" active="%s" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%g" height="%g" color="%s" raycastTarget="false">',
i, tostring(n >= 2), xyAttr(d / 2 - bw / 2, -d / 2 + bh / 2), bw, bh, COL.badge)
.. textXml{ id = "condCount_" .. i, w = bw, h = bh, text = badge,
size = badgeSize, color = COL.value } .. "</Panel>",
}
parts[#parts + 1] = string.format(
'<Image id="condFx_%d" active="false" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' color="%s" raycastTarget="false" />', i, d + LAY.condGap, d + LAY.condGap,
SKILL.fxTint(COL.valueMod))
parts[#parts + 1] = "</Panel>"
end
return table.concat(parts)
end
do
local S = SKILL
function S.key(name)
return (trimText(name):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end
function S.title(name)
return ((" " .. trimText(name)):gsub("([%s%-/%(])(%a)", function(a, b) return a .. b:upper() end):sub(2))
end
S.KINDS = {
{ kind = "skill", field = "skills", defs = SKILLS, ink = "value" },
{ kind = "wargear", field = "wargear", defs = WARGEAR, ink = "label" },
}
RULES.follow(function() S.index = nil end)
function S.def(name, kind)
kind = kind or "skill"
S.index = S.index or {}
if not S.index[kind] then
local idx = {}
for _, k in ipairs(S.KINDS) do
if k.kind == kind then
for _, d in ipairs(k.defs) do
for _, a in ipairs(type(d.aka) == "table" and d.aka or {}) do idx[S.key(a)] = d end
end
for _, d in ipairs(k.defs) do idx[S.key(d.name)] = d end
end
end
S.index[kind] = idx
end
return S.index[kind][S.key(name)]
end
function S.parse(v)
local out, seen = {}, {}
local function add(name)
name = trimText(name)
local k = S.key(name)
if k ~= "" and not seen[k] then seen[k], out[#out + 1] = true, name end
end
if type(v) == "string" then
local depth, cur = 0, {}
for c in v:gmatch(".") do
if c == "(" or c == "[" then depth = depth + 1
elseif (c == ")" or c == "]") and depth > 0 then depth = depth - 1 end
if c == "," and depth == 0 then add(table.concat(cur)); cur = {} else cur[#cur + 1] = c end
end
add(table.concat(cur))
elseif type(v) == "table" then
for _, s in ipairs(v) do add(type(s) == "table" and tostring(s.name or "") or tostring(s)) end
end
return out
end
RULES.follow(function() S.ownedNames = nil end)
function S.items()
local was, n, same = S.ownedNames, 0, S.ownedNames ~= nil
for _, k in ipairs(S.KINDS) do
for _, name in ipairs(same and fighter[k.field] or {}) do
n = n + 1
same = same and was[n] == tostring(name)
end
n = n + 1
same = same and was[n] == false
end
if not (same and was[n + 1] == nil) then
local names = {}
for _, k in ipairs(S.KINDS) do
for _, name in ipairs(fighter[k.field] or {}) do names[#names + 1] = tostring(name) end
names[#names + 1] = false
end
S.ownedList, S.ownedNames = S.entries(), names
end
return S.ownedList
end
function S.owned()
local out = {}
for i, it in ipairs(S.items()) do out[i] = it end
return out
end
function S.entries()
local out = {}
for state, k in ipairs(S.KINDS) do
for _, name in ipairs(fighter[k.field] or {}) do
local d = S.def(name, k.kind) or {}
out[#out + 1] = { kind = k.kind, ink = k.ink, key = S.key(name), name = S.title(name), short = d.short,
desc = d.desc or "", mods = d.mods, action = d.action, type = d.type,
costs = d.costs, weapon = d.weapon, meleeS = d.meleeS, secondary = d.secondary,
master = d.master, springUp = d.springUp, catfall = d.catfall,
distance = d.distance, lines = d.lines, fearsome = d.fearsome, ironJaw = d.ironJaw,
steel = d.steel, unstoppable = d.unstoppable, backstab = d.backstab,
cutThroat = d.cutThroat, lieLow = d.lieLow, shoots = d.shoots,
gunfighter = d.gunfighter, hipShooting = d.hipShooting, marksman = d.marksman,
aimed = d.aimed, fastReload = d.fastReload, ironWill = d.ironWill,
label = d.label, distribute = d.distribute, when = d.when, once = d.once,
boost = d.boost, reaction = d.reaction, noFall = d.noFall, assist = d.assist,
maintained = d.maintained, overLimit = d.overLimit, flaming = d.flaming,
meleeL = d.meleeL, target = d.target, area = d.area, aura = d.aura,
rerollHits = d.rerollHits, void = d.void, visions = d.visions,
inv = d.inv, burns = d.burns, noAp = d.noAp, immune = d.immune, gasInv = d.gasInv,
bioBooster = d.bioBooster, precise = d.precise, flashMod = d.flashMod,
condition = d.condition, juggernaut = d.juggernaut, heal = d.heal,
dodge = d.dodge, bullCharge = d.bullCharge, biceps = d.biceps,
rainOfBlows = d.rainOfBlows, agility = d.agility, statuses = d.statuses,
counterAttack = d.counterAttack, groupReroll = d.groupReroll,
agilityReroll = d.agilityReroll, spends = d.spends, burst = d.burst,
toxicBlood = d.toxicBlood, voidSoul = d.voidSoul, jumpDown = d.jumpDown,
activeMelee = d.activeMelee, booster = d.booster, refraction = d.refraction,
check = d.check, restrain = d.restrain, enrage = d.enrage,
bar = #out + 1, state = state }
end
end
return out
end
function S.grants(key)
for _, it in ipairs(S.with("condition")) do
if it.condition == key then return 1 end
end
return 0
end
function S.with(field)
local out, off = {}, S.off()
for _, it in ipairs(S.items()) do
if it[field] ~= nil and STAT.works(it, off) then out[#out + 1] = it end
end
return out
end
function S.split()
local bar, actions = S.owned(), {}
for _, it in ipairs(bar) do
if it.action then
actions[#actions + 1] = { key = it.key, label = it.label or it.name, cost = it.action, type = it.type,
distance = it.distance, lines = it.lines, distribute = it.distribute, heal = it.heal,
kind = it.kind, burst = it.burst, check = it.check, restrain = it.restrain,
enrage = it.enrage, spends = it.spends,
once = it.once, boost = it.boost, reaction = it.reaction, item = it.name,
statuses = it.statuses }
end
end
return bar, actions
end
function S.spent(it)
return it.spends == true and (fighter.usedOnce or {})[it.key] == true
end
function S.live(it)
local w = fighter.wyrd
return it.kind == "skill" and it.type == "wyrd" and type(w) == "table" and w.power == it.key
end
function S.ink(it)
if S.live(it) then return COL.wyrdInk end
if it.burns and (fighter.burnt or {})[it.key] then return COL.itemSpent end
if S.spent(it) then return COL.itemSpent end
return COL[it.ink] or COL.value
end
function S.label(it)
return (S.live(it) and (CFG.wyrdMark or "") or "") .. (it.short or it.name)
end
function S.room(it)
local keep = it.kind == "skill" and it.type == "wyrd" and ACTIVATION.continuous({ cost = it.action })
return (keep and (CFG.wyrdMark or "") or "") .. (it.short or it.name)
end
function S.maintainable(it)
return it.kind == "skill" and it.type == "wyrd" and ACTIVATION.continuous({ cost = it.action }) and STAT.works(it)
end
function S.off()
return ui.hpOut() or fighter.status == "seriously_injured" or fighter.outOfAction == true
end
function S.listed()
local out = {}
for _, it in ipairs(S.items()) do
if it.state == 1 and STAT.works(it) then out[#out + 1] = it end
end
return out
end
function S.shape()
local t = {}
for _, it in ipairs(S.listed()) do t[#t + 1] = it.bar end
return table.concat(t, ",")
end
function S.hasWyrd()
for _, it in ipairs(S.items()) do
if it.kind == "skill" and it.type == "wyrd" then return true end
end
return false
end
function S.state(v)
if ACTIVATION.roll then return "roll" end
if S.coverBy() then return "target" end
if v and v.barFx then return v.barFx end
if v and v.target and not v.barHover then return "target" end
local n = { 0, 0 }
for _, it in ipairs(S.items()) do
if it.state == 2 or STAT.works(it) then n[it.state] = n[it.state] + 1 end
end
if n[1] == 0 then return 2 end
if n[2] == 0 then return 1 end
if not (v and v.barHover) then return 1 end
return v.barFlip and 1 or 2
end
function S.fxItems(stat, wargearOnly, owned)
local out = {}
for _, it in ipairs(owned or S.items()) do
local can = (it.mods and (it.mods[stat] or 0) ~= 0) or (it.boost and (it.boost[stat] or 0) ~= 0)
or (it.maintained and (it.maintained[stat] or 0) ~= 0)
if can and not (wargearOnly and it.kind == "skill" and it.type ~= "wyrd") then
out[#out + 1] = it
end
end
return out
end
function S.fxKey(stat, wargearOnly)
if #S.fxItems(stat, wargearOnly) == 0 then return nil end
return stat .. (wargearOnly and "_w" or "")
end
function S.fxInk(it, stat)
local d = STAT.gives(it, stat)
if d == 0 then return COL[it.ink] or COL.value end
return STAT.color(STAT.better(stat, d), not STAT.better(stat, d), nil, it.type == "wyrd")
end
local function rowWidth(y, size)
local half = LAY.sideX - halfDiag(LAY.sideD) - LAY.sideY - (y + 0.4 * size) - LAY.skillPad
return math.max(0, math.min(LAY.colW, 2 * half))
end
function S.rollTitle()
local roll = ACTIVATION.roll
local text = roll and roll.title or ""
local mod = roll and roll.mod ~= "" and roll.mod or nil
local full = mod and text .. " " .. mod or text
local lo, hi = 1, math.min(LAY.labelFont * LAY.skillScale, LAY.skillBand / 1.2)
local function fits(sz) return textWidth(full, sz, true) <= rowWidth(LAY.skillY, sz) * FIT end
if fits(hi) then lo = hi else
for _ = 1, 20 do
local mid = (lo + hi) / 2
if fits(mid) then lo = mid else hi = mid end
end
end
local t = { text = text, size = lo, w = math.max(1, rowWidth(LAY.skillY, lo)), x = 0,
mod = mod or "", modInk = roll and roll.modInk or COL.accent, mx = 0 }
if mod then
local all = textWidth(full, lo, true)
t.x = (textWidth(text, lo, true) - all) / 2
t.mx = (all - textWidth(mod, lo, true)) / 2
end
return t
end
function S.coverBy()
if ACTIVATION.asksPair() then return ACTIVATION.nerve.coverBy end
return ACTIVATION.questioning() and ACTIVATION.nerve.item or nil
end
function S.targetTitle(v)
local tg = v and v.target or {}
local by = S.coverBy()
if by then tg = { text = by, ink = COL.valueMod } end
local text = tg.text or ""
local art = hasAsset("target_mark") and not by
local k = art and (tonumber(CFG.targetIcon) or 1) or 0
local g = art and (tonumber(CFG.targetGap) or 0.3) or 0
local lo, hi = 1, LAY.skillBand * (tonumber(CFG.targetFill) or 1)
local function fits(sz) return textWidth(text, sz, true) + 2 * (k + g) * sz <= rowWidth(LAY.skillY, sz) * FIT end
if fits(hi) then lo = hi else
for _ = 1, 20 do
local mid = (lo + hi) / 2
if fits(mid) then lo = mid else hi = mid end
end
end
local d = math.min(k * lo, LAY.skillBand)
return { text = text, ink = tg.ink or COL.accent, size = lo, w = math.max(1, rowWidth(LAY.skillY, lo)),
icon = art, d = math.max(1, d), ix = textWidth(text, lo, true) / 2 + g * lo + d / 2 }
end
S.TARGET_MARKS = { { "targetMarkL", -1 }, { "targetMarkR", 1 } }
function S.titleFits(text)
local sz = math.min(LAY.labelFont * LAY.skillScale, LAY.skillBand / 1.2)
return textWidth(text, sz, true) <= rowWidth(LAY.skillY, sz) * FIT
end
function S.layout(items)
if #items == 0 then return { rows = {} } end
local band, top, space = LAY.skillBand, LAY.skillY + LAY.skillBand / 2, LAY.skillSpace
local std = LAY.labelFont * LAY.skillScale
local function wide(it, size) return textWidth(S.room(it), size, true) end
local function pack(n, size)
local h, rows, r = band / n, {}, 1
for k = 1, n do
local y = top - (k - 0.5) * h
rows[k] = { y = y, h = h, items = {}, room = rowWidth(y, size) * FIT, used = 0 }
end
for _, it in ipairs(items) do
local w = wide(it, size)
while rows[r] and #rows[r].items > 0 and rows[r].used + space * size + w > rows[r].room do r = r + 1 end
local row = rows[r]
if not row or w > row.room then return nil end
row.used = row.used + w + (#row.items > 0 and space * size or 0)
row.items[#row.items + 1] = it
end
local out = {}
for _, row in ipairs(rows) do if #row.items > 0 then out[#out + 1] = row end end
return out
end
local function best(n)
local hi = math.min(std, band / n / LAY.skillLeading)
local rows = pack(n, hi)
if rows then return hi, rows end
local lo = 0
for _ = 1, 24 do
local mid = (lo + hi) / 2
if pack(n, mid) then lo = mid else hi = mid end
end
return lo, pack(n, lo)
end
local size, rows = 0, nil
for n = 1, math.min(LAY.skillRows, #items) do
local s, r = best(n)
if r and #r == n and s > size + 0.01 then size, rows = s, r end
end
rows = rows or {}
local function used(row, sz)
local u = 0
for k, it in ipairs(row.items) do u = u + wide(it, sz) + (k > 1 and space * sz or 0) end
return u
end
local function fits(row, sz) return used(row, sz) <= rowWidth(row.y, sz) * FIT end
local smallest = math.huge
for _, row in ipairs(rows) do
local lo, hi = size, math.min(std, row.h / LAY.skillLeading)
if fits(row, hi) then lo = hi end
for _ = 1, 20 do
if hi - lo < 0.05 then break end
local mid = (lo + hi) / 2
if fits(row, mid) then lo = mid else hi = mid end
end
row.size, smallest = lo, math.min(smallest, lo)
end
for _, row in ipairs(rows) do
if LAY.skillEven then row.size = smallest end
local sz = row.size
local x = -used(row, sz) / 2
for k, it in ipairs(row.items) do
if k > 1 then x = x + space * sz end
local w = wide(it, sz)
it.x, it.w, x = x + w / 2, w, x + w
end
end
return { rows = rows }
end
local function stateXml(key, items, prefix, ink, buttons, on)
local parts, by = {}, LAY.skillY
for _, row in ipairs(S.layout(items).rows) do
local size = row.size
local space, mark = LAY.skillSpace * size, LAY.skillMark * size
local y = row.y - by
for k, it in ipairs(row.items) do
parts[#parts + 1] = textXml{ id = prefix .. it.bar, x = it.x, y = y, w = it.w / FIT, h = row.h,
text = S.label(it), size = size, color = ink(it), extra = ' raycastTarget="false"' }
if k > 1 and mark > 0 then
parts[#parts + 1] = string.format(
'<Image rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' rotation="0 0 45" color="%s" raycastTarget="false" />',
xyAttr(it.x - it.w / 2 - space / 2, y), mark, mark, COL.profileEdge)
end
if buttons then
parts[#parts + 1] = string.format(
'<Button id="skillBtn_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onMouseEnter="onSkillEnter" onMouseExit="onSkillExit"' ..
' onClick="onBarClick" />',
it.bar, xyAttr(it.x, y), it.w + space, row.h, COL.clear, COL.clear, COL.clear, COL.clear)
end
end
end
return string.format(
'<Panel id="skillState_%s" active="%s" rectAlignment="MiddleCenter" width="%g" height="%.1f"' ..
' color="%s" raycastTarget="false">%s</Panel>',
key, tostring(on), LAY.colW, LAY.skillBand, COL.clear, table.concat(parts))
end
function S.barXml()
local owned, shown = S.owned(), S.state(nil)
local title = S.rollTitle()
local states = { string.format('<Panel id="skillState_roll" active="%s" rectAlignment="MiddleCenter" width="%g"' ..
' height="%.1f" color="%s" raycastTarget="false">', tostring(shown == "roll"), LAY.colW, LAY.skillBand, COL.clear) ..
textXml{ id = "rollTitle", x = title.x, y = 0, w = title.w, h = LAY.skillBand, text = title.text, color = COL.accent,
size = title.size, extra = ' raycastTarget="false"' } ..
textXml{ id = "rollTitleMod", x = title.mx, y = 0, w = title.w, h = LAY.skillBand, text = title.mod,
color = title.modInk, size = title.size,
extra = string.format(' active="%s" raycastTarget="false"', tostring(title.mod ~= "")) } .. '</Panel>' }
local tt = S.targetTitle(nil)
local marks = {}
for _, m in ipairs(tt.icon and S.TARGET_MARKS or {}) do
marks[#marks + 1] = string.format('<Image id="%s" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" image="target_mark" color="%s" raycastTarget="false" />', m[1], xyAttr(m[2] * tt.ix, 0),
tt.d, tt.d, tt.ink)
end
states[#states + 1] = string.format('<Panel id="skillState_target" active="false" rectAlignment="MiddleCenter"' ..
' width="%g" height="%.1f" color="%s" raycastTarget="false">', LAY.colW, LAY.skillBand, COL.clear) ..
textXml{ id = "targetTitle", x = 0, y = 0, w = tt.w, h = LAY.skillBand, text = "", color = tt.ink,
size = tt.size, extra = ' raycastTarget="false"' } .. table.concat(marks) .. '</Panel>'
for state = 1, #S.KINDS do
local items = {}
for _, it in ipairs(state == 1 and S.listed() or owned) do
if it.state == state then items[#items + 1] = it end
end
states[#states + 1] = stateXml(state, items, "skillTxt_", S.ink, true, state == shown)
end
S.fxStates = {}
local stats, seen = {}, {}
for _, list in ipairs({ CFG.statOrder, CFG.statOrderHover }) do
for _, k in ipairs(list) do if not seen[k] then seen[k], stats[#stats + 1] = true, k end end
end
for _, stat in ipairs(stats) do
for _, gearOnly in ipairs({ false, true }) do
local key = S.fxKey(stat, gearOnly)
if key and not S.fxStates[key] then
local items = {}
for i, it in ipairs(S.fxItems(stat, gearOnly, owned)) do
local copy = {}
for k2, v2 in pairs(it) do copy[k2] = v2 end
items[i] = copy
end
S.fxStates[key], S.fxStates[#S.fxStates + 1] = stat, key
states[#states + 1] = stateXml(key, items, "skillFx_" .. key .. "_", function(it)
return S.fxInk(it, stat)
end, false, false)
end
end
end
return string.format(
'<Panel id="skillBar" rectAlignment="MiddleCenter" offsetXY="0 %.1f" width="%g" height="%.1f" color="%s"' ..
' onMouseEnter="onBarEnter" onMouseExit="onBarExit">' ..
'<Button id="skillBarHit" rectAlignment="MiddleCenter" width="%g" height="%.1f" colors="%s|%s|%s|%s"' ..
' onMouseEnter="onBarEnter" onClick="onBarClick" />%s</Panel>',
LAY.skillY, LAY.colW, LAY.skillBand, COL.clear, LAY.colW, LAY.skillBand,
COL.clear, COL.clear, COL.clear, COL.clear, table.concat(states))
end
function S.wrap(text, w, size)
local lines = {}
for para in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
local line = nil
for word in para:gmatch("%S+") do
local next = line and (line .. " " .. word) or word
if line and textWidth(next, size, true) > w * FIT then
lines[#lines + 1], line = line, word
else
line = next
end
end
if line then lines[#lines + 1] = line end
end
return lines
end
function S.infoXml(id, it)
local W, H = ACTIVATION.geometry(0)
local pad, df = LAY.skillInfoPad, LAY.skillInfoFont
local tw = 2 * (LAY.sideX - halfDiag(LAY.sideD)) - 2 * pad
local titleH = LAY.midTitleFont * 1.25
local desc = trimText(it.desc)
local lines = {}
if desc ~= "" then
repeat
lines = S.wrap(desc, tw, df)
if #lines * df * 1.25 <= H - 2 * pad - titleH or df <= 8 then break end
df = df - 1
until false
end
local lineH = df * 1.25
local top = (titleH + #lines * lineH) / 2
local parts = { textXml{ w = tw, h = titleH, x = 0, y = top - titleH / 2, text = it.name, color = COL.accent,
size = fitSize(it.name, tw, titleH, LAY.midTitleFont, true), extra = ' raycastTarget="false"' } }
for k, l in ipairs(lines) do
parts[#parts + 1] = textXml{ w = tw, h = lineH, x = 0, y = top - titleH - (k - 0.5) * lineH, text = l,
color = COL.popupText, size = fitSize(l, tw, lineH, df, true), extra = ' raycastTarget="false"' }
end
return string.format(
'<Panel id="%s" active="false" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' color="%s" raycastTarget="false">%s</Panel>',
id, W, H, COL.statPlate:sub(1, 7) .. "ff", table.concat(parts))
end
function S.infosXml()
local out, ids = {}, {}
local function add(id, it) out[#out + 1], ids[#ids + 1] = S.infoXml(id, it), id end
for i, it in ipairs((S.split())) do add("skillInfo_" .. i, it) end
for i, c in ipairs(CONDITIONS) do add("condInfo_" .. i, { name = c.label, desc = c.desc }) end
for i, a in ipairs(ACTIONS) do
if trimText(a.desc) ~= "" then add("actInfo_" .. i, { name = a.label, desc = a.desc }) end
end
S.infoIds = ids
return table.concat(out)
end
end
local mixColor, PANELS
do
ui.flyoutBgs = {}
local function flyoutPanel(id, x, w, h, inner, y)
y = y or 0
local inward = x > 0 and LAY.sideX or -LAY.sideX
local left = math.min(x - w / 2, inward)
local right = math.max(x + w / 2, inward)
ui.flyoutBgs[#ui.flyoutBgs + 1] = string.format(
'<Image id="%sBg" active="false" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%.1f" height="%.1f" color="%s" raycastTarget="false" />',
id, xyAttr((left + right) / 2, y), right - left, h, COL.popupBg)
return string.format(
'<Panel id="%s" active="false" rectAlignment="MiddleCenter" offsetXY="%.1f %.1f"' ..
' width="%.1f" height="%.1f" color="%s" onMouseEnter="onFlyoutEnter"' ..
' onMouseExit="onFlyoutExit">%s</Panel>',
id, x, y, w, h, COL.clear, inner)
end
function ui.statusSpots()
local hd = halfDiag(LAY.statusD)
local cx = -LAY.statusX - hd
local spots = { { cx, hd }, { cx - hd, 0 }, { cx, -hd } }
local at, k = {}, 0
for _, s in ipairs(STATUSES) do
if s.key ~= fighter.status then
k = k + 1
at[s.key] = spots[k]
end
end
return at
end
function ui.statusIconsXml()
local parts = {}
for _, s in ipairs(STATUSES) do
parts[#parts + 1] = iconXml{ id = "statusIcon_" .. s.key, x = 0, y = 0,
d = LAY.sideD * LAY.iconPad, icon = "status_" .. s.key, label = s.short,
labelSize = LAY.diamondLabel(s.short, LAY.sideD), labelD = LAY.sideD,
active = s.key == fighter.status }
end
return table.concat(parts)
end
function ui.statusPickerXml()
local at, parts = ui.statusSpots(), {}
for _, s in ipairs(STATUSES) do
local p = at[s.key]
parts[#parts + 1] = string.format(
'<Panel id="statusOptBox_%s" active="%s" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%d" height="%d" color="%s" raycastTarget="false">',
s.key, tostring(p ~= nil), xyAttr(p and p[1] or 0, p and p[2] or 0),
LAY.statusD, LAY.statusD, COL.clear)
parts[#parts + 1] = diamond{
id = "statusOpt_" .. s.key, size = LAY.statusD, x = 0, y = 0,
icon = "status_" .. s.key, label = s.short, frame = "diamond_frame",
labelSize = LAY.diamondLabel(s.short, LAY.statusD), labelD = LAY.statusD,
bgColor = ui.statusFill(s), labelColor = COL.statusInk,
onClick = "onPickStatus", onEnter = "onFlyoutEnter", onExit = "onFlyoutExit",
}
parts[#parts + 1] = "</Panel>"
end
return string.format(
'<Panel id="statusPick" active="false" rectAlignment="MiddleCenter" width="%d"' ..
' height="%d" color="%s" raycastTarget="false">%s</Panel>',
LAY.cardW, LAY.cardH, COL.clear, table.concat(parts))
end
local function toggleLook(on)
if on then return COL.toggleOn, COL.toggleTextOn end
return COL.toggleOff, COL.toggleTextOff
end
function SKILL.costOf(a)
if fighter.freeStrike and fighter.activation == "active" and (a.key == "fight" or a.key == "coup_de_grace") then
return "F"
end
local arm = a.key == "braced_shot" and ACTIVATION.extraArm()
if arm and arm.cost then return arm.cost end
local g = CFG.palaniteGang
if type(g) == "table" and type(g.costs) == "table" and a.key and g.costs[a.key]
and (not g.status or g.status == fighter.status) and ACTIVATION.gangIs(g) then
return g.costs[a.key]
end
for _, d in ipairs(SKILL.with("costs")) do
if a.key and d.costs[a.key] then return d.costs[a.key] end
end
return a.cost
end
function SKILL.cost(a)
local c = tostring(SKILL.costOf(a) or ""):sub(1, 1)
return c == "D" and 2 or c == "F" and 0 or 1
end
local function actionDimmed(a)
if a.once and (fighter.usedOnce or {})[a.key] then return true end
if ACTIVATION.armBlocks(a.key) then return true end
if a.type == "wyrd" and fighter.activation == "active" and (fighter.wyrd or {}).locked then return true end
if a.roll or a.always or fighter.activation ~= "active" then return false end
return fighter.usedActions[a.key] == true or SKILL.cost(a) > fighter.actionsLeft
end
function SKILL.shownLabel(a)
local mod = 0
if a.key == "coup_de_grace" then mod = ACTIVATION.gangMod(CFG.coupGang)
elseif a.roll == "agility" then
local rr = ACTIVATION.AGILITY_RR[ACTIVATION.agilityReroll() or ""]
local am = ACTIVATION.agilityMod()
local parts = {}
if rr then parts[#parts + 1] = rr end
if am ~= 0 then parts[#parts + 1] = string.format("%+d", am) end
if #parts > 0 then return string.format("%s (%s)", a.label, table.concat(parts, ", ")) end
end
if mod ~= 0 then return string.format("%s (%+d)", a.label, mod) end
return a.label
end
local function actionState(a) return false, SKILL.shownLabel(a), ACTION_TYPES[a.type or ""], actionDimmed(a) end
local function conditionState(c) return conditionCount(c.key) > 0, conditionLabel(c) end
function mixColor(a, b, k)
local function ch(hex, i) return tonumber(hex:sub(i, i + 1), 16) end
local out = "#"
for i = 2, 6, 2 do out = out .. string.format("%02X", math.floor(ch(a, i) + (ch(b, i) - ch(a, i)) * k + 0.5)) end
return out .. (#a >= 9 and a:sub(8, 9) or "ff")
end
function ACTIVATION.litColor(col)
return hasAsset("diamond") and col or mixColor(col, "#000000ff", 0.45)
end
function ui.gradTint(col)
if not hasAsset("diamond") then return col end
local k, out = tonumber(CFG.diamondDepth) or 1, "#"
for i = 2, 6, 2 do
out = out .. string.format("%02X", math.min(255, math.floor(tonumber(col:sub(i, i + 1), 16) * k + 0.5)))
end
return out .. (#col >= 9 and col:sub(8, 9) or "ff")
end
function ui.actionLit(spent)
local c = statusDef(fighter.status).color:sub(1, 7) .. "ff"
if spent then c = mixColor(c, "#000000ff", clamp(tonumber(CFG.spendShade) or 0.55, 0, 1)) end
return ACTIVATION.litColor(c)
end
function ACTIVATION.readyLook(n)
if n == 1 and fighter.lostAction and fighter.activation == "active" and fighter.actionsLeft < 2 then
local c = statusDef("suppressed").color:sub(1, 7) .. "ff"
return true, mixColor(c, "#000000ff", clamp(tonumber(CFG.spendShade) or 0.55, 0, 1))
end
return fighter.actionsLeft >= 3 - n, nil
end
function ui.statusFill(s) return s.color:sub(1, 7) .. "ff" end
function ui.entryLook(P, e, key)
local on, label, tint, dim = P.state(e, key)
local fill, ink = toggleLook(on)
fill = tint or fill
local costInk = COL.actCost
if dim then
fill, ink, costInk = mixColor(fill, COL.popupBg, 0.6), COL.actDimInk, COL.actDimInk
end
return { label = label, fill = fill, ink = ink, costInk = costInk }
end
PANELS = {}
function ui.actionPanelOf(status) return "act_" .. status end
RULES.follow(function()
for _, s in ipairs(STATUSES) do
local cols, list, spots = STATUS_ACTIONS[s.key] or {}, {}, {}
for c, side in ipairs({ "right", "left" }) do
local keys = {}
for _, key in ipairs(cols[side] or {}) do
if indexOf(ACTIONS, key) then keys[#keys + 1] = key end
end
for r, key in ipairs(keys) do
list[#list + 1] = ACTIONS[indexOf(ACTIONS, key)]
spots[#list] = { c = c, r = r - 1, n = #keys }
end
end
PANELS[ui.actionPanelOf(s.key)] = { id = "actionsPanel_" .. s.key, list = list, spots = spots,
w = LAY.popS.actionW, state = actionState, onClick = "onChooseAction", status = s.key }
end
local rows, spots, conds = math.max(1, LAY.popS.condRows or LAY.popS.panelRows), {}, {}
for _, c in ipairs(CONDITIONS) do
if not c.auto then conds[#conds + 1] = c end
end
for i = 1, #conds do
local c = math.floor((i - 1) / rows) + 1
spots[i] = { c = c, r = (i - 1) % rows, n = math.min(rows, #conds - (c - 1) * rows) }
end
PANELS.cond = { id = "conditionsPanel", list = conds, spots = spots,
w = LAY.popS.entryW, icon = "cond_", state = conditionState,
onClick = "onToggleCondition" }
end)
function ui.panelLayout(prefix)
local P, S = PANELS[prefix], LAY.popS
local hd = halfDiag(LAY.sideD)
local rowH = 4 * hd / math.max(1, S.panelRows)
local gap = S.entryGap
local dd = rowH - gap
local x0 = -(LAY.sideX + hd) - S.gap
local function rowY(sp) return ((sp.n - 1) / 2 - sp.r) * rowH end
local over = 0
for _, sp in pairs(P.spots) do
local y = rowY(sp)
local d = math.abs(math.abs(y) - hd)
if sp.c == 1 and d < hd then
local edge = -(LAY.sideX + hd - d)
over = math.max(over, x0 + dd / 2 + gap / 2 - edge)
end
end
x0 = x0 - over
local cols, most = 1, 0
for _, sp in pairs(P.spots) do cols, most = math.max(cols, sp.c), math.max(most, sp.n) end
local colR = { x0 }
for c = 2, cols do colR[c] = colR[c - 1] - P.w - (c == 2 and 0 or dd / 2) - gap end
local cells, left, right = {}, x0, x0 + dd / 2
for i = 1, #P.list do
local sp = P.spots[i]
local c = sp.c
local xr = colR[c]
local xl = xr - P.w
local cell = { x = (xl + xr) / 2, y = rowY(sp), w = P.w, h = dd, dd = dd }
if c == 1 then
cell.dx = xr
cell.textL, cell.textR = xl + S.boxPad, xr - dd / 2
cell.hitL, cell.hitR = xl, xr - dd / 2
else
cell.dx = xl
cell.textL, cell.textR = xl + dd / 2, xr - S.boxPad
cell.hitL, cell.hitR = xl + dd / 2, xr
end
cell.textX, cell.textW = (cell.textL + cell.textR) / 2, cell.textR - cell.textL
left = math.min(left, c == 1 and xl or xl - dd / 2)
cells[i] = cell
end
return cells, left - S.pad, right, most * rowH / 2 + S.pad
end
SKILL.ROLLS = {
{ key = "roll_dice", label = "Roll Dice", cost = "D6", roll = "d6" },
{ key = "roll_firepower", label = "Roll Firepower", cost = "FP", roll = "firepower" },
{ key = "roll_injuries", label = "Roll Injuries", cost = "INJ", roll = "injury" },
{ key = "agility_test", label = "Agility Test", cost = "AT", roll = "agility" },
{ key = "falling_down", label = "Falling Down", cost = "FD", roll = "fall" },
{ key = "nerve_check", label = "Nerve Check", cost = "NC", roll = "nerve" },
{ key = "recovery_roll", label = "Recovery Test", cost = "RT", roll = "recovery" },
{ key = "out_of_action", label = "Out of Action", cost = "†", roll = "out", icon = "dice_out" },
}
function SKILL.special(status)
if (status or fighter.status) == "seriously_injured" then return "act_spsi" end
if status == nil and SKILL.off() then return SKILL.gearActs() and "act_spw" or "act_spsi" end
return "act_sp"
end
SKILL.SPECIALS = { act_sp = "actionsPanel_sp", act_spw = "actionsPanel_spw", act_spsi = "actionsPanel_spsi" }
SKILL.SPECIAL_ORDER = { "act_sp", "act_spw", "act_spsi" }
function SKILL.stillWorks(a) return a.kind == "wargear" or a.type == "wyrd" end
function SKILL.gearActs()
local _, acts = SKILL.split()
for _, a in ipairs(acts) do if SKILL.stillWorks(a) then return true end end
return SKILL.wyrdActs()
end
function SKILL.wyrdActs() return fighter.category == "wyrd" or SKILL.hasWyrd() end
function SKILL.specialList(prefix)
prefix = prefix or SKILL.special()
local _, acts = SKILL.split()
local list, spots, rows = {}, {}, math.max(1, LAY.popS.specialRows or 6)
for k, r in ipairs(SKILL.ROLLS) do list[k], spots[k] = r, { c = 1, r = k - 1, n = #SKILL.ROLLS } end
local group = {}
if prefix == "act_spsi" then return list, spots end
if SKILL.wyrdActs() then
for _, a in ipairs(ACTIONS) do if a.wyrd then group[#group + 1] = a end end
end
for _, a in ipairs(acts) do
if (prefix == "act_sp" or SKILL.stillWorks(a)) and SKILL.inStatus(a) then group[#group + 1] = a end
end
for i, a in ipairs(group) do
local c = math.floor((i - 1) / rows)
list[#list + 1] = a
spots[#list] = { c = 2 + c, r = (i - 1) % rows, n = math.min(rows, #group - c * rows) }
end
return list, spots
end
function SKILL.inStatus(a, status)
if type(a.statuses) ~= "table" then return true end
status = status or fighter.status
for _, s in ipairs(a.statuses) do if s == status then return true end end
return false
end
function SKILL.statusSig()
local _, acts = SKILL.split()
local t = {}
for _, a in ipairs(acts) do
if type(a.statuses) == "table" and SKILL.inStatus(a) then t[#t + 1] = a.key end
end
return table.concat(t, ",")
end
function SKILL.panels()
SKILL.builtStatus = SKILL.statusSig()
for prefix, id in pairs(SKILL.SPECIALS) do
if prefix == "act_spw" and not SKILL.gearActs() then
PANELS[prefix] = nil
else
local list, spots = SKILL.specialList(prefix)
PANELS[prefix] = { id = id, list = list, spots = spots, w = LAY.popS.actionW,
state = actionState, onClick = "onChooseAction", special = true }
end
end
end
function SKILL.entryInfo(prefix, i)
local P = PANELS[prefix]
local e = P and P.list[i]
if not e then return nil end
if prefix == "cond" then return trimText(e.desc) ~= "" and "condInfo_" .. i or nil end
local n = indexOf(ACTIONS, e.key)
if n and ACTIONS[n] == e then return trimText(e.desc) ~= "" and "actInfo_" .. n or nil end
if P.special and not e.roll then
for k, it in ipairs((SKILL.split())) do
if it.action and it.key == e.key then return trimText(it.desc) ~= "" and "skillInfo_" .. k or nil end
end
end
return nil
end
function SKILL.mindStats(prefix, i)
local P = prefix ~= "cond" and PANELS[prefix] or nil
local e = P and P.list[i]
return e ~= nil and (e.type == "wyrd" or e.type == "utility" or e.roll == "nerve")
end
function SKILL.action(key)
for _, a in ipairs((SKILL.specialList())) do
if a.key == key and not a.roll then return a end
end
end
function SKILL.tabs(prefix)
local P = PANELS[prefix]
if not (P and (P.status or P.special) and PANELS[SKILL.special()]) then return nil end
local cells, _, _, half = ui.panelLayout(prefix)
local r1 = -(LAY.sideX + halfDiag(LAY.sideD))
for i, sp in ipairs(P.spots) do if sp.c == 1 then r1 = cells[i].dx break end end
local w, gap, th = P.w, LAY.popS.entryGap, LAY.popS.tabH
local l2 = r1 - 2 * w - gap
return { active = P.special and 2 or 1, base = half,
{ xl = r1 - w, xr = r1 - th, side = 1 },
{ xl = l2 + th, xr = l2 + w, side = -1 } }
end
function ui.panelXml(prefix)
local P, S = PANELS[prefix], LAY.popS
local cells, left, right, half = ui.panelLayout(prefix)
local tabs = SKILL.tabs(prefix)
local top = tabs and tabs.base + S.tabH + S.pad or half
if tabs then
left = math.min(left, tabs[2].xl - S.tabH - S.pad)
right = math.max(right, tabs[1].xr + S.tabH)
end
local cx, cy = (left + right) / 2, (top - half) / 2
local b = S.border
local parts = {}
local function img(id, x, y, w, h, color, rot, image)
parts[#parts + 1] = string.format(
'<Image%s rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"%s' ..
' color="%s"%s raycastTarget="false" />', id and string.format(' id="%s"', id) or "",
xyAttr(x - cx, y - cy), w, h, rot and ' rotation="0 0 45"' or "", color, imgAttr(image))
end
local tipX = -(LAY.sideX + halfDiag(LAY.sideD))
local cover = COL.popupBg:sub(1, 7) .. "ff"
img(nil, (left + tipX) / 2, cy, tipX - left, top + half, cover)
local hdN = math.min(halfDiag(LAY.sideD), half)
img(nil, tipX + halfDiag(LAY.sideD) - hdN, 0, hdN * math.sqrt(2), hdN * math.sqrt(2), cover, true)
if tabs then
local th, bot = S.tabH, tabs.base
for t, name in ipairs({ "Generic", "Special" }) do
local T, on = tabs[t], t == tabs.active
local fill = on and COL.toggleOn or COL.toggleOff
local w, tip = T.xr - T.xl, T.side > 0 and T.xr or T.xl
local out, far = T.side, T.side > 0 and T.xl or T.xr
img(prefix .. "Tab_" .. t, (T.xl + T.xr) / 2, bot + th / 2, w, th, fill)
img(prefix .. "TabTip_" .. t, tip, bot, th * math.sqrt(2), th * math.sqrt(2), fill, true)
img(nil, tip, bot - th / 2, 2 * th, th, cover)
local k = b / 2 / math.sqrt(2)
parts[#parts + 1] = edgeLineXml((T.xl + T.xr) / 2 - cx, bot + th - b / 2 - cy, w, b, 0, COL.profileEdge)
.. edgeLineXml(far - out * b / 2 - cx, bot + th / 2 - cy, th, b, 90, COL.profileEdge)
.. edgeLineXml((T.xl + T.xr) / 2 + out * th / 2 - cx, bot + b / 2 - cy, w + th, b, 0, COL.profileEdge)
.. edgeLineXml(tip + out * (th / 2 - k) - cx, bot + th / 2 - k - cy, th * math.sqrt(2), b,
-45 * out, COL.profileEdge)
parts[#parts + 1] = textXml{ id = prefix .. "TabTxt_" .. t, x = (T.xl + T.xr) / 2 - cx,
y = bot + th / 2 - cy, w = w - 2 * S.boxPad, h = th, text = name,
color = on and COL.toggleTextOn or COL.actDimInk,
size = fitSize(name, w - 2 * S.boxPad, th, S.tabFont, true) }
parts[#parts + 1] = string.format(
'<Button id="%sTabBtn_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="onActionTab" />', prefix, t,
xyAttr((T.xl + T.xr) / 2 - cx, bot + th / 2 - cy), w, th, COL.clear,
on and COL.clear or COL.hover, on and COL.clear or COL.press, COL.clear)
end
end
for i, e in ipairs(P.list) do
local c = cells[i]
local look = ui.entryLook(P, e)
local label, fill, ink = look.label, look.fill, look.ink
local side = c.dd / math.sqrt(2)
local farX = c.dx > c.x and b / 2 or -b / 2
local lines = hasAsset("edge_line")
if not lines then img(nil, c.x, c.y, c.w, c.h, COL.profileEdge) end
img(prefix .. "Bg_" .. i, c.x + farX, c.y, c.w - b, c.h - 2 * b, fill, nil, "hp_segment")
if lines then
parts[#parts + 1] = edgeFrameXml(c.x - cx, c.y - cy, c.w, c.h, b, COL.profileEdge, 0,
c.dx > c.x and "right" or "left")
else
img(nil, c.dx, c.y, side, side, COL.profileEdge, true)
end
img(prefix .. "Dia_" .. i, c.dx, c.y, side - 2 * b, side - 2 * b, fill, true)
if lines then parts[#parts + 1] = edgeFrameXml(c.dx - cx, c.y - cy, side, side, b, COL.profileEdge, 45) end
if P.icon then
parts[#parts + 1] = iconXml{ id = prefix .. "Icon_" .. i, x = c.dx - cx, y = c.y - cy,
d = c.dd / 2 * (S.condIconPad or S.iconPad), icon = P.icon .. e.key, label = e.short,
labelSize = S.btnFont }
else
local d, cost = c.dd * S.costPad, SKILL.costOf(e)
local art = e.icon and hasAsset(e.icon)
parts[#parts + 1] = textXml{ id = prefix .. "Cost_" .. i, x = c.dx - cx, y = c.y - cy,
w = d, h = d, text = art and "" or cost, color = look.costInk,
size = fitSize(cost, d, d, S.valueFont, true) }
if art then
parts[#parts + 1] = string.format('<Image id="%sCostIcon_%d" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%.1f" height="%.1f" image="%s" color="%s" raycastTarget="false" />',
prefix, i, xyAttr(c.dx - cx, c.y - cy), d, d, e.icon, statusDef("seriously_injured").color)
end
end
parts[#parts + 1] = textXml{ id = prefix .. "Txt_" .. i, x = c.textX - cx, y = c.y - cy,
w = c.textW, h = c.h, text = label, color = ink,
size = fitSize(label, c.textW, c.h, S.valueFont, true) }
parts[#parts + 1] = string.format(
'<Button id="%s_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="%s"%s />',
prefix, i, xyAttr((c.hitL + c.hitR) / 2 - cx, c.y - cy), c.hitR - c.hitL, c.h,
COL.clear, COL.hover, COL.press, COL.clear, P.onClick,
(SKILL.entryInfo(prefix, i) or SKILL.mindStats(prefix, i) or ACTIVATION.spender(e, P))
and ' onMouseEnter="onInfoEnter" onMouseExit="onInfoExit"' or "")
end
return flyoutPanel(P.id, cx, right - left, top + half, table.concat(parts), cy)
end
end
local hasTrait
do
local known, count = {}, 0
function hasTrait(p, pattern)
local traits = tostring(p.traits or "")
local key = traits .. "\0" .. pattern
local hit = known[key]
if hit ~= nil then return hit end
hit = (("," .. traits .. ","):lower():find(",%s*" .. pattern .. "%s*,")) ~= nil
if count > 4000 then known, count = {}, 0 end
known[key], count = hit, count + 1
return hit
end
end
local TRAIT = RULES.traits
local function isMelee(p) return hasTrait(p, TRAIT.melee) end
local function hasRapidFire(p) return not isMelee(p) and hasTrait(p, TRAIT.rapidFire) end
local WEAPON_TYPES = {
gun = "R", heavy = "RH", sidearm = "RL", melee = "M", melee_heavy = "MH", grenade = "G",
}
local function weaponType(weapon)
local profiles = (weapon and weapon.profiles) or {}
local function any(test)
for _, p in ipairs(profiles) do if test(p) then return true end end
return false
end
local function dash(v) return tostring(v or "-"):match("^%s*%-?%s*$") ~= nil end
if any(function(p) return hasTrait(p, TRAIT.light) end) then return "sidearm" end
if any(isMelee) then
return any(function(p) return hasTrait(p, TRAIT.heavy) end) and "melee_heavy" or "melee"
end
if any(function(p) return dash(p.SR) and not dash(p.LR) end) then return "grenade" end
if any(function(p) return hasTrait(p, TRAIT.heavy) end) then return "heavy" end
return "gun"
end
local function showsCol(p, key)
if key == "Am" then return not isMelee(p) end
if key == "D" then
local v = trimText(p.D)
return v ~= "" and v ~= "-"
end
return true
end
local function weaponCols(weapon)
local profiles, shown = (weapon and weapon.profiles) or {}, {}
for i, col in ipairs(PROFILE_COLS) do
shown[i] = #profiles == 0
for _, p in ipairs(profiles) do shown[i] = shown[i] or showsCol(p, col.key) end
end
return shown
end
local function profileMode(p)
if fighter.status == "engaged" and hasTrait(p, TRAIT.light) then return 1 end
return hasRapidFire(p) and indexOf(PROFILE_MODES, p.mode) or 1
end
local function profileDown(p) return p.ammo == "out" or p.ammo == "jam" or p.ammo == "spent" end
local TRAIT_RULES = { stabbing = {}, aiming = {}, volley = {}, support = {}, supportBy = {}, longShot = {},
reroll = {} }
do
local R = TRAIT_RULES
function R.number(p, name)
local n = ("," .. tostring(p.traits or "") .. ","):lower()
:match(",%s*" .. name .. "%s*%(%s*(%d+)%s*%)%s*,")
return tonumber(n)
end
function R.paired(p) return isMelee(p) and R.number(p, TRAIT.paired) or nil end
function R.lightFight(p)
return fighter.status == "engaged" and not isMelee(p) and hasTrait(p, TRAIT.light)
end
function R.aa(p)
if R.lightFight(p) then return nil end
return R.number(p, TRAIT.additional)
end
function R.aaOn(p)
if not R.aa(p) then return false end
local own = nil
for i = 1, weaponCount() do
local w = weaponAt(i)
for _, q in ipairs((w and w.profiles) or {}) do if q == p then own = w end end
end
for i = 1, weaponCount() do
local w = weaponAt(i)
if w and w ~= own then
for _, q in ipairs(w.profiles or {}) do if isMelee(q) then return true end end
end
end
return false
end
function R.extra(p) return isMelee(p) and R.number(p, TRAIT.additional) or nil end
function R.aaCharge(p) return isMelee(p) and R.aaOn(p) and R.number(p, TRAIT.additional) or nil end
function R.stab(p)
if not isMelee(p) then return 0 end
local own, skill = hasTrait(p, TRAIT.backstab), #SKILL.with("backstab") > 0
return (own and 1 or 0) + (skill and 1 or 0)
end
function R.backstab(p) return R.stab(p) > 0 end
function R.combi(p) return not isMelee(p) and hasTrait(p, TRAIT.combi) end
function R.extraShots(p) return not isMelee(p) and R.aaOn(p) and R.aa(p) or nil end
function R.limited(p)
return not isMelee(p) and (hasTrait(p, TRAIT.limited) or hasTrait(p, TRAIT.singleShot))
end
function R.steps(p)
local s = { "charge" }
if R.paired(p) then s[#s + 1] = "paired" end
if R.extra(p) then s[#s + 1] = "extra" end
return s
end
function R.step(p, v)
if v == nil then v = p.attacks end
local n = tonumber(v)
if n then return math.max(1, math.floor(n)) end
v = tostring(v or ""):lower():gsub("%s", "")
if (v == "paired" or v == "a+n") and R.paired(p) then return "paired" end
if (v == "extra" or v == "xn") and R.extra(p) then return "extra" end
return "charge"
end
function R.combiUp(w, skip)
local n = 0
for _, q in ipairs((w and w.profiles) or {}) do
if q ~= skip and R.combi(q) and not profileDown(q) then n = n + 1 end
end
return n
end
function R.held(w, p)
local v = R.volley[w]
return v ~= nil and R.combi(p) and not v.fired[p]
end
function R.fire(w, p, combi)
if not combi or fighter.activation ~= "active" then return end
if R.held(w, p) then R.volley[w].fired[p] = true return end
R.volley[w] = { fired = { [p] = true }, aimed = (R.aiming[w] and R.canAim(p)) or nil }
end
function R.ammoState(w, p)
if p.ammo == "combi" then
return (R.combi(p) and (R.combiUp(w) >= 2 or R.held(w, p))) and "combi" or "fine"
end
if p.ammo == "extra" then return R.extraShots(p) and "extra" or "fine" end
return p.ammo or "fine"
end
function R.ammoNext(w, p, right)
local now = R.ammoState(w, p)
local down = R.limited(p) and "spent" or (right and "jam" or "out")
if now == down then
if R.combi(p) and not right and R.combiUp(w, p) >= 1 then return "combi" end
if R.extraShots(p) and not right then return "extra" end
return "fine"
end
if (now == "combi" or now == "extra") and not right then return "fine" end
return down
end
function R.empties()
local out = {}
for i = 1, weaponCount() do
local w = weaponAt(i)
for pi, p in ipairs((w and w.profiles) or {}) do
if R.ammoState(w, p) == "out" then out[#out + 1] = { i = i, pi = pi, w = w, p = p } end
end
end
return out
end
RULES.follow(function() R.accIndex, R.names = nil, {} end)
function R.accessory(name)
local function key(s) return (tostring(s):lower():gsub("[^%w]", "")) end
if not R.accIndex then
R.accIndex = {}
for _, d in ipairs(RULES.accessories) do
for _, a in ipairs(type(d.aka) == "table" and d.aka or {}) do R.accIndex[key(a)] = d end
end
for _, d in ipairs(RULES.accessories) do R.accIndex[key(d.name)] = d end
end
return R.accIndex[key(name)]
end
function R.named(w)
local full = trimText(w and w.name or "")
local got = R.names[full]
if not got then
local acc = {}
local name = full:gsub("%s*%(([^()]*)%)", function(inside)
local keep, found = {}, false
for each in (inside .. ","):gmatch("([^,]*),") do
local item = trimText(each)
local d = R.accessory(item)
if d then
acc[#acc + 1], found = { name = SKILL.title(item), def = d }, true
elseif item ~= "" then
keep[#keep + 1] = item
end
end
if not found then return nil end
return #keep > 0 and " (" .. table.concat(keep, ", ") .. ")" or ""
end)
got = { name = trimText(name), acc = acc }
R.names[full] = got
end
return got.name, got.acc
end
function R.name(w)
local name = R.named(w)
return name ~= "" and name or "Weapon"
end
R.hitMax = 9
function R.hit(w)
local n = math.floor(tonumber(w and w.hit) or 0)
return math.max(-R.hitMax, math.min(R.hitMax, n))
end
function R.shownHit(w, p)
local n, combi = R.hit(w), false
for _, q in ipairs((w and w.profiles) or {}) do
if R.ammoState(w, q) == "combi" then n, combi = n - 1, true break end
end
if R.aiming[w] then n, combi = n + R.aimHit(w), false end
local support = p and isMelee(p) and w and R.support[w] or nil
n = n + (support or 0)
if p and R.longShot[p] then n = n + (select(3, R.marksman(p)) or 0) end
n = n + R.jumpHit(p, w)
return math.max(-R.hitMax, math.min(R.hitMax, n)), combi, support
end
function R.jumpHit(p, w)
local b = ACTIVATION.jumping()
if not b then return 0 end
if not (ACTIVATION.charged() or (p and R.charging(p, w))) then return 0 end
return math.floor(tonumber((b.charge or {}).hit) or 0)
end
function R.canAim(p) return not isMelee(p) and not hasTrait(p, TRAIT.heavy) and not R.template(p) end
function R.aimHit(w)
local n = 1
for _, it in ipairs(SKILL.with("aimed")) do n = math.max(n, math.floor(tonumber(it.aimed) or 1)) end
return math.max(n, R.sight(w) or 1)
end
function R.sight(w, name)
local best = nil
for _, a in ipairs(select(2, R.named(w))) do
local n = math.floor(tonumber(a.def.aimed) or 0)
if n > 0 and (name == nil or R.accessory(name) == a.def) then best = math.max(best or 0, n) end
end
return best
end
function R.mayAim(w, p)
if not R.canAim(p) then return false end
if fighter.activation ~= "active" or fighter.status == "engaged" or R.held(w, p) then return true end
return not fighter.usedActions.dash and #(fighter.shots or {}) == 0
end
function R.attackAction(w, p)
local key = R.fightsWith(p) and "fight" or hasTrait(p, TRAIT.heavy) and "braced_shot"
or (R.aiming[w] and R.canAim(p)) and "aimed_shot" or "shoot"
local volley = R.held(w, p) and R.ammoState(w, p) == "combi"
local _, free = R.shot(w, p)
return key, (R.aaOn(p) or volley or free) and 0 or nil, free
end
function R.usable(p, w)
if R.multi and not R.spreads(p) then return false end
local back = ACTIVATION.back
if back and back.state == "armed" then
return R.fightReady(p) and (not back.extra or R.aa(p) ~= nil)
end
if back and back.state == "striking" then return false end
if fighter.status == "seriously_injured" then return false end
if w and w.fromWyrd then
if not ACTIVATION.wyrdCan() then return false end
elseif w and (w.fromKind == "skill" or w.needs) and SKILL.off() then
return false
end
if fighter.status == "engaged" then
return R.fightReady(p) and R.fightUsable(w, p)
end
if isMelee(p) then return false end
return not w or (R.shot(w, p)) == true
end
function R.hitStat(p)
if isMelee(p) or (fighter.status == "engaged" and hasTrait(p, TRAIT.light)) then return "WS" end
return "BS"
end
function R.blocked(w)
if not (w and w.profiles and #w.profiles > 0) then return false end
for _, p in ipairs(w.profiles) do
if R.usable(p, w) then return false end
end
return true
end
R.VOLLEY_SHADE = 0.3
function R.glow(w)
if R.flammable(w) then return COL.wyrdInk end
if R.blocked(w) then return COL.weaponBlocked end
for _, p in ipairs((w and w.profiles) or {}) do
if R.held(w, p) and R.ammoState(w, p) == "combi" and R.usable(p, w) then
return mixColor(COL.ammoCombi:sub(1, 7) .. "ff", "#000000ff", R.VOLLEY_SHADE)
end
end
return nil
end
function R.assault(p)
if isMelee(p) then return false end
return hasTrait(p, TRAIT.assault) or (not hasTrait(p, TRAIT.heavy) and #SKILL.with("hipShooting") > 0)
end
function R.shoots()
local n = 1
for _, it in ipairs(SKILL.with("shoots")) do n = math.max(n, math.floor(tonumber(it.shoots) or 1)) end
return n
end
function R.gunfight()
if #SKILL.with("gunfighter") == 0 then return false end
for i = 1, weaponCount() do
if (weaponAt(i) or {}).gunfight then return true end
end
return false
end
function R.shot(w, p)
if fighter.activation ~= "active" or fighter.status == "engaged" or isMelee(p) then return true end
if R.aaOn(p) or (R.held(w, p) and R.ammoState(w, p) == "combi") then return true end
local plain = not hasTrait(p, TRAIT.heavy) and not R.aiming[w]
if ACTIVATION.armBlocks(hasTrait(p, TRAIT.heavy) and "braced_shot" or plain and "shoot" or "aimed_shot") then
return false
end
local dashed = fighter.usedActions.dash == true
if plain and hasTrait(p, TRAIT.light) and not w.gunfight and R.gunfight() then return true, "gunfighter" end
if plain and dashed and not fighter.assaulted and R.assault(p) then return true, "assault" end
if dashed then return false end
local shots = fighter.shots or {}
if #shots == 0 then return true end
if not plain or #shots >= R.shoots() then return false end
if fighter.actionsLeft <= 0 and (tonumber(fighter.shotsPaid) or 0) <= 0 then return false end
for _, key in ipairs(shots) do
if key ~= "shoot" then return false end
end
return true
end
function R.marksman(p)
if isMelee(p) or fighter.status == "engaged" then return nil end
local n = 0
for _, it in ipairs(SKILL.with("marksman")) do
n = math.max(n, it.marksman == true and 1 or tonumber(it.marksman) or 0)
end
if n <= 0 then return nil end
local function inches(key)
local t = R.parts(R.adjust(key, p[key] or "-", R.adjSteps(p, key)))
if not t or t.token then return nil end
return t.dash and 0 or t.num
end
local sr, lr = inches("SR"), inches("LR")
if not (sr and lr and lr > sr) then return nil end
return sr, lr, n
end
function R.slot(w)
for i = 1, weaponCount() do
if weaponAt(i) == w then return i end
end
return nil
end
function R.fightsWith(p)
return isMelee(p) or (fighter.status == "engaged" and hasTrait(p, TRAIT.light))
end
function R.fightReady(p)
return isMelee(p) or (hasTrait(p, TRAIT.light) and not profileDown(p))
end
function R.fightProfiles(w)
local out = {}
for _, p in ipairs((w and w.profiles) or {}) do
if isMelee(p) or hasTrait(p, TRAIT.light) then out[#out + 1] = p end
end
return out
end
function R.aaWeapon(w)
for _, p in ipairs((w and w.profiles) or {}) do
if isMelee(p) and R.number(p, TRAIT.additional) then return true end
end
return false
end
function R.declarable(w, melee)
if type(w) ~= "table" or R.aaWeapon(w) then return false end
for _, p in ipairs(R.fightProfiles(w)) do
if not melee or isMelee(p) then return true end
end
return false
end
function R.canSecond(w)
if not R.declarable(w) then return false end
for _, p in ipairs(R.fightProfiles(w)) do
if not hasTrait(p, TRAIT.heavy) and not R.paired(p) then return true end
end
return false
end
function R.allowsSecond(w, biceps)
if not w then return true end
local paired, heavy = true, true
for _, p in ipairs(R.fightProfiles(w)) do
paired = paired and R.paired(p) ~= nil
heavy = heavy and hasTrait(p, TRAIT.heavy)
end
if biceps == nil then biceps = #SKILL.with("biceps") > 0 end
return not paired and not (heavy and not biceps)
end
function R.declared(role)
for i = 1, weaponCount() do
local w = weaponAt(i)
if w and w.role == role then return w, i end
end
return nil
end
function R.roleScore(w)
local best = nil
for _, p in ipairs(R.fightProfiles(w)) do
local s = tostring(p.S or ""):gsub("%s", "")
local sv = tonumber(s:match("^[Ss]([%+%-]%d+)$") or (s:upper() == "S" and "0") or "")
sv = sv or ((tonumber(s) or 3) - 3)
local ap = math.abs(tonumber((tostring(p.AP or ""):gsub("%s", ""))) or 0)
local d = tonumber((tostring(p.D or ""):gsub("%s", ""))) or 1
local n = sv + ap + 2 * d + (isMelee(p) and 0 or -2) + (hasTrait(p, TRAIT.parry) and 0.5 or 0)
best = math.max(best or n, n)
end
return best or -99
end
function R.roles()
local list, prim, sec = R.allWeapons(fighter), nil, nil
for _, w in ipairs(list) do
if w.role == "primary" and R.declarable(w) and not prim then prim = w
elseif w.role == "secondary" and R.canSecond(w) and not sec then sec = w
else w.role = nil end
end
local function pick(test)
local best, score = nil, nil
for _, w in ipairs(list) do
if not w.role and test(w) then
local n = R.roleScore(w)
if not best or n > score then best, score = w, n end
end
end
return best
end
if not prim then
prim = pick(function(w) return R.declarable(w, true) and not R.canSecond(w) end)
or pick(function(w) return R.declarable(w, true) end)
or sec
or pick(function(w) return R.declarable(w) end)
if prim == sec then sec = nil end
if prim then prim.role = "primary" end
end
if sec and not R.allowsSecond(prim) then sec.role, sec = nil, nil end
if not sec and not fighter.rolesChosen and R.allowsSecond(prim) then
sec = pick(function(w) return R.declarable(w, true) and R.canSecond(w) end)
or pick(function(w) return R.canSecond(w) end)
if sec then sec.role = "secondary" end
end
end
function R.allWeapons(f)
local all = {}
for _, list in ipairs({ f.weapons or {}, f.moreWeapons or {} }) do
for i = 1, #list do if type(list[i]) == "table" then all[#all + 1] = list[i] end end
end
return all
end
function R.keepRoles(f, old)
if type(old) ~= "table" or old == f or old.name ~= f.name or not old.rolesChosen then return end
f.rolesChosen = true
local had = {}
for _, w in ipairs(R.allWeapons(old)) do
if w.role then
local k = tostring(w.name or "")
had[k] = had[k] or {}
table.insert(had[k], w.role)
end
end
for _, w in ipairs(R.allWeapons(f)) do
local k = tostring(w.name or "")
if not w.role and had[k] and #had[k] > 0 then w.role = table.remove(had[k], 1) end
end
end
function R.roleLocked()
local st = fighter.activation == "active" and fighter.fight
return (st and (st.primary or st.secondary)) and true or false
end
function R.defending()
return fighter.status == "engaged" and fighter.activation ~= "active"
end
function R.switchRole(slot)
local w = weaponAt(slot)
if fighter.status ~= "engaged" or R.roleLocked() or not R.declarable(w) then return false end
local prim, sec = R.declared("primary"), R.declared("secondary")
if w.role == "primary" then
if not sec or R.defending() then return false end
sec.role, w.role = "primary", nil
if R.canSecond(w) and R.allowsSecond(sec) then w.role = "secondary" end
elseif w.role == "secondary" or R.defending() or not (R.canSecond(w) and R.allowsSecond(prim)) then
if w.role ~= "secondary" and sec then sec.role = nil end
w.role = "primary"
if prim and prim ~= w then
prim.role = (R.canSecond(prim) and R.allowsSecond(w)) and "secondary" or nil
end
else
if sec then sec.role = nil end
w.role = "secondary"
end
fighter.rolesChosen = true
R.roles()
return true
end
function R.roleShown(w) return R.declarable(w) or R.aaWeapon(w) end
function R.roleLabel(w)
if type(w) ~= "table" or fighter.status ~= "engaged" then return nil end
if w.role == "primary" then return "PRI" end
if R.defending() then return nil end
if w.role == "secondary" then return "SEC" end
if R.aaWeapon(w) and R.declared("primary") then return "AA" end
return nil
end
function R.secondaryOk(w, p)
if type(w) ~= "table" or w.role ~= "secondary" then return false end
local st = fighter.fight or {}
if st.secondary then return false end
if R.aa(p) then return false end
if hasTrait(p, TRAIT.heavy) or R.paired(p) then return false end
if st.primary then
return not st.paired and (not st.heavy or #SKILL.with("biceps") > 0)
end
return R.allowsSecond((R.declared("primary")))
end
function R.fightUsable(w, p)
if fighter.activation ~= "active" or not w then return true end
local st = fighter.fight or {}
if R.aa(p) then return not (st.extra or {})[R.slot(w)] end
if st.done then return false end
if w.role == "primary" then return not st.primary end
return R.secondaryOk(w, p)
end
function R.fought(w, p)
if fighter.activation ~= "active" or not R.fightsWith(p) then return end
local slot = R.slot(w)
if not slot then return end
local st = fighter.fight or { round = 1 }
fighter.fight = st
if R.aa(p) then
st.extra = st.extra or {}
st.extra[slot] = true
elseif w.role == "primary" and not st.primary then
st.primary, st.heavy = slot, hasTrait(p, TRAIT.heavy) or nil
st.paired, st.charged = R.paired(p) and true or nil, R.charging(p, w) or nil
elseif w.role == "secondary" and not st.secondary then
st.secondary = slot
end
R.roundOver()
end
function R.roundOver()
local st = fighter.fight
if not st or st.done or not (st.primary or st.secondary) then return end
local left = false
for i = 1, weaponCount() do
local w = weaponAt(i)
for _, q in ipairs((w or {}).profiles or {}) do
if R.fightsWith(q) and R.fightReady(q) and not R.aa(q) then
left = left or (w.role == "primary" and not st.primary) or R.secondaryOk(w, q)
end
end
end
if left then return end
if st.round == 1 and fighter.status == "engaged" and #SKILL.with("rainOfBlows") > 0 then
fighter.fight = { round = 2 }
chat(string.format("%s fights on -- Rain Of Blows: a second round", fighter.name), rgbOf(COL.valueUp))
else
st.done = true
end
end
function R.opening(w, p)
if R.number(p, TRAIT.additional) then return nil end
if fighter.activation ~= "active" then
return #SKILL.with("counterAttack") > 0 and 2 or 1
end
if not R.secondaryOk(w, p) then return nil end
if hasTrait(p, TRAIT.light) then return 1 end
local n = 1
for _, it in ipairs(SKILL.with("secondary")) do
n = math.max(n, math.floor(tonumber(it.secondary) or 1))
end
return n
end
function R.endFight()
fighter.fight, fighter.freeStrike = nil, nil
for i = 1, weaponCount() do
if weaponAt(i) then weaponAt(i).fought = nil end
end
ui.drawStats()
TRAIT_RULES.drawWeapons()
end
function R.melee(w)
for _, p in ipairs((w and w.profiles) or {}) do
if isMelee(p) then return true end
end
return false
end
function R.flammable(w)
local wy = fighter.wyrd
return type(wy) == "table" and wy.choosing == true and wy.power ~= nil and R.melee(w)
end
function R.warpL(p)
local n = 0
if not isMelee(p) then return n end
for _, it in ipairs(SKILL.with("meleeL")) do
if SKILL.live(it) then n = n + (tonumber(it.meleeL) or 0) end
end
return n
end
function R.blows(p)
local n = 0
if not isMelee(p) then return n end
for _, it in ipairs(SKILL.with("meleeS")) do
for trait, add in pairs(it.meleeS) do
if TRAIT[trait] and hasTrait(p, TRAIT[trait]) then n = n + (tonumber(add) or 0) end
end
end
return n
end
R.ADJ = {
SR = { min = 0, tokens = false }, LR = { min = 0, tokens = false },
S = { min = 1 }, AP = { lower = true, mod = true }, L = { min = 0 },
D = { min = 0 }, Am = { lower = true, min = 2, max = 6 },
}
function R.parts(v)
local s = trimText(v)
if s == "" or s == "-" then return { dash = true } end
local sign, n, rest = s:match("^([%+%-]?)(%d+)(.*)$")
if n then return { num = tonumber(n) * (sign == "-" and -1 or 1), suffix = rest } end
local tok, sg, m = s:match("^(%a%w*)%s*([%+%-])%s*(%d+)$")
if tok then return { token = tok, num = tonumber(m) * (sg == "-" and -1 or 1) } end
tok = s:match("^(%a%w*)$")
if tok then return { token = tok, num = 0 } end
return nil
end
function R.adjustable(p, key)
local a, v = R.ADJ[key], R.parts(p[key])
if not (a and v) then return false end
if v.dash then return a.mod == true end
return not (v.token and a.tokens == false)
end
function R.adjust(key, v, steps)
local a, t = R.ADJ[key], R.parts(v)
if not (a and t) or steps == 0 or (t.dash and not a.mod) or (t.token and a.tokens == false) then
return tostring(v or "-")
end
local n = (t.num or 0) + steps * (a.lower and -1 or 1)
if not t.token then n = math.max(a.min or -math.huge, math.min(a.max or math.huge, n)) end
if t.token then return t.token .. (n > 0 and "+" .. n or n < 0 and tostring(n) or "") end
if a.mod or t.dash then return n == 0 and "-" or string.format("%+d", n) end
return tostring(n) .. (t.suffix or "")
end
function R.adjSteps(p, key) return math.floor(tonumber(p.adj and p.adj[key]) or 0) end
function R.value(w, p, key)
if key == "Hit" and R.template(p) then return "-", COL.popupText end
if key == "Hit" then
local n, combi, support = R.shownHit(w, p)
local col = n > 0 and COL.valueUp or (combi and COL.valueBoth)
or (n < 0 and COL.valueMod) or (support and COL.valueBoth) or COL.popupText
return (n < 0 and "" or "+") .. n, col
end
local steps = R.adjSteps(p, key)
local v = R.adjust(key, p[key] or "-", steps)
if trimText(v) == "" then v = "-" end
local warp = key == "L" and R.warpL(p) or 0
if warp ~= 0 and tonumber(v) then return tostring(math.max(0, tonumber(v) + warp)), COL.wyrdInk end
local more = key == "S" and (R.stabbing[w] and R.stab(p) or 0) + R.blows(p) + R.lance(p, w) + R.bull(p, w)
+ R.goliath(p, w) + R.jumpS(p, w) or 0
local function ink(up)
if not (up or steps < 0) then
return (key == "SR" or key == "LR") and R.marksman(p) and COL.marksman or COL.popupText
end
return STAT.color(up, steps < 0)
end
if more <= 0 then return v, ink(steps > 0) end
local n = tonumber(v)
if n then return tostring(math.min(10, n + more)), ink(true) end
local base, sign, m = v:match("^%s*(%a+)%s*([%+%-]?)%s*(%d*)%s*$")
if not base then return v, ink(steps > 0) end
local k = (tonumber(m) or 0) * (sign == "-" and -1 or 1) + more
return base .. (k > 0 and "+" .. k or k < 0 and tostring(k) or ""), ink(true)
end
function R.strength(w, p)
local t = R.parts(R.value(w, p, "S"))
if not t or t.dash then return nil end
if t.token then
if t.token:upper() ~= "S" then return nil end
local s = statNumber("S")
return s and math.max(1, s + t.num) or nil
end
return math.max(1, t.num)
end
function R.noAp(w, p)
local t = R.parts(R.value(w, p, "AP"))
return t ~= nil and (t.dash == true or t.num == 0)
end
function R.apOf(w, p)
local t = R.parts(R.value(w, p, "AP"))
return t and t.num and not t.token and t.num < 0 and -t.num or 0
end
function R.toxin(p)
local n = ("," .. tostring(p.traits or "") .. ","):lower()
:match(",%s*" .. TRAIT.toxin .. "%s*%(%s*(%d+)%s*%+?%s*%)%s*,")
return tonumber(n)
end
R.RANGE_SIGN = "↔"
function R.rangeView(w, p, g)
local S = LAY.popS
local a, b = indexOf(PROFILE_COLS, "SR"), indexOf(PROFILE_COLS, "LR")
if isMelee(p) or not (a and b and g.shown[a] and g.shown[b]) then return nil end
local function half(ci, key)
local val = R.value(w, p, key)
return textWidth(val, fitSize(val, g.need[ci], g.hd, S.valueFont, true), true) / 2
end
local l, r = g.colX[a] + half(a, "SR"), g.colX[b] - half(b, "LR")
local room = math.max(1, r - l)
return { on = R.marksman(p) ~= nil, x = (l + r) / 2 - g.boxW / 2, w = room,
size = math.max(1, fitSize(R.RANGE_SIGN, room, g.hd, S.valueFont, true)) }
end
function R.rapidFire(p)
if not hasRapidFire(p) or R.lightFight(p) then return nil end
return tonumber(("," .. tostring(p.traits or "") .. ","):lower():match(",%s*rapid fire%s*%(%s*(%d+)")) or 1
end
function R.ammoNeed(p)
if isMelee(p) then return nil end
local n = ("," .. tostring(p.traits or "") .. ","):lower()
:match(",%s*" .. TRAIT.ammo .. "%s*%(%s*(%d+)%s*%+?%s*%)%s*,")
n = tonumber(n or tostring(p.Am or ""):match("^%s*(%d)%s*%+?%s*$"))
local steps = R.adjSteps(p, "Am")
if n and steps ~= 0 then n = math.max(2, math.min(6, n - steps)) end
return n
end
function R.scarce(p)
if isMelee(p) or not TRAIT.scarce then return nil end
return tonumber((("," .. tostring(p.traits or "") .. ","):lower()
:match(",%s*" .. TRAIT.scarce .. "%s*%(%s*(%d+)%s*%+?%s*%)%s*,")))
end
function R.reliable(p) return hasTrait(p, TRAIT.reliable) end
function R.reliableReady(p) return R.reliable(p) and not p.reliableUsed end
function R.numbers(line, pattern)
local out = {}
for t in (tostring(line or "") .. ","):gmatch("([^,]*),") do
local n = trimText(t):lower():match("^" .. pattern .. "%s*%(%s*(%d+)%s*%+?%s*%)$")
if n then out[#out + 1] = tonumber(n) end
end
return out
end
function R.lowest(line, pattern)
local best = nil
for _, n in ipairs(pattern and R.numbers(line, pattern) or {}) do best = math.min(best or n, n) end
return best
end
function R.shock(p)
if not TRAIT.shock then return nil end
return R.lowest(p.traits, TRAIT.shock) or (hasTrait(p, TRAIT.shock) and 6) or nil
end
function R.knockback(p, w)
if not TRAIT.knockback then return nil end
return R.lowest(p.traits, TRAIT.knockback) or (hasTrait(p, TRAIT.knockback) and 6)
or (R.bullTrait(p, w) and 6) or nil
end
function R.blast(p) return TRAIT.blast ~= nil and hasTrait(p, TRAIT.blast) end
function R.blaze(p, w)
local line = tostring(p.traits or "")
local fire = w and isMelee(p) and ACTIVATION.flameTrait and ACTIVATION.flameTrait(w)
if fire then line = line .. "," .. fire end
local mantle = ACTIVATION.mantleTrait and ACTIVATION.mantleTrait(p)
if mantle then line = line .. "," .. mantle end
return R.lowest(line, TRAIT.blaze)
end
function R.hurts(w, p)
local line = tostring(p.traits or "")
local gained = R.gangShred(p)
if gained then line = line .. "," .. gained end
local function n6(pat)
if not pat then return nil end
return R.lowest(line, pat) or (hasTrait(p, pat) and 6) or nil
end
local function has(pat) return pat ~= nil and hasTrait(p, pat) or nil end
local most = nil
for _, n in ipairs(TRAIT.damage and R.numbers(line, TRAIT.damage) or {}) do most = math.max(most or n, n) end
local l = R.parts(R.value(w, p, "L"))
return { l = l and l.num and not l.token and math.max(0, l.num) or 0, dmg = most, rend = n6(TRAIT.rending), shred = n6(TRAIT.shred), conc = n6(TRAIT.concussive),
breach = n6(TRAIT.breaching),
gas = has(TRAIT.gas), web = has(TRAIT.web), rad = has(TRAIT.radphage) }
end
function R.gangShred(p)
local g = ACTIVATION.escher()
local n = g and tonumber(g.toxinShred)
if not n or not TRAIT.shred or not R.toxin(p) then return nil end
if R.lowest(tostring(p.traits or ""), TRAIT.shred) or hasTrait(p, TRAIT.shred) then return nil end
return string.format("Shred (%d+)", math.floor(n))
end
function R.cursed(p) return TRAIT.cursed ~= nil and hasTrait(p, TRAIT.cursed) end
function R.flash(p) return TRAIT.flash ~= nil and not isMelee(p) and hasTrait(p, TRAIT.flash) end
function R.graviton(p) return TRAIT.graviton ~= nil and not isMelee(p) and hasTrait(p, TRAIT.graviton) end
function R.noWound(p) return R.flash(p) or R.smoke(p) end
function R.smoke(p) return TRAIT.smoke ~= nil and hasTrait(p, TRAIT.smoke) end
function R.noWoundWhy(p)
if R.flash(p) then return "Flash: no Wound roll" end
if R.smoke(p) then return "Smoke: no Wound roll" end
if R.graviton(p) then return "Graviton Pulse: Strength check" end
return nil
end
function R.drag(p) return TRAIT.drag ~= nil and hasTrait(p, TRAIT.drag) end
function R.twin(p) return TRAIT.twinLinked ~= nil and hasTrait(p, TRAIT.twinLinked) end
function R.closeTemplate(p)
return R.template(p) and fighter.status == "engaged" and hasTrait(p, TRAIT.light) or false
end
function R.template(p) return TRAIT.template ~= nil and not isMelee(p) and hasTrait(p, TRAIT.template) end
function R.wild(p) return R.template(p) and R.unstable(p) end
function R.unstable(p)
return (TRAIT.unstable ~= nil and hasTrait(p, TRAIT.unstable)) or R.jumpUnstable(p)
end
function R.jumpUnstable(p)
local b = ACTIVATION.jumping()
if not (b and b.unstable and TRAIT.unstable) or isMelee(p) or hasTrait(p, TRAIT.unstable) then return false end
local function dash(v) return tostring(v or "-"):match("^%s*%-?%s*$") ~= nil end
return R.template(p) or (dash(p.SR) and not dash(p.LR))
end
function R.hitButton(p) return not R.template(p) or R.wild(p) end
function R.spreads(p) return R.template(p) end
function R.spreadsAny()
for i = 1, weaponCount() do
for _, p in ipairs((weaponAt(i) or {}).profiles or {}) do
if R.spreads(p) then return true end
end
end
return false
end
function R.charging(p, w)
if not isMelee(p) then return false end
if R.bullForce or ACTIVATION.charged() or R.step(p) == "charge" then return true end
local st = fighter.activation == "active" and fighter.fight
return (w and st and st.charged and st.primary ~= R.slot(w)) and true or false
end
function R.lance(p, w)
if not (TRAIT.lance and isMelee(p) and hasTrait(p, TRAIT.lance)) then return 0 end
return (R.charging(p, w) and ACTIVATION.tags().mounted) and 1 or 0
end
R.BULL_TRAIT = "Knockback (6+)"
function R.lanceBomb(p) return TRAIT.lanceBomb ~= nil and isMelee(p) and hasTrait(p, TRAIT.lanceBomb) end
function R.bull(p, w)
if not isMelee(p) then return 0 end
if R.bullForce then return 1 end
if not R.charging(p, w) then return 0 end
return #SKILL.with("bullCharge") > 0 and 1 or 0
end
function R.goliath(p, w)
if ACTIVATION.charged() or not R.charging(p, w) then return 0 end
local g = ACTIVATION.gangRule("goliathGang")
local n = g and type(g.charge) == "table" and tonumber(g.charge.S) or 0
local t = n ~= 0 and R.parts(p.S or "-")
return (t and t.token and t.token:upper() == "S") and n or 0
end
function R.bullTrait(p, w)
if R.bull(p, w) == 0 or (TRAIT.knockback and hasTrait(p, TRAIT.knockback)) then return nil end
return R.BULL_TRAIT
end
function R.jumpS(p, w)
local b = ACTIVATION.jumping()
if not b or ACTIVATION.charged() or not R.charging(p, w) then return 0 end
local n = tonumber((b.charge or {}).S) or 0
local t = n ~= 0 and R.parts(p.S or "-")
return (t and t.token and t.token:upper() == "S") and n or 0
end
R.AIM_MARK = "<aimed>"
R.REROLL_MARK = "<reroll>"
RULES.follow(function()
R.AA_MARK = TRAIT.additional .. "%s*%(%s*%d+%s*%)"
R.MARKED = { TRAIT.reliable, TRAIT.shield, TRAIT.parry, R.AA_MARK }
end)
function R.markInk(p, mark, w)
if mark == R.BULL_TRAIT then return COL.traitOn end
if mark == TRAIT.reliable then return p.reliableUsed and COL.traitUsed or COL.traitOn end
if mark == R.AA_MARK then return R.aaOn(p) and COL.traitOn or COL.popupTraits end
if mark == R.AIM_MARK then return (w and R.aiming[w] and R.canAim(p)) and COL.traitOn or COL.popupTraits end
if mark == R.REROLL_MARK then return COL.traitOn end
return R.saveUp() == mark and COL.traitOn or COL.popupTraits
end
function R.marked(p, w)
if R.bullTrait(p, w) then return true end
for _, m in ipairs(R.MARKED) do if hasTrait(p, m) then return true end end
if w and R.reroll[w] then return true end
return R.canAim(p) and R.sight(w) ~= nil
end
function R.saveUp()
local t = R.saveTrait()
if not t then return nil end
local plain = statNumber("Sv")
return (not plain or statNumber("Sv", { save = t }) < plain) and t or nil
end
function R.segments(p, t, w)
if not R.marked(p, w) then return nil end
local sights = R.canAim(p) and R.sight(w) ~= nil
local rr = w and R.REROLL[R.reroll[w]]
local segs, space = {}, textWidth(" ", t.size, true)
for k, line in ipairs({ t.text, t.text2 }) do
local items, parts, cur = {}, {}, nil
for item in (tostring(line) .. ","):gmatch("([^,]*),") do items[#items + 1] = trimText(item) end
for n, item in ipairs(items) do
local comma = n < #items and "," or ""
local mark = nil
for _, m in ipairs(R.MARKED) do if item:lower():match("^" .. m .. "$") then mark = m end end
if not mark and sights and R.sight(w, item) then mark = R.AIM_MARK end
if not mark and rr and item == rr then mark = R.REROLL_MARK end
if not mark and item == R.BULL_TRAIT and R.bullTrait(p, w) then mark = R.BULL_TRAIT end
if mark then
parts[#parts + 1] = { text = item, mark = mark, gap = #parts > 0 }
cur = nil
if comma ~= "" then
cur = { text = comma, gap = false }
parts[#parts + 1] = cur
end
elseif item ~= "" then
if cur then cur.text = cur.text .. " " .. item .. comma
else
cur = { text = item .. comma, gap = #parts > 0 }
parts[#parts + 1] = cur
end
end
end
local total = 0
for _, s in ipairs(parts) do
s.w = textWidth(s.text, t.size, true)
total = total + s.w + (s.gap and space or 0)
end
local x = -total / 2
for _, s in ipairs(parts) do
if s.gap then x = x + space end
s.x, s.y, s.h = x + s.w / 2, k == 1 and t.y or t.y2, t.h
x = x + s.w
segs[#segs + 1] = s
end
end
return segs
end
end
local function meleeAttacks(p)
if hasTrait(p, TRAIT.light) then return 1, "x1" end
local step = TRAIT_RULES.step(p)
if type(step) == "number" then return step, "x" .. step end
local A, N = statNumber("A") or 1, TRAIT_RULES.paired(p)
if step == "extra" then
local x = TRAIT_RULES.extra(p)
return x, "x" .. x
end
if step == "paired" then return A + N, "A+" .. N end
local more = (N or 0) + (TRAIT_RULES.aaCharge(p) or 0)
if more > 0 then return A + 1 + more, "A+1+" .. more end
return A + 1, "A + 1"
end
local function meleeStep(p, up)
local steps, step = TRAIT_RULES.steps(p), TRAIT_RULES.step(p)
local k = type(step) == "number" and #steps + step or 1
for i, s in ipairs(steps) do if s == step then k = i end end
k = math.max(1, k + (up and 1 or -1))
if k > #steps then return k - #steps end
return k > 1 and steps[k] or nil
end
local AMMO_LOOK = {
fine = { text = "AM", col = "ammoFine", box = "profile" },
out = { text = "OUT", col = "ammoOut", box = "profile_out" },
jam = { text = "JAM", col = "ammoJam", box = "profile_jam" },
spent = { text = "SPENT", col = "ammoSpent", box = "profile_jam" },
combi = { text = "Combi", col = "ammoCombi", box = "profile" },
extra = { text = "AA", col = "ammoCombi", box = "profile" },
}
local function ammoLook(w, p) return AMMO_LOOK[TRAIT_RULES.ammoState(w, p)] or AMMO_LOOK.fine end
local function traitLine(p, w)
local line = p.traits or ""
local fire = isMelee(p) and ACTIVATION.flameTrait(w)
if fire then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. fire end
local mantle = ACTIVATION.mantleTrait(p)
if mantle then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. mantle end
if TRAIT_RULES.jumpUnstable(p) then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. "Unstable" end
local shred = TRAIT_RULES.gangShred(p)
if shred then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. shred end
for _, a in ipairs(select(2, TRAIT_RULES.named(w))) do
line = trimText(line)
line = line .. (line ~= "" and ", " or "") .. a.name
end
local rr = w and TRAIT_RULES.REROLL[TRAIT_RULES.reroll[w]]
if rr then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. rr end
local bull = TRAIT_RULES.bullTrait(p, w)
if bull then line = trimText(line); line = line .. (line ~= "" and ", " or "") .. bull end
return line
end
TRAIT_RULES.REROLL = { ones = "RR 1s to hit", all = "RR to hit" }
TRAIT_RULES.REROLL_NEXT = { none = "ones", ones = "all", all = nil }
function TRAIT_RULES.segRoom(w, p, g)
local R, was, most = TRAIT_RULES, TRAIT_RULES.reroll[w], 0
local bull = { false }
for _, it in ipairs(SKILL.owned()) do
if it.bullCharge and isMelee(p) then bull[2] = true end
end
for _, how in ipairs({ false, "ones", "all" }) do
for _, b in ipairs(bull) do
R.reroll[w], R.bullForce = how or nil, b or nil
local segs = R.segments(p, R.traitLines(traitLine(p, w), g), w)
most = math.max(most, segs and #segs or 0)
end
end
R.reroll[w], R.bullForce = was, nil
return most
end
do
local popGeoms = setmetatable({}, { __mode = "k" })
RULES.follow(function()
for k in pairs(popGeoms) do if type(k) == "table" then popGeoms[k] = nil end end
end)
function ui.popupGeom(weapon)
if type(weapon) == "table" and popGeoms[weapon] then return popGeoms[weapon] end
local g = popGeoms.of(weapon)
if type(weapon) == "table" then popGeoms[weapon] = g end
return g
end
function popGeoms.of(weapon)
local shown, sig = weaponCols(weapon), {}
for i = 1, #shown do sig[i] = shown[i] and "1" or "0" end
sig = table.concat(sig)
if popGeoms[sig] then return popGeoms[sig] end
local S, n = LAY.popS, #PROFILE_COLS
local g = { need = {}, colX = {}, shown = shown }
local count = 0
g.areaW = 0
for i, col in ipairs(PROFILE_COLS) do
g.need[i] = math.max(textWidth(col.key, S.headFont, true),
textWidth(col.fit, S.valueFont, true)) / FIT
if shown[i] then g.areaW, count = g.areaW + g.need[i], count + 1 end
end
g.areaW = g.areaW + S.colGap * math.max(0, count - 1)
g.boxW = 2 * S.boxPad + g.areaW
g.areaX = S.boxPad + g.areaW / 2
g.traitW = g.boxW - 2 * S.traitPad
local x = S.boxPad
for i = 1, n do
if shown[i] then
g.colX[i] = x + g.need[i] / 2
x = x + g.need[i] + S.colGap
end
end
g.hd = halfDiag(LAY.sideD)
g.tip = LAY.weaponX + g.hd
g.div = g.tip + S.btnW
g.cellL = g.tip
g.cellW = S.btnW
popGeoms[sig] = g
return g
end
function TRAIT_RULES.traitLines(line, g)
local S = LAY.popS
local w = g.traitW * S.traitFit / FIT
local t = { text = line, text2 = "", color = COL.popupTraits, y = -g.hd / 2, y2 = -g.hd / 2, h = g.hd,
size = fitSize(line, w, g.hd, S.traitFont, true) }
if t.size >= S.traitFont then return t end
local uneven = math.huge
for i = 1, #line do
if line:sub(i, i) == "," then
local a, b = trimText(line:sub(1, i)), trimText(line:sub(i + 1))
local size = math.min(fitSize(a, w, g.hd / 2, S.traitFont, true), fitSize(b, w, g.hd / 2, S.traitFont, true))
local off = math.abs(textEm(a) - textEm(b))
if b ~= "" and (size > t.size + 0.01 or (size > t.size - 0.01 and t.text2 ~= "" and off < uneven)) then
t.text, t.text2, t.size, t.h, uneven = a, b, size, g.hd / 2, off
t.y, t.y2 = -g.hd / 4, -3 * g.hd / 4
end
end
end
return t
end
function TRAIT_RULES.saveTrait(kind)
local engaged = fighter.status == "engaged"
if kind then engaged = kind == "close" end
local want = engaged and TRAIT.parry or TRAIT.shield
local from = {}
for i = 1, weaponCount() do
local w = weaponAt(i) or {}
local held = not engaged or w.role == "primary"
or (w.role == "secondary" and fighter.activation == "active")
for _, p in ipairs(held and w.profiles or {}) do
if hasTrait(p, want) then from[#from + 1] = i break end
end
end
if #from == 0 then return nil end
return engaged and "parry" or "shield", from
end
function TRAIT_RULES.saveContext(kind)
local t, from = TRAIT_RULES.saveTrait(kind)
if kind then return { save = t, saveFrom = t and from or nil, attack = kind } end
return t and { save = t, saveFrom = from } or nil
end
TRAIT_RULES.AIM_SIGN = "⊕"
function TRAIT_RULES.aimView(i, pi, p, mode)
local S, g = LAY.popS, ui.popupGeom(weaponAt(i))
local on = TRAIT_RULES.aiming[weaponAt(i)] == true and TRAIT_RULES.canAim(p)
local a = { on = on, color = on and COL.valueUp or COL.iconText, modes = {} }
for k, m in ipairs(PROFILE_MODES) do
local size = fitSize(m.short, g.cellW, g.hd, S.btnFont, true)
local x, signX = 0, 0
if on then
local em = (textEm(m.short) + textEm("O") + 0.1) * 1.06
size = math.min(size, g.cellW * FIT / em)
local left = -em * size / 2
signX = left + textWidth("O", size, true) / 2
x = left + em * size - textWidth(m.short, size, true) / 2
end
a.modes[k] = { size = size, x = x, signX = signX }
end
a.signX, a.signSize = a.modes[mode].signX, a.modes[mode].size
return a
end
function ui.profileView(i, pi, p)
local S, g = LAY.popS, ui.popupGeom(weaponAt(i))
local ammo = ammoLook(weaponAt(i), p)
local line = traitLine(p, weaponAt(i))
local v = {
box = ammo.box,
melee = isMelee(p),
rapidFire = hasRapidFire(p),
combi = TRAIT_RULES.combi(p),
mode = profileMode(p),
traits = TRAIT_RULES.traitLines(line, g),
}
v.aim = TRAIT_RULES.aimView(i, pi, p, v.mode)
v.segs = TRAIT_RULES.segments(p, v.traits, weaponAt(i))
for _, s in ipairs(v.segs or {}) do
s.color = s.mark and TRAIT_RULES.markInk(p, s.mark, weaponAt(i)) or v.traits.color
end
local t = ammo.text
if ammo == AMMO_LOOK.extra then t = string.format("AA(%d)", TRAIT_RULES.extraShots(p)) end
if v.melee and p.ammo == "spent" then
v.second = { text = ammo.text, color = COL[ammo.col] }
t = ammo.text
elseif v.melee then
local _, label = meleeAttacks(p)
v.second = { text = label, color = COL.iconText }
t = label
else
v.second = { text = t, color = COL[ammo.col] }
end
v.second.size = fitSize(t, g.cellW, g.hd, v.melee and S.valueFont or S.btnFont, true)
return v
end
local function profileButtonsXml(i, pi, v, y, ox, oy)
local S, g = LAY.popS, ui.popupGeom(weaponAt(i))
local tag = function(t) return string.format("%s_%d_%d", t, i, pi) end
local cx = g.cellL + g.cellW / 2 - ox
local up, down = y + g.hd / 2 - oy, y - g.hd / 2 - oy
local labels = { string.format('<Panel rectAlignment="MiddleCenter" offsetXY="%s" width="%g"' ..
' height="%g" color="%s" raycastTarget="false">', xyAttr(cx, up), g.cellW, g.hd, COL.clear) }
local aim = v.aim
for k, m in ipairs(PROFILE_MODES) do
if k == 1 or v.rapidFire then
labels[#labels + 1] = textXml{ id = tag("pmode") .. "_" .. k, x = aim.modes[k].x, y = 0,
w = g.cellW, h = g.hd, text = m.short, color = aim.color, size = aim.modes[k].size,
extra = string.format(' active="%s"', tostring(k == v.mode)) }
end
end
if not v.melee then
labels[#labels + 1] = textXml{ id = tag("paimSign"), x = aim.signX, y = 0, w = g.cellW, h = g.hd,
text = TRAIT_RULES.AIM_SIGN, color = COL.valueUp, size = aim.signSize,
extra = string.format(' active="%s"', tostring(aim.on)) }
end
labels[#labels + 1] = "</Panel>"
local edge = not v.melee and string.format('<Panel id="%s" active="%s" rectAlignment="MiddleCenter"' ..
' offsetXY="%s" width="%g" height="%g" color="%s" raycastTarget="false">%s</Panel>',
tag("paimEdge"), tostring(aim.on), xyAttr(cx, up), g.cellW, g.hd, COL.clear,
edgeFrameXml(0, 0, g.cellW, g.hd, S.aimEdge, COL.valueUp)) or nil
local second = textXml{ id = tag("psecond"), x = cx, y = down, w = g.cellW, h = g.hd,
text = v.second.text, size = v.second.size, color = v.second.color }
local function cell(id, cy, inner, under, hover)
return layeredButton{ id = id, size = g.hd, w = g.cellW, x = cx, y = cy,
bgAsset = "action_bg", under = under, inner = inner, onClick = "onProfileButton",
onEnter = hover and "onProfileEnter" or nil, onExit = hover and "onProfileExit" or nil }
end
return cell(tag("patk"), up, table.concat(labels), edge, true)
.. cell(tag(v.melee and "pcnt" or "pammo"), down, second, nil, v.combi or not v.melee)
end
local function splitTwo(s)
local best, bestA, bestB = nil, nil, nil
for i in s:gmatch("() ") do
local a, b = s:sub(1, i - 1), s:sub(i + 1)
local worse = math.max(textEm(a), textEm(b))
if a ~= "" and b ~= "" and (not best or worse < best) then best, bestA, bestB = worse, a, b end
end
return bestA, bestB
end
function ui.weaponPopupXml(index, weapon)
if not weapon then return "" end
local dy = index > #LAY.weaponSpots and LAY.weaponSpot(index).y or 0
local S, g = LAY.popS, ui.popupGeom(weapon)
local profiles = weapon.profiles or {}
local n = #profiles
local title = (TRAIT_RULES.named(weapon))
local hd, tip, wx = g.hd, g.tip, LAY.weaponX
local line = S.border
local rowsTop = n * hd
local right = g.div + g.boxW + S.pad
local colY = rowsTop + S.headGap + S.headH / 2
local nameY = colY
local top = colY + S.headH / 2 + S.headTop
local bottom = n > 0 and -rowsTop - S.pad or -S.pad
local left = tip
local ox, oy = (left + right) / 2, (top + bottom) / 2
local function at(x, y) return x - ox, y - oy end
local slants = {}
for y = hd, rowsTop - hd + 1e-6, 2 * hd do
slants[#slants + 1] = y
slants[#slants + 1] = -y
end
local filled = (#slants > 0 and slants[#slants - 1] or 0) + hd
local function edgeX(y)
if n == 0 or math.abs(y) > filled + 1e-6 then return tip end
local m = (math.abs(y) % (2 * hd)) / hd
return wx + hd * math.abs(1 - m)
end
local bg = {}
local function rect(x0, x1, y0, y1)
bg[#bg + 1] = string.format(
'<Image rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' color="%s" raycastTarget="false" />',
xyAttr((x0 + x1) / 2, (y0 + y1) / 2), x1 - x0, y1 - y0, COL.popupBg)
end
if n == 1 then
rect(wx, right, bottom, top)
else
if n > 0 then
rect(tip, right, bottom, rowsTop)
rect(wx, tip, -hd, hd)
end
rect(n > 0 and wx or tip, right, n > 0 and rowsTop - hd or bottom, top)
end
for _, y in ipairs(slants) do
bg[#bg + 1] = string.format(
'<Image rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' rotation="0 0 45" color="%s" raycastTarget="false" />',
xyAttr(tip, y), hd * math.sqrt(2), hd * math.sqrt(2), COL.popupBg)
end
for pi = 1, n do
local rowY = (n + 1 - 2 * pi) * hd
bg[#bg + 1] = edgeLineXml((wx + g.div) / 2, rowY, g.div - wx, line, 0, COL.profileEdge)
end
ui.flyoutBgs[#ui.flyoutBgs + 1] = string.format(
'<Panel id="pop_%dBg" active="false" rectAlignment="MiddleCenter" offsetXY="0 %.1f"' ..
' width="%d" height="%d" color="%s" raycastTarget="false">%s</Panel>',
index, dy, LAY.cardW, LAY.cardH, COL.clear, table.concat(bg))
local parts = {}
local function hline(x0, x1, y, thick)
local cx, cy = at((x0 + x1) / 2, y)
parts[#parts + 1] = edgeLineXml(cx, cy, x1 - x0, thick or line, 0, COL.profileEdge)
end
local function slant(x0, y0, x1, y1)
local cx, cy = at((x0 + x1) / 2, (y0 + y1) / 2)
parts[#parts + 1] = edgeLineXml(cx, cy, math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2), line,
(y1 - y0) * (x1 - x0) > 0 and 45 or -45, COL.profileEdge)
end
local nameL = n > 0 and wx or tip
local nameW = (n > 0 and g.div or right - S.pad) - nameL
local unstable = false
for _, p in ipairs(profiles) do unstable = unstable or TRAIT_RULES.unstable(p) end
local warn = "⚠"
if unstable then title = warn .. " " .. title end
local stripH = top - rowsTop
local function fit(s, w, h) return fitSize(s, w * S.nameFit / FIT, h, S.titleFont, true) end
local function fitName(w)
local one = fit(title, w, S.headH)
local a, b = splitTwo(title)
if a then
local two = math.min(fit(a, w, stripH / 2), fit(b, w, stripH / 2))
if two > one * 1.1 then return { a, b }, two end
end
return { title }, one
end
local lines, size = fitName(nameW)
local nameX, textW = nameL + nameW / 2, nameW
local function emit(id, l, y, h)
local x = nameX
if l:sub(1, #warn + 1) == warn .. " " then
l = l:sub(#warn + 2)
local sw, gap, nw = textWidth(warn, size, true), textWidth(" ", size, true), textWidth(l, size, true)
local left = nameX - (sw + gap + nw) / 2
local sx, sy = at(left + sw / 2, y)
parts[#parts + 1] = textXml{ id = "ptitleWarn_" .. index, x = sx, y = sy, w = size * 1.5,
h = h, text = warn, color = COL.accent, size = size }
x = left + sw + gap + nw / 2
end
local tx, ty = at(x, y)
parts[#parts + 1] = textXml{ id = id, x = tx, y = ty, w = textW, h = h, text = l,
color = COL.accent, size = size }
end
if #lines == 1 then
emit("ptitle_" .. index, lines[1], nameY, S.headH)
else
local pitch = size * S.nameLeading
for k, l in ipairs(lines) do
emit("ptitle_" .. index .. (k == 1 and "" or "_2"), l,
(rowsTop + top) / 2 + (k == 1 and 1 or -1) * pitch / 2, stripH / 2)
end
end
if n > 0 then
for i, col in ipairs(PROFILE_COLS) do
if g.shown[i] then
local hx, hy = at(g.div + g.colX[i], colY)
parts[#parts + 1] = textXml{ id = string.format("phead_%d_%d", index, i),
x = hx, y = hy, w = g.need[i], h = S.headH, text = col.key,
color = COL.popupHead, size = fitSize(col.key, g.need[i], S.headH, S.headFont, true) }
end
end
end
for pi, p in ipairs(profiles) do
local v, inner = ui.profileView(index, pi, p), {}
local rowY = (n + 1 - 2 * pi) * hd
local bx = g.div + g.boxW / 2
local lx = g.div
inner[#inner + 1] = edgeLineXml(lx + g.areaX - bx, 0, g.areaW, line, 0, COL.profileEdge)
local rv = TRAIT_RULES.rangeView(weapon, p, g)
if rv then
inner[#inner + 1] = textXml{ id = string.format("prange_%d_%d", index, pi), x = rv.x, y = hd / 2,
w = rv.w, h = hd, text = TRAIT_RULES.RANGE_SIGN, color = COL.marksman, size = rv.size,
extra = string.format(' active="%s" raycastTarget="false"', tostring(rv.on)) }
end
for i, col in ipairs(PROFILE_COLS) do
if g.shown[i] and showsCol(p, col.key) then
local val, tint = TRAIT_RULES.value(weapon, p, col.key)
inner[#inner + 1] = textXml{ id = string.format("pval_%d_%d_%d", index, pi, i),
x = lx + g.colX[i] - bx, y = hd / 2, w = g.need[i], h = hd, text = val,
color = tint, size = fitSize(val, g.need[i], hd, S.valueFont, true) }
if col.key == "Hit" and TRAIT_RULES.hitButton(p) then
local bw = g.need[i] + 2 * math.max(0, S.boxPad - S.border)
inner[#inner + 1] = string.format('<Panel id="phitEdge_%d_%d" active="%s"' ..
' rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f" color="%s"' ..
' raycastTarget="false">%s</Panel>', index, pi,
tostring(TRAIT_RULES.reroll[weapon] ~= nil), xyAttr(lx + g.colX[i] - bx, hd / 2), bw,
hd - 2 * S.border, COL.clear,
edgeFrameXml(0, 0, bw, hd - 2 * S.border, S.aimEdge, COL.valueUp))
inner[#inner + 1] = string.format(
'<Button id="phit_%d_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="onHitClick" onMouseEnter="onHitEnter"' ..
' onMouseExit="onHitExit" />', index, pi,
xyAttr(lx + g.colX[i] - bx, hd / 2), bw, hd - 2 * S.border, COL.clear, COL.hover,
COL.press, COL.clear)
elseif TRAIT_RULES.adjustable(p, col.key) then
local function reach(dir)
for j = i + dir, dir > 0 and #PROFILE_COLS or 1, dir do
if g.shown[j] then return S.colGap / 2 end
end
return math.max(0, S.boxPad - S.border)
end
local l, r = reach(-1), reach(1)
inner[#inner + 1] = string.format(
'<Button id="padj_%d_%d_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="onProfileStatClick"%s />', index, pi, i,
xyAttr(lx + g.colX[i] - bx + (r - l) / 2, hd / 2), g.need[i] + l + r,
hd - 2 * S.border, COL.clear, COL.hover, COL.press, COL.clear,
v.combi and ' onMouseEnter="onProfileEnter" onMouseExit="onProfileExit"' or "")
end
end
end
local tr = v.traits
inner[#inner + 1] = textXml{ id = string.format("ptraits_%d_%d", index, pi),
x = 0, y = tr.y, w = g.traitW, h = tr.h, text = v.segs and "" or tr.text,
color = tr.color, style = "BoldItalic", size = tr.size }
inner[#inner + 1] = textXml{ id = string.format("ptraits2_%d_%d", index, pi),
x = 0, y = tr.y2, w = g.traitW, h = tr.h, text = v.segs and "" or tr.text2,
color = tr.color, style = "BoldItalic", size = tr.size }
for n = 1, TRAIT_RULES.segRoom(weapon, p, g) do
local s = v.segs and v.segs[n] or { x = 0, y = tr.y, w = 0, h = tr.h, text = "", color = tr.color }
inner[#inner + 1] = textXml{ id = string.format("ptseg_%d_%d_%d", index, pi, n),
x = s.x, y = s.y, w = s.w / FIT + 2, h = s.h, text = s.text,
color = s.color, style = "BoldItalic", size = tr.size }
if s.mark == TRAIT.reliable then
inner[#inner + 1] = string.format(
'<Button id="prelBtn_%d_%d" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f"' ..
' height="%.1f" colors="%s|%s|%s|%s" onClick="onReliableClick" />', index, pi,
xyAttr(s.x, s.y), s.w + 8, s.h, COL.clear, COL.hover, COL.press, COL.clear)
end
end
local bxl, byl = at(bx, rowY)
parts[#parts + 1] = edgedBox(string.format("prof_%d_%d", index, pi), bxl, byl,
g.boxW, 2 * hd, v.box, table.concat(inner), v.combi)
if pi == 1 then
hline(edgeX(rowY + hd - line / 2), g.div, rowY + hd - line / 2)
else
hline(edgeX(rowY + hd), g.div, rowY + hd, 2 * line)
end
if pi == n then hline(edgeX(rowY - hd + line / 2), g.div, rowY - hd + line / 2) end
parts[#parts + 1] = profileButtonsXml(index, pi, v, rowY, ox, oy)
end
for _, y in ipairs(slants) do
local s = y > 0 and 1 or -1
slant(wx, y, tip, y + s * hd)
if math.abs(y) > hd then slant(wx, y, tip, y - s * hd) end
end
return string.format(
'<Panel id="pop_%d" active="false" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%.1f" height="%.1f" color="%s" onMouseEnter="onFlyoutEnter"' ..
' onMouseExit="onFlyoutExit">%s</Panel>',
index, xyAttr(ox, oy + dy), right - left, top - bottom, COL.clear, table.concat(parts))
end
end
do
ui.SPECTATOR = "Grey"
ui.spectatorHint = -1e9
function ui.spectating(player, hint)
local ok, color = pcall(function() return player.color end)
if not (ok and color == ui.SPECTATOR) then return false end
local now = os.clock()
if hint and now - ui.spectatorHint >= (tonumber(CFG.watchHint) or 5) then
ui.spectatorHint = now
pcall(function()
broadcastToColor(CFG.infoPrefix .. "Spectators only watch. To play, sit at a colour and put one of your " ..
"gang's models in front of your side panel of the Mundane Controller.", ui.SPECTATOR, { 0.9, 0.8, 0.4 })
end)
end
return true
end
ui.playing = nil
function ui.watcher(key)
if key == ui.SPECTATOR then return true end
return ui.playing ~= nil and key ~= "all" and not ui.playing[key]
end
function ui.wantedViewers()
if CFG.billboard then
local allowed = CFG.visibility ~= "" and ("|" .. CFG.visibility .. "|") or nil
local function wanted(color) return not allowed or allowed:find("|" .. color .. "|", 1, true) end
local keys, seen = {}, {}
local okP, players = pcall(function() return Player.getPlayers() end)
for _, p in ipairs(okP and type(players) == "table" and players or {}) do
local ok, color, seated = pcall(function() return p.color, p.seated end)
if ok and type(color) == "string" and color ~= "" and color ~= ui.SPECTATOR
and seated and not seen[color] and wanted(color) then
seen[color], keys[#keys + 1] = true, color
end
end
if #keys > 0 then
table.sort(keys)
return keys
end
if not CFG.unseatedCopy then return {} end
end
return { "all" }
end
function ui.playerOf(color)
if type(color) ~= "string" then return color end
if color == "all" then return ui.facingPlayer("all") end
if color == "" or color == ui.SPECTATOR then return nil end
local ok, p = pcall(function() return Player[color] end)
return ok and p or nil
end
function ui.facingPlayer(key)
if key == ui.SPECTATOR then return nil end
if key == "all" then
local okP, all = pcall(function() return Player.getPlayers() end)
local list = okP and type(all) == "table" and all or {}
for _, p in ipairs(list) do
if ui.yawFor(p, 0) then return p end
end
return list[1]
end
local p = ui.playerOf(key)
local ok, seated = pcall(function() return p.seated end)
if ok and seated then return p end
end
function ui.yawFor(p, own)
local ok, r = pcall(function() return p.getPointerRotation() end)
if not ok or type(r) ~= "number" then return nil end
return ((own or self.getRotation().y) - r) % 360 + CFG.faceOffset
end
function ui.wrapAngle(d) return ((d + 180) % 360) - 180 end
local function looksArt()
local function pick(value, dyn)
for k in pairs(dynamicAssets) do
if k:sub(1, #dyn + 1) == dyn .. "_" then dynamicAssets[k] = nil end
end
if not value:match("^https?://") then return nil end
local h = 0
for i = 1, #value do h = (h * 31 + value:byte(i)) % 16777216 end
local name = dyn .. "_" .. h
dynamicAssets[name] = value
return name
end
return pick(looks.frame, "looks_frame"), pick(looks.trim, "looks_trim")
end
function ui.placement()
local ok, s = pcall(function() return self.getScale() end)
local sx, sy, sz = 1, 1, 1
if ok and s then
sx, sy, sz = tonumber(s.x or s[1]) or 1, tonumber(s.y or s[2]) or 1, tonumber(s.z or s[3]) or 1
end
local k = math.max(0.01, (math.abs(sx) + math.abs(sz)) / 2)
sy = math.max(0.01, math.abs(sy))
local c, p = {}, {}
for n in CFG.scale:gmatch("[%d.%-]+") do c[#c + 1] = tonumber(n) / k end
for n in CFG.position:gmatch("[%d.%-]+") do p[#p + 1] = tonumber(n) end
local h = tonumber(fighter.height)
if h then
local lift = LAY.cardH / 2 * c[2] * math.abs(math.sin(math.rad(CFG.standAngle)))
p[3] = -((h + CFG.headGap / sy) * 100 + lift)
end
p[3] = p[3] - (tonumber(fighter.lift) or 0) / sy * 100
return string.format("%.1f %.1f %.1f", p[1], p[2], p[3]),
string.format("%.4f %.4f %.4f", c[1], c[2], c[3])
end
function ui.nameView()
local nameH = LAY.nameFont * 1.25
local name = fighter.name or ""
if fighter.grouped and (CFG.groupMark or "") ~= "" then name = name .. " " .. CFG.groupMark end
local sym = CFG.rankSymbols[tostring(fighter.rank or ""):lower()]
local k = CFG.rankScale
local function across(size)
if not sym then return 0, 0, textWidth(name, size, true) end
return textWidth(sym, size * k, true), textWidth(" ", size, true), textWidth(name, size, true)
end
local s1, g1, n1 = across(1)
local size = math.min(LAY.nameFont, nameH / 1.2, LAY.nameW * FIT / math.max(s1 + g1 + n1, 1e-6))
local symW, gap, nmW = across(size)
local left = -(symW + gap + nmW) / 2
local sd, ol = LAY.nameShadow * LAY.nameFont, LAY.nameOutline * LAY.nameFont
local copies = {}
if sd > 0 then copies[#copies + 1] = { "Shadow", sd, -sd } end
if ol > 0 then
for i, c in ipairs({ { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } }) do
copies[#copies + 1] = { "Rim_" .. i, c[1] * ol, c[2] * ol }
end
end
copies[#copies + 1] = { "", 0, 0 }
local ad = LAY.nameArrow * LAY.nameFont
return { name = name, sym = sym, size = size, symSize = size * k, h = nameH,
y = LAY.cardH / 2 + LAY.nameGap + nameH / 2, w = symW + gap + nmW,
nameX = left + symW + gap + nmW / 2, symX = left + symW / 2, copies = copies,
arrowD = ad, arrowX = (symW + gap + nmW) / 2 + LAY.nameArrowGap + ad * 1.25 / 2 }
end
function ui.arrowsXml(nv)
local box, sd = nv.arrowD * 1.25, LAY.nameShadow * nv.arrowD
local out = { string.format('<Panel id="nameArrows" active="false" rectAlignment="MiddleCenter" offsetXY="%s"' ..
' width="%.1f" height="%.1f" color="%s" raycastTarget="false">', xyAttr(0, nv.y),
LAY.nameW + 2 * (LAY.nameArrowGap + box), nv.h, COL.clear) }
for _, a in ipairs({ { "nameDown", -1, CFG.nameArrows.down }, { "nameUp", 1, CFG.nameArrows.up } }) do
local x = a[2] * nv.arrowX
out[#out + 1] = textXml{ id = a[1] .. "Shadow", x = x + sd, y = -sd, w = box, h = box, text = a[3],
color = COL.nameShadow, size = nv.arrowD, extra = ' raycastTarget="false"' }
out[#out + 1] = textXml{ id = a[1] .. "Txt", x = x, y = 0, w = box, h = box, text = a[3],
color = COL.value, size = nv.arrowD, extra = ' raycastTarget="false"' }
out[#out + 1] = string.format(
'<Button id="%s" rectAlignment="MiddleCenter" offsetXY="%s" width="%.1f" height="%.1f"' ..
' colors="%s|%s|%s|%s" onClick="onNameArrow" onMouseEnter="onNameEnter" onMouseExit="onNameExit" />',
a[1], xyAttr(x, 0), box, box, COL.clear, COL.hover, COL.press, COL.clear)
end
out[#out + 1] = "</Panel>"
return table.concat(out)
end
function ui.buildContent()
ui.flyoutBgs = {}
ui.rawTexts = {}
SKILL.panels()
SKILL.registerFlyouts()
local flyouts = { ui.statusPickerXml(), ui.panelXml("cond") }
for _, st in ipairs(STATUSES) do flyouts[#flyouts + 1] = ui.panelXml(ui.actionPanelOf(st.key)) end
for _, prefix in ipairs(SKILL.SPECIAL_ORDER) do
if PANELS[prefix] then flyouts[#flyouts + 1] = ui.panelXml(prefix) end
end
ui.registerWeaponFlyouts()
for i = 1, weaponCount() do
flyouts[#flyouts + 1] = ui.weaponPopupXml(i, weaponAt(i))
end
local function layer(id)
return string.format('<Panel id="%s" active="@@FULL@@" rectAlignment="MiddleCenter" width="%d"' ..
' height="%d" color="%s" raycastTarget="false">', id, LAY.cardW, LAY.cardH, COL.clear)
end
local x = { layer("cardBack") }
local frameArt, trimArt = looksArt()
if frameArt then
x[#x + 1] = string.format(
'<Image id="frameArt" rectAlignment="MiddleCenter" offsetXY="%g %g" width="%g"' ..
' height="%g" color="%s" image="%s" preserveAspect="true" raycastTarget="false" />',
LAY.frameX, LAY.frameY, LAY.frameW, LAY.frameH,
looks.tint == "no" and "#FFFFFFff" or COL.frame, frameArt)
end
if trimArt then
x[#x + 1] = string.format(
'<Image id="frameTrim" rectAlignment="MiddleCenter" offsetXY="%g %g" width="%g"' ..
' height="%g" color="%s" image="%s" preserveAspect="true" raycastTarget="false" />',
LAY.frameX, LAY.frameY, LAY.frameW, LAY.frameH, COL.frameTrim, trimArt)
end
if ui.glowing() then
x[#x + 1] = string.format(
'<Image id="statusGlow" rectAlignment="MiddleCenter" offsetXY="%g 0" width="%g"' ..
' height="%g" color="%s" image="status_glow" raycastTarget="false" />',
(LAY.glowL + LAY.glowR) / 2, LAY.glowR - LAY.glowL, LAY.glowH, ui.glowColor())
end
x[#x + 1] = ui.activeXml()
x[#x + 1] = string.format(
'<Panel id="clickBlock" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' color="%s" raycastTarget="true" />',
LAY.blockW, LAY.blockH, frameArt and COL.clear or COL.frame)
if not frameArt then
local grad = hasAsset("hp_segment")
x[#x + 1] = string.format(
'<Image id="skillBack" rectAlignment="MiddleCenter" offsetXY="0 %.1f" width="%g" height="%.1f"' ..
' color="%s"%s raycastTarget="false" />',
-(LAY.sideY + halfDiag(LAY.sideD) / 2), 2 * LAY.sideX, halfDiag(LAY.sideD),
grad and COL.skillBack or COL.dicePanel, imgAttr("hp_segment"))
end
x[#x + 1] = table.concat(ui.flyoutBgs)
x[#x + 1] = "</Panel>"
x[#x + 1] = string.format('<Panel id="cardHead" rectAlignment="MiddleCenter" offsetXY="@@HEADXY@@" width="%d"' ..
' height="%d" color="%s" raycastTarget="false">', LAY.cardW, LAY.cardH, COL.clear)
local e = LAY.compactEdge
x[#x + 1] = string.format('<Image id="hpBack" active="@@COMPACT@@" rectAlignment="MiddleCenter" offsetXY="0 %g"' ..
' width="%g" height="%g" color="%s" raycastTarget="false" />', LAY.hpY, LAY.hpW + 2 * e, LAY.hpH + 2 * e,
COL.hpBack)
x[#x + 1] = ui.hpBarXml()
local nv = ui.nameView()
for _, c in ipairs(nv.copies) do
local col = c[1] == "" and COL.value or COL.nameShadow
if nv.sym then
x[#x + 1] = textXml{ id = "fighterRank" .. c[1], x = nv.symX + c[2], y = nv.y + c[3], w = LAY.nameW,
h = nv.h, text = nv.sym, color = col, size = nv.symSize, extra = ' raycastTarget="false"' }
end
x[#x + 1] = textXml{ id = "fighterName" .. c[1], x = nv.nameX + c[2], y = nv.y + c[3], w = LAY.nameW,
h = nv.h, text = nv.name, color = col, size = nv.size, extra = ' raycastTarget="false"' }
end
x[#x + 1] = string.format(
'<Button id="nameBtn" rectAlignment="MiddleCenter" offsetXY="%s" width="%g" height="%g"' ..
' colors="%s|%s|%s|%s" onClick="onNameClick" onMouseEnter="onNameEnter" onMouseExit="onNameExit" />',
xyAttr(0, nv.y), nv.w, nv.h,
COL.clear, COL.clear, COL.clear, COL.clear)
x[#x + 1] = ui.arrowsXml(nv)
x[#x + 1] = "</Panel>"
x[#x + 1] = layer("cardBody")
x[#x + 1] = ui.conditionBarXml()
x[#x + 1] = SKILL.barXml()
x[#x + 1] = ui.statBlockXml(TRAIT_RULES.saveContext())
x[#x + 1] = ACTIVATION.panelXml()
x[#x + 1] = SKILL.infosXml()
x[#x + 1] = ACTIVATION.diceXml()
local triggers = { onClick = "onTriggerClick", onEnter = "onTriggerEnter", onExit = "onTriggerExit" }
local function trigger(o)
for k, v in pairs(triggers) do o[k] = v end
o.frame = "diamond_frame"
if o.label then o.labelSize, o.labelD = LAY.diamondLabel(o.label, o.size), o.size end
return diamond(o)
end
local function glowXml(id, on, gx, gy, col, d)
d = d or LAY.sideD
return string.format(
'<Image id="%s" active="%s" rectAlignment="MiddleCenter" offsetXY="%g %g"' ..
' width="%g" height="%g" rotation="0 0 45" color="%s"%s raycastTarget="false" />',
id, tostring(on), gx, gy, d, d, ACTIVATION.litColor(col), imgAttr("diamond"))
end
x[#x + 1] = string.format(
'<Panel id="statusBox" rectAlignment="MiddleCenter" offsetXY="%s" width="%g" height="%g"' ..
' scale="1 1 1" color="%s" raycastTarget="false">', xyAttr(-LAY.statusRestX, 0), LAY.sideD, LAY.sideD, COL.clear)
local split, first, later = ACTIVATION.readyHalves()
local function halfXml(id, on, rot)
return string.format(
'<Image id="%s" active="%s" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' rotation="0 0 %d" color="%s"%s raycastTarget="false" />', id, tostring(on), LAY.sideD, LAY.sideD,
rot, ACTIVATION.litColor(COL.ready), imgAttr("dice_half"))
end
local halves = hasAsset("dice_half") and (halfXml("readyHalf_S", later, 45) .. halfXml("readyHalf2_S", first, 225) ..
string.format('<Panel id="readySplit_S" active="%s" rectAlignment="MiddleCenter" width="%g" height="%g"' ..
' color="%s" raycastTarget="false">%s</Panel>', tostring(split), LAY.readySplit, LAY.sideD * math.sqrt(2),
COL.clear, edgeLineXml(0, 0, LAY.sideD * math.sqrt(2), LAY.readySplit, 90, COL.diamond))) or ""
x[#x + 1] = trigger{ id = "btnStatus", size = LAY.sideD, x = 0, y = 0,
under = glowXml("readyGlow_S", fighter.activation == "ready" and not split, 0, 0, COL.ready, LAY.sideD) .. halves ..
string.format('<Image id="statusFill_S" active="false" rectAlignment="MiddleCenter" width="%g"' ..
' height="%g" rotation="0 0 45" color="%s"%s raycastTarget="false" />', LAY.sideD, LAY.sideD,
ui.statusFill(statusDef(fighter.status)), imgAttr("diamond")),
inner = ui.statusIconsXml() }
x[#x + 1] = "</Panel>"
local function glow(n)
local on, lost = ACTIVATION.readyLook(n)
return glowXml("readyGlow_" .. n, on, -LAY.sideX, n == 1 and LAY.sideY or -LAY.sideY,
lost or statusDef(fighter.status).color:sub(1, 7) .. "ff")
end
local typeIcon = fighter.category and "type_" .. tostring(fighter.category)
x[#x + 1] = trigger{ id = "btnActions", size = LAY.sideD, x = -LAY.sideX, y = LAY.sideY, under = glow(1),
icon = (typeIcon and hasAsset(typeIcon)) and typeIcon or "menu_actions", label = "A" }
x[#x + 1] = trigger{ id = "btnConditions", size = LAY.sideD, x = -LAY.sideX, y = -LAY.sideY, under = glow(2),
icon = "menu_conditions", label = "C" }
ui.wpnStandIn = {}
local function weaponDiamond(i)
local w, spot = weaponAt(i), LAY.weaponSpot(i)
if w then
local kind, glow = weaponType(w), TRAIT_RULES.glow(w)
local fx = string.format(
'<Image id="fxGlow_%d" active="false" rectAlignment="MiddleCenter" offsetXY="%g %g"' ..
' width="%g" height="%g" rotation="0 0 45" color="%s"%s raycastTarget="false" />',
i, spot.x, spot.y, LAY.sideD, LAY.sideD, SKILL.glowColor(COL.valueUp), imgAttr("diamond"))
local icon = ui.resolveIcon(w.icon, "wpnIcon_" .. i) or ("wpn_" .. kind)
local role = TRAIT_RULES.roleLabel(w)
ui.wpnStandIn[i] = not hasAsset(icon) or nil
local d = LAY.sideD * LAY.iconPad
local size = LAY.diamondLabel("PRI", LAY.sideD)
local plate = not ui.wpnStandIn[i] and string.format(
'<Image id="wpnRolePlate_%d" active="%s" rectAlignment="MiddleCenter" offsetXY="%g %g"' ..
' width="%.1f" height="%.1f" color="%s" raycastTarget="false" />',
i, tostring(role ~= nil), spot.x, spot.y, d, d * 0.5, COL.badge) or ""
local bw, bh = LAY.sideD, LAY.sideD
if not ui.wpnStandIn[i] then bw, bh = d, d * 0.5 end
local roleText = TRAIT_RULES.roleShown(w) and (plate .. textXml{ id = "wpnRole_" .. i, x = spot.x, y = spot.y, w = bw, h = bh,
text = role or "", size = fitSize("PRI", bw, bh, size, true), color = COL.iconText,
style = "Bold", extra = string.format(' active="%s"', tostring(role ~= nil)) }) or nil
return trigger{ id = "btnWeapon_" .. i, size = LAY.sideD, x = spot.x, y = spot.y,
icon = icon, label = WEAPON_TYPES[kind], iconId = "wpnType_" .. i,
iconActive = not (ui.wpnStandIn[i] and role),
under = glowXml("blockedGlow_" .. i, glow ~= nil, spot.x, spot.y,
glow or COL.weaponBlocked) .. fx,
inner = roleText }
end
return diamond{ id = "btnWeapon_" .. i, size = LAY.sideD, x = spot.x, y = spot.y,
frame = "diamond_frame", disabled = true }
end
for i = 1, #LAY.weaponSpots do x[#x + 1] = weaponDiamond(i) end
if weaponCount() > #LAY.weaponSpots then
local more = {}
for i = #LAY.weaponSpots + 1, weaponCount() do more[#more + 1] = weaponDiamond(i) end
x[#x + 1] = string.format(
'<Panel id="moreWeapons" active="false" rectAlignment="MiddleCenter" width="%d"' ..
' height="%d" color="%s" raycastTarget="false">%s</Panel>',
LAY.cardW, LAY.cardH, COL.clear, table.concat(more))
end
x[#x + 1] = ui.statPlatesXml()
x[#x + 1] = table.concat(flyouts)
x[#x + 1] = "</Panel>"
local content = table.concat(x)
if CFG.lighterXml then content = ui.lightContent(content) end
return content
end
function ui.buildXml(reuse)
local content = reuse and ui.content
if not content then
content = ui.buildContent()
ui.content = content
end
local out = {}
local pos, size = ui.placement()
ui.placed = pos .. "|" .. size
local watchers = CFG.visibility == "" or ("|" .. CFG.visibility .. "|"):find("|" .. ui.SPECTATOR .. "|", 1, true)
for n, key in ipairs(ui.viewers) do
local vis = key ~= "all" and key or CFG.visibility
if n == 1 and key ~= "all" and watchers then vis = vis .. "|" .. ui.SPECTATOR end
out[#out + 1] = string.format(
'<Panel id="%s_mundaRoot" active="%s" position="%s" rotation="0 0 %.1f"' ..
' width="%d" height="%d" color="%s" raycastTarget="false"%s>' ..
'<Panel id="%s_mundaTilt" rotation="%g 0 0" scale="%s" width="%d" height="%d" color="%s"' ..
' raycastTarget="false">',
key, tostring(ui.visible), pos, view(key).yaw, LAY.cardW, LAY.cardH,
COL.clear, vis ~= "" and string.format(' visibility="%s"', vis) or "",
key, CFG.standAngle, size, LAY.cardW, LAY.cardH, COL.clear)
local compact = view(key).compact == true
local fill = { FULL = tostring(not compact), COMPACT = tostring(compact), HEADXY = ui.headXY(compact) }
out[#out + 1] = (content:gsub(' id="', ' id="' .. key .. '_'):gsub("@@(%u+)@@", fill))
out[#out + 1] = "</Panel></Panel>"
end
return table.concat(out)
end
end
local setAttr
do
local sent, seeding = {}, false
function setAttr(id, name, value, key)
if not ui.built then return end
key = key or ui.only
if not key then
for _, k in ipairs(ui.viewers) do setAttr(id, name, value, k) end
return
end
value = tostring(value)
local full = key .. "_" .. id
local c = full .. "|" .. name
if sent[c] == value then return end
sent[c] = value
if not seeding then self.UI.setAttribute(full, name, value) end
end
local function setText(id, text, key)
if not ui.built then return end
key = key or ui.only
if not key then
for _, k in ipairs(ui.viewers) do setText(id, text, k) end
return
end
text = tostring(text)
local full = key .. "_" .. id
local c = full .. "|#text"
if sent[c] == text then return end
sent[c] = text
if not seeding then self.UI.setValue(full, text) end
end
local function setTextSize(id, size, w, h, key)
local t = textSize(size, w, h)
setAttr(id, "fontSize", t.fontSize, key)
setAttr(id, "scale", t.scale, key)
setAttr(id, "width", t.width, key)
setAttr(id, "height", t.height, key)
end
local FLYOUT_OF = { btnStatus = "statusPick", btnConditions = "conditionsPanel" }
local FLYOUTS = { "statusPick", "conditionsPanel" }
local HAS_BG = { conditionsPanel = true }
ui.IS_ACTIONS = {}
for _, st in ipairs(STATUSES) do
local f = PANELS[ui.actionPanelOf(st.key)].id
FLYOUTS[#FLYOUTS + 1], HAS_BG[f], ui.IS_ACTIONS[f] = f, true, true
end
ui.registerWeaponFlyouts = function()
for k in pairs(FLYOUT_OF) do if k:match("^btnWeapon_") then FLYOUT_OF[k] = nil end end
for k in pairs(HAS_BG) do if k:match("^pop_") then HAS_BG[k] = nil end end
for j = #FLYOUTS, 1, -1 do if FLYOUTS[j]:match("^pop_") then table.remove(FLYOUTS, j) end end
for i = 1, math.max(#LAY.weaponSpots, fighter and weaponCount() or 0) do
FLYOUT_OF["btnWeapon_" .. i] = "pop_" .. i
FLYOUTS[#FLYOUTS + 1] = "pop_" .. i
HAS_BG["pop_" .. i] = true
end
end
ui.registerWeaponFlyouts()
function SKILL.registerFlyouts()
local ours = {}
for _, id in pairs(SKILL.SPECIALS) do ours[id] = true end
for k in pairs(HAS_BG) do if ours[k] then HAS_BG[k], ui.IS_ACTIONS[k] = nil, nil end end
for j = #FLYOUTS, 1, -1 do if ours[FLYOUTS[j]] then table.remove(FLYOUTS, j) end end
for prefix in pairs(SKILL.SPECIALS) do
local P = PANELS[prefix]
if P then FLYOUTS[#FLYOUTS + 1], HAS_BG[P.id], ui.IS_ACTIONS[P.id] = P.id, true, true end
end
end
function ui.flyoutOf(trigger, key)
if trigger == "btnActions" then
local sp = PANELS[SKILL.special()]
if sp and key and view(key).actTab == "special" then return sp.id end
return PANELS[ui.actionPanelOf(fighter.status)].id
end
return FLYOUT_OF[trigger]
end
local function drawBox(id, kind)
setAttr(id, "color", ui.boxColor(kind))
end
function ui.growStatus(key, on)
local k = LAY.statusD / LAY.sideD
setAttr("statusBox", "scale", on and string.format("%g %g 1", k, k) or "1 1 1", key)
setAttr("statusBox", "offsetXY", xyAttr(-(on and LAY.statusX or LAY.statusRestX), 0), key)
setAttr("statusFill_S", "active", on, key)
if on then setAttr("statusFill_S", "color", ui.statusFill(statusDef(fighter.status)), key) end
for _, s in ipairs(STATUSES) do
if not hasAsset("status_" .. s.key) then
setAttr("statusIcon_" .. s.key, "color", on and COL.statusInk or COL.iconText, key)
end
end
end
local openedFlyout, redrawActions
function ui.showFlyout(id, key, quiet)
for _, f in ipairs(FLYOUTS) do
local was = sent[key .. "_" .. f .. "|active"] == "true"
setAttr(f, "active", f == id, key)
if HAS_BG[f] then setAttr(f .. "Bg", "active", f == id, key) end
if f == id and not was and not quiet and not seeding then openedFlyout(f, key) end
if was and f ~= id and not seeding and f:match("^pop_%d+$") then
TRAIT_RULES.setAim(tonumber(f:match("%d+")), false)
TRAIT_RULES.setReroll(tonumber(f:match("%d+")), nil)
TRAIT_RULES.measure(tonumber(f:match("%d+")), nil, true)
end
end
ui.growStatus(key, id == "statusPick")
if weaponCount() > #LAY.weaponSpots then
setAttr("moreWeapons", "active", tostring(id or ""):match("^pop_") ~= nil, key)
end
local v = view(key)
if v.hitHover and id ~= "pop_" .. v.hitHover then
v.hitHover = nil
TRAIT_RULES.lightSupport()
end
if v.costHover and id ~= "pop_" .. (tostring(v.costHover):match("^r?(%d+)") or "") then
v.costHover = nil
if not seeding then ACTIVATION.drawReady() end
end
if v.actHover then
local P = PANELS[tostring(v.actHover):match("^(.-)_%d+$") or ""]
if not P or P.id ~= id then
v.actHover = nil
if not seeding then ACTIVATION.drawReady() end
end
end
local mind = v.mindFrom
if mind then
local P = PANELS[mind:match("^(.-)_%d+$") or ""]
if not P or P.id ~= id then v.mindFrom = nil end
end
if v.open ~= id or (mind and not v.mindFrom) then
v.open = id
if not seeding then ui.redrawStats(key) end
end
if v.infoFrom and not v.infoFrom:match("^condBar_") and not seeding then
local P = PANELS[v.infoFrom:match("^(.-)_%d+$") or ""]
if not P or P.id ~= id then
v.infoHover, v.infoFrom = nil, nil
SKILL.drawInfo(key)
end
end
if not ui.IS_ACTIONS[id or ""] then v.actTab = nil end
end
local function weaponContext(key)
local v = view(key)
local i = tonumber(tostring(v.open or ""):match("^pop_(%d+)$"))
local w = i and weaponAt(i)
local ctx = nil
for pi, p in ipairs((w and w.profiles) or {}) do
if isMelee(p) then
ctx = ctx or {}
ctx.melee = i
if hasTrait(p, TRAIT.unwieldy) then ctx.unwieldy = true end
elseif v.profHover == i .. "_" .. pi and TRAIT_RULES.ammoState(w, p) == "combi"
and not TRAIT_RULES.aiming[w] then
ctx = ctx or {}
ctx.combi = i
end
end
local save, from = TRAIT_RULES.saveTrait()
if save then
ctx = ctx or {}
ctx.save, ctx.saveFrom = save, from
end
return ctx
end
function ui.drawStats(key)
if not key then
TRAIT_RULES.drawMarks()
for _, k in ipairs(ui.viewers) do ui.drawStats(k) end
return
end
local v = view(key)
for _, c in ipairs(ui.statCells(v.statsHover or v.mindFrom ~= nil, weaponContext(key))) do
setText(c.id, c.text, key)
setAttr(c.id, "offsetXY", xyAttr(c.x, c.y), key)
setTextSize(c.id, c.size, c.w, c.h, key)
setAttr(c.id, "color", c.color, key)
end
for i, t in ipairs(ui.statTools(v)) do setAttr("statSet_" .. i, "active", t.set, key) end
SKILL.drawSources(key)
end
function SKILL.glowColor(c) return c:sub(1, 7) .. "B3" end
function SKILL.fxTint(c) return c:sub(1, 7) .. "80" end
function SKILL.drawSources(key)
local v = view(key)
local stat = v.statCol and (v.statsHover and STAT.hoverOrder() or CFG.statOrder)[v.statCol]
local lit = { item = {}, weapon = {}, condition = {} }
if stat then
for _, e in ipairs(STAT.effects(stat, weaponContext(key))) do
if e.i then lit[e.kind][e.i] = STAT.color(e.up, e.down, e.capped, e.wyrd) end
end
end
local changed = stat and (next(STAT.effects(stat, weaponContext(key))) ~= nil
or statEdited(stat) or pendingStats[stat] ~= nil)
v.barFx = stat and (next(lit.item) and SKILL.fxKey(stat, SKILL.off()) or (changed and "none")) or nil
SKILL.drawBar(key)
local owned = SKILL.fxStates and #SKILL.fxStates > 0 and SKILL.owned() or nil
for _, fx in ipairs(SKILL.fxStates or {}) do
local st = SKILL.fxStates[fx]
for _, it in ipairs(SKILL.fxItems(st, fx ~= st, owned)) do
setAttr("skillFx_" .. fx .. "_" .. it.bar, "color", SKILL.fxInk(it, st), key)
end
end
local pulse = ACTIVATION.pulse
for i = 1, weaponCount() do
if weaponAt(i) then
local c = lit.weapon[i] or (pulse and pulse.weapons[i] and pulse.color) or nil
if c then setAttr("fxGlow_" .. i, "color", SKILL.glowColor(c), key) end
setAttr("fxGlow_" .. i, "active", c ~= nil, key)
end
end
for i = 1, #CONDITIONS do
if lit.condition[i] then setAttr("condFx_" .. i, "color", SKILL.fxTint(lit.condition[i]), key) end
setAttr("condFx_" .. i, "active", lit.condition[i] ~= nil, key)
end
end
function ui.drawHp(key)
if not key then
for _, k in ipairs(ui.viewers) do ui.drawHp(k) end
return
end
local upTo = idNum(view(key).hpHover, "hpSeg") or 0
for i = 1, ui.hpMax() do
local s = ui.hpSegment(i, upTo)
setAttr("hpSeg_" .. i, "colors", s.colors, key)
setAttr("hpSeg_" .. i, "image", s.image, key)
end
setAttr("hpOut", "active", ui.hpOut(), key)
SKILL.drawBar(key)
end
ui.redrawStats = ui.drawStats
function ui.drawStatus()
for _, s in ipairs(STATUSES) do
setAttr("statusIcon_" .. s.key, "active", s.key == fighter.status)
end
if ui.glowing() then setAttr("statusGlow", "color", ui.glowColor()) end
ACTIVATION.drawReady()
local at = ui.statusSpots()
for _, s in ipairs(STATUSES) do
local p = at[s.key]
if p then setAttr("statusOptBox_" .. s.key, "offsetXY", xyAttr(p[1], p[2])) end
setAttr("statusOptBox_" .. s.key, "active", p ~= nil)
end
end
function ACTIVATION.attackCost(i, pi)
local w = weaponAt(i)
local p = w and w.profiles and w.profiles[pi]
if not p or fighter.activation ~= "active" or fighter.actionsLeft <= 0 then return 0 end
if profileDown(p) or not TRAIT_RULES.usable(p, w) then return 0 end
local key, cost = TRAIT_RULES.attackAction(w, p)
if cost == nil and ACTIVATION.prepaid(key) then return 0 end
local entry = ACTIONS[indexOf(ACTIONS, key) or 0]
return math.min(fighter.actionsLeft, cost or (entry and SKILL.cost(entry)) or 1)
end
function ACTIVATION.prepaid(key)
if key == "fight" then return fighter.usedActions.fight == true end
return (tonumber(fighter.shotsPaid) or 0) > 0
end
ACTIVATION.PULSE = {
fight = function(p) return isMelee(p) end,
shoot = function(p) return not isMelee(p) end,
braced_shot = function(p) return not isMelee(p) and hasTrait(p, TRAIT.heavy) end,
aimed_shot = function(p) return TRAIT_RULES.canAim(p) end,
}
function ACTIVATION.pulseWeapons(key)
local fits = ACTIVATION.PULSE[key]
if not fits then return false end
local lit = {}
for i = 1, weaponCount() do
for _, p in ipairs((weaponAt(i) or {}).profiles or {}) do
if fits(p) then lit[i] = true end
end
end
if next(lit) == nil then return false end
local c, token = ACTIVATION.actionGlow(key), {}
ACTIVATION.pulse = { weapons = lit, token = token, color = string.format("#%02X%02X%02Xff",
math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) }
for _, k in ipairs(ui.viewers) do SKILL.drawSources(k) end
Wait.time(function()
if not (ACTIVATION.pulse and ACTIVATION.pulse.token == token) then return end
ACTIVATION.pulse = nil
for _, k in ipairs(ui.viewers) do SKILL.drawSources(k) end
end, tonumber(CFG.weaponFlash) or 1.5)
return true
end
function ACTIVATION.hoverSpends(key)
local v = view(key)
local prefix, n = tostring(v.actHover or ""):match("^(act_.+)_(%d+)$")
local P = PANELS[prefix or ""]
local a = P and P.list[tonumber(n)]
if a then
if a.roll or a.always or fighter.actionsLeft <= 0 then return 0 end
return math.min(fighter.actionsLeft, SKILL.cost(a))
end
local r, i, pi = tostring(v.costHover or ""):match("^(r?)(%d+)_(%d+)$")
if r == "r" then return ACTIVATION.reloadCost(tonumber(i), tonumber(pi)) end
return i and ACTIVATION.attackCost(tonumber(i), tonumber(pi)) or 0
end
function ACTIVATION.reloadCost(i, pi)
local w = weaponAt(i)
local p = w and w.profiles and w.profiles[pi]
local entry = ACTIONS[indexOf(ACTIONS, "reload") or 0]
if not (p and entry) or TRAIT_RULES.ammoState(w, p) ~= "out" then return 0 end
if fighter.activation ~= "active" or fighter.actionsLeft <= 0 then return 0 end
return math.min(fighter.actionsLeft, SKILL.cost(entry))
end
function ACTIVATION.spender(e, P) return not P.icon and not e.roll and not e.always end
function ui.drawReady()
local split, first, later = ACTIVATION.readyHalves()
setAttr("readyGlow_S", "active", fighter.activation == "ready" and not split)
if hasAsset("dice_half") then
setAttr("readyHalf_S", "active", later)
setAttr("readyHalf2_S", "active", first)
setAttr("readySplit_S", "active", split)
end
setAttr("activeMark", "active", ui.activeShown())
for n = 1, ui.activeParts or 0 do setAttr("activeMark_" .. n, "color", ui.activeColor()) end
local lost = {}
for n = 1, 2 do
local on = nil
on, lost[n] = ACTIVATION.readyLook(n)
setAttr("readyGlow_" .. n, "active", on)
end
for _, key in ipairs(ui.viewers) do
local after = fighter.actionsLeft - ACTIVATION.hoverSpends(key)
for n = 1, 2 do
local spent = fighter.actionsLeft >= 3 - n and after < 3 - n
setAttr("readyGlow_" .. n, "color", lost[n] and ACTIVATION.litColor(lost[n]) or ui.actionLit(spent), key)
end
end
ACTIVATION.drawReach()
end
ACTIVATION.drawReady = ui.drawReady
function ACTIVATION.hoverEnter(key, field, id)
local v = view(key)
v[field .. "Token"] = (v[field .. "Token"] or 0) + 1
if v[field] == id then return end
v[field] = id
ui.drawReady()
end
function ACTIVATION.hoverLeave(key, field, id)
local v = view(key)
if v[field] ~= id then return end
local tk = field .. "Token"
v[tk] = (v[tk] or 0) + 1
local token = v[tk]
Wait.time(function()
if token ~= v[tk] or v[field] ~= id then return end
v[field] = nil
ui.drawReady()
end, CFG.popupLinger)
end
function ACTIVATION.draw()
setAttr("outPanel", "active", fighter.outOfAction == true)
if fighter.outOfAction then
local W, _, _, titleH = ACTIVATION.geometry(LAY.midBtnH)
local t = ACTIVATION.outTitle()
setText("outTitle", t)
setTextSize("outTitle", fitSize(t, W * 0.9, titleH, LAY.midTitleFont, true), W * 0.9, titleH)
end
setAttr("recoveryPanel", "active", ACTIVATION.isOpen())
setAttr("recoveryRow", "active", not ACTIVATION.doomed())
setAttr("recoveryDoom", "active", ACTIVATION.doomed())
if fighter.recovery then setText("recoveryValTxt", tostring(fighter.recovery.dice)) end
setAttr("nervePanel", "active", ACTIVATION.nerveOpen())
if ACTIVATION.nerve then
local v, s = ACTIVATION.nerveValue(), LAY.midDiamond * LAY.iconPad
setText("nerveValTxt", v)
setTextSize("nerveValTxt", fitSize(v, s, s, LAY.midBtnFont, true), s, s)
setAttr("nerveValTxt", "color", ACTIVATION.nerveInk())
local head, stat = ACTIVATION.nerveTexts()
setText("nerveTitle", head.text)
setTextSize("nerveTitle", head.size, head.w, head.h)
setAttr("nerveTitle", "color", head.ink)
setText("nerveStat", stat.text)
setTextSize("nerveStat", stat.size, stat.w, stat.h)
setAttr("nerveStat", "offsetXY", xyAttr(stat.x, stat.y))
end
setAttr("nerveConfirm", "active", ACTIVATION.nerveAsks())
local asking = ACTIVATION.questioning()
setAttr("nerveRow", "active", not asking)
setAttr("nerveQuestion", "active", asking)
setAttr("nerveQGo", "active", not (ACTIVATION.asksPair() or ACTIVATION.asksYes() or ACTIVATION.asksSkip()))
setAttr("nerveQPair", "active", ACTIVATION.asksPair())
setAttr("nerveQYes", "active", ACTIVATION.asksYes())
setAttr("nerveQSkip", "active", ACTIVATION.asksSkip())
if ACTIVATION.asksPair() then
setText("nerveCoverTxt", ACTIVATION.coverText())
setAttr("nerveCoverTxt", "color", ACTIVATION.coverInk())
end
SKILL.drawBar()
end
function ui.drawName()
local v = ui.nameView()
for _, c in ipairs(v.copies) do
if v.sym then
setTextSize("fighterRank" .. c[1], v.symSize, LAY.nameW, v.h)
setAttr("fighterRank" .. c[1], "offsetXY", xyAttr(v.symX + c[2], v.y + c[3]))
end
setText("fighterName" .. c[1], v.name)
setTextSize("fighterName" .. c[1], v.size, LAY.nameW, v.h)
setAttr("fighterName" .. c[1], "offsetXY", xyAttr(v.nameX + c[2], v.y + c[3]))
end
setAttr("nameBtn", "width", string.format("%g", v.w))
local sd = LAY.nameShadow * v.arrowD
for id, side in pairs({ nameDown = -1, nameUp = 1 }) do
setAttr(id .. "Shadow", "offsetXY", xyAttr(side * v.arrowX + sd, -sd))
setAttr(id .. "Txt", "offsetXY", xyAttr(side * v.arrowX, 0))
setAttr(id, "offsetXY", xyAttr(side * v.arrowX, 0))
end
end
function ui.drawArrows(key)
for _, k in ipairs(key and { key } or ui.viewers) do
setAttr("nameArrows", "active", view(k).nameHover == true, k)
end
end
function ACTIVATION.drawDice()
local v = ACTIVATION.diceView()
setAttr("dicePanel", "active", v.on)
if not v.on then return end
setAttr("diceWait", "active", v.rolling)
local function size(id, d)
local t = string.format("%.1f", d)
setAttr(id, "width", t)
setAttr(id, "height", t)
end
for i, s in ipairs(v.slots) do
local id, f, D = "_" .. i, s.face, s.D
setAttr("dieSlot" .. id, "active", s.on)
if s.on then
setAttr("dieSlot" .. id, "offsetXY", xyAttr(s.x, s.y))
size("dieSlot" .. id, D)
local plain = f.cart == nil
setAttr("dieEdge" .. id, "active", plain)
setAttr("dieFace" .. id, "active", plain)
if plain then
size("dieEdge" .. id, D)
setAttr("dieEdge" .. id, "color", f.ink)
size("dieFace" .. id, ACTIVATION.faceSide(D))
setAttr("dieFace" .. id, "color", ui.gradTint(f.fill))
end
if hasAsset("dice_half") then
setAttr("dieHalf" .. id, "active", f.half ~= nil)
if f.half then
size("dieHalf" .. id, ACTIVATION.faceSide(D))
setAttr("dieHalf" .. id, "color", f.half)
end
end
if hasAsset("dice_ammo") then
setAttr("dieAmmo" .. id, "active", not plain)
if not plain then
size("dieAmmo" .. id, f.cart)
setAttr("dieAmmo" .. id, "color", f.cartInk)
end
for _, part in ipairs(ACTIVATION.cartTexts(f)) do
local pid = part.id .. id
setAttr(pid, "active", part.on)
if part.on then
setText(pid, part.text)
setAttr(pid, "offsetXY", xyAttr(part.x, part.y))
setTextSize(pid, part.size, part.w, part.h)
end
end
end
for k = 1, #ACTIVATION.PIP_SPOTS do
local pid = "diePip" .. id .. "_" .. k
setAttr(pid, "active", f.pips[k] == true)
if f.pips[k] then
local px, py, pw = ACTIVATION.pipAt(k, ACTIVATION.markSide(D))
setAttr(pid, "offsetXY", xyAttr(px, py))
size(pid, pw)
setAttr(pid, "color", f.ink)
end
end
setAttr("dieNum" .. id, "active", f.num ~= nil)
if f.num then
setText("dieNum" .. id, f.num)
setAttr("dieNum" .. id, "color", f.numInk)
setAttr("dieNum" .. id, "offsetXY", xyAttr(f.numX, f.numY))
setTextSize("dieNum" .. id, f.numSize, f.numW, f.numH)
end
setAttr("dieIcon" .. id, "active", f.icon ~= nil)
if f.icon then
setAttr("dieIcon" .. id, "image", f.icon)
setAttr("dieIcon" .. id, "color", f.iconInk)
setAttr("dieIcon" .. id, "offsetXY", xyAttr(f.iconX, 0))
size("dieIcon" .. id, f.iconD)
end
setAttr("dieMark" .. id, "active", f.mark ~= nil)
if f.mark then
setAttr("dieMark" .. id, "color", f.markInk)
setAttr("dieMark" .. id, "offsetXY", xyAttr(f.markX, 0))
setTextSize("dieMark" .. id, f.markSize, f.markW, ACTIVATION.markSide(D) * 0.84)
end
for k, g in ipairs(s.tags) do
local tid, xid = "dieTag" .. id .. "_" .. k, "dieTagTxt" .. id .. "_" .. k
setAttr(tid, "active", g.on)
setAttr(xid, "active", g.on)
if g.on then
setAttr(tid, "color", g.ink)
setAttr(tid, "offsetXY", xyAttr(g.x, g.y))
setAttr(tid, "width", string.format("%.1f", g.w))
setAttr(tid, "height", string.format("%.1f", g.h))
setText(xid, g.text)
setAttr(xid, "offsetXY", xyAttr(g.x, g.y))
local t = ACTIVATION.tagText(g)
setAttr(xid, "fontSize", t.fontSize)
setAttr(xid, "scale", t.scale)
setAttr(xid, "width", t.width)
setAttr(xid, "height", t.height)
end
end
end
end
local b = v.sum or {}
setAttr("diceSum", "active", b.text ~= nil)
if b.text then
setText("diceSum", b.text)
setAttr("diceSum", "color", b.ink)
setAttr("diceSum", "offsetXY", xyAttr(b.x, 0))
setTextSize("diceSum", b.size, b.w / FIT + 2, b.size * 1.25)
end
setAttr("diceSumIcon", "active", b.icon ~= nil)
if b.icon then
setAttr("diceSumIcon", "image", b.icon)
setAttr("diceSumIcon", "color", b.ink)
setAttr("diceSumIcon", "offsetXY", xyAttr(b.x, 0))
size("diceSumIcon", b.d)
end
local a = v.ammo
setAttr("ammoSum", "active", a ~= nil)
if a then
setText("ammoSum", a.text)
setAttr("ammoSum", "color", a.ink)
setAttr("ammoSum", "offsetXY", xyAttr(a.x, 0))
setTextSize("ammoSum", a.size, a.w / FIT + 2, a.size * 1.25)
end
local l = v.best or {}
setAttr("diceBest", "active", l.text ~= nil)
if l.text then
setText("diceBest", l.text)
setAttr("diceBest", "color", l.ink)
setAttr("diceBest", "offsetXY", xyAttr(l.x, 0))
setTextSize("diceBest", l.size, l.w / FIT + 2, l.size * 1.25)
end
setAttr("diceBestIcon", "active", l.icon ~= nil)
if l.icon then
setAttr("diceBestIcon", "image", l.icon)
setAttr("diceBestIcon", "color", l.ink)
setAttr("diceBestIcon", "offsetXY", xyAttr(l.x, 0))
size("diceBestIcon", l.d)
end
for k = 1, 2 do
local t, id = v.lines and v.lines[k] or {}, "diceLine_" .. k
setAttr(id, "active", t.text ~= nil)
if t.text then
setText(id, t.text)
setAttr(id, "color", t.ink)
setAttr(id, "offsetXY", xyAttr(0, t.y))
setTextSize(id, t.size, t.w / FIT + 2, t.size * 1.25)
end
end
end
function ACTIVATION.rolling(title, mod, modInk)
ACTIVATION.roll = { title = title, mod = mod, modInk = modInk, rolling = true }
ACTIVATION.rollToken = (ACTIVATION.rollToken or 0) + 1
ACTIVATION.drawDice()
SKILL.drawBar()
end
function ACTIVATION.showDice(roll)
ACTIVATION.roll = roll
ACTIVATION.rollToken = (ACTIVATION.rollToken or 0) + 1
roll.held = true
ACTIVATION.drawDice()
SKILL.drawBar()
Wait.time(function()
if ACTIVATION.roll ~= roll then return end
roll.held = nil
if not next(ACTIVATION.rollHover) and not ACTIVATION.leaving then ACTIVATION.hideDice() end
end, CFG.diceShow)
end
function ACTIVATION.hideDice()
ACTIVATION.roll, ACTIVATION.rollHover, ACTIVATION.leaving = nil, {}, nil
ACTIVATION.rollToken = (ACTIVATION.rollToken or 0) + 1
ACTIVATION.drawDice()
SKILL.drawBar()
end
ACTIVATION.rollHover = {}
function ACTIVATION.rollEnter(key)
if not ACTIVATION.roll then return end
ACTIVATION.rollHover[key] = true
ACTIVATION.leaveToken = (ACTIVATION.leaveToken or 0) + 1
ACTIVATION.leaving = nil
end
function ACTIVATION.rollLeave(key)
if not ACTIVATION.rollHover[key] then return end
ACTIVATION.rollHover[key] = nil
ACTIVATION.leaveToken = (ACTIVATION.leaveToken or 0) + 1
local t, roll = ACTIVATION.leaveToken, ACTIVATION.roll
ACTIVATION.leaving = t
Wait.time(function()
if ACTIVATION.leaving == t then ACTIVATION.leaving = nil end
if t == ACTIVATION.leaveToken and roll and ACTIVATION.roll == roll and not roll.rolling
and not roll.held and not next(ACTIVATION.rollHover) then
ACTIVATION.hideDice()
end
end, CFG.diceLeave or CFG.popupLinger)
end
function ui.drawToggle(prefix, i, key)
local P = PANELS[prefix]
local c = ui.panelLayout(prefix)[i]
local look = ui.entryLook(P, P.list[i], key)
setAttr(prefix .. "Bg_" .. i, "color", look.fill, key)
setAttr(prefix .. "Dia_" .. i, "color", look.fill, key)
setAttr(prefix .. "Txt_" .. i, "color", look.ink, key)
setText(prefix .. "Txt_" .. i, look.label, key)
setTextSize(prefix .. "Txt_" .. i, fitSize(look.label, c.textW, c.h, LAY.popS.valueFont, true),
c.textW, c.h, key)
if P.icon then return end
setAttr(prefix .. "Cost_" .. i, "color", look.costInk, key)
local e = P.list[i]
if not (e.icon and hasAsset(e.icon)) then
local d, cost = c.dd * LAY.popS.costPad, tostring(SKILL.costOf(e) or "")
setText(prefix .. "Cost_" .. i, cost, key)
setTextSize(prefix .. "Cost_" .. i, fitSize(cost, d, d, LAY.popS.valueFont, true), d, d, key)
end
end
function ui.drawActions(key)
if not key then
for _, k in ipairs(ui.viewers) do ui.drawActions(k) end
return
end
local prefixes = {}
for _, prefix in ipairs(SKILL.SPECIAL_ORDER) do prefixes[#prefixes + 1] = prefix end
for _, st in ipairs(STATUSES) do prefixes[#prefixes + 1] = ui.actionPanelOf(st.key) end
for _, prefix in ipairs(prefixes) do
for i = 1, #((PANELS[prefix] or {}).list or {}) do ui.drawToggle(prefix, i, key) end
end
end
redrawActions = ui.drawActions
function SKILL.drawInfo(key)
if not key then
for _, k in ipairs(ui.viewers) do SKILL.drawInfo(k) end
return
end
local v, owned = view(key), SKILL.owned()
local it = owned[v.skillHover or 0]
if it and it.state ~= SKILL.state(v) then v.skillHover = nil end
local shown = v.infoHover or (v.barInfo and v.skillHover and "skillInfo_" .. v.skillHover)
for _, id in ipairs(SKILL.infoIds or {}) do setAttr(id, "active", shown == id, key) end
end
function SKILL.drawBar(key)
if not key then
for _, k in ipairs(ui.viewers) do SKILL.drawBar(k) end
return
end
local shown = SKILL.state(view(key))
setAttr("skillState_roll", "active", shown == "roll", key)
setAttr("skillState_target", "active", shown == "target", key)
if shown == "target" then
local t = SKILL.targetTitle(view(key))
setText("targetTitle", t.text, key)
setAttr("targetTitle", "color", t.ink, key)
setTextSize("targetTitle", t.size, t.w, LAY.skillBand, key)
if hasAsset("target_mark") then
for _, m in ipairs(SKILL.TARGET_MARKS) do setAttr(m[1], "active", t.icon == true, key) end
end
for _, m in ipairs(t.icon and SKILL.TARGET_MARKS or {}) do
local d = string.format("%.1f", t.d)
setAttr(m[1], "offsetXY", xyAttr(m[2] * t.ix, 0), key)
setAttr(m[1], "width", d, key)
setAttr(m[1], "height", d, key)
setAttr(m[1], "color", t.ink, key)
end
end
if shown == "roll" then
local t = SKILL.rollTitle()
setText("rollTitle", t.text, key)
setAttr("rollTitle", "offsetXY", xyAttr(t.x, 0), key)
setTextSize("rollTitle", t.size, t.w, LAY.skillBand, key)
setAttr("rollTitleMod", "active", t.mod ~= "", key)
if t.mod ~= "" then
setText("rollTitleMod", t.mod, key)
setAttr("rollTitleMod", "color", t.modInk, key)
setAttr("rollTitleMod", "offsetXY", xyAttr(t.mx, 0), key)
setTextSize("rollTitleMod", t.size, t.w, LAY.skillBand, key)
end
end
for state = 1, #SKILL.KINDS do setAttr("skillState_" .. state, "active", state == shown, key) end
for _, fx in ipairs(SKILL.fxStates or {}) do setAttr("skillState_" .. fx, "active", fx == shown, key) end
SKILL.drawInfo(key)
end
function SKILL.drawWyrd()
for _, it in ipairs(SKILL.owned()) do
if it.kind == "skill" and it.type == "wyrd" and STAT.works(it) then
setAttr("skillTxt_" .. it.bar, "color", SKILL.ink(it))
setText("skillTxt_" .. it.bar, SKILL.label(it))
for _, fx in ipairs(SKILL.fxStates or {}) do
if SKILL.fxStates[fx] and it.maintained and (it.maintained[SKILL.fxStates[fx]] or 0) ~= 0 then
setText("skillFx_" .. fx .. "_" .. it.bar, SKILL.label(it))
end
end
end
end
end
function SKILL.drawBurnt()
for _, it in ipairs(SKILL.owned()) do
if (it.burns or it.spends) and (it.kind ~= "skill" or STAT.works(it)) then
setAttr("skillTxt_" .. it.bar, "color", SKILL.ink(it))
end
end
end
function ui.drawConditionBar()
local slots = ui.conditionSlots()
for i, c in ipairs(CONDITIONS) do
local s, n = slots[i], conditionCount(c.key)
if s then
setAttr("condSlot_" .. i, "offsetXY", xyAttr(s.x, s.y))
local badge, size = ui.stackBadge(n)
setText("condCount_" .. i, badge)
local bw, bh = ui.badgePlate()
setTextSize("condCount_" .. i, size, bw, bh)
setAttr("condBadge_" .. i, "active", n >= 2)
end
setAttr("condSlot_" .. i, "active", s ~= nil)
if not s then
for _, key in ipairs(ui.viewers) do
local v = view(key)
if v.infoFrom == "condBar_" .. i then
v.infoHover, v.infoFrom = nil, nil
if not seeding then SKILL.drawInfo(key) end
end
end
end
end
end
function TRAIT_RULES.perViewer(key, fn)
key = key or ui.only
local keys = key and { key } or {}
if not key then
for _, k in ipairs(ui.viewers) do
if view(k).targetMulti then keys = ui.viewers break end
end
end
if #keys == 0 then return fn() end
local was, wasMulti = ui.only, TRAIT_RULES.multi
for _, k in ipairs(keys) do
ui.only, TRAIT_RULES.multi = k, view(k).targetMulti == true or nil
local ok, err = pcall(fn)
ui.only, TRAIT_RULES.multi = was, wasMulti
if not ok then error(err, 0) end
end
end
local drawProfileNow
function ui.drawProfile(i, pi, key)
TRAIT_RULES.perViewer(key, function() drawProfileNow(i, pi) end)
end
function drawProfileNow(i, pi)
local p = weaponAt(i) and weaponAt(i).profiles[pi]
if not p then return end
local v = ui.profileView(i, pi, p)
local tag = function(t) return string.format("%s_%d_%d", t, i, pi) end
drawBox(tag("prof"), v.box)
local g = ui.popupGeom(weaponAt(i))
for ci, col in ipairs(PROFILE_COLS) do
if g.shown[ci] and showsCol(p, col.key) then
local id = string.format("%s_%d", tag("pval"), ci)
local val, tint = TRAIT_RULES.value(weaponAt(i), p, col.key)
setText(id, val)
setAttr(id, "color", tint)
setTextSize(id, fitSize(val, g.need[ci], g.hd, LAY.popS.valueFont, true), g.need[ci], g.hd)
end
end
for _, k in ipairs({ "", "2" }) do
local id = tag("ptraits" .. k)
setText(id, v.segs and "" or v.traits["text" .. k])
setAttr(id, "color", v.traits.color)
setAttr(id, "offsetXY", xyAttr(0, v.traits["y" .. k]))
setTextSize(id, v.traits.size, g.traitW, v.traits.h)
end
for n = 1, TRAIT_RULES.segRoom(weaponAt(i), p, g) do
local s = v.segs and v.segs[n] or { x = 0, y = v.traits.y, w = 0, h = v.traits.h, text = "",
color = v.traits.color }
local id = tag("ptseg") .. "_" .. n
setText(id, s.text)
setAttr(id, "color", s.color)
setAttr(id, "offsetXY", xyAttr(s.x, s.y))
setTextSize(id, v.traits.size, s.w / FIT + 2, s.h)
if s.mark == TRAIT.reliable then
setAttr(tag("prelBtn"), "offsetXY", xyAttr(s.x, s.y))
setAttr(tag("prelBtn"), "width", string.format("%.1f", s.w + 8))
end
end
for ci, col in ipairs(PROFILE_COLS) do
if col.key == "Hit" and g.shown[ci] and showsCol(p, col.key) and TRAIT_RULES.hitButton(p) then
setAttr(tag("phitEdge"), "active", TRAIT_RULES.reroll[weaponAt(i)] ~= nil)
end
end
setText(tag("psecond"), v.second.text)
setAttr(tag("psecond"), "color", v.second.color)
setTextSize(tag("psecond"), v.second.size, g.cellW, g.hd)
if v.rapidFire then
for k = 1, #PROFILE_MODES do setAttr(tag("pmode") .. "_" .. k, "active", k == v.mode) end
end
if v.melee then return end
local rv = TRAIT_RULES.rangeView(weaponAt(i), p, g)
if rv then
setAttr(tag("prange"), "active", rv.on)
setAttr(tag("prange"), "offsetXY", xyAttr(rv.x, g.hd / 2))
setTextSize(tag("prange"), rv.size, rv.w, g.hd)
end
setAttr(tag("paimEdge"), "active", v.aim.on)
for k in ipairs(PROFILE_MODES) do
if k == 1 or v.rapidFire then
local id, a = tag("pmode") .. "_" .. k, v.aim.modes[k]
setAttr(id, "color", v.aim.color)
setAttr(id, "offsetXY", xyAttr(a.x, 0))
setTextSize(id, a.size, g.cellW, g.hd)
end
end
setAttr(tag("paimSign"), "active", v.aim.on)
setAttr(tag("paimSign"), "offsetXY", xyAttr(v.aim.signX, 0))
setTextSize(tag("paimSign"), v.aim.signSize, g.cellW, g.hd)
end
function TRAIT_RULES.setAim(i, on)
local w = weaponAt(i)
if not w or (TRAIT_RULES.aiming[w] == true) == (on == true) then return end
TRAIT_RULES.aiming[w] = on and true or nil
for pi = 1, #(w.profiles or {}) do ui.drawProfile(i, pi) end
ui.drawStats()
end
function TRAIT_RULES.setReroll(i, how)
local w = weaponAt(i)
if not w or TRAIT_RULES.reroll[w] == how then return end
TRAIT_RULES.reroll[w] = how
for pi = 1, #(w.profiles or {}) do ui.drawProfile(i, pi) end
end
function TRAIT_RULES.drawMarks()
for i = 1, weaponCount() do
local w = weaponAt(i)
for pi, p in ipairs((w and w.profiles) or {}) do
if TRAIT_RULES.marked(p, w) then ui.drawProfile(i, pi) end
end
end
end
function TRAIT_RULES.drawGlows(key)
TRAIT_RULES.perViewer(key, function()
for i = 1, weaponCount() do
local w = weaponAt(i)
if w then
local col = TRAIT_RULES.glow(w)
setAttr("blockedGlow_" .. i, "color", ACTIVATION.litColor(col or COL.weaponBlocked))
setAttr("blockedGlow_" .. i, "active", col ~= nil)
if TRAIT_RULES.roleShown(w) then
local role = TRAIT_RULES.roleLabel(w)
if role then setText("wpnRole_" .. i, role) end
setAttr("wpnRole_" .. i, "active", role ~= nil)
if ui.wpnStandIn and ui.wpnStandIn[i] then
setAttr("wpnType_" .. i, "active", role == nil)
else
setAttr("wpnRolePlate_" .. i, "active", role ~= nil)
end
end
end
end
end)
end
function TRAIT_RULES.drawWeapons(key)
TRAIT_RULES.perViewer(key, function()
TRAIT_RULES.drawGlows()
for i = 1, weaponCount() do
local w = weaponAt(i)
for pi = 1, #((w and w.profiles) or {}) do ui.drawProfile(i, pi) end
end
end)
end
function TRAIT_RULES.measure(i, player, draw)
local R, w = TRAIT_RULES, weaponAt(i)
local gap, aim, asked, changed = nil, nil, player == nil, false
for _, p in ipairs((w and w.profiles) or {}) do
local sr, lr = R.marksman(p)
if sr and not asked then
if R.gapTo then gap, aim = R.gapTo(player) end
asked = true
end
local void = gap and aim and tonumber(aim.void)
local on = (sr and gap and ((void and gap <= void + CFG.engageSlack)
or (gap > sr + CFG.engageSlack and gap <= lr + CFG.engageSlack))) and true or nil
changed = changed or on ~= R.longShot[p]
R.longShot[p] = on
end
if changed and draw then
for pi = 1, #w.profiles do ui.drawProfile(i, pi) end
end
return changed
end
function TRAIT_RULES.dropAims()
local R = TRAIT_RULES
for i = 1, weaponCount() do
local w = weaponAt(i)
if w and R.aiming[w] then
local may = false
for _, p in ipairs(w.profiles or {}) do may = may or R.mayAim(w, p) end
if not may then R.setAim(i, false) end
end
end
end
function TRAIT_RULES.shotFired(w, p, attack)
local R = TRAIT_RULES
if not attack.melee then fighter.aimedShot = nil end
if attack.melee or fighter.activation ~= "active" or fighter.status == "engaged" then return end
local function close()
for i = 1, weaponCount() do
if weaponAt(i) then weaponAt(i).gunfight = nil end
end
end
if attack.free == "gunfighter" then
close()
elseif attack.free == "assault" or attack.cost == nil then
close()
if attack.free then fighter.assaulted = true else
fighter.shots = fighter.shots or {}
fighter.shots[#fighter.shots + 1] = attack.action
end
if attack.action == "shoot" and hasTrait(p, TRAIT.light) and #SKILL.with("gunfighter") > 0 then
w.gunfight = true
end
end
R.dropAims()
R.drawGlows()
end
function TRAIT_RULES.endShots()
fighter.shots, fighter.assaulted, fighter.shotsPaid, fighter.aimedShot = nil, nil, nil, nil
for i = 1, weaponCount() do
if weaponAt(i) then weaponAt(i).gunfight = nil end
end
TRAIT_RULES.drawGlows()
end
function TRAIT_RULES.endVolleys()
if next(TRAIT_RULES.volley) == nil then return end
TRAIT_RULES.volley = {}
TRAIT_RULES.drawWeapons()
ui.drawStats()
end
openedFlyout = function(id, key)
local R = TRAIT_RULES
local i = tonumber(tostring(id):match("^pop_(%d+)$"))
local w = i and weaponAt(i)
if not w then return end
local stab, melee = false, false
R.aiming[w] = nil
for _, p in ipairs(w.profiles or {}) do
if R.held(w, p) and not profileDown(p) then R.aiming[w] = R.volley[w].aimed end
if fighter.aimedShot and fighter.activation == "active" and R.mayAim(w, p) then R.aiming[w] = true end
end
for _, p in ipairs(w.profiles or {}) do
if isMelee(p) then
p.attacks = R.opening(w, p)
stab, melee = stab or R.backstab(p), true
else
if hasRapidFire(p) then p.mode = fighter.status == "engaged" and "attack" or "rapid_fire" end
if R.combi(p) and not profileDown(p) and (R.combiUp(w) >= 2 or R.held(w, p)) then p.ammo = "combi"
elseif R.extraShots(p) and not profileDown(p) then p.ammo = "extra" end
end
end
R.stabbing[w] = stab and R.backstabNear ~= nil and R.backstabNear(key) or nil
R.support[w], R.supportBy[w] = nil, nil
if melee and fighter.status == "engaged" and R.supportNear then
local n, by = R.supportNear(key)
R.support[w], R.supportBy[w] = n, n and by or nil
end
R.measure(i, CFG.preMeasure and key or nil)
for pi = 1, #(w.profiles or {}) do ui.drawProfile(i, pi) end
end
local function drawAll()
for _, key in ipairs(ui.viewers) do ui.showFlyout(nil, key, true) end
SKILL.wasOff = SKILL.off()
SKILL.wasShape = SKILL.shape()
SKILL.builtShape = SKILL.wasShape
ui.drawStats()
SKILL.drawWyrd()
SKILL.drawBurnt()
ui.drawHp()
ui.drawStatus()
ui.drawReady()
ACTIVATION.draw()
ACTIVATION.drawDice()
ui.drawActions()
for i = 1, #PANELS.cond.list do ui.drawToggle("cond", i) end
ui.drawConditionBar()
TRAIT_RULES.drawWeapons()
SKILL.drawInfo()
ui.drawName()
ui.drawArrows()
ui.drawCompact()
end
function ui.headXY(compact) return xyAttr(0, compact and LAY.compactDrop or 0) end
function ui.drawCompact(key)
for _, k in ipairs(key and { key } or ui.viewers) do
local on = view(k).compact == true
setAttr("cardBack", "active", not on, k)
setAttr("cardBody", "active", not on, k)
setAttr("hpBack", "active", on, k)
setAttr("cardHead", "offsetXY", ui.headXY(on), k)
end
end
function ui.setCompact(key, on)
local v = view(key)
v.compact = on == true
v.actTab = nil
v.statsHover, v.statCol, v.headHeld = false, nil, nil
v.skillHover, v.barHover, v.barFx, v.barInfo, v.barFlip = nil, nil, nil, nil, nil
v.infoHover, v.infoFrom, v.mindFrom = nil, nil, nil
v.nameHover = nil
for stat, p in pairs(pendingStats) do
if p.by == key then pendingStats[stat] = nil end
end
ui.showFlyout(nil, key, true)
ui.drawStats(key)
SKILL.drawBar(key)
SKILL.drawInfo(key)
ui.drawArrows(key)
ui.drawCompact(key)
return v.compact
end
function ui.place()
local pos, size = ui.placement()
if pos .. "|" .. size == ui.placed then return end
ui.placed = pos .. "|" .. size
for _, key in ipairs(ui.viewers) do
self.UI.setAttribute(key .. "_mundaRoot", "position", pos)
self.UI.setAttribute(key .. "_mundaTilt", "scale", size)
end
end
function refresh(reuse)
if ui.hold then ui.holdPending = true return end
local t0 = os.clock()
ui.viewers = ui.wantedViewers()
ui.facing, ui.still = nil, nil
for k in pairs(pendingStats) do pendingStats[k] = nil end
for _, key in ipairs(ui.viewers) do
local v = view(key)
v.statsHover, v.hpHover, v.pushed, v.statCol = false, nil, nil, nil
v.skillHover, v.barHover, v.barFx, v.barInfo, v.barFlip = nil, nil, nil, nil, nil
v.infoHover, v.infoFrom, v.mindFrom = nil, nil, nil
v.nameHover = nil
v.target, v.targetSig, v.targetMulti = nil, nil, nil
local p = CFG.billboard and ui.facingPlayer(key)
local yaw = p and ui.yawFor(p)
if yaw then v.yaw = yaw % 360 end
end
reuse = reuse == true and ui.content ~= nil and ui.contentSent ~= nil
local xml = ui.buildXml(reuse)
if CFG.lighterXml then xml = ui.XML_DEFAULTS .. xml end
local t1 = os.clock()
local mark = reuse and {} or nil
ui.catchUp = mark
self.UI.setXml(xml, ui.buildAssetList())
local t2 = os.clock()
ui.built = true
local raw = ui.rawTexts
local function sendRaw()
for _, key in ipairs(ui.viewers) do
for _, r in ipairs(raw) do
sent[key .. "_" .. r.id .. "|#text"] = r.text
self.UI.setValue(key .. "_" .. r.id, r.text)
end
end
end
if reuse then
local function asBuilt()
sent = {}
for _, key in ipairs(ui.viewers) do
for k, v in pairs(ui.contentSent) do sent[key .. "_" .. k] = v end
end
end
asBuilt()
local function catchUp()
if ui.catchUp ~= mark then return end
if self.UI.loading then Wait.frames(catchUp, 5) return end
ui.catchUp = nil
asBuilt()
sendRaw()
drawAll()
end
Wait.frames(catchUp, 1)
else
sent, seeding = {}, true
drawAll()
seeding = false
ui.contentSent = nil
if ui.viewers[1] then
local first = ui.viewers[1] .. "_"
ui.contentSent = {}
for k, v in pairs(sent) do
if k:sub(1, #first) == first then ui.contentSent[k:sub(#first + 1)] = v end
end
end
end
if CFG.timingLog then ui.timing(t0, t1, t2, #xml, reuse) end
local function rawLater()
if ui.rawTexts ~= raw then return end
if self.UI.loading then Wait.frames(rawLater, 5) return end
sendRaw()
end
if #raw > 0 and not reuse then Wait.frames(rawLater, 1) end
ui.retryArt()
end
function ui.timing(t0, t1, t2, bytes, reused)
local t3, w3, frames = os.clock(), os.time(), 0
local why, copies = (ui.why or "rebuild") .. (reused and ", content reused" or ""), #ui.viewers
ui.why = nil
local function done()
frames = frames + 1
local ok, loading = pcall(function() return self.UI.loading end)
if ok and loading then Wait.frames(done, 1) return end
print(string.format("[Munda timing] %s (%s): script %.0f ms (XML %.0f, setXml %.0f, drawing %.0f) -- " ..
"TTS built it in %d frame(s), %.1f s (%d s by the wall) -- %d KB, %d cop%s",
tostring(fighter.name), why, (t3 - t0) * 1000, (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000,
frames, os.clock() - t3, os.time() - w3, math.floor(bytes / 1024), copies, copies == 1 and "y" or "ies"))
end
Wait.frames(done, 1)
end
ui.XML_DEFAULTS = '<Defaults><Text verticalOverflow="Overflow" fontStyle="Bold" /></Defaults>\n'
function ui.lightContent(xml)
return (xml:gsub(' rectAlignment="MiddleCenter"', ""))
end
ui.artShown = {}
function ui.retryArt()
local fresh = nil
for _, url in ipairs({ tostring(looks.frame or ""), tostring(looks.trim or "") }) do
if url:match("^https?://") and not ui.artShown[url] then ui.artShown[url], fresh = true, url end
end
if not fresh then return end
local function again()
if self.UI.loading then Wait.frames(again, 5) return end
Wait.time(function()
if looks.frame == fresh or looks.trim == fresh then ui.why = "art"; refresh(true) end
end, (tonumber(CFG.artRetry) or 1.5) + ui.seatSlot())
end
Wait.frames(again, 1)
end
function ui.requestHide(key, delay)
local v = view(key)
v.hoverToken = v.hoverToken + 1
local token = v.hoverToken
Wait.time(function()
if token == v.hoverToken then ui.showFlyout(nil, key) end
end, delay or CFG.popupLinger)
end
function ui.cancelHide(key)
local v = view(key)
v.hoverToken = v.hoverToken + 1
end
function update()
if not ui.built or self.UI.loading then return end
local now = os.clock()
if now - (ui.placeCheck or 0) > 1 then
ui.placeCheck = now
ui.place()
end
if now - (ui.targetAt or 0) > (tonumber(CFG.targetPoll) or 0.25) then
ui.targetAt = now
ACTIVATION.drawTarget()
end
if not CFG.billboard then return end
local dt = now - (ui.turnAt or 0)
local every = tonumber(CFG.faceEvery) or 0.02
if dt < (ui.still and (tonumber(CFG.faceIdle) or every) or every) then return end
ui.turnAt = now
local again = tonumber(CFG.seatRecheck) or 0
local due = ui.seatDue ~= nil and now >= ui.seatDue
if not ui.seatAt or due or (again > 0 and now - ui.seatAt > again) then
local first = not ui.seatAt
ui.seatAt = now
if due then ui.seatDue = nil end
if table.concat(ui.wantedViewers(), ",") ~= table.concat(ui.viewers, ",") then
if due or first then
ui.why = "seats"
refresh(true)
return
end
if not ui.seatDue then ui.seatDue = now + ui.seatSlot() end
end
ui.facing = nil
end
if not ui.facing then
ui.facing = {}
for _, key in ipairs(ui.viewers) do ui.facing[key] = ui.facingPlayer(key) or false end
end
local a = CFG.faceSmooth > 0 and (1 - math.exp(-math.min(dt, math.max(every, 0.05)) / CFG.faceSmooth)) or 1
local step = math.max(tonumber(CFG.faceStep) or 0.25, 0.01)
local okR, rot = pcall(function() return self.getRotation() end)
local own = okR and rot and tonumber(rot.y) or nil
local still = own ~= nil
for _, key in ipairs(ui.viewers) do
local p = ui.facing[key]
local yaw = own and p and ui.yawFor(p, own)
local snap = yaw and ui.snaps(key)
if yaw and (snap or ui.watcher(key)) then
local v = view(key)
local moving = v.aim ~= nil and math.abs(ui.wrapAngle(yaw - v.aim)) > 0.05
v.aim = yaw
if moving then
v.settle = now + (snap and (tonumber(CFG.snapSettle) or 0.15)
or (tonumber(CFG.watchSettle) or 0.3))
end
if moving or now < (v.settle or 0) then
still = false
elseif not v.pushed or math.abs(ui.wrapAngle(yaw - v.pushed)) > 0.05 then
local left = ui.wrapAngle(yaw - v.yaw)
if snap or math.abs(left) <= (tonumber(CFG.watchStep) or 5) then v.yaw = yaw % 360
else v.yaw = (v.yaw + left * (tonumber(CFG.watchEase) or 0.6)) % 360 end
v.pushed = v.yaw
self.UI.setAttribute(key .. "_mundaRoot", "rotation", string.format("0 0 %.1f", v.yaw))
still = false
end
elseif yaw then
local v = view(key)
local turn = ui.wrapAngle(yaw - v.yaw)
local moving = v.aim ~= nil and math.abs(ui.wrapAngle(yaw - v.aim)) > 0.05
v.aim = yaw
local close = math.abs(turn) < step
if close then v.yaw = yaw % 360 else v.yaw = (v.yaw + turn * a) % 360 end
local off = v.pushed and math.abs(ui.wrapAngle(v.yaw - v.pushed)) or 360
if off >= step or (off > 0.05 and close and not moving) then
v.pushed = v.yaw
self.UI.setAttribute(key .. "_mundaRoot", "rotation",
string.format("0 0 %.1f", v.yaw))
end
if moving or math.abs(ui.wrapAngle(yaw - v.pushed)) > 0.05 then still = false end
end
end
ui.still = still
end
function ui.buildTurn()
local step = tonumber(CFG.buildStagger) or 0
if step <= 0 then return 0 end
local okT, now = pcall(function() return Time.time end)
if not (okT and type(now) == "number") then return 0 end
local okG, nextAt = pcall(function() return Global.getVar("MUNDA_NEXT_BUILD") end)
if not okG then return 0 end
local at = math.max(now, tonumber(nextAt) or 0)
if not pcall(function() Global.setVar("MUNDA_NEXT_BUILD", at + step) end) then return 0 end
return at - now
end
function ui.snaps(key)
for _, c in ipairs(type(CFG.qualityFor) == "table" and CFG.qualityFor or {}) do
if c == key then return false end
end
for _, c in ipairs(type(CFG.performanceFor) == "table" and CFG.performanceFor or {}) do
if c == key then return true end
end
return CFG.performanceMode == true
end
function ui.seatsMoved(wait)
local at = os.clock() + math.max(tonumber(CFG.seatDelay) or 0.5, tonumber(wait) or 0) + ui.seatSlot()
ui.seatDue = math.max(ui.seatDue or 0, at)
end
function ui.seatSlot()
local step = tonumber(CFG.seatStagger) or 0
if step <= 0 then return 0 end
local okM, mine = pcall(function() return self.getGUID() end)
local ok, objs = pcall(function() return getObjectsWithTag(CFG.importTag) end)
local guids = {}
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
local okG, guid = pcall(function() return obj.getGUID() end)
if okG and type(guid) == "string" then guids[#guids + 1] = guid end
end
table.sort(guids)
for k, guid in ipairs(guids) do
if okM and guid == mine then return (k - 1) * step end
end
return #guids * step
end
function onPlayerChangeColor() ui.seatsMoved() end
function onPlayerConnect() ui.seatsMoved(CFG.joinDelay) end
function onPlayerDisconnect() ui.seatsMoved() end
end
do
local function viewerOf(id)
local k, rest = tostring(id or ""):match("^(%a+)_(.+)$")
if k and ui.view[k] then return k, rest end
return ui.viewers[1], id
end
local hinted = {}
local function watching(id)
local key = viewerOf(id)
if not ui.watcher(key) then return false end
local now = os.clock()
if now - (hinted[key] or -1e9) >= (tonumber(CFG.watchHint) or 5) then
hinted[key] = now
local msg = key == ui.SPECTATOR
and "Spectators only watch. To play, sit at a colour and put one of your gang's models in front of " ..
"your side panel of the Mundane Controller."
or "You are watching this game. To play, put one of your gang's models in front of your side panel " ..
"of the Mundane Controller."
pcall(function() broadcastToColor(CFG.infoPrefix .. msg, key, { 0.9, 0.8, 0.4 }) end)
end
return true
end
function onTriggerEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local f = ui.flyoutOf(id, key)
if not f then return end
ui.cancelHide(key)
ui.showFlyout(f, key)
end
function onTriggerExit(player, value, id) if ui.spectating(player) then return end ui.requestHide((viewerOf(id))) end
function onTriggerClick(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local slot = tonumber(tostring(id or ""):match("^btnWeapon_(%d+)$"))
if slot and tostring(value) ~= "-2" and TRAIT_RULES.flammable(weaponAt(slot)) then
ACTIVATION.flame(slot)
return
end
if slot and tostring(value) ~= "-2" then
if TRAIT_RULES.switchRole(slot) then
for i = 1, weaponCount() do
local w = weaponAt(i)
for _, p in ipairs((w and w.profiles) or {}) do
if isMelee(p) then p.attacks = TRAIT_RULES.opening(w, p) end
end
end
TRAIT_RULES.drawWeapons()
ui.drawStats()
end
return
end
if id ~= "btnStatus" then return end
if tostring(value) == "-2" then
local short = (tonumber(fighter.readyMarks) or 0) < ACTIVATION.marks() and ACTIVATION.marks() > 1
setReady({ value = fighter.activation ~= "ready" or short, hand = true })
elseif fighter.activation == "ready" then
activate(player)
elseif fighter.activation == "active" then
completeActivation(player)
end
end
function onFlyoutEnter(player, value, id) if ui.spectating(player) then return end ui.cancelHide((viewerOf(id))) end
function onFlyoutExit(player, value, id) if ui.spectating(player) then return end ui.requestHide((viewerOf(id))) end
function onPickStatus(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local key; key, id = viewerOf(id)
local s = tostring(id or ""):match("^statusOpt_(.+)$")
if not (s and indexOf(STATUSES, s)) then return end
setStatus(s)
ui.showFlyout(nil, key)
end
function onNameClick(player, value, id)
if ui.spectating(player, true) then return end
local key = viewerOf(id)
if tostring(value) ~= "-2" then return end
ui.setCompact(key, not view(key).compact)
end
function onNameEnter(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
local v = view(key)
v.nameToken, v.nameMoved = (v.nameToken or 0) + 1, nil
if v.nameHover then return end
v.nameHover = true
ui.drawArrows(key)
end
function onNameExit(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
local v = view(key)
v.nameToken = (v.nameToken or 0) + 1
local token = v.nameToken
Wait.time(function()
if token ~= v.nameToken then return end
v.nameHover, v.nameMoved = nil, nil
ui.drawArrows(key)
end, v.nameMoved and CFG.tabLinger or CFG.popupLinger)
end
function onNameArrow(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local key, bare = viewerOf(id)
nudgeLift(bare == "nameUp" and 1 or -1)
view(key).nameMoved = true
end
function onChooseAction(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local prefix, n = tostring(id or ""):match("^(act_.+)_(%d+)$")
local P = PANELS[prefix or ""]
local a = P and P.list[tonumber(n)]
if not a or tostring(value) == "-2" then return end
if a.roll then
if a.roll == "nerve" then nerveCheck(player)
elseif a.roll == "agility" then agilityTest(nil, player)
elseif a.roll == "fall" then ACTIVATION.fallAsk(player)
elseif a.roll == "out" then setOutOfAction(true)
elseif a.roll == "recovery" then recoveryTest()
else ACTIVATION.stack(a.roll, player) end
return
end
useAction(a.key, player)
end
function onRevive(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end setOutOfAction(false) end
function onRecoveryValue(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
if fighter.recovery then setRecoveryDice(fighter.recovery.dice + (tostring(value) == "-2" and -1 or 1)) end
end
function onRecoveryRoll(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end rollRecovery(player) end
function onRecoveryClose(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end closeRecovery() end
function onRecoveryOut(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local rec = fighter.recovery
if not rec then return end
if tostring(value) == "-2" then closeRecovery() return end
__nqs_mundane_bus.within("cause", { action = "Recovery" }, function()
setOutOfAction({ value = true, why = rec.foes and ('within 1" of ' .. rec.foes) or nil })
end)
end
function onDiceEnter(player, value, id) if ui.spectating(player) then return end ACTIVATION.rollEnter((viewerOf(id))) end
function onDiceExit(player, value, id) if ui.spectating(player) then return end ACTIVATION.rollLeave((viewerOf(id))) end
function onNerveValue(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local n = ACTIVATION.nerve
if n and n.value then setNerveValue(n.value + (tostring(value) == "-2" and -1 or 1)) end
end
function onNerveRoll(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end rollNerve(player) end
function onNerveClose(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end ACTIVATION.giveUp(player) end
function onNerveOk(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end ACTIVATION.fall(player) end
function onNerveGo(player, value, id) if ui.spectating(player, true) then return end if watching(id) then return end ACTIVATION.goOn(player) end
function onNerveCover(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local n = ACTIVATION.nerve
if n and n.cover then setNerveValue(n.value + (tostring(value) == "-2" and -1 or 1)) end
end
function onActionTab(player, value, id)
if ui.spectating(player, true) then return end
local key; key, id = viewerOf(id)
local t = tonumber(tostring(id or ""):match("TabBtn_(%d+)$"))
if not t then return end
local v = view(key)
v.actTab = t == 2 and "special" or nil
local f = ui.flyoutOf("btnActions", key)
if v.open == f then return end
ui.cancelHide(key)
ui.showFlyout(f, key)
ui.requestHide(key, CFG.tabLinger)
end
function onSkillEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local i = idNum(id, "skillBtn")
if not i then return end
local v = view(key)
v.skillHover, v.barHover = i, true
SKILL.drawBar(key)
end
function onBarEnter(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
view(key).barHover = true
ACTIVATION.rollEnter(key)
SKILL.drawBar(key)
end
function onBarExit(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
local v = view(key)
v.barHover, v.skillHover, v.barInfo, v.barFlip = nil, nil, nil, nil
ACTIVATION.rollLeave(key)
SKILL.drawBar(key)
end
function onBarClick(player, value, id)
if ui.spectating(player, true) then return end
local key; key, id = viewerOf(id)
local v = view(key)
v.barHover = true
local it = idNum(id, "skillBtn") and SKILL.owned()[idNum(id, "skillBtn")]
if tostring(value) == "-2" then
v.barFlip = not v.barFlip or nil
elseif it and (it.burns or SKILL.maintainable(it)) and ui.watcher(key) then
return
elseif it and it.burns then
setBurnt(it.key)
elseif it and SKILL.maintainable(it) then
setMaintained({ key = it.key }, player)
elseif idNum(id, "skillBtn") then
v.barInfo = not v.barInfo or nil
v.skillHover = idNum(id, "skillBtn")
end
SKILL.drawBar(key)
end
function onSkillExit(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local v = view(key)
if v.skillHover ~= idNum(id, "skillBtn") then return end
v.skillHover = nil
SKILL.drawInfo(key)
end
function onInfoEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local panel, mind = nil, nil
if tostring(id):match("^act_") then
ACTIVATION.hoverEnter(key, "actHover", id)
end
local i = idNum(id, "condBar")
if i then
panel = CONDITIONS[i] and "condInfo_" .. i
else
local prefix, n = tostring(id):match("^(.-)_(%d+)$")
panel = prefix and SKILL.entryInfo(prefix, tonumber(n))
mind = prefix and SKILL.mindStats(prefix, tonumber(n))
end
local v = view(key)
if mind then
local was = v.mindFrom
v.mindFrom, v.mindToken = id, (v.mindToken or 0) + 1
if not was then ui.drawStats(key) end
end
if not panel then return end
v.infoHover, v.infoFrom = panel, id
v.infoToken = (v.infoToken or 0) + 1
SKILL.drawInfo(key)
end
function onInfoExit(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local v = view(key)
ACTIVATION.hoverLeave(key, "actHover", id)
if v.mindFrom == id then
v.mindToken = (v.mindToken or 0) + 1
local token = v.mindToken
Wait.time(function()
if token ~= v.mindToken or v.mindFrom ~= id then return end
v.mindFrom = nil
ui.drawStats(key)
end, CFG.popupLinger)
end
if v.infoFrom ~= id then return end
v.infoToken = (v.infoToken or 0) + 1
local token = v.infoToken
Wait.time(function()
if token ~= v.infoToken or v.infoFrom ~= id then return end
v.infoHover, v.infoFrom = nil, nil
SKILL.drawInfo(key)
end, CFG.popupLinger)
end
function onToggleCondition(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local c = ((PANELS.cond or {}).list or CONDITIONS)[idNum(id, "cond") or 0]
if not c then return end
local n = conditionCount(c.key)
if tostring(value) == "-2" then
if c.stacks then setCondition(c.key, n + 1) end
return
end
setCondition(c.key, (c.stacks and n >= 2) and n - 1 or (n > 0 and 0 or 1))
end
function onClearCondition(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local c = CONDITIONS[idNum(id, "condBar") or 0]
if c then setCondition(c.key, conditionCount(c.key) - 1) end
end
function onClickHpSegment(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local i = idNum(id, "hpSeg")
if not i then return end
local cur = clamp(fighter.wounds.current, 0, fighter.wounds.max)
setWounds(i == cur and i - 1 or i)
end
function onHpEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
if not idNum(id, "hpSeg") then return end
view(key).hpHover = id
ui.drawHp(key)
end
function onHpExit(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local v = view(key)
if v.hpHover ~= id then return end
v.hpHover = nil
ui.drawHp(key)
end
function onProfileButton(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local tag, i, pi = tostring(id or ""):match("^(%a+)_(%d+)_(%d+)$")
i, pi = tonumber(i), tonumber(pi)
local w = i and weaponAt(i)
local p = w and w.profiles and w.profiles[pi]
if not p then return end
local right = tostring(value) == "-2"
local middle = tostring(value) == "-3"
local at = { weapon = i, profile = pi }
if tag == "patk" then
if middle then
if TRAIT_RULES.aiming[w] then
TRAIT_RULES.setAim(i, false)
fighter.aimedShot = nil
elseif TRAIT_RULES.mayAim(w, p) then TRAIT_RULES.setAim(i, true) end
elseif right then
if hasRapidFire(p) and not TRAIT_RULES.lightFight(p) then
at.mode = PROFILE_MODES[profileMode(p) % #PROFILE_MODES + 1].key
setProfileState(at)
end
else
rollAttack(at, player)
end
elseif tag == "pammo" then
if middle then
reloadWeapon(at, player)
else
at.ammo = TRAIT_RULES.ammoNext(w, p, right)
setProfileState(at)
end
elseif tag == "pcnt" then
if p.ammo == "spent" then
at.ammo = "fine"
else
at.attacks = meleeStep(p, not right) or "A+1"
end
setProfileState(at)
end
end
function TRAIT_RULES.lightSupport()
local R, want = TRAIT_RULES, {}
for _, key in ipairs(ui.viewers) do
local w = weaponAt(tonumber(view(key).hitHover) or 0)
local n = w and R.support[w]
for _, obj in ipairs(n and R.supportBy[w] or {}) do
want[obj] = rgbOf(n > 0 and COL.valueUp or COL.valueMod)
end
end
local was = R.lit or {}
for obj in pairs(was) do
if not want[obj] then pcall(function() obj.highlightOff() end) end
end
for obj, rgb in pairs(want) do
if not was[obj] then pcall(function() obj.highlightOn(rgb) end) end
end
R.lit = next(want) and want or nil
if next(was) and not R.lit then ACTIVATION.nerveLight(true) end
end
function onHitEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local i, pi = tostring(id or ""):match("^phit_(%d+)_(%d+)$")
local w = weaponAt(tonumber(i) or 0)
local p = w and w.profiles and w.profiles[tonumber(pi)]
view(key).hitHover = p and isMelee(p) and tonumber(i) or nil
TRAIT_RULES.lightSupport()
end
function onHitExit(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
view(key).hitHover = nil
TRAIT_RULES.lightSupport()
end
function onHitClick(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local si, spi = tostring(id or ""):match("^phit_(%d+)_(%d+)$")
local i = tonumber(si)
local w = i and weaponAt(i)
if not w then return end
local p = w.profiles and w.profiles[tonumber(spi) or 0]
if p and TRAIT_RULES.template(p) and not (TRAIT_RULES.wild(p) and tostring(value) == "-3") then return end
if tostring(value) == "-3" then
return TRAIT_RULES.setReroll(i, TRAIT_RULES.REROLL_NEXT[TRAIT_RULES.reroll[w] or "none"])
end
setWeaponHit({ weapon = i, value = TRAIT_RULES.hit(w) + (tostring(value) == "-2" and -1 or 1) })
end
function onProfileStatClick(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local _; _, id = viewerOf(id)
local i, pi, ci = tostring(id or ""):match("^padj_(%d+)_(%d+)_(%d+)$")
local col = PROFILE_COLS[tonumber(ci) or 0]
local w = tonumber(i) and weaponAt(tonumber(i))
local p = w and w.profiles and w.profiles[tonumber(pi)]
if not (p and col) then return end
setProfileStat({ weapon = tonumber(i), profile = tonumber(pi), key = col.key,
value = TRAIT_RULES.adjSteps(p, col.key) + (tostring(value) == "-2" and -1 or 1) })
end
function onReliableClick(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
if tostring(value) == "-2" then return end
local _; _, id = viewerOf(id)
local i, pi = tostring(id or ""):match("^prelBtn_(%d+)_(%d+)$")
local w = tonumber(i) and weaponAt(tonumber(i))
local p = w and w.profiles and w.profiles[tonumber(pi)]
if not p then return end
setReliable({ weapon = tonumber(i), profile = tonumber(pi), value = p.reliableUsed == true })
end
function onProfileEnter(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local v, row = view(key), tostring(id or ""):match("(%d+_%d+)")
if tostring(id):match("^patk_") then ACTIVATION.hoverEnter(key, "costHover", row) end
if tostring(id):match("^pammo_") then ACTIVATION.hoverEnter(key, "costHover", "r" .. row) end
local i, pi = tostring(row):match("^(%d+)_(%d+)$")
local p = weaponAt(tonumber(i) or 0) and weaponAt(tonumber(i)).profiles[tonumber(pi)]
if p and TRAIT_RULES.combi(p) then
v.profHover = row
ui.redrawStats(key)
end
end
function onProfileExit(player, value, id)
if ui.spectating(player) then return end
local key; key, id = viewerOf(id)
local v, row = view(key), tostring(id or ""):match("(%d+_%d+)")
if tostring(id):match("^patk_") then ACTIVATION.hoverLeave(key, "costHover", row) end
if tostring(id):match("^pammo_") then ACTIVATION.hoverLeave(key, "costHover", "r" .. row) end
if v.profHover ~= row then return end
v.profHover = nil
ui.redrawStats(key)
end
local function statsLater(key, token, fn)
local v = view(key)
v[token] = (v[token] or 0) + 1
local mine = v[token]
Wait.time(function() if v[token] == mine then fn(v) end end, CFG.popupLinger)
end
local function statsHold(key, token)
local v = view(key)
v[token] = (v[token] or 0) + 1
end
local function leaveStats(key)
statsLater(key, "leaveToken", function(v)
v.statsHover, v.statCol, v.headHeld = false, nil, nil
for stat, p in pairs(pendingStats) do
if p.by == key then pendingStats[stat] = nil end
end
ui.drawStats()
end)
end
local function leaveColumn(key, i)
statsLater(key, "colToken", function(v)
if v.statCol ~= i then return end
v.statCol = nil
ui.drawStats(key)
end)
end
function onStatsEnter(player, value, id)
if ui.spectating(player) then return end
local key = viewerOf(id)
statsHold(key, "leaveToken")
local v = view(key)
if v.headHeld then return end
v.statsHover = true
ui.drawStats(key)
end
function onStatsHeadExit(player, value, id)
if ui.spectating(player) then return end
view((viewerOf(id))).headHeld = nil
end
function onStatsExit(player, value, id)
if ui.spectating(player) then return end
leaveStats(viewerOf(id))
end
local function statColumnOf(id)
local key, rest = viewerOf(id)
local i = tonumber(tostring(rest or ""):match("^stat%a+_(%d+)$"))
return key, i, i and (view(key).statsHover and STAT.hoverOrder() or CFG.statOrder)[i]
end
local function enterColumn(id)
local key, i = statColumnOf(id)
if not i then return end
statsHold(key, "leaveToken")
statsHold(key, "colToken")
view(key).statCol = i
ui.drawStats(key)
end
function onStatColEnter(player, value, id) if ui.spectating(player) then return end enterColumn(id) end
function onStatPlateEnter(player, value, id) if ui.spectating(player) then return end enterColumn(id) end
function onStatColExit(player, value, id)
if ui.spectating(player) then return end
local key, i = statColumnOf(id)
if i then leaveColumn(key, i) end
end
function onStatPlateExit(player, value, id)
if ui.spectating(player) then return end
local key, i = statColumnOf(id)
if not i then return end
leaveColumn(key, i)
leaveStats(key)
end
function onStatClick(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local key, _, stat = statColumnOf(id)
if not stat then return end
if tostring(value) == "-2" then nudgeStat(stat, 1, key) else rollStat(stat, player) end
end
function onStatSet(player, value, id)
if ui.spectating(player, true) then return end
if watching(id) then return end
local key, _, stat = statColumnOf(id)
if not stat then return end
view(key).headHeld = true
keepStat(stat)
end
end
local function validBase(t)
if type(t) ~= "table" then return nil end
local d = tonumber(t.diameter)
if not d or d <= 0 then return nil end
t.diameter, t.mm = d, tonumber(t.mm) or d * MODEL.MM_PER_INCH
return t
end
local engage = { token = 0, spot = nil, pending = false }
local function positionOf(obj)
local ok, p = pcall(function() return obj.getPosition() end)
if not ok or p == nil then return nil end
local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
return (x and y and z) and { x = x, y = y, z = z } or nil
end
local function isSelf(obj)
if obj == self then return true end
local ok, same = pcall(function() return obj.getGUID() == self.getGUID() end)
return ok and same == true
end
local function baseGap(a, b)
return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - a.r - b.r
end
local currentBase, runEngagement
do
function currentBase()
local ok, desc = pcall(function() return self.getDescription() end)
local mm = ok and MODEL.baseLine(desc)
if mm then return MODEL.baseRecord(mm, "description") end
if not validBase(fighter.base) then fighter.base = MODEL.measureBase(self) end
return fighter.base or MODEL.baseRecord(CFG.baseDefault, "default")
end
local gangOf = ui.gangOf
local function inReach(a, b)
return baseGap(a, b) <= CFG.engageRange + CFG.engageSlack
and math.abs(a.y - b.y) <= CFG.engageLevel + CFG.engageSlack
end
local ENGAGING = { active = true, suppressed = true, engaged = true }
local ENGAGEABLE = { active = true, suppressed = true }
local function friends(a, b)
if a.gang == b.gang then return true end
return a.team ~= nil and a.team == b.team
end
ACTIVATION.friends = friends
local function tableEntry(obj)
local gang, team = gangOf(obj)
local pos = gang and positionOf(obj)
if not pos then return nil end
local me, info = isSelf(obj), nil
if me then
info = engageInfo()
else
local ok, v = ACTIVATION.ask(obj, "engageInfo")
info = ok and type(v) == "table" and v or nil
if not info then
local okF, f = ACTIVATION.ask(obj, "getFighter")
if okF and type(f) == "table" and f.status then
local b = validBase(f.base) or MODEL.measureBase(obj) or MODEL.baseRecord(CFG.baseDefault, "default")
info = { name = f.name, status = f.status, diameter = b.diameter, rank = f.rank, old = true }
end
end
end
if not (info and info.status) or info.out then return nil end
local d = tonumber(info.diameter) or CFG.baseDefault / MODEL.MM_PER_INCH
return { obj = obj, self = me, old = info.old == true, gang = gang, team = team, name = tostring(info.name or "?"),
status = info.status, r = d / 2, x = pos.x, y = pos.y, z = pos.z,
rank = info.rank, cl = tonumber(info.cl), t = tonumber(info.t), s = tonumber(info.s),
activation = info.activation, master = info.master == true,
fearsome = info.fearsome == true, ironJaw = tonumber(info.ironJaw),
lieLow = info.lieLow == true, assist = tonumber(info.assist),
assistWith = info.assistWith and tostring(info.assistWith) or nil,
wyrd = info.wyrd == true, wil = tonumber(info.wil),
auras = type(info.auras) == "table" and info.auras or nil,
cacophony = info.cacophony and tostring(info.cacophony) or nil, void = tonumber(info.void),
visions = type(info.visions) == "table" and info.visions or nil,
immune = type(info.immune) == "table" and info.immune or nil, hanger = info.hanger == true,
refraction = type(info.refraction) == "table" and info.refraction or nil,
voidSoul = info.voidSoul and tostring(info.voidSoul) or nil,
agilityMod = tonumber(info.agilityMod), agilityReroll = info.agilityReroll }
end
local function selfSpot()
local me = tableEntry(self)
if me then return me end
local pos = positionOf(self)
if not pos then return nil end
pos.r = currentBase().diameter / 2
return pos
end
function ACTIVATION.me()
local e = tableEntry(self)
if e or fighter.outOfAction then return e end
local info = engageInfo()
return { obj = self, self = true, name = tostring(info.name or "?"), status = info.status,
t = tonumber(info.t), s = tonumber(info.s), ironJaw = tonumber(info.ironJaw),
immune = type(info.immune) == "table" and info.immune or nil }
end
function ACTIVATION.picked(player, withSelf)
local p = ui.playerOf(player)
local ok, sel = __nqs_mundane_bus.selection(player)
if ok == nil then ok, sel = pcall(function() return p.getSelectedObjects() end) end
local out = {}
for _, obj in ipairs(ok and type(sel) == "table" and sel or {}) do
local okT, tags = pcall(function() return obj.getTags() end)
local tagged = false
for _, t in ipairs(okT and type(tags) == "table" and tags or {}) do tagged = tagged or t == CFG.importTag end
if tagged and (withSelf or not isSelf(obj)) then
local okO, gone = ACTIVATION.ask(obj, "isOutOfAction")
if not (okO and gone == true) then out[#out + 1] = obj end
end
end
return out
end
function ACTIVATION.targets(player, any, withSelf)
local mine, myTeam = gangOf(self)
local out, me = {}, { gang = mine, team = myTeam }
if not (mine or any) then return out end
for _, obj in ipairs(ACTIVATION.picked(player, withSelf)) do
local gang, team = gangOf(obj)
local foe = gang ~= nil and mine ~= nil and not friends({ gang = gang, team = team }, me)
if any or foe then
local e = isSelf(obj) and ACTIVATION.me() or tableEntry(obj)
if e then
if not (e.t and e.s) then
local okF, f = ACTIVATION.ask(obj, "getFighter")
local stats = okF and type(f) == "table" and type(f.stats) == "table" and f.stats or {}
e.t = e.t or tonumber(tostring(stats.T or ""):match("%d+"))
e.s = e.s or tonumber(tostring(stats.S or ""):match("%d+"))
end
e.foe = foe
out[#out + 1] = e
end
end
end
return out
end
function ACTIVATION.target(player, any)
local all = ACTIVATION.targets(player, any)
if #all < 2 then return all[1] end
local me = tableEntry(self)
if not me then return all[1] end
local best, gap = nil, nil
for _, e in ipairs(all) do
local g = baseGap(me, e)
if not gap or g < gap then best, gap = e, g end
end
return best
end
function ACTIVATION.blastTargets(player) return ACTIVATION.targets(player, true, true) end
function ACTIVATION.nearestFirst(list, of)
local me, keyed = selfSpot(), {}
for k, item in ipairs(list) do
local e = of and of(item) or item
local gap = e.self and -math.huge or (me and e.x and e.z and e.r and baseGap(me, e)) or math.huge
keyed[k] = { item = item, gap = gap, k = k }
end
table.sort(keyed, function(a, b)
if a.gap ~= b.gap then return a.gap < b.gap end
return a.k < b.k
end)
local out = {}
for k, v in ipairs(keyed) do out[k] = v.item end
return out
end
function ACTIVATION.drawTarget()
local blast = ACTIVATION.blasting()
local on = blast or (fighter.activation == "active" and not fighter.outOfAction)
for _, key in ipairs(ui.viewers) do
local v = view(key)
local objs = on and ACTIVATION.picked(key == "all" and ui.facingPlayer(key) or key, blast) or {}
local ids = {}
for k, o in ipairs(objs) do
local ok, g = pcall(function() return o.getGUID() end)
ids[k] = ok and tostring(g) or "?"
end
local sig = (blast and "blast:" or "") .. table.concat(ids, ",")
if sig ~= (v.targetSig or "") then
local wasMulti = v.targetMulti == true
v.targetSig, v.targetMulti = sig, not blast and #objs > 1 or nil
if blast then
v.target = { text = ACTIVATION.blastCount(#objs), ink = #objs > 0 and COL.valueUp or COL.valueMod }
elseif #objs == 0 then
v.target = nil
elseif #objs > 1 then
v.target = { text = string.format(CFG.targetMulti, #objs),
ink = TRAIT_RULES.spreadsAny() and COL.valueUp or COL.valueMod }
else
local e = tableEntry(objs[1])
local ok, nm = pcall(function() return objs[1].getName() end)
local name = e and e.name or (ok and nm ~= "" and nm) or "?"
v.target = { text = string.format(CFG.targetName, name), ink = COL.valueUp }
end
SKILL.drawBar(key)
if wasMulti ~= (v.targetMulti == true) then TRAIT_RULES.drawWeapons(key) end
end
end
end
function TRAIT_RULES.gapTo(player)
local aim = ACTIVATION.target(player, true)
local me = aim and tableEntry(self)
if not me then return nil end
return baseGap(me, aim), aim
end
function ACTIVATION.coverFor(w, p, aim)
local cover, band = ACTIVATION.coverBand(w, p, aim)
if not cover then return nil end
for _, a in ipairs(select(2, TRAIT_RULES.named(w))) do
local m = band == "short" and a.def.coverShort or band == "long" and a.def.coverLong or nil
if tonumber(m) then return math.max(0, cover + tonumber(m)), a.name end
end
return cover
end
function ACTIVATION.coverBand(w, p, aim)
if not (w and p and aim) or isMelee(p) then return nil end
local R = TRAIT_RULES
local function inches(key)
local t = R.parts(R.value(w, p, key))
if not t or t.dash or t.token then return nil end
return t.num
end
local sr, lr = inches("SR"), inches("LR")
if not (sr or lr) then return CFG.coverTemplate end
if not lr then return CFG.coverShort, "short" end
if not sr then return CFG.coverLong, "long" end
local me = tableEntry(self)
local gap = me and aim.x and aim.z and baseGap(me, aim)
if not gap then return CFG.coverShort, "short" end
local slack = CFG.engageSlack or 0
if aim.void and gap <= aim.void + slack then return CFG.coverLong, "long" end
if gap > sr + slack then return CFG.coverLong, "long" end
return CFG.coverShort, "short"
end
function ACTIVATION.inShort(w, p, aim)
local t = TRAIT_RULES.parts(TRAIT_RULES.value(w, p, "SR"))
if not (t and t.num) or t.dash or t.token then return false end
local me = tableEntry(self)
if not (me and aim and aim.x and aim.z) then return false end
return baseGap(me, aim) <= t.num + (CFG.engageSlack or 0)
end
function ACTIVATION.heal(a, player, rgb)
local MOD = rgbOf(COL.valueMod)
local obj = ACTIVATION.picked(player, true)[1]
if not obj then
chat(string.format("%s: %s -- nobody selected to heal", fighter.name, a.label), MOD)
return nil
end
local mine, e = isSelf(obj), nil
if mine then e = ACTIVATION.me() else e = tableEntry(obj) end
local me = tableEntry(self)
if not e or (not mine and me and not friends(e, me)) then
chat(string.format("%s: %s -- %s is no ally", fighter.name, a.label, e and e.name or "that"), MOD)
return nil
end
if e.status == "seriously_injured" then
chat(string.format("%s: %s -- %s is Seriously Injured, beyond healing", fighter.name, a.label, e.name), MOD)
return nil
end
local f = fighter
if not mine then
local ok, v = ACTIVATION.ask(obj, "getFighter")
f = ok and type(v) == "table" and v or nil
end
local w = f and type(f.wounds) == "table" and f.wounds or nil
local cur, max = w and tonumber(w.current), w and tonumber(w.max)
if not (cur and max) then return nil end
local n = math.min(math.max(0, max - cur), math.max(1, math.floor(tonumber(a.heal) or 1)))
if n <= 0 then
chat(string.format("%s: %s -- %s has no wound lost", fighter.name, a.label, e.name), MOD)
return nil
end
if mine then setWounds(cur + n) else ACTIVATION.ask(obj, "setWounds", cur + n) end
chat(string.format("%s heals %s -- %d wound%s back (%d/%d)", fighter.name, mine and "themselves" or e.name,
n, n == 1 and "" or "s", cur + n, max), rgb)
flash(obj, ACTIVATION.actionGlow(a.key, a.type))
return n
end
function ACTIVATION.everyone(o)
o = o or {}
local ok, objs = pcall(function() return getObjectsWithTag(o.tag or CFG.importTag) end)
local all, me = {}, nil
local reach, spots = nil, nil
if tonumber(o.within) then
local big = 0
for _, mm in ipairs(MODEL.BASE_SIZES) do big = math.max(big, tonumber(mm) or 0) end
big = math.max(big / MODEL.MM_PER_INCH, tonumber(currentBase().diameter) or 0)
local hops = tonumber(o.hops) or 1
reach = hops * (tonumber(o.within) + CFG.engageSlack + big) + 1
spots = { positionOf(self) }
for _, s in ipairs(o.spots or {}) do spots[#spots + 1] = s end
end
local function near(obj)
if not reach then return true end
local p = positionOf(obj)
if p then
for _, s in ipairs(spots) do
if (p.x - s.x) ^ 2 + (p.z - s.z) ^ 2 <= reach * reach then return true end
end
end
return isSelf(obj)
end
local slots = {}
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
if near(obj) then
local gang, team = nil, nil
if o.skip and not isSelf(obj) then gang, team = gangOf(obj) end
if gang and o.skip(gang, team) then
slots[#slots + 1] = { later = obj }
else
local e = tableEntry(obj)
if e then
slots[#slots + 1] = e
if e.self then me = e end
end
end
end
end
local function list()
local out = {}
for _, s in ipairs(slots) do
if s.obj then out[#out + 1] = s end
end
return out
end
local function rest()
for k, s in ipairs(slots) do
if s.later then slots[k] = tableEntry(s.later) or {} end
end
return list()
end
all = list()
return all, me, rest
end
local function foesOf(f, all)
local out = {}
if not ENGAGING[f.status] then return out end
for _, o in ipairs(all) do
if o ~= f and not friends(o, f) and ENGAGING[o.status] and inReach(f, o) then out[#out + 1] = o end
end
return out
end
function TRAIT_RULES.backstabNear(player)
local all, me = ACTIVATION.everyone()
if not me then
me = tableEntry(self)
if not me then return false end
all[#all + 1] = me
end
local foe = ACTIVATION.target(player)
if not foe then
local foes = foesOf(me, all)
foe = #foes == 1 and foes[1] or nil
end
if not (foe and ENGAGING[foe.status]) then return false end
for _, o in ipairs(all) do
if o ~= me and friends(o, me) and ENGAGING[o.status] and inReach(o, foe) then return true end
end
return false
end
function TRAIT_RULES.supportNear(player)
local all, me = ACTIVATION.everyone({ within = CFG.engageRange, hops = 3 })
if not me then
me = tableEntry(self)
if not me then return nil end
all[#all + 1] = me
end
local foes = foesOf(me, all)
local function counts(o) return o.master or #foesOf(o, all) == 1 end
if #foes >= 2 and #SKILL.with("master") == 0 then
local aim = ACTIVATION.target(player)
local function aimedAt(o)
if not aim then return false end
local ok, same = pcall(function() return aim.obj == o.obj or aim.obj.getGUID() == o.obj.getGUID() end)
return ok and same == true
end
local by = {}
for _, o in ipairs(foes) do
if not aimedAt(o) and counts(o) then by[#by + 1] = o.obj end
end
if #by > 0 then return -1, by end
elseif #foes == 1 then
local by = {}
for _, o in ipairs(all) do
if o ~= me and friends(o, me) and ENGAGING[o.status] and inReach(o, foes[1]) and counts(o) then
by[#by + 1] = o.obj
end
end
if #by > 0 then return 1, by end
end
return nil
end
function ACTIVATION.surroundings()
local all, me = ACTIVATION.everyone({ within = CFG.engageRange, hops = 2 })
me = me or tableEntry(self)
local foes, helper = {}, nil
if not me then return { foes = foes } end
local function threat(a, b) return not friends(b, a) and ENGAGING[b.status] and inReach(a, b) end
for _, o in ipairs(all) do
if not o.self and threat(me, o) then foes[#foes + 1] = o end
end
for _, o in ipairs(all) do
if not o.self and friends(o, me) and ENGAGING[o.status] and inReach(me, o)
and (not helper or (o.assist or 0) > (helper.assist or 0)) then
local free = true
for _, e in ipairs(all) do if threat(o, e) then free = false break end end
if free then helper = o end
end
end
return { foes = foes, helper = helper }
end
function ACTIVATION.treat(player, rgb)
local me = tableEntry(self)
local best = nil
for _, obj in ipairs(me and ACTIVATION.picked(player) or {}) do
local o = tableEntry(obj)
if o and friends(o, me) and o.status == "seriously_injured" and inReach(me, o)
and (not best or baseGap(me, o) < baseGap(me, best)) then
best = o
end
end
if not best then return nil end
local ok, dice = ACTIVATION.ask(best.obj, "recoveryTest")
if not (ok and dice) then return nil end
chat(string.format("%s treats %s -- their Recovery Test is open", fighter.name, best.name), rgb)
flash(best.obj, ACTIVATION.actionGlow("treat_ally"))
return best
end
function ACTIVATION.groupOf(objs)
local me = tableEntry(self)
local near, far = {}, {}
for _, obj in ipairs(me and objs or {}) do
local o = tableEntry(obj)
if o and friends(o, me) and o.activation == "ready" then
local list = baseGap(me, o) <= (CFG.groupRange or 3) + CFG.engageSlack and near or far
list[#list + 1] = o
end
end
return near, far
end
function ACTIVATION.friendsWithin(range)
local all, me = ACTIVATION.everyone({ within = range })
me = me or tableEntry(self)
local out = {}
for _, o in ipairs(me and all or {}) do
if not o.self and friends(o, me) and baseGap(me, o) <= range + CFG.engageSlack then
out[#out + 1] = o
end
end
return out
end
function ACTIVATION.allWithin(range)
local me = selfSpot()
local out = {}
if not me then return out end
for _, o in ipairs((ACTIVATION.everyone({ within = range }))) do
if not o.self and baseGap(me, o) <= range + CFG.engageSlack then out[#out + 1] = o end
end
return out
end
function ACTIVATION.wholeWithin(range)
local all, me = ACTIVATION.everyone({ within = range })
me = me or tableEntry(self)
local out = {}
for _, o in ipairs(me and all or {}) do
if not o.self and friends(o, me) and baseGap(me, o) + 2 * o.r <= range + CFG.engageSlack then
out[#out + 1] = o
end
end
return out
end
function ACTIVATION.disrupters()
local range = tonumber(CFG.disruptRange) or 18
local all, me = ACTIVATION.everyone({ within = range })
me = me or tableEntry(self)
local near = {}
for _, o in ipairs(me and all or {}) do
if not o.self and not friends(o, me) and o.wyrd and o.wil and baseGap(me, o) <= range + CFG.engageSlack then
near[#near + 1] = o
end
end
return ACTIVATION.nearestFirst(near)
end
function ACTIVATION.sideOf(me, o, side)
if o.obj == me.obj or (o.self and me.self) then return false end
if side == "friends" then return friends(o, me) end
if side == "enemies" then return not friends(o, me) end
return true
end
function ACTIVATION.within(me, o, range)
range = tonumber(range)
return not range or baseGap(me, o) <= range + CFG.engageSlack
end
function ACTIVATION.aimFor(it, player)
local aim = ACTIVATION.target(player)
if not aim then return nil, "no enemy selected" end
local me = tableEntry(self)
aim.gap = me and baseGap(me, aim) or nil
local range = tonumber(it.target and it.target.range)
if range and aim.gap and aim.gap > range + CFG.engageSlack then
return nil, string.format('%s is %s" away -- out of range (%s")', aim.name,
string.format("%g", math.floor(aim.gap * 10 + 0.5) / 10), string.format("%g", range))
end
return aim
end
function ACTIVATION.areaHex(it)
local a, names = it.area, {}
local h = { label = it.name, by = fighter.name, mods = a.mods, oneAction = a.oneAction, turn = true }
local id = ACTIVATION.hexId(it.key)
if a.self and wyrdHex({ id = id, value = h }) then names[#names + 1] = { name = fighter.name } end
local all, me = ACTIVATION.everyone({ within = tonumber(a.range) })
me = me or tableEntry(self)
for _, o in ipairs(me and all or {}) do
if ACTIVATION.sideOf(me, o, a.side or "all") and ACTIVATION.within(me, o, a.range) then
local ok, took = ACTIVATION.ask(o.obj, "wyrdHex", { id = id, value = h })
if ok and took then
names[#names + 1] = { name = o.name }
flash(o.obj, rgbOf(COL.wyrdInk))
end
end
end
return names
end
local function pushAuras(auras, had)
local far = 0
for _, a in ipairs(auras or {}) do far = far and tonumber(a.range) and math.max(far, tonumber(a.range)) end
local all, me = ACTIVATION.everyone({ within = far or nil })
me = me or tableEntry(self)
local got, names = {}, {}
for _, a in ipairs((me and auras) or {}) do
for _, o in ipairs(all) do
local okG, guid = pcall(function() return o.obj.getGUID() end)
if okG and guid and ACTIVATION.sideOf(me, o, a.side) and ACTIVATION.within(me, o, a.range) then
local ok, took = ACTIVATION.ask(o.obj, "wyrdHex", { id = a.id, value = { label = a.label,
by = fighter.name, mods = a.mods, lend = a.lend, aura = true, gear = a.gear, once = a.once } })
if ok and took then got[guid], names[#names + 1] = a.id, { name = o.name } end
end
end
end
for guid, id in pairs(had or {}) do
if got[guid] ~= id then
local ok, obj = pcall(function() return getObjectFromGUID(guid) end)
if ok and obj then ACTIVATION.ask(obj, "wyrdHex", { id = id, value = false }) end
end
end
return next(got) and got or nil, names
end
function ACTIVATION.auraPush()
local w = fighter.wyrd
if type(w) ~= "table" then return {} end
local names = nil
w.hexed, names = pushAuras(ACTIVATION.auraOf(), w.hexed)
return names
end
function ACTIVATION.gearPush()
local names = nil
fighter.gearHexed, names = pushAuras(ACTIVATION.gearAuras(), fighter.gearHexed)
return names
end
function ACTIVATION.gearUnhex()
if not fighter.gearHexed then return end
ACTIVATION.unhex({ hexed = fighter.gearHexed })
fighter.gearHexed = nil
end
function ACTIVATION.auraPull()
local all, me = ACTIVATION.everyone({ tag = CFG.wyrdTag })
me = me or tableEntry(self)
if not me then return false end
local want = {}
for _, o in ipairs(all) do
for _, a in ipairs((not o.self and o.auras) or {}) do
if type(a) == "table" and a.id and ACTIVATION.sideOf(o, me, a.side)
and ACTIVATION.within(o, me, a.range) then
want[a.id] = { label = a.label, by = o.name, mods = a.mods, lend = a.lend, aura = true,
gear = a.gear, once = a.once }
end
end
end
local changed = false
for id, h in pairs(fighter.hexes or {}) do
if h.aura and not want[id] then fighter.hexes[id], changed = nil, true end
end
for id, h in pairs(want) do
if not RULES.same((fighter.hexes or {})[id], h) then
fighter.hexes = fighter.hexes or {}
fighter.hexes[id], changed = h, true
end
end
if fighter.hexes and next(fighter.hexes) == nil then fighter.hexes = nil end
if changed then ui.drawStats() end
return changed
end
function ACTIVATION.cacophony()
local all, me = ACTIVATION.everyone({ tag = CFG.wyrdTag })
me = me or tableEntry(self)
for _, o in ipairs(me and all or {}) do
if o.cacophony and not friends(o, me) then return o end
end
return nil
end
function ACTIVATION.visionsCheck()
local all, me = ACTIVATION.everyone({ tag = CFG.wyrdTag })
me = me or tableEntry(self)
for _, o in ipairs(me and all or {}) do
local v = o.visions
if type(v) == "table" and not friends(o, me) and ACTIVATION.within(o, me, tonumber(v.range) or 0) then
local key = tostring(v.condition or "insanity")
local i = indexOf(CONDITIONS, key)
if i and conditionCount(key) == 0 then
setCondition(key, true)
ACTIVATION.purple(string.format('%s ends their activation within %s" of %s -- %s (%s)', fighter.name,
tostring(v.range), o.name, CONDITIONS[i].label, tostring(v.label or "Maddening Visions")))
flash(self, rgbOf(COL.wyrdInk))
return key
end
end
end
return nil
end
function ACTIVATION.drawReach()
local want = nil
if CFG.preMeasure and not fighter.outOfAction then
for _, key in ipairs(ui.viewers) do
local prefix, n = tostring(view(key).actHover or ""):match("^(act_.+)_(%d+)$")
local P = PANELS[prefix or ""]
local a = P and P.list[tonumber(n)]
if not want and a and (a.key == "group_activation" or tonumber(a.distribute)) then want = a end
end
end
local was = ACTIVATION.reach
if (want and want.key) == (was and was.key) then return end
if was then
for _, obj in ipairs(was) do pcall(function() obj.highlightOff() end) end
ACTIVATION.reach = nil
ACTIVATION.nerveLight(true)
end
if not want then return end
local lit, rgb = { key = want.key }, ACTIVATION.actionGlow(want.key, want.type)
for _, o in ipairs(ACTIVATION.friendsWithin(tonumber(want.distribute) or CFG.groupRange or 3)) do
lit[#lit + 1] = o.obj
pcall(function() o.obj.highlightOn(rgb) end)
end
ACTIVATION.reach = lit
end
function ACTIVATION.sees(obj)
if not (Physics and Physics.cast) then return true end
local function box(o)
local ok, b = pcall(function() return o.getBounds() end)
if not (ok and type(b) == "table" and b.center and b.size) then return nil end
local c, sz = b.center, b.size
local x, y, z = tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3])
local w, h, dd = tonumber(sz.x or sz[1]), tonumber(sz.y or sz[2]), tonumber(sz.z or sz[3])
if not (x and y and z and w and h and dd) then return nil end
return { x = x, y = y + h / 4, z = z, w = math.min(w, dd) }
end
local from, to = box(self), box(obj)
if not (from and to) then return true end
local function passes(o)
if o == nil or o == obj or isSelf(o) then return true end
local okG, same = pcall(function() return o.getGUID() == obj.getGUID() end)
if okG and same then return true end
local okT, tagged = pcall(function() return o.hasTag(CFG.importTag) end)
return okT and tagged == true
end
local dx, dz = to.x - from.x, to.z - from.z
local flat = math.sqrt(dx * dx + dz * dz)
local px, pz = 1, 0
if flat > 0 then px, pz = -dz / flat, dx / flat end
for k = 1, math.max(1, math.floor(CFG.nerveRays or 3)) do
local side = (k % 2 == 0 and 1 or -1) * math.floor(k / 2) * (CFG.nerveSpread or 0.35) * to.w
local ex, ey, ez = to.x + px * side - from.x, to.y - from.y, to.z + pz * side - from.z
local len = math.sqrt(ex * ex + ey * ey + ez * ez)
if len <= 0 then return true end
local ok, hits = pcall(function()
return Physics.cast({ origin = { x = from.x, y = from.y, z = from.z },
direction = { x = ex / len, y = ey / len, z = ez / len },
type = 1, max_distance = len, debug = false })
end)
local clear = true
for _, h in ipairs(ok and type(hits) == "table" and hits or {}) do
if not passes(h.hit_object) then clear = false break end
end
if clear then return true end
end
return false
end
function ACTIVATION.nerveSource()
local own = statNumber("Cl")
local best = { value = own, own = own }
local far = 0
for _, r in pairs(CFG.nerveRanges or {}) do far = math.max(far, tonumber(r) or 0) end
local all, me = ACTIVATION.everyone({ within = far })
me = me or tableEntry(self)
if not me then return best end
local lend = {}
for _, o in ipairs(all) do
local range = (CFG.nerveRanges or {})[tostring(o.rank or ""):lower()]
if not o.self and friends(o, me) and range and o.cl and (not own or o.cl > own)
and baseGap(me, o) <= range + CFG.engageSlack then
lend[#lend + 1] = o
end
end
table.sort(lend, function(a, b) return a.cl > b.cl end)
for _, o in ipairs(lend) do
if ACTIVATION.sees(o.obj) then
best.value, best.from = o.cl, o
break
end
end
return best
end
function ACTIVATION.shaken()
local list, tags = {}, ACTIVATION.tags()
if not CFG.nerveOutRange then return list end
for _, t in ipairs(CFG.nerveOutNone or {}) do if tags[t] then return list end end
local prospect = tostring(fighter.rank or ""):lower() == "prospect"
local all, me = ACTIVATION.everyone({ within = CFG.nerveOutRange })
me = me or tableEntry(self)
if not me then return list end
for _, o in ipairs(all) do
if not o.self and (CFG.nerveOutFoes or friends(o, me))
and (not prospect or tostring(o.rank or ""):lower() == "prospect")
and baseGap(me, o) <= CFG.nerveOutRange + CFG.engageSlack then
list[#list + 1] = o
end
end
return list
end
function ACTIVATION.finishOthers()
local ok, objs = pcall(function() return getObjectsWithTag(CFG.importTag) end)
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
if not isSelf(obj) then
local okI, info = ACTIVATION.ask(obj, "engageInfo")
if okI and type(info) == "table" and info.activation == "active" then
ACTIVATION.ask(obj, "completeActivation")
end
end
end
end
local function nameList(list)
local n = {}
for _, f in ipairs(list) do n[#n + 1] = f.name end
if #n <= 1 then return n[1] or "" end
return table.concat(n, ", ", 1, #n - 1) .. " and " .. n[#n]
end
ACTIVATION.nameList = nameList
local function setStatusOf(f, key)
f.status = key
local arg = f.old and key or { key = key, quiet = true }
if f.self then setStatus(arg)
else ACTIVATION.ask(f.obj, "setStatus", arg) end
end
function runEngagement()
local mine, myTeam = gangOf(self)
local myself = { gang = mine, team = myTeam }
local all, me, rest = ACTIVATION.everyone({ within = CFG.engageRange, hops = 2, spots = { engage.spot },
skip = function(gang, team) return mine == nil or friends({ gang = gang, team = team }, myself) end })
local extra = nil
if not me then
me = tableEntry(self)
local gang, team = gangOf(self)
local pos = positionOf(self)
if not me and fighter.outOfAction and gang and pos then
me = { obj = self, self = true, gang = gang, team = team, name = fighter.name, status = "out",
r = (tonumber(currentBase().diameter) or CFG.baseDefault / MODEL.MM_PER_INCH) / 2,
x = pos.x, y = pos.y, z = pos.z }
end
if not me then
engage.spot, engage.pending = positionOf(self), false
return 0
end
all[#all + 1] = me
extra = me
end
local was = engage.spot and { x = engage.spot.x, y = engage.spot.y, z = engage.spot.z, r = me.r }
local affected = nil
local function findAffected()
affected = { me }
for _, f in ipairs(all) do
if f ~= me and not friends(f, me) and (inReach(me, f) or (was and inReach(was, f))) then
affected[#affected + 1] = f
end
end
end
findAffected()
if #affected > 1 then
all = rest()
if extra then all[#all + 1] = extra end
findAffected()
end
engage.spot, engage.pending = { x = me.x, y = me.y, z = me.z }, false
local changed, engaged, freed, n = {}, {}, {}, 0
for _, f in ipairs(affected) do
local foes = #foesOf(f, all)
if foes > 0 and ENGAGEABLE[f.status] then
setStatusOf(f, "engaged"); changed[f] = true; engaged[#engaged + 1] = f; n = n + 1
elseif foes == 0 and f.status == "engaged" then
setStatusOf(f, "active"); changed[f] = true; freed[#freed + 1] = f; n = n + 1
end
end
if n == 0 then return 0 end
local ENG, ACT = rgbOf(statusDef("engaged").color), rgbOf(statusDef("active").color)
local lines, lit, named = {}, {}, {}
local function say(f, foes)
lines[#lines + 1] = { string.format("%s is now engaged with %s", f.name, nameList(foes)), ENG }
named[f], lit[#lit + 1] = true, { f, ENG }
for _, o in ipairs(foes) do
if not named[o] then named[o], lit[#lit + 1] = true, { o, ENG } end
end
end
local myFoes = foesOf(me, all)
local news = changed[me]
for _, o in ipairs(myFoes) do news = news or changed[o] end
if #myFoes > 0 and news then say(me, myFoes) end
for _, f in ipairs(engaged) do
if not named[f] then say(f, foesOf(f, all)) end
end
if #freed > 0 then
lines[#lines + 1] = { nameList(freed) .. (#freed > 1 and " are" or " is") .. " no longer engaged", ACT }
for _, f in ipairs(freed) do lit[#lit + 1] = { f, ACT } end
end
for _, l in ipairs(lines) do chat(l[1], l[2]) end
for _, l in ipairs(lit) do flash(l[1].obj, l[2]) end
return n
end
end
do
local WEAPON_ORDER = { gun = 1, heavy = 1, sidearm = 2, melee = 3, melee_heavy = 3, grenade = 3 }
local function sortWeapons(weapons, more)
local all = {}
for _, list in ipairs({ weapons or {}, more or {} }) do
local idx = {}
for k in pairs(list) do if type(k) == "number" then idx[#idx + 1] = k end end
table.sort(idx)
for _, k in ipairs(idx) do
if type(list[k]) == "table" then all[#all + 1] = list[k] end
end
end
local keyed = {}
for n, w in ipairs(all) do keyed[n] = { w = w, n = n, r = WEAPON_ORDER[weaponType(w)] or 3 } end
table.sort(keyed, function(a, b)
if a.r ~= b.r then return a.r < b.r end
return a.n < b.n
end)
local slots, rest = {}, {}
for n, k in ipairs(keyed) do
if n <= #LAY.weaponSpots then slots[#slots + 1] = k.w else rest[#rest + 1] = k.w end
end
return slots, rest
end
function SKILL.arm(f)
local want, order = {}, {}
for _, k in ipairs(SKILL.KINDS) do
for _, name in ipairs(f[k.field] or {}) do
local d = SKILL.def(name, k.kind)
local wyrd = d and d.type == "wyrd" and ACTIVATION.continuous({ cost = d.action })
if wyrd and not (type(f.wyrd) == "table" and f.wyrd.power == SKILL.key(name)) then
elseif d and type(d.weapon) == "table" and not want[SKILL.key(name)] then
want[SKILL.key(name)] = { weapon = d.weapon, kind = k.kind }
order[#order + 1] = SKILL.key(name)
end
end
end
local changed, all, have, named, hand = false, {}, {}, {}, nil
local hw = type(CFG.handWeapon) == "table" and SKILL.key(tostring(CFG.handWeapon.name or "")) or nil
for _, list in ipairs({ sortWeapons(f.weapons, f.moreWeapons) }) do
for _, w in ipairs(list) do
if w.hand then
hand = w
elseif hw and hw ~= "" and not w.from and SKILL.key(w.name or "") == hw then
changed = true
elseif w.from and not want[w.from] then
changed = true
else
all[#all + 1] = w
if w.from then have[w.from] = true end
named[SKILL.key(w.name or "")] = named[SKILL.key(w.name or "")] or w
w.needs = nil
end
end
end
for _, key in ipairs(order) do
local give = want[key].weapon
local own = named[SKILL.key(give.name or "")]
if have[key] then
elseif own then
if want[key].kind == "skill" and not own.from then own.needs = key end
else
local w = RULES.copy(give)
w.from, w.fromKind = key, want[key].kind
local d = SKILL.def(key, want[key].kind)
w.fromWyrd = (d and d.type == "wyrd") or nil
all[#all + 1], changed = w, true
end
end
local give, mark = SKILL.hand(all)
if give and hand and hand.hand == mark then
all[#all + 1] = hand
elseif give then
local w = RULES.copy(give)
w.light, w.hand = nil, mark
all[#all + 1], changed = w, true
elseif hand then
changed = true
end
if changed then f.weapons, f.moreWeapons = sortWeapons(all) end
if changed and f == fighter then TRAIT_RULES.roles() end
return changed
end
function SKILL.hand(list)
local hw = CFG.handWeapon
if type(hw) ~= "table" or type(hw.profiles) ~= "table" then return nil end
for _, w in ipairs(list) do
for _, p in ipairs(w.profiles or {}) do
if isMelee(p) or (hw.light and hasTrait(p, TRAIT.light)) then
return nil
end
end
end
local mark = tostring(hw.name or "")
for _, p in ipairs(hw.profiles) do
for _, k in ipairs({ "SR", "LR", "S", "AP", "L", "D", "Am", "traits" }) do
mark = mark .. "|" .. tostring(type(p) == "table" and p[k] or "")
end
end
return hw, mark
end
function setFighter(data)
data = type(data) == "table" and data or {}
if ACTIVATION.nerve then ACTIVATION.nerveLight(false); ACTIVATION.nerve = nil end
ACTIVATION.roll = nil
local base = defaultFighter()
local f = {}
for k, v in pairs(base) do f[k] = v end
for k, v in pairs(data) do f[k] = v end
local stats = base.stats
if type(data.stats) == "table" then
for k, v in pairs(data.stats) do stats[k] = v end
end
f.stats = stats
local given = type(data.wounds) == "table" and data.wounds or nil
local maxW = math.max(1, math.floor(
tonumber(given and given.max) or tonumber(f.stats.W) or 1))
f.wounds = { max = maxW, current = clamp(given and given.current or maxW, 0, maxW) }
f.status = statusDef(f.status).key
f.conditions = type(f.conditions) == "table" and f.conditions or {}
f.statEdits = type(f.statEdits) == "table" and f.statEdits or {}
f.actionsLeft = clamp(math.floor(tonumber(f.actionsLeft) or 0), 0, 2)
f.usedActions = type(f.usedActions) == "table" and f.usedActions or {}
if f.activation ~= "ready" and f.activation ~= "active" then
f.activation = f.actionsLeft > 0 and "active" or nil
end
f.outOfAction = f.outOfAction == true
f.outCold = f.outOfAction and f.outCold == true or nil
f.startedSI = f.startedSI == true and f.activation == "active"
if type(f.recovery) == "table" then
f.recovery.dice = clamp(math.floor(tonumber(f.recovery.dice) or 1), 1, ACTIVATION.MAX_DICE)
local foes = f.recovery.foes
f.recovery.foes = type(foes) == "string" and foes ~= "" and foes or nil
else
f.recovery = nil
end
f.treated = f.status == "seriously_injured" and not f.outOfAction and (tonumber(f.treated) or 0) >= 1
and math.floor(tonumber(f.treated)) or nil
f.grouped = f.grouped == true and f.activation == "ready" and not f.outOfAction or nil
local marks = math.floor(tonumber(f.readyMarks) or -1)
f.readyMarks = (f.activation == "ready" and marks >= 1 or f.activation == "active" and marks >= 0) and marks or nil
f.noReady = f.noReady == true and not f.outOfAction or nil
f.shots = f.activation == "active" and type(f.shots) == "table" and f.shots or nil
f.assaulted = f.activation == "active" and f.assaulted == true or nil
f.shotsPaid = f.activation == "active" and math.floor(tonumber(f.shotsPaid) or 0) > 0
and math.floor(tonumber(f.shotsPaid)) or nil
f.aimedShot = f.activation == "active" and f.aimedShot == true or nil
f.fight = f.activation == "active" and type(f.fight) == "table" and f.fight or nil
f.rolesChosen = f.rolesChosen == true or nil
f.freeStrike = f.activation == "active" and f.freeStrike == true or nil
f.usedOnce = type(f.usedOnce) == "table" and next(f.usedOnce) ~= nil and f.usedOnce or nil
f.boosted = type(f.boosted) == "table" and next(f.boosted) ~= nil and f.boosted or nil
f.timed = type(f.timed) == "table" and next(f.timed) ~= nil and f.timed or nil
f.burnt = type(f.burnt) == "table" and next(f.burnt) ~= nil and f.burnt or nil
f.hexes = type(f.hexes) == "table" and next(f.hexes) ~= nil and f.hexes or nil
if type(f.wyrd) == "table" then
f.wyrd.kept = nil
if f.activation ~= "active" then f.wyrd.cast, f.wyrd.held, f.wyrd.concentrate, f.wyrd.locked = nil, nil, nil, nil end
f.wyrd.power = type(f.wyrd.power) == "string" and f.wyrd.power or nil
if next(f.wyrd) == nil then f.wyrd = nil end
else
f.wyrd = nil
end
f.skills = SKILL.parse(f.skills)
f.wargear = SKILL.parse(f.wargear)
f.base = validBase(f.base)
f.height = tonumber(f.height) or MODEL.height(self)
f.lift = tonumber(f.lift) and tonumber(f.lift) ~= 0
and clamp(tonumber(f.lift), -CFG.liftMax, CFG.liftMax) or nil
f.toughness = nil
f.weapons, f.moreWeapons = sortWeapons(f.weapons, f.moreWeapons)
TRAIT_RULES.keepRoles(f, fighter)
SKILL.arm(f)
for _, w in pairs(f.weapons) do
for _, p in ipairs((type(w) == "table" and w.profiles) or {}) do
if p.jammed then p.ammo = "jam" elseif p.ammoOut then p.ammo = "out" end
p.jammed, p.ammoOut = nil, nil
end
end
fighter = f
TRAIT_RULES.roles()
ACTIVATION.fireShown = ACTIVATION.traitsNow()
ACTIVATION.gangNear = nil
refresh()
ACTIVATION.delaqueCheck()
return true
end
function getFighter() return fighter end
function SKILL.switched()
local off, shape = SKILL.off(), SKILL.shape()
if off == SKILL.wasOff and shape == SKILL.wasShape then return end
local rebuild = shape ~= "" and shape ~= SKILL.builtShape and SKILL.hasWyrd() and ui.built
SKILL.wasOff, SKILL.wasShape = off, shape
if rebuild then return refresh() end
ui.drawStats()
SKILL.drawBar()
ui.drawConditionBar()
TRAIT_RULES.drawWeapons()
ui.drawActions()
ui.swapActions()
end
function ui.swapActions()
for _, k in ipairs(ui.viewers) do
local v = view(k)
local now = ui.flyoutOf("btnActions", k)
if ui.IS_ACTIONS[v.open or ""] and v.open ~= now then
ui.showFlyout(now, k, true)
ui.requestHide(k)
end
end
end
function setWounds(n)
fighter.wounds.current = clamp(n, 0, fighter.wounds.max)
ui.drawHp()
ui.drawStats()
SKILL.switched()
onWoundsChanged(fighter.wounds.current, fighter.wounds.max)
return fighter.wounds.current
end
function applyDamage(n) return setWounds(fighter.wounds.current - (tonumber(n) or 1)) end
function healWounds(n) return setWounds(fighter.wounds.current + (tonumber(n) or 1)) end
function setStatus(key)
local quiet = false
if type(key) == "table" then key, quiet = key.key or key.value, key.quiet == true end
local def = statusDef(key)
local before = fighter.status
fighter.status = def.key
if def.key ~= "seriously_injured" then fighter.treated = nil end
if def.key == "seriously_injured" then ACTIVATION.wyrdDrop() end
ui.drawStatus()
TRAIT_RULES.drawWeapons()
ui.drawStats()
SKILL.switched()
ui.swapActions()
if ACTIVATION.gangRule("palaniteGang") then ui.drawActions() end
if def.key ~= "seriously_injured" and SKILL.builtStatus and SKILL.statusSig() ~= SKILL.builtStatus then refresh() end
if def.key ~= before and not quiet then
chat(string.format("%s is now %s", fighter.name, def.label), rgbOf(def.color))
flash(self, rgbOf(def.color))
end
if def.key == "seriously_injured" and before ~= def.key then checkEngagement() end
onStatusChanged(def.key, def.label)
if def.key ~= before then
__nqs_mundane_bus.send({
kind = "state_change", action = "status",
fighter = fighter and fighter.name or nil,
field = "status",
from = before,
to = def.key,
label = def.label,
})
end
return def.key
end
function highlight(v)
if type(v) ~= "table" then
v = rgbOf(v == nil and statusDef(fighter.status).color
or indexOf(STATUSES, v) and statusDef(v).color or v)
end
flash(self, v)
return true
end
function setReady(on)
local hand = false
if type(on) == "table" then on, hand = on.value, on.hand == true end
if on then ACTIVATION.turnOver() end
if on and fighter.outOfAction then return false end
local marks = ACTIVATION.marks()
if on and fighter.noReady then
fighter.noReady = nil
if not hand then
marks = marks - 1
on = marks > 0
chat(on and string.format("%s gets only %d Ready marker%s this round (Flash)", fighter.name, marks,
marks == 1 and "" or "s")
or string.format("%s gets no Ready marker this round (Flash)", fighter.name), rgbOf(COL.valueMod))
end
end
if fighter.activation == "active" then
ACTIVATION.wyrdEnd()
ACTIVATION.backsEnd()
end
fighter.activation = on and "ready" or nil
fighter.readyMarks = on and ACTIVATION.marks() > 1 and marks or nil
fighter.actionsLeft, fighter.usedActions, fighter.startedSI, fighter.lostAction = 0, {}, false, nil
setGroupActivated(false)
TRAIT_RULES.endVolleys()
TRAIT_RULES.endFight()
TRAIT_RULES.endShots()
ACTIVATION.endQuestion()
ACTIVATION.endFear()
ui.drawReady()
ui.drawActions()
onActionsChanged(fighter.actionsLeft)
return fighter.activation == "ready"
end
function ACTIVATION.marks()
local n, tags = 1, ACTIVATION.tags()
for tag, m in pairs(type(CFG.readyMarks) == "table" and CFG.readyMarks or {}) do
if tags[tostring(tag):lower()] then n = math.max(n, math.floor(tonumber(m) or 1)) end
end
return n
end
function ACTIVATION.loseMark(why)
return __nqs_mundane_bus.within("why", why, function()
local left = ACTIVATION.loseMarkNow()
__nqs_mundane_bus.readiness()
return left
end)
end
function ACTIVATION.loseMarkNow()
local marks = tonumber(fighter.readyMarks)
if fighter.activation == "ready" then
if marks and marks > 1 then
fighter.readyMarks = marks - 1
ui.drawReady()
return marks - 1
end
setReady(false)
return 0
end
if fighter.activation == "active" and marks and marks > 0 then
fighter.readyMarks = marks - 1
return marks - 1
end
return nil
end
function ACTIVATION.readyHalves()
if not (hasAsset("dice_half") and ACTIVATION.marks() > 1) then return false, false, false end
local left, act = tonumber(fighter.readyMarks) or 0, fighter.activation
return true, act == "ready" and left >= 2, (act == "ready" or act == "active") and left >= 1
end
function activate(player)
if fighter.outOfAction then return 0 end
ACTIVATION.finishOthers()
__nqs_mundane_bus.send({ kind = "activation", state = "start",
group = fighter.grouped and __nqs_mundane_bus.card.group or nil, by = player })
__nqs_mundane_bus.card.group = nil
setGroupActivated(false)
if fighter.readyMarks then fighter.readyMarks = math.max(0, fighter.readyMarks - 1) end
ACTIVATION.delaqueCheck()
ACTIVATION.wyrdStart()
local suppressed, frozen = fighter.status == "suppressed", ACTIVATION.frozen()
if suppressed then setStatus({ key = "active", quiet = true }) end
fighter.activation, fighter.startedSI = "active", fighter.status == "seriously_injured"
fighter.actionsLeft, fighter.usedActions = (suppressed or frozen) and 1 or 2, {}
fighter.lostAction = suppressed or nil
fighter.jumping = nil
TRAIT_RULES.endVolleys()
TRAIT_RULES.endFight()
TRAIT_RULES.endShots()
if not ACTIVATION.traitsCheck() then
ui.drawReady()
ui.drawActions()
end
local col = rgbOf(statusDef("active").color)
chat(suppressed and string.format("%s activates -- no longer Suppressed, 1 action", fighter.name)
or string.format("%s activates", fighter.name), col)
if suppressed then flash(self, col) end
if frozen then ACTIVATION.purple(string.format("%s is caught in %s -- 1 action", fighter.name, frozen)) end
onActionsChanged(fighter.actionsLeft)
ACTIVATION.comedown(player, function()
if fighter.activation ~= "active" then return end
ACTIVATION.insane(player, function()
if fighter.activation ~= "active" then return end
ACTIVATION.boosterAsk(player, function()
if fighter.activation ~= "active" then return end
if suppressed and not frozen and #SKILL.with("springUp") > 0 then ACTIVATION.spring(player) end
if #SKILL.with("unstoppable") > 0 then ACTIVATION.unstoppable(player) end
end)
end)
end)
return fighter.actionsLeft
end
function ACTIVATION.unstoppable(player)
local max = tonumber(fighter.wounds.max) or 0
if (tonumber(fighter.wounds.current) or 0) >= max or not statNumber("Wil") then return end
ACTIVATION.rollTest("Wil", player, { why = "Unstoppable", done = function(test)
local now = tonumber(fighter.wounds.current) or 0
if not test.passed or fighter.outOfAction or now >= max then return end
setWounds(now + 1)
chat(string.format("%s is Unstoppable -- regains 1 wound (%d/%d)", fighter.name, now + 1, max),
rgbOf(COL.valueUp))
end })
end
function completeActivation(player)
if fighter.activation ~= "active" then return nil end
local recover = fighter.startedSI and fighter.status == "seriously_injured"
local again = (tonumber(fighter.readyMarks) or 0) > 0
ACTIVATION.wyrdEnd()
fighter.activation, fighter.actionsLeft, fighter.startedSI, fighter.lostAction = again and "ready" or nil, 0, false, nil
if not again then fighter.readyMarks = nil end
local jumped = fighter.jumping ~= nil
fighter.jumping = nil
TRAIT_RULES.endVolleys()
TRAIT_RULES.endFight()
TRAIT_RULES.endShots()
ACTIVATION.endQuestion()
ACTIVATION.endFear()
if not ACTIVATION.traitsCheck() then
if jumped then ui.drawStats() end
ui.drawReady()
ui.drawActions()
end
onActionsChanged(0)
chat(again and string.format("%s has completed their activation -- %d more this round", fighter.name, fighter.readyMarks)
or string.format("%s has completed their activation", fighter.name))
__nqs_mundane_bus.send({ kind = "activation", state = "end", by = player })
ACTIVATION.backsEnd()
ACTIVATION.visionsCheck()
ACTIVATION.timedEnd()
if not recover then return "done" end
local near = ACTIVATION.surroundings()
if #near.foes > 0 then
__nqs_mundane_bus.within("cause", { action = "Recovery" }, function()
setOutOfAction({ value = true, why = 'within 1" of ' .. ACTIVATION.nameList(near.foes) })
end)
return "out"
end
recoveryTest(near)
return "recovery"
end
function getActivation()
return { activation = fighter.activation, actionsLeft = fighter.actionsLeft,
outOfAction = fighter.outOfAction == true, grouped = fighter.grouped == true,
readyMarks = fighter.readyMarks }
end
GR_SHOWN_STATS = true
function getShownStats()
local out = {}
for _, key in ipairs({ "M", "WS", "BS", "S", "T", "W", "I", "A", "Ld", "Cl", "Wil", "Int", "Sv" }) do
out[key] = statText(key, TRAIT_RULES.saveContext())
end
return JSON.encode(out)
end
function setGroupActivated(on)
if type(on) == "table" then
__nqs_mundane_bus.card.group = on.value == true and on.group or nil
on = on.value
end
on = on == true and fighter.activation == "ready" and not fighter.outOfAction
if on == (fighter.grouped == true) then return on end
fighter.grouped = on or nil
ui.drawName()
__nqs_mundane_bus.readiness()
return on
end
function setOutOfAction(on)
local why, cold = nil, nil
if type(on) == "table" then on, why, cold = on.value, on.why, on.cold end
on = on == true
if on == (fighter.outOfAction == true) then return on end
local shaken = on and ACTIVATION.shaken() or {}
fighter.outOfAction = on
fighter.outCold = on and cold == true or nil
if on then
fighter.recovery, fighter.activation, fighter.actionsLeft, fighter.startedSI = nil, nil, 0, false
fighter.treated, fighter.readyMarks, fighter.jumping = nil, nil, nil
ACTIVATION.wyrdDrop()
ACTIVATION.gearUnhex()
setGroupActivated(false)
TRAIT_RULES.endShots()
if ACTIVATION.nerve then
ACTIVATION.nerveLight(false)
ACTIVATION.nerve = nil
end
ui.drawReady()
ui.drawActions()
end
ACTIVATION.draw()
ui.drawStats()
SKILL.drawBar()
SKILL.switched()
local col = rgbOf(statusDef("seriously_injured").color)
chat(on and string.format("%s %s%s", fighter.name, fighter.outCold and "is Out Cold" or "goes Out of Action",
why and (" -- " .. why) or "")
or string.format("%s is revived -- no longer Out of Action", fighter.name), col)
flash(self, col)
if on then
if #shaken > 0 then
chat(string.format("%s must take a Nerve Check", ACTIVATION.nameList(shaken)),
rgbOf(statusDef("suppressed").color))
end
for _, o in ipairs(shaken) do ACTIVATION.ask(o.obj, "nerveCheck") end
checkEngagement()
end
ACTIVATION.gangMoved()
ACTIVATION.tellController(not on)
__nqs_mundane_bus.readiness()
__nqs_mundane_bus.send({
kind = "state_change", action = "out_of_action",
fighter = fighter and fighter.name or nil,
field = "out_of_action",
from = not on,
to = on,
out_cold = fighter and fighter.outCold or nil,
why = why,
})
return on
end
function ACTIVATION.tellController(back)
local ok, objs = pcall(function() return getObjectsWithTag(CFG.controllerTag) end)
local gang = ui.gangOf(self)
if not gang or gang == "" then gang = trimText(fighter.gang or "") end
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
ACTIVATION.ask(obj, "onFighterOut", { gang = gang, name = fighter.name, back = back or nil,
player = __nqs_mundane_bus.clickerColor() })
end
end
function setPlaying(t)
t = type(t) == "table" and t or {}
if t.all or type(t.colors) ~= "table" then ui.playing = nil return end
local set = {}
for _, c in ipairs(t.colors) do if type(c) == "string" then set[c] = true end end
ui.playing = set
end
function ui.fetchPlaying()
local ok, objs = pcall(function() return getObjectsWithTag(CFG.controllerTag) end)
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
local okC, t = ACTIVATION.ask(obj, "getPlaying")
if okC and type(t) == "table" then setPlaying(t) return end
end
end
function useAction(key, player)
local scripted = __nqs_mundane_bus.scripted(key)
key, player = keyValue(key, player)
player = scripted or player
local a = ACTIONS[indexOf(ACTIONS, key) or 0] or SKILL.action(key)
if not a then return false end
if a.key == "reload" then return ACTIVATION.reload(player) end
if a.once and (fighter.usedOnce or {})[a.key] then
chat(string.format("%s has used %s already -- once a game", fighter.name, a.label), rgbOf(COL.valueMod))
return false
end
local arm = ACTIVATION.armBlocks(a.key)
if arm then
chat(arm, rgbOf(COL.valueMod))
return false
end
if not SKILL.inStatus(a) then
chat(string.format("%s can't take %s while %s", fighter.name, a.label, statusDef(fighter.status).label),
rgbOf(COL.valueMod))
return false
end
local refused = a.type == "wyrd" and ACTIVATION.wyrdRefuses(a)
if refused then
ACTIVATION.purple(refused)
return false
end
local several = ACTIVATION.aimsAt(a) == "one" and #ACTIVATION.picked(player, a.heal ~= nil)
if several and several > 1 then
chat(string.format("%s: %s takes one target -- %d fighters are selected", fighter.name, a.label, several),
rgbOf(COL.valueMod))
return false
end
if a.type == "wyrd" and a.kind == "skill" and ACTIVATION.voidAsk(a, player) then return false end
if a.key == "recovery_test" then recoveryTest() end
local spending = fighter.actionsLeft > 0 and not a.always
if spending then
fighter.actionsLeft = math.max(0, fighter.actionsLeft - SKILL.cost(a))
fighter.usedActions[a.key] = true
if a.key == "shoot" or a.key == "braced_shot" or a.key == "aimed_shot" then
fighter.shotsPaid = (tonumber(fighter.shotsPaid) or 0) + 1
end
end
local strike = a.key == "fight" or a.key == "coup_de_grace"
if strike then fighter.freeStrike = nil end
if (a.key == "engage" or a.key == "charge") and fighter.activation == "active" then fighter.freeStrike = true end
if a.key == "charge" or strike then TRAIT_RULES.drawWeapons() end
if a.key == "charge" then ui.drawStats() end
if a.key == "aimed_shot" and fighter.activation == "active" then fighter.aimedShot = true end
local left = not spending and ""
or fighter.actionsLeft == 0 and ", no actions left"
or string.format(", %d action%s left", fighter.actionsLeft, fighter.actionsLeft == 1 and "" or "s")
local rgb = a.type == "wyrd" and rgbOf(COL.wyrdInk)
or rgbOf(mixColor(ACTION_TYPES[a.type or ""] or "#E6E6E6ff", "#FFFFFFff", 0.55))
local head = string.format("%s: %s (%s)", fighter.name, a.label, SKILL.costOf(a) or "")
if a.distance or a.lines then ACTIVATION.moveBy(a, player, rgb, head) else chat(head .. left, rgb) end
if a.escape then ACTIVATION.escape(a, player) end
if a.key == "treat_ally" then ACTIVATION.treat(player, rgb)
elseif a.key == "group_activation" then groupActivation(player)
elseif a.key == "coup_de_grace" then ACTIVATION.coup(player)
elseif a.key == "concentrate" and a.type == "wyrd" then ACTIVATION.concentrate()
elseif (a.key == "maintain_control_s" or a.key == "maintain_control_f") and a.type == "wyrd" then
ACTIVATION.maintain(a, player)
elseif a.type == "wyrd" and a.kind == "skill" then ACTIVATION.cast(a, player) end
if a.distribute then ACTIVATION.distribute(a, player) end
if a.check then ACTIVATION.checked(a, player, rgb)
elseif a.heal then ACTIVATION.heal(a, player, rgb) end
if a.burst then ACTIVATION.burst(a, player) end
if a.restrain then ACTIVATION.restrain(a, player, rgb) end
if a.enrage then ACTIVATION.enrage(a, player, rgb) end
ACTIVATION.pulseWeapons(a.key)
if a.once then
fighter.usedOnce = fighter.usedOnce or {}
fighter.usedOnce[a.key] = true
if a.spends then
SKILL.drawBurnt()
ui.drawStats()
end
end
if a.boost then ACTIVATION.boost(a, rgb) end
TRAIT_RULES.dropAims()
TRAIT_RULES.drawGlows()
ui.drawReady()
ui.drawActions()
onActionsChanged(fighter.actionsLeft)
onActionChosen(player, a.key)
return true
end
function cycleStatus()
local i = indexOf(STATUSES, fighter.status) or 1
return setStatus(STATUSES[i % #STATUSES + 1].key)
end
function getBase() return currentBase() end
function setBase(v)
if type(v) == "table" then
if v.mm == nil and v.value == nil and tonumber(v.diameter) then
v = tonumber(v.diameter) * MODEL.MM_PER_INCH
else
v = v.mm or v.value
end
end
local mm = tonumber(v) or tonumber(tostring(v or ""):match("^%s*(%d+%.?%d*)%s*[Mm]?[Mm]?%s*$"))
fighter.base = (mm and mm > 0) and MODEL.baseRecord(mm, "manual") or MODEL.measureBase(self)
return currentBase()
end
function getHeight()
local h = tonumber(fighter.height)
if not h then return nil end
local ok, s = pcall(function() return self.getScale() end)
local sy = math.abs(ok and s and tonumber(s.y or s[2]) or 1)
return { height = h * sy, units = h }
end
function setHeight(v)
if type(v) == "table" then v = v.height or v.value end
local ok, s = pcall(function() return self.getScale() end)
local sy = math.max(0.01, math.abs(ok and s and tonumber(s.y or s[2]) or 1))
fighter.height = tonumber(v) and tonumber(v) / sy or MODEL.height(self)
refresh()
return getHeight()
end
function getLift() return tonumber(fighter.lift) or 0 end
function setLift(v)
if type(v) == "table" then v = v.value or v.lift end
local max = tonumber(CFG.liftMax) or 5
local n = math.floor(clamp(tonumber(v) or 0, -max, max) * 1000 + 0.5) / 1000
fighter.lift = n ~= 0 and n or nil
if ui.built then ui.place() end
return getLift()
end
function nudgeLift(steps)
if type(steps) == "table" then steps = steps.value end
return setLift(getLift() + (tonumber(steps) or 1) * (tonumber(CFG.liftStep) or 0.1))
end
function baseToBase(other)
if type(other) == "string" then
local ok, o = pcall(function() return getObjectFromGUID(other) end)
other = ok and o or nil
end
local a, b = positionOf(self), other and positionOf(other)
if not (a and b) then return nil end
local ob = nil
if isSelf(other) then ob = currentBase() else
local ok, v = ACTIVATION.ask(other, "getBase")
ob = (ok and validBase(v)) or MODEL.measureBase(other) or MODEL.baseRecord(CFG.baseDefault, "default")
end
a.r, b.r = currentBase().diameter / 2, ob.diameter / 2
return baseGap(a, b)
end
function engageInfo()
local will = 0
for _, it in ipairs(SKILL.with("ironWill")) do will = will + math.max(0, math.floor(tonumber(it.ironWill) or 0)) end
local assist, kits = 0, {}
for _, it in ipairs(SKILL.with("assist")) do
local n = math.max(0, math.floor(tonumber(it.assist) or 0))
if n > 0 then assist, kits[#kits + 1] = assist + n, it.name end
end
local wil = ACTIVATION.wyrdCan() and statNumber("Wil") or nil
local cacophony, void = ACTIVATION.liveField("rerollHits"), ACTIVATION.liveField("void")
local immune = ACTIVATION.immunity()
local cloak, soul = SKILL.with("refraction")[1], SKILL.with("voidSoul")[1]
local agMod, agRr = ACTIVATION.agilityMod(), ACTIVATION.agilityReroll()
return { name = fighter.name, status = fighter.status, diameter = currentBase().diameter,
ironWill = will > 0 and will or nil, wyrd = wil and true or nil, wil = wil,
assist = assist > 0 and assist or nil, assistWith = assist > 0 and table.concat(kits, ", ") or nil,
out = fighter.outOfAction == true or nil, activation = fighter.activation,
rank = fighter.rank, cl = statNumber("Cl"), ld = statNumber("Ld"),
t = statNumber("T"), s = statNumber("S"), loner = ACTIVATION.tags().loner or nil,
master = #SKILL.with("master") > 0 or nil,
fearsome = ACTIVATION.isFearsome() or nil,
ironJaw = ACTIVATION.jaw(),
lieLow = #SKILL.with("lieLow") > 0 or nil,
refraction = cloak and type(cloak.refraction) == "table" and { moved = cloak.refraction.moved,
still = cloak.refraction.still, name = cloak.name } or nil,
voidSoul = soul and soul.name or nil,
agilityMod = agMod ~= 0 and agMod or nil, agilityReroll = agRr,
auras = ACTIVATION.allAuras(), cacophony = cacophony and cacophony.name or nil,
void = void and tonumber(void.void) or nil,
visions = ACTIVATION.wyrdCan() and type(fighter.wyrd) == "table" and fighter.wyrd.visions or nil,
immune = next(immune) and immune or nil, hanger = ACTIVATION.noGangRule() or nil }
end
function ACTIVATION.aimsAt(a)
if a.targets == "one" or a.targets == "several" then return a.targets end
if a.key == "group_activation" then return "several" end
if a.key == "treat_ally" or a.key == "coup_de_grace" or a.heal or a.restrain then return "one" end
local it = a.type == "wyrd" and a.kind == "skill" and ACTIVATION.item(a.key)
if it and it.target then return "one" end
return nil
end
function isOutOfAction() return fighter.outOfAction == true end
function ACTIVATION.immunity()
local out = {}
for _, it in ipairs(SKILL.with("immune")) do
for _, k in ipairs(type(it.immune) == "table" and it.immune or { it.immune }) do
local key = tostring(k):lower()
out[key] = out[key] or it.name
end
end
return out
end
function checkEngagement()
if not CFG.autoEngage then return 0 end
return runEngagement()
end
function getSkills()
local out = {}
for i, name in ipairs(fighter.skills or {}) do out[i] = name end
return out
end
function setSkills(v)
fighter.skills = SKILL.parse(v)
SKILL.arm(fighter)
refresh()
return getSkills()
end
function addSkill(name)
local list = getSkills()
list[#list + 1] = type(name) == "table" and name.value or name
return setSkills(list)
end
function removeSkill(name)
local key, list = SKILL.key(type(name) == "table" and name.value or name), {}
for _, s in ipairs(getSkills()) do
if SKILL.key(s) ~= key then list[#list + 1] = s end
end
return setSkills(list)
end
function getWargear()
local out = {}
for i, name in ipairs(fighter.wargear or {}) do out[i] = name end
return out
end
function setWargear(v)
fighter.wargear = SKILL.parse(v)
SKILL.arm(fighter)
refresh()
return getWargear()
end
function addWargear(name)
local list = getWargear()
list[#list + 1] = type(name) == "table" and name.value or name
return setWargear(list)
end
function removeWargear(name)
local key, list = SKILL.key(type(name) == "table" and name.value or name), {}
for _, s in ipairs(getWargear()) do
if SKILL.key(s) ~= key then list[#list + 1] = s end
end
return setWargear(list)
end
function clearConditions()
local n = 0
for _, c in ipairs(CONDITIONS) do
local keeps = c.key == "maintaining_power" and type(fighter.wyrd) == "table" and fighter.wyrd.power
if conditionCount(c.key) > 0 and not keeps then
n = n + 1
setCondition(c.key, 0)
end
end
return n
end
function ui.drawCondToggle(key)
for i, c in ipairs(PANELS.cond.list) do
if c.key == key then return ui.drawToggle("cond", i) end
end
end
function setCondition(key, n)
key, n = keyValue(key, n)
local i = indexOf(CONDITIONS, key)
if not i then return nil end
if n == true then n = 1 elseif n == false or n == nil then n = 0 end
n = math.max(0, math.floor(tonumber(n) or 0))
if not CONDITIONS[i].stacks then n = math.min(n, 1) end
local proof = n > 0 and ACTIVATION.immunity()[tostring(key):lower()]
if proof then
chat(string.format("%s has a %s -- never %s", fighter.name, proof, CONDITIONS[i].label), rgbOf(COL.valueMod))
ui.drawCondToggle(key)
return conditionCount(key)
end
local before = conditionCount(key)
fighter.conditions[key] = n > 0 and n or nil
ui.drawCondToggle(key)
ui.drawConditionBar()
ui.drawStats()
if key == "maintaining_power" and n == 0 and before > 0 and type(fighter.wyrd) == "table" and fighter.wyrd.power then
ACTIVATION.wyrdExpire(" -- Maintaining Power taken off")
ACTIVATION.wyrdDraw()
end
if n ~= before then onConditionChanged(key, n, before) end
if n ~= before then
__nqs_mundane_bus.send({
kind = "state_change", action = "condition",
fighter = fighter and fighter.name or nil,
field = "condition",
key = tostring(key),
label = CONDITIONS[i] and CONDITIONS[i].label or nil,
from = before,
to = n,
stacks = (CONDITIONS[i] and CONDITIONS[i].stacks) and true or false,
})
end
return n
end
function setWeapon(index, weapon)
index, weapon = keyValue(index, weapon)
index = tonumber(index)
if not index or not LAY.weaponSpots[index] then return false end
fighter.weapons[index] = weapon
TRAIT_RULES.roles()
refresh()
return true
end
function setProfileState(t)
if type(t) ~= "table" then return nil end
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p then return nil end
if t.mode ~= nil and indexOf(PROFILE_MODES, t.mode) then p.mode = t.mode end
if t.ammo ~= nil then
local was, volley = TRAIT_RULES.ammoState(w, p), TRAIT_RULES.volley[w]
p.ammo = AMMO_LOOK[t.ammo] and t.ammo ~= "fine" and t.ammo or nil
for _, q in ipairs(w.profiles) do
if q ~= p and p.ammo == "combi" and TRAIT_RULES.combi(q) and not profileDown(q) then
q.ammo = "combi"
elseif q ~= p and p.ammo ~= "combi" and was == "combi" and q.ammo == "combi"
and not (volley and profileDown(p)) then
q.ammo = nil
end
end
if volley and was == "combi" and p.ammo == nil then TRAIT_RULES.volley[w] = nil end
end
if t.attacks ~= nil then
local step = TRAIT_RULES.step(p, t.attacks)
p.attacks = step ~= "charge" and step or nil
end
for k = 1, #w.profiles do ui.drawProfile(i, k) end
TRAIT_RULES.drawGlows()
ui.drawStats()
onProfileChanged(i, pi, p)
return p
end
function setWeaponHit(t)
if type(t) ~= "table" then return nil end
local i = tonumber(t.weapon)
local w = i and weaponAt(i)
if not w then return nil end
w.hit = TRAIT_RULES.hit({ hit = t.value })
if w.hit == 0 then w.hit = nil end
for k = 1, #(w.profiles or {}) do ui.drawProfile(i, k) end
return TRAIT_RULES.hit(w)
end
function setProfileStat(t)
if type(t) ~= "table" then return nil end
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not (p and TRAIT_RULES.adjustable(p, t.key)) then return nil end
local R, key = TRAIT_RULES, t.key
local want, now = math.floor(tonumber(t.value) or 0), R.adjSteps(p, key)
while want ~= now do
local nxt = now + (want > now and 1 or -1)
if R.adjust(key, p[key], nxt) == R.adjust(key, p[key], now) then break end
now = nxt
end
p.adj = p.adj or {}
p.adj[key] = now ~= 0 and now or nil
if next(p.adj) == nil then p.adj = nil end
for k = 1, #w.profiles do ui.drawProfile(i, k) end
onProfileChanged(i, pi, p)
return now
end
function setReliable(t)
if type(t) ~= "table" then return nil end
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not (p and TRAIT_RULES.reliable(p)) then return nil end
p.reliableUsed = t.value == false or nil
ui.drawProfile(i, pi)
onProfileChanged(i, pi, p)
return not p.reliableUsed
end
function ACTIVATION.readyReliables()
local n = 0
for i = 1, weaponCount() do
local w = weaponAt(i)
for pi, p in ipairs((w and w.profiles) or {}) do
if p.reliableUsed then
n, p.reliableUsed = n + 1, nil
ui.drawProfile(i, pi)
end
end
end
return n
end
function resetReliable()
local n = ACTIVATION.readyReliables()
setUsedOnce(nil, false)
for i = 1, weaponCount() do
local w = weaponAt(i)
for pi, p in ipairs((w and w.profiles) or {}) do
if TRAIT_RULES.lanceBomb(p) and p.ammo == "spent" then setProfileState({ weapon = i, profile = pi, ammo = "fine" }) end
end
end
if fighter.burnt then
fighter.burnt = nil
SKILL.drawBurnt()
ui.drawStats()
end
if fighter.wyrd then
ACTIVATION.unhex(fighter.wyrd)
fighter.wyrd = nil
ACTIVATION.wyrdDraw()
end
if fighter.hexes then
fighter.hexes = nil
ui.drawStats()
end
return n
end
function resetFighter()
local src = ACTIVATION.imported
if type(src) ~= "table" then return false end
if fighter.wyrd then ACTIVATION.unhex(fighter.wyrd) end
ACTIVATION.gearUnhex()
local data = RULES.copy(src)
data.base, data.height, data.lift = fighter.base, fighter.height, fighter.lift
setFighter(data)
ACTIVATION.powerMark()
if CFG.autoEngage then checkEngagement() end
return true
end
function setUsedOnce(key, used)
key, used = keyValue(key, used)
used = used == true
local boosted = fighter.boosted
if key == nil then
fighter.usedOnce = nil
if not used then fighter.boosted = nil end
else
fighter.usedOnce = fighter.usedOnce or {}
fighter.usedOnce[tostring(key)] = used or nil
if not used and boosted then boosted[tostring(key)] = nil end
end
if boosted and not used then ui.drawStats() end
SKILL.drawBurnt()
ui.drawStats()
ui.drawActions()
return used
end
function setBurnt(key, burnt)
key, burnt = keyValue(key, burnt)
local it, k = nil, SKILL.key(tostring(key or ""))
for _, o in ipairs(SKILL.owned()) do
if o.burns and o.key == k then it = o end
end
if not it then return nil end
local was = (fighter.burnt or {})[it.key] == true
if burnt == nil then burnt = not was end
burnt = burnt == true
if burnt ~= was then
fighter.burnt = fighter.burnt or {}
fighter.burnt[it.key] = burnt or nil
if next(fighter.burnt) == nil then fighter.burnt = nil end
SKILL.drawBurnt()
ui.drawStats()
local words = it.bioBooster and { "is used up", "is ready again" } or { "is burnt out", "works again" }
chat(string.format("%s's %s %s (set by hand)", fighter.name, it.name, words[burnt and 1 or 2]),
rgbOf(burnt and COL.valueMod or COL.valueUp))
end
return burnt
end
function attackWith(t, player)
if type(t) ~= "table" then return nil end
player = __nqs_mundane_bus.scripted(t) or player
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p or profileDown(p) or not TRAIT_RULES.usable(p, w) then return nil end
local melee = isMelee(p)
local hit, _, support = TRAIT_RULES.shownHit(w, p)
local attack = {
weapon = i, profile = pi, name = TRAIT_RULES.name(w), stats = p, melee = melee,
mode = melee and PROFILE_MODES[1].key or PROFILE_MODES[profileMode(p)].key,
attacks = melee and meleeAttacks(p) or nil,
combi = TRAIT_RULES.ammoState(w, p) == "combi" or nil,
additional = TRAIT_RULES.ammoState(w, p) == "extra" and TRAIT_RULES.extraShots(p) or nil,
backstab = (TRAIT_RULES.stabbing[w] and TRAIT_RULES.backstab(p)) or nil,
hit = hit,
support = support == 1 and "assist" or support == -1 and "interference" or nil,
marksman = (TRAIT_RULES.longShot[p] and TRAIT_RULES.marksman(p)) and true or nil,
aimed = (TRAIT_RULES.aiming[w] and TRAIT_RULES.canAim(p)) or nil,
stat = TRAIT_RULES.hitStat(p),
reroll = TRAIT_RULES.reroll[w],
}
attack.action, attack.cost, attack.free = TRAIT_RULES.attackAction(w, p)
onWeaponAttack(player, attack)
return attack
end
function setStat(key, value)
key, value = keyValue(key, value)
local was = fighter.stats[key]
fighter.stats[key] = value
fighter.statEdits[key] = nil
pendingStats[key] = nil
refresh()
__nqs_mundane_bus.statChanged("statline", key, was, value)
return true
end
local function steppedStat(key, dir)
local base = statBase(key)
if not base then return nil end
local lo, hi = STAT.range(key)
local n = STAT.clamp(key, base) + dir
if n > hi then n = lo elseif n < lo then n = hi end
return n
end
function nudgeStat(key, dir, by)
local n = steppedStat(key, dir)
if not n then return nil end
pendingStats[key] = n ~= statKept(key) and { n = n, by = by } or nil
ui.drawStats()
return n
end
function keepStat(key)
local was = statKept(key)
local n = statBase(key)
pendingStats[key] = nil
if n then
n = STAT.clamp(key, n)
fighter.statEdits[key] = n ~= statOriginal(key) and n or nil
end
ui.drawStats()
__nqs_mundane_bus.statChanged("stat", key, was, statKept(key))
return n
end
function stepStat(key)
local n = steppedStat(key, 1)
if not n then return nil end
local was = statKept(key)
pendingStats[key] = nil
fighter.statEdits[key] = n ~= statOriginal(key) and n or nil
ui.drawStats()
__nqs_mundane_bus.statChanged("stat", key, was, statKept(key))
return n
end
end
local colorOf, announce, throwDice
do
function colorOf(player)
if type(player) == "string" then return player ~= "" and player or nil end
if player == nil then return nil end
local ok, c = pcall(function() return player.color end)
return ok and type(c) == "string" and c ~= "" and c or nil
end
function announce(msg, color)
chat(msg, color and stringColorToRGB and stringColorToRGB(color) or nil)
end
local function blocksDice(o)
if o == nil or o == self then return false end
if o.type == "Surface" or o.tag == "Surface" then return false end
local ok, locked = pcall(function() return o.getLock() end)
return not (ok and locked)
end
local function diceSpot(color)
if not (Physics and Physics.cast) then return nil end
local ok, b = pcall(function() return self.getBounds() end)
if not ok or not b then return nil end
local c, sz = b.center, b.size
local floor = c.y - sz.y / 2
local r = math.max(sz.x, sz.z) / 2 + CFG.diceGap + CFG.diceArea / 2
local start = 0
local p = color and ui.playerOf(color)
local okH, hand = pcall(function() return p.getHandTransform() end)
if okH and hand and hand.position then
start = math.deg((math.atan2 or math.atan)(hand.position.z - c.z, hand.position.x - c.x))
end
local h = 3
for k = 0, 11 do
local step = math.floor((k + 1) / 2) * (k % 2 == 1 and 1 or -1)
local a = math.rad(start + step * 30)
local x, z = c.x + r * math.cos(a), c.z + r * math.sin(a)
local hits = Physics.cast({ origin = { x, floor + 0.2 + h / 2, z }, direction = { 0, 1, 0 },
type = 3, size = { CFG.diceArea, h, CFG.diceArea }, max_distance = 0 }) or {}
local clear = true
for _, hit in ipairs(hits) do
if blocksDice(hit.hit_object) then clear = false break end
end
if clear then return { x = x, z = z }, floor end
end
return nil
end
function ACTIVATION.tumble(o, spin, push)
local function turn() return (math.random() * 0.5 + 0.5) * (spin or 12) * (math.random() < 0.5 and -1 or 1) end
local av = { turn(), turn(), turn() }
local a, v = math.random() * 2 * math.pi, (math.random() * 0.5 + 0.5) * (push or 0)
local function go()
pcall(function()
if o.isDestroyed and o.isDestroyed() then return end
o.setAngularVelocity(av)
if v > 0 then
local ok, now = pcall(function() return o.getVelocity() end)
local fall = ok and type(now) == "table" and tonumber(now.y or now[2]) or 0
o.setVelocity({ v * math.cos(a), fall, v * math.sin(a) })
end
end)
end
go()
if Wait and Wait.frames then Wait.frames(go, 2) end
return go
end
ACTIVATION.FALL, ACTIVATION.KICK = 0.3, 10
function ACTIVATION.fallen(d)
local o = d.obj
if o == nil or (o.isDestroyed and o.isDestroyed()) then return true end
if o.spawning or not d.kick then return false end
if not d.fell then
local ok, p = pcall(function() return o.getPosition() end)
local x, y, z = ok and p and tonumber(p.x or p[1]), ok and p and tonumber(p.y or p[2]),
ok and p and tonumber(p.z or p[3])
local f = d.from
if not (x and y and z and f) then
d.fell = true
elseif (x - f.x) ^ 2 + (y - f.y) ^ 2 + (z - f.z) ^ 2 >= ACTIVATION.FALL ^ 2 then
d.fell = true
d.kick()
return false
else
d.waited = (d.waited or 0) + 1
if d.waited % ACTIVATION.KICK == 0 then d.kick() end
return false
end
end
return o.resting == true
end
function ACTIVATION.digitalFaces(n)
local faces = {}
for i = 1, n do faces[i] = math.random(1, 6) end
return faces
end
ACTIVATION.throws = { n = 0 }
function ACTIVATION.viaController(n, color, done, kind, label)
local ok, objs = pcall(function() return getObjectsWithTag(CFG.controllerTag) end)
local okG, guid = pcall(function() return self.getGUID() end)
if not (ok and type(objs) == "table" and okG and guid) then return false end
local T = ACTIVATION.throws
local kinds = type(kind) == "table" and kind or nil
for _, obj in ipairs(objs) do
T.n = T.n + 1
local token = T.n
T[token] = done
local okC, took = ACTIVATION.ask(obj, "throwDice", { n = n, kind = kinds and kinds[1] or kind or "d6",
kinds = kinds, color = color, label = label, from = guid, token = token })
if okC and took == true then
Wait.time(function()
local fn = T[token]
if fn then T[token] = nil; fn(ACTIVATION.digitalFaces(n), true) end
end, CFG.diceWait)
return true
end
T[token] = nil
end
return false
end
function onDiceThrown(t)
local T = ACTIVATION.throws
local fn = type(t) == "table" and T[t.token]
if not fn then return false end
T[t.token] = nil
local faces = {}
for i, f in ipairs(t.faces or {}) do faces[i] = clamp(math.floor(tonumber(f) or 1), 1, 6) end
fn(faces, t.digital == true)
return true
end
function throwDice(n, color, done, kind, label)
if ACTIVATION.viaController(n, color, done, kind, label) then return end
local function digital() done(ACTIVATION.digitalFaces(n), true) end
local spot, floor = diceSpot(color)
if not (spot and spawnObject and Wait and Wait.condition) then return digital() end
local dice = {}
for i = 1, n do
local dx = (i - (n + 1) / 2) * 1.2
local d = { from = { x = spot.x + dx, y = floor + 1.5, z = spot.z } }
dice[i] = d
d.obj = spawnObject({
type = "Die_6", position = { d.from.x, d.from.y, d.from.z },
rotation = { math.random(0, 359), math.random(0, 359), math.random(0, 359) },
callback_function = function(o)
if color and stringColorToRGB then o.setColorTint(stringColorToRGB(color)) end
o.addTag("gang-roster-roll")
d.kick = ACTIVATION.tumble(o, CFG.diceSpin, CFG.dicePush)
end,
})
end
local function settled()
local all = true
for _, d in ipairs(dice) do
local ok, down = pcall(ACTIVATION.fallen, d)
if not (ok and down) then all = false end
end
return all
end
local function clear()
Wait.time(function()
for _, d in ipairs(dice) do
local o = d.obj
if o and not (o.isDestroyed and o.isDestroyed()) then o.destruct() end
end
end, CFG.diceKeep)
end
Wait.condition(function()
local faces = {}
for i, d in ipairs(dice) do
local ok, v = pcall(function() return d.obj.getValue() end)
faces[i] = ok and tonumber(v) or math.random(1, 6)
end
clear()
done(faces, false)
end, settled, 10, function() clear() digital() end)
end
function ACTIVATION.checkInk(test)
if test.target == nil then return nil end
return test.passed and COL.valueUp or COL.valueMod
end
function ACTIVATION.injuryText(faces, k)
local R, each = ACTIVATION.INJURY, {}
for i, f in ipairs(faces) do each[i] = R[ACTIVATION.INJURY_DICE[f] or "serious"].short end
if #each < 2 then return R[ACTIVATION.INJURY_DICE[faces[1]] or k or "serious"].label end
return table.concat(each, ", ") .. " = " .. R[k].label
end
function ACTIVATION.say(what, each, total, o)
o = o or {}
local body = tostring(total) .. (o.unit or "")
if #each > 1 then body = table.concat(each, " + ") .. " = " .. body end
local msg = string.format("%s - %s: %s%s%s", fighter.name, what, body, o.more or "",
o.digital and " (rolled digitally)" or "")
if o.ink then chat(msg, rgbOf(o.ink)) else announce(msg, o.color) end
end
function rollStat(key, player)
key, player = keyValue(key, player)
return ACTIVATION.rollTest(key, player)
end
function ACTIVATION.rollTest(key, player, o)
o = o or {}
local roll = key == "Inv" and STAT_ROLLS.Sv or STAT_ROLLS[key]
local target = key == "Inv" and STAT.inv() or statNumber(key, key == "Sv" and TRAIT_RULES.saveContext() or nil)
if not target then return nil end
local own, suffix = target, ""
for _, m in ipairs(roll and o.mods or {}) do
target = target + m
suffix = suffix .. string.format(" %s %d", m < 0 and "-" or "+", math.abs(m))
end
local test = {
stat = key, dice = roll and roll.dice or 1, target = roll and target or nil,
under = roll and roll.under or nil,
}
test.text = roll and string.format("%s test: %dD6, %d or %s", key, roll.dice, target,
roll.under and "under" or "over") or string.format("%s roll: 1D6", key)
local label = o.label or "Check"
local title = test.target and string.format("%s: %s (%d%s)%s", label, STAT.NAMES[key] or key, own,
test.under and "" or "+", suffix)
or key .. " Roll"
local color = colorOf(player)
ACTIVATION.rolling(title)
throwDice(test.dice, color, function(faces, digital)
local total = 0
for _, f in ipairs(faces) do total = total + f end
test.faces, test.total, test.digital = faces, total, digital
if test.target then test.passed = statTestPasses(test, total) end
if o.natural and test.target and #faces == 2 then
test.natural = total == 2 and 2 or total == 12 and 12 or nil
if test.natural then test.passed = test.natural == 2 end
end
ACTIVATION.say(test.target and string.format("%s: %s (%d%s%s)", label, key, test.target, test.under and "" or "+",
o.why and ", " .. o.why or "")
or key .. " Roll", faces, total,
{ ink = o.ink or ACTIVATION.checkInk(test), color = color, digital = digital })
ACTIVATION.showDice{ title = test.natural and "Perils of the Warp!" or title, kind = "d6", faces = faces,
hl = ACTIVATION.checkInk(test), sum = not test.target and ("∑" .. total) or nil }
onStatRoll(player, test)
__nqs_mundane_bus.try(function()
local names = { Cl = "Cool", Ld = "Leadership", Wil = "Willpower", Int = "Intelligence",
S = "Strength", T = "Toughness", I = "Initiative", Sv = "Save",
Inv = "Invulnerable save", M = "Movement", A = "Attacks" }
local out = { total = test.total }
if test.target ~= nil then out.passed, out.natural = test.passed and true or false, test.natural end
test.busLabel = (names[key] or key) .. (test.target == nil and " roll" or " check")
__nqs_mundane_bus.test(test.busLabel, faces, "D6", {
direction = test.target and (test.under and "lte" or "gte") or nil,
stat = key, target = test.target, modifiers = roll and o.mods and #o.mods > 0 and o.mods or nil,
outcome = out, why = o.why, by = color or player,
})
end)
if o.done then
local shown = ACTIVATION.roll
__nqs_mundane_bus.within("cause", { roll = test.busLabel }, function() o.done(test, shown) end)
end
end, "d6", title)
return test
end
function ACTIVATION.rollName(kind, n)
if kind == "firepower" or kind == "injury" then
local name = kind == "firepower" and "Firepower Dice" or "Injury Dice"
return n > 1 and string.format("%d %s", n, name) or name
end
return n > 1 and string.format("Roll %dD6", n) or "Roll D6"
end
function ACTIVATION.stack(kind, player)
local s = ACTIVATION.stacking
if s and s.kind ~= kind then
ACTIVATION.stacking = nil
ACTIVATION.throwStack(s)
s = nil
end
if s then
s.n, s.player = math.min(ACTIVATION.MAX_DICE, s.n + 1), player
else
s = { kind = kind, n = 1, player = player, token = 0 }
ACTIVATION.stacking = s
end
s.token = s.token + 1
local t = s.token
ACTIVATION.rolling(ACTIVATION.rollName(kind, s.n))
Wait.time(function()
if ACTIVATION.stacking == s and s.token == t then
ACTIVATION.stacking = nil
ACTIVATION.throwStack(s)
end
end, CFG.diceJoin)
end
function ACTIVATION.throwStack(s)
if s.kind == "firepower" then rollFirepower(s.n, s.player)
elseif s.kind == "injury" then rollInjuries(s.n, s.player)
else rollDice(s.n, s.player) end
end
function ACTIVATION.count(n, player)
if type(n) == "table" then
if n.color and player == nil then return 1, n end
n = n.value or n.n
end
return math.max(1, math.min(ACTIVATION.MAX_DICE, math.floor(tonumber(n) or 1))), player
end
function rollDice(n, player)
n, player = ACTIVATION.count(n, player)
local color = colorOf(player)
local title = ACTIVATION.rollName("d6", n)
ACTIVATION.rolling(title)
throwDice(n, color, function(faces, digital)
local total = 0
for _, f in ipairs(faces) do total = total + f end
ACTIVATION.say(string.format("Roll %dD6", n), faces, total, { color = color, digital = digital })
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, sum = "∑" .. total }
__nqs_mundane_bus.send({
kind = "roll", action = "d6 roll",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
outcome = { total = total },
by = color or player,
})
end, "d6", title)
return true
end
function rollFirepower(n, player)
n, player = ACTIVATION.count(n, player)
local color = colorOf(player)
local title = ACTIVATION.rollName("firepower", n)
ACTIVATION.rolling(title)
throwDice(n, color, function(faces, digital)
local hits, ammo, each, checks = 0, false, {}, 0
for i, f in ipairs(faces) do
local fp = ACTIVATION.FIREPOWER[f] or ACTIVATION.FIREPOWER[1]
hits, ammo = hits + fp.hits, ammo or fp.ammo == true
if fp.ammo then checks = checks + 1 end
each[i] = tostring(fp.hits)
end
ACTIVATION.say(string.format("Roll %dx Firepower", n), each, hits,
{ unit = hits == 1 and " Hit" or " Hits", color = color, digital = digital,
more = checks > 0 and string.format(", %d Ammo check%s", checks, checks == 1 and "" or "s") or nil })
ACTIVATION.showDice{ title = title, kind = "firepower", faces = faces, sumInk = hits > 0 and COL.valueUp or COL.valueMod,
sum = "∑" .. hits, ammoState = ACTIVATION.ammoState(checks) }
onFirepowerRolled(player, { face = faces[1], faces = faces, hits = hits, ammo = ammo })
__nqs_mundane_bus.send({
kind = "roll", action = "firepower",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "FIREPOWER"),
outcome = { hits = hits, ammo_checks = checks, ammo_fired = ammo and true or false },
by = color or player,
})
end, "firepower", title)
return true
end
function rollInjuries(n, player)
n, player = ACTIVATION.count(n, player)
local color = colorOf(player)
local title = ACTIVATION.rollName("injury", n)
ACTIVATION.rolling(title)
throwDice(n, color, function(faces, digital)
local R, results, count = ACTIVATION.INJURY, {}, {}
for i, f in ipairs(faces) do
local k = ACTIVATION.INJURY_DICE[f] or "serious"
results[i], count[k] = k, (count[k] or 0) + 1
end
local worst, best = nil, nil
for _, k in ipairs({ "out", "serious", "injured" }) do worst = worst or (count[k] and k) end
for _, k in ipairs({ "injured", "serious", "out" }) do best = best or (count[k] and k) end
ACTIVATION.say("Roll Injuries", {}, ACTIVATION.injuryText(faces, best),
{ color = color, digital = digital })
ACTIVATION.showDice{ title = title, kind = "injury", faces = faces, result = worst, best = best }
if count.out == #faces and not fighter.outOfAction then
setOutOfAction{ value = true, why = "every Injury dice Out of Action" }
end
onInjuriesRolled(player, results, faces)
do
__nqs_mundane_bus.send({
kind = "roll", action = "injury roll",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "INJURY"),
outcome = {
out = count.out or 0,
serious = count.serious or 0,
injured = count.injured or 0,
worst = worst,
best = best,
out_of_action = (count.out == #faces) and true or false,
},
by = color or player,
})
end
end, "injury", title)
return true
end
end
function ACTIVATION.sayAttack(verb, what, body, ink, digital, why)
chat(string.format("%s - %s - %s: %s%s%s", fighter.name, verb, what, body,
digital and " (rolled digitally)" or "",
type(why) == "table" and #why > 0 and " || (" .. table.concat(why, ", ") .. ")" or ""), rgbOf(ink))
end
ACTIVATION.seqs, ACTIVATION.seqCount, ACTIVATION.SEQ_INK = {}, 0, { 1, 1, 1 }
function ACTIVATION.attackHeader(verb, aims, player)
local named = {}
for _, a in ipairs(aims or {}) do
if a and a.name then
local gang = trimText(a.gang or "")
named[#named + 1] = { name = gang ~= "" and string.format("%s [%s]", a.name, gang) or a.name }
end
end
local text = string.format("%s - %s%s", fighter.name, verb, #named > 0 and " vs " .. ACTIVATION.nameList(named) or "")
local c = colorOf(player)
ACTIVATION.seqCount = ACTIVATION.seqCount + 1
if #named == 0 or (CFG.seqRule or "") == "" then
announce(text, c)
ACTIVATION.seqs[ACTIVATION.seqCount] = { pending = 1, at = os.time(), told = {}, quiet = true }
return ACTIVATION.seqCount
end
ACTIVATION.line(string.format("%s %s%s %s", CFG.seqRule, ui.gangPrefix(), text, CFG.seqRule), ACTIVATION.SEQ_INK)
ACTIVATION.seqs[ACTIVATION.seqCount] = { pending = 1, at = os.time(), told = {} }
return ACTIVATION.seqCount
end
function ACTIVATION.line(msg, rgb)
if printToAll then pcall(printToAll, msg, rgb or { 0.9, 0.9, 0.9 }) else print(msg) end
end
ACTIVATION.targeted = {}
function ACTIVATION.seqRole()
local now, stale = os.time(), tonumber(CFG.seqStale) or 120
local s = ACTIVATION.seqs[ACTIVATION.seqCount]
if s and not s.quiet and now - (s.at or now) <= stale then return "A" end
for k, at in pairs(ACTIVATION.targeted) do
if now - at <= stale then return "T" else ACTIVATION.targeted[k] = nil end
end
return nil
end
function ACTIVATION.seqJoin(t)
if type(t) == "table" and t.seq and t.from then
ACTIVATION.targeted[tostring(t.from) .. ":" .. tostring(t.seq)] = os.time()
__nqs_mundane_bus.card.attack = __nqs_mundane_bus.attackId(t.seq, t.from)
__nqs_mundane_bus.card.attackAt = os.time()
end
end
function ACTIVATION.onClose(token, fn)
local s = token and ACTIVATION.seqs[token]
if not s then return fn() end
s.finally = s.finally or {}
s.finally[#s.finally + 1] = fn
end
function ACTIVATION.seqTell(token, obj)
local s = token and ACTIVATION.seqs[token]
if not (s and obj) then return end
local ok, guid = pcall(function() return obj.getGUID() end)
if ok and guid then s.told[guid] = obj end
end
function ACTIVATION.seqWait(token, obj)
local s = token and ACTIVATION.seqs[token]
ACTIVATION.seqTell(token, obj)
if not (s and obj and ACTIVATION.has(obj, "attackOver")) then return false end
s.pending = s.pending + 1
return true
end
function ACTIVATION.seqDone(token)
local s = token and ACTIVATION.seqs[token]
if not s then return end
s.pending = s.pending - 1
if s.pending > 0 then
if s.next and s.pending == 1 then
local go = s.next
s.next = nil
go()
end
return
end
if s.finally and #s.finally > 0 then
s.pending = 1
return table.remove(s.finally, 1)()
end
ACTIVATION.seqs[token] = nil
if not s.quiet then ACTIVATION.line(CFG.seqRule, ACTIVATION.SEQ_INK) end
local ok, me = pcall(function() return self.getGUID() end)
for _, obj in pairs(s.told) do
ACTIVATION.ask(obj, "seqClosed", { from = ok and me or nil, seq = token })
end
local back = ACTIVATION.back
if back and back.state == "striking" and back.token == token then
ACTIVATION.later(ACTIVATION.roll, function()
if ACTIVATION.back == back then ACTIVATION.backDone() end
end)
end
end
function ACTIVATION.seqEnd(t)
if type(t) == "table" and t.after and not t.afterDone then
t.afterDone = true
ACTIVATION.later(ACTIVATION.roll, t.after)
end
if type(t) ~= "table" or not (t.seq and t.from) or t.seqEnded then return end
t.seqEnded = true
if __nqs_mundane_bus.card.attack == __nqs_mundane_bus.attackId(t.seq, t.from) then
__nqs_mundane_bus.card.attack = nil
end
local ok, obj = pcall(function() return getObjectFromGUID(t.from) end)
if ok and obj then ACTIVATION.ask(obj, "attackOver", { token = t.seq }) end
end
function ACTIVATION.attackVerb(a)
if a.melee and fighter.activation ~= "active" then return "FIGHTING BACK" end
local e = ACTIONS[indexOf(ACTIONS, a.action) or 0]
return (e and e.label or "Attack"):upper()
.. (a.free == "gunfighter" and " (Gunfighter)" or a.free == "assault" and " (Assault)" or "")
end
function ACTIVATION.spendAttack(a)
if a.action == "fight" and fighter.activation == "active" and fighter.freeStrike then
fighter.freeStrike, fighter.usedActions.fight = nil, true
ui.drawActions()
return 0
end
if a.action ~= "fight" and a.cost == nil and fighter.activation == "active"
and (tonumber(fighter.shotsPaid) or 0) > 0 then
fighter.shotsPaid = fighter.shotsPaid > 1 and fighter.shotsPaid - 1 or nil
return 0
end
local cost = ACTIVATION.attackCost(a.weapon, a.profile)
if cost <= 0 then return 0 end
fighter.actionsLeft = math.max(0, fighter.actionsLeft - cost)
fighter.usedActions[a.action] = true
ui.drawReady()
ui.drawActions()
onActionsChanged(fighter.actionsLeft)
return cost
end
function rollAttack(t, player)
player = __nqs_mundane_bus.scripted(t) or player
if ACTIVATION.noTarget(t, player) then return nil end
if ACTIVATION.tooMany(t, player) then return nil end
if ACTIVATION.lyingLow(t, player) then return nil end
if ACTIVATION.cloaked(t, player) then return nil end
return ACTIVATION.strike(t, player)
end
function ACTIVATION.cloaked(t, player)
if type(t) ~= "table" or t.refraction then return false end
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p or isMelee(p) or TRAIT_RULES.template(p) or profileDown(p) or not TRAIT_RULES.usable(p, w) then
return false
end
if TRAIT_RULES.hitStat(p) == "WS" then return false end
local aim = ACTIVATION.target(player, true)
local rf = aim and type(aim.refraction) == "table" and aim.refraction
if not rf then return false end
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", yes = true, title = CFG.cloakAsk, item = tostring(rf.name or "Refraction Cloak"),
obj = aim.obj, ink = rgbOf(COL.valueMod),
done = function(moved, _, who)
local go = {}
for k, v in pairs(t) do go[k] = v end
go.refraction = math.floor(tonumber(moved and rf.moved or rf.still) or 0)
go.cloak = string.format("%s, %s", tostring(rf.name or "Refraction Cloak"), moved and "moved" or "still")
ACTIVATION.strike(go, who or player)
end })
return true
end
function ACTIVATION.lyingLow(t, player)
local i, pi = type(t) == "table" and tonumber(t.weapon), type(t) == "table" and tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p or isMelee(p) or profileDown(p) or not TRAIT_RULES.usable(p, w) or TRAIT_RULES.held(w, p) then
return false
end
local aim = ACTIVATION.target(player, true)
if not (aim and aim.lieLow and aim.status == "suppressed") then return false end
if ACTIVATION.inShort(w, p, aim) then return false end
chat(string.format("%s is lying low -- %s can't target them with a ranged attack", aim.name, fighter.name),
rgbOf(COL.valueMod))
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", title = "Enemy has Lie Low", obj = aim.obj, ink = rgbOf(COL.valueMod),
done = function(yes, _, who)
if yes then ACTIVATION.strike(t, who or player) end
end })
return true
end
function ACTIVATION.noTarget(t, player)
if type(t) ~= "table" or #ACTIVATION.targets(player, true) > 0 then return false end
if ACTIVATION.back and ACTIVATION.back.state == "armed" then return false end
chat(string.format("%s - no target selected: select an enemy before the attack is rolled", fighter.name),
rgbOf(COL.valueMod))
return true
end
function ACTIVATION.tooMany(t, player)
local i, pi = type(t) == "table" and tonumber(t.weapon), type(t) == "table" and tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p or TRAIT_RULES.spreads(p) then return false end
return #ACTIVATION.targets(player, true) > 1
end
function ACTIVATION.strike(t, player)
local R = TRAIT_RULES
local slot = type(t) == "table" and tonumber(t.weapon) or nil
if slot and weaponAt(slot) then R.measure(slot, player, CFG.preMeasure) end
local attack = attackWith(t, player)
if slot and weaponAt(slot) and not CFG.preMeasure then R.measure(slot, nil) end
if not attack then return nil end
local verb = ACTIVATION.attackVerb(attack)
ACTIVATION.spendAttack(attack)
local w, p = weaponAt(attack.weapon), attack.stats
R.fought(w, p)
if R.fightsWith(p) then R.drawWeapons() end
local aim = ACTIVATION.target(player, true)
local template = not attack.melee and R.template(p)
local aims = template and not R.closeTemplate(p) and ACTIVATION.targets(player, true) or { aim }
if template and attack.mode == "rapid_fire" then aims = ACTIVATION.nearestFirst(aims) end
local plans = {}
for k, a in ipairs(aims) do plans[k] = not R.noWound(p) and ACTIVATION.woundPlan(w, p, a) or nil end
local fight = fighter.activation == "active" and R.hitStat(p) == "WS"
for _, plan in pairs(plans) do plan.fight = fight or nil end
local back = ACTIVATION.back
if back and back.state == "armed" then
back.state, back.weapon = "striking", w
end
attack.target = (plans[1] and plans[1].target) or (R.noWound(p) and aims[1] and aims[1].name) or nil
if not attack.melee and not template and aim and aim.status == "seriously_injured" then
attack.hit, attack.prone = (attack.hit or 0) - 1, true
end
if type(t) == "table" and tonumber(t.refraction) and not attack.melee and not template then
attack.hit, attack.cloak = (attack.hit or 0) + tonumber(t.refraction), t.cloak
end
if template then
attack.targets = {}
for k, a in ipairs(aims) do attack.targets[k] = a.name end
end
if fighter.activation == "active" then __nqs_mundane_bus.try(function()
local names = {}
for k, a in ipairs(aims) do if a and a.name then names[#names + 1] = tostring(a.name) end end
local pr = type(w) == "table" and type(w.profiles) == "table" and w.profiles[tonumber(attack.profile) or 0]
__nqs_mundane_bus.action(player, attack.action or (attack.melee and "fight" or "shoot"), {
weapon = tostring(R.name(w) or attack.name or "Weapon"),
profile = type(pr) == "table" and pr.name and tostring(pr.name)
or attack.profile ~= nil and tostring(attack.profile) or nil,
mode = attack.mode == "rapid_fire" and "rapid_fire" or "single",
aimed = attack.aimed and true or nil, targets = #names > 0 and names or nil,
}, names[1], attack.free and true or nil)
end) end
attack.seq = ACTIVATION.attackHeader(verb, aims, player)
if back and back.state == "striking" and not back.token then back.token = attack.seq end
local cac = not attack.melee and ACTIVATION.cacophony() or nil
attack.cacophony = cac and { name = cac.name, power = cac.cacophony } or nil
if attack.combi then
R.fire(w, p, true)
for k = 1, #w.profiles do ui.drawProfile(attack.weapon, k) end
end
R.shotFired(w, p, attack)
ACTIVATION.fearFirst(attack.melee and aim and aim.foe and aim or nil, player, function()
ACTIVATION.attackDice(attack, verb, { aims = aims, plans = plans }, player)
end)
return attack
end
function ACTIVATION.hitOnly(kind)
local n, why = nil, nil
for _, c in ipairs(CONDITIONS) do
local v = type(c.hitOnly) == "table" and tonumber(c.hitOnly[kind]) or nil
if v and conditionCount(c.key) > 0 and v > (n or 0) then n, why = v, c.label end
end
return n, why
end
function ACTIVATION.hitRead(attack)
local only, why = ACTIVATION.hitOnly(attack.melee and "melee" or "ranged")
local mod = only and 0 or (attack.hit or 0)
local h = { mod = mod, only = only, why = why, shock = TRAIT_RULES.shock(attack.stats),
knock = TRAIT_RULES.knockback(attack.stats, weaponAt(attack.weapon)) }
h.need = only or ((statNumber(attack.stat or (attack.melee and "WS" or "BS")) or 7) - mod)
h.shown = clamp(h.need, 2, 6)
function h.hits(f) return f ~= 1 and (f == 6 or f >= h.need) end
local function reaches(f, n)
if not (n and h.hits(f)) then return false end
return f + ((CFG.shockNatural or only) and 0 or mod) >= n
end
function h.shocked(f) return reaches(f, h.shock) end
function h.knocked(f) return reaches(f, h.knock) end
return h
end
function ACTIVATION.hitHead(attack, h, template)
local key = attack.stat or (attack.melee and "WS" or "BS")
if h.only then return string.format("%s natural %d+", key, h.only) end
local n = statNumber(key)
local head = n and string.format("%s%d+", key, n) or key .. "-"
if template or h.mod == 0 then return head end
return head, string.format("%+d to Hit", h.mod), h.mod > 0 and COL.valueUp or COL.valueMod
end
function ACTIVATION.hitWhy(attack, h)
local R, w = TRAIT_RULES, weaponAt(attack.weapon)
local out = {}
if h.only then
out[1] = h.why
else
STAT.why(attack.stat or (attack.melee and "WS" or "BS"), nil, out)
local own = w and R.hit(w) or 0
if own ~= 0 then out[#out + 1] = string.format("Hit %+d set by hand", own) end
if attack.combi then out[#out + 1] = "Combi" end
if attack.aimed then
local n, by = w and R.aimHit(w) or 1, nil
if n > 1 then
for _, it in ipairs(SKILL.with("aimed")) do if (tonumber(it.aimed) or 0) >= n then by = by or it.name end end
for _, a in ipairs(w and select(2, R.named(w)) or {}) do
if (tonumber(a.def.aimed) or 0) >= n then by = by or a.name end
end
end
out[#out + 1] = by and "Aimed (" .. by .. ")" or "Aimed"
end
if attack.support == "assist" then out[#out + 1] = "Assist"
elseif attack.support then out[#out + 1] = "Interference" end
if attack.marksman then out[#out + 1] = "Marksman" end
if attack.prone then out[#out + 1] = "Target S. Inj." end
if attack.cloak then out[#out + 1] = tostring(attack.cloak) end
local _, gear = ACTIVATION.jumping()
if gear and R.jumpHit(attack.stats, w) ~= 0 then out[#out + 1] = gear.name end
end
local rr = R.REROLL[attack.reroll or ""]
if attack.rerolls and rr then
out[#out + 1] = attack.melee and string.format("%s: %d re-rolled", rr, attack.rerolls)
or string.format("%s: re-rolled %d", rr, attack.rerolled or 1)
end
if attack.cacRerolled and attack.cacophony then
out[#out + 1] = string.format("%s's %s: re-rolled %d", attack.cacophony.name, attack.cacophony.power,
attack.cacRerolled)
end
return out
end
function ACTIVATION.attackDice(attack, verb, aimed, player)
local R, w, p = TRAIT_RULES, weaponAt(attack.weapon), attack.stats
local UP, MOD = COL.valueUp, COL.valueMod
local aims, plans = aimed.aims or {}, aimed.plans or {}
local h = ACTIVATION.hitRead(attack)
local shown, hits = h.shown, h.hits
local template = not attack.melee and R.template(p)
local wild = template and R.wild(p)
local blast = not attack.melee and not template and R.blast(p)
local kinds, rf, ammoNeed = {}, nil, nil
if attack.melee then
for k = 1, clamp(math.floor(tonumber(attack.attacks) or 1), 1, ACTIVATION.MAX_SHOWN) do kinds[k] = "d6" end
else
if not template or wild then kinds[1] = "d6" end
rf = attack.mode == "rapid_fire" and not R.closeTemplate(p) and R.rapidFire(p) or nil
for _ = 1, rf or 0 do kinds[#kinds + 1] = "firepower" end
ammoNeed = R.ammoNeed(p)
if ammoNeed then kinds[#kinds + 1] = "d6" end
end
local shownKinds = kinds
if wild then
shownKinds = {}
for i, k in ipairs(kinds) do shownKinds[i] = k end
shownKinds[1] = "unstable"
end
local fp0 = (template and not wild) and 0 or 1
local name = R.name(w)
local head, mod, modInk = ACTIVATION.hitHead(attack, h, template)
local single = not attack.melee and R.lightFight(p)
local count = attack.melee and " x" .. #kinds or rf and " RF" .. rf or single and " x1" or ""
local title = name .. count .. " (" .. head .. ")" .. (template and " - Template" or "")
.. (wild and " - Unstable" or "")
local tags = {}
if attack.melee then tags[#tags + 1] = "x" .. #kinds elseif single then tags[#tags + 1] = "x1" end
if rf then tags[#tags + 1] = "RF" .. rf end
if template then tags[#tags + 1] = "Template" end
local what = name .. (#tags > 0 and " (" .. table.concat(tags, ", ") .. ")" or "")
local lead = head .. (mod and " w. " .. mod or "") .. ": "
local VERB = "HIT ROLLS"
local color = colorOf(player)
attack.bus = { kinds = kinds, ammo = ammoNeed and #kinds or nil, ammoNeed = ammoNeed, weapon = name,
need = h and h.need or nil }
local function landed(faces, digital)
local hls, fx = {}, {}
local kb = false
local why = template and {} or ACTIVATION.hitWhy(attack, h)
if wild and attack.rerolls and R.REROLL[attack.reroll or ""] then
why[1] = string.format("%s: re-rolled %d", R.REROLL[attack.reroll], attack.rerolled or 1)
end
local function kbWhy()
if kb then why[#why + 1] = "Knockback" end
end
local roll = { title = title, mod = mod, modInk = modInk, kinds = shownKinds, faces = faces, hls = hls }
local res = { attack = attack, faces = faces, need = shown, digital = digital }
local dice, struck = {}, {}
local function turned()
local me = ACTIVATION.me()
local plan = me and not R.noWound(p) and ACTIVATION.woundPlan(w, p, me) or nil
if plan then plan.cover, plan.fight, plan.area = nil, nil, nil end
aims, plans = { me }, { plan }
end
local melee1 = false
for _, f in ipairs(attack.melee and faces or {}) do melee1 = melee1 or f == 1 end
if melee1 and TRAIT_RULES.unstable(p) then
turned()
local read = {}
for i, f in ipairs(faces) do hls[i], read[i] = f == 1 and COL.diceOut or MOD, tostring(f) end
dice[1], struck[1] = { plan = 1 }, aims[1]
res.hits, res.unstable, roll.sum, roll.sumInk = 1, 1, "∑1", COL.diceOut
if R.noWoundWhy(p) then why[#why + 1] = R.noWoundWhy(p) end
ACTIVATION.sayAttack(VERB, what, string.format("%s%s = Unstable: ∑1 Hit on %s", lead, table.concat(read, ", "),
fighter.name), COL.diceOut, digital, why)
elseif attack.melee then
local n, read, sh = 0, {}, 0
for i, f in ipairs(faces) do
local ok, s, k = hits(f), h.shocked(f), h.knocked(f)
hls[i], read[i], n = ok and UP or MOD, tostring(f), n + (ok and 1 or 0)
fx[i] = ACTIVATION.effects({ shock = s, knock = k })
if s then sh = sh + 1 end
kb = kb or k
if ok then dice[#dice + 1] = { plan = 1, auto = s or nil } end
end
res.hits, roll.sum, roll.sumInk = n, "∑" .. n, n > 0 and UP or MOD
res.shock = sh > 0 and sh or nil
if n > 0 and aims[1] then struck[1] = aims[1] end
if sh > 0 then why[#why + 1] = "Shock: " .. sh end
local bomb = n > 0 and R.lanceBomb(p) and attack.profile
if bomb then why[#why + 1] = "Lance-bomb spent" end
kbWhy()
ACTIVATION.sayAttack(VERB, what, string.format("%s%s = %s", lead, table.concat(read, ", "),
n > 0 and string.format("∑%d Hit%s", n, n == 1 and "" or "s") or "Miss"),
n > 0 and UP or MOD, digital, why)
if bomb then setProfileState({ weapon = attack.weapon, profile = bomb, ammo = "spent" }) end
else
local parts, hit, sh, precise = {}, true, false, false
local unstable = (not template or wild) and (faces[1] or 1) == 1 and TRAIT_RULES.unstable(p)
if unstable then turned() end
local checks, fpHits, each = {}, 0, {}
for i = fp0 + 1, fp0 + (rf or 0) do
local fp = ACTIVATION.FIREPOWER[faces[i] or 1] or ACTIVATION.FIREPOWER[1]
fpHits, each[#each + 1] = fpHits + fp.hits, tostring(fp.hits)
if fp.ammo then checks[#checks + 1] = i end
end
local fpText = rf and "FP " .. table.concat(each, " + ") or nil
local function hitsText(k) return string.format("∑%d Hit%s", k, k == 1 and "" or "s") end
local own = unstable and (CFG.unstableAll and rf and math.max(1, fpHits) or 1) or 0
if not template then
local f1 = faces[1] or 1
hit, sh, kb = hits(f1), h.shocked(f1), not blast and h.knocked(f1)
hls[1] = unstable and COL.diceOut or hit and UP or MOD
parts[1] = string.format("%s%d%s = %s", lead, f1, fpText and ", " .. fpText or "",
unstable and string.format("Unstable: %s on %s", hitsText(own), fighter.name)
or not hit and "Miss" or rf and hitsText(fpHits) or "Hit")
if sh then why[#why + 1] = "Shock" end
precise = hit and f1 == 6 and not R.blast(p) and not hasRapidFire(p)
and #SKILL.with("precise") > 0
if precise then why[#why + 1] = "Precision Shot" end
fx[1] = ACTIVATION.effects({ shock = sh, knock = kb, precise = precise })
kbWhy()
elseif rf then
local rest = {}
for k = 2, #aims do rest[#rest + 1] = aims[k] end
parts[1] = fpText .. " = " .. hitsText(fpHits) .. (aims[1] and " on " .. aims[1].name or ", no enemy selected")
.. (#rest > 0 and ", 1 Hit on " .. ACTIVATION.nameList(rest) or "")
else
parts[1] = #aims > 0 and ACTIVATION.nameList(aims) .. " hit" or "no enemy selected"
end
if wild then
local f1 = faces[1] or 1
hls[1] = unstable and COL.diceOut or nil
parts[1] = unstable and string.format("Unstable %d%s = Unstable: %s on %s", f1,
fpText and ", " .. fpText or "", hitsText(own), fighter.name)
or string.format("Unstable %d, %s", f1, parts[1])
end
if rf then
if #checks > 0 then parts[#parts + 1] = #checks .. "x AM" end
local all = hit and fpHits + (template and math.max(0, #aims - 1) or 0) or 0
roll.sum, roll.sumInk = "∑" .. all, hit and UP or MOD
elseif template then
if #aims > 0 then roll.sum, roll.sumInk = "∑" .. #aims, UP end
else
roll.sum, roll.sumInk = hit and "∑1" or "∑0", hit and UP or MOD
end
if unstable then roll.sum, roll.sumInk = "∑" .. own, COL.diceOut end
if ammoNeed then
local ai = #kinds
roll.ammoDie, roll.ammoGoal = ai, ammoNeed .. "+"
local f = faces[ai] or 1
hls[ai] = f >= ammoNeed and UP or MOD
parts[#parts + 1] = string.format("Ammo (%d+): %d", ammoNeed, f)
if f < ammoNeed then checks[#checks + 1] = ai end
end
local spare = nil
if #checks > 0 and R.reliableReady(p) then
spare, p.reliableUsed = table.remove(checks, 1), true
if kinds[spare] == "firepower" then roll.spare = spare else hls[spare] = COL.ammoSpared end
why[#why + 1] = "Reliable"
end
local state = ACTIVATION.ammoState(#checks, R.limited(p))
if state then parts[#parts + 1] = state:upper() end
roll.ammoState = state
if unstable then
for _ = 1, own do dice[#dice + 1] = { plan = 1 } end
if aims[1] then struck[1] = aims[1] end
hit = false
elseif template then
if rf then
for _ = 1, aims[1] and fpHits or 0 do dice[#dice + 1] = { plan = 1 } end
for k = 2, #aims do dice[#dice + 1] = { plan = k } end
else
for k = 1, #aims do dice[#dice + 1] = { plan = k } end
end
for k, a in ipairs(aims) do struck[k] = a end
hit = #aims > 0
elseif hit then
for k = 1, rf and fpHits or 1 do
local auto = sh and (k == 1 or not CFG.rapidOneHit)
dice[#dice + 1] = { plan = 1, auto = auto or nil, precise = precise or nil }
end
if aims[1] then struck[1] = aims[1] end
end
if (hit or unstable) and R.noWoundWhy(p) then why[#why + 1] = R.noWoundWhy(p) end
res.hit, res.hits = hit, #dice
res.shock, res.precise = sh or nil, precise or nil
res.ammo, res.spared, res.state = #checks, spare ~= nil, state
res.unstable = unstable and own or nil
ACTIVATION.sayAttack(VERB, what, table.concat(parts, ", "), unstable and COL.diceOut or hit and UP or MOD,
digital, why)
if state then setProfileState({ weapon = attack.weapon, profile = attack.profile, ammo = state })
elseif spare then ui.drawProfile(attack.weapon, attack.profile) end
end
roll.tags = next(fx) and fx or nil
if #faces > 0 then ACTIVATION.showDice(roll) else roll = nil end
res.target, res.targets = attack.target, attack.targets
if res.unstable then res.target, res.targets = fighter.name, nil end
res.knockback = kb or nil
local blasted = blast and not res.unstable
if blasted then
res.blast, res.targets = true, nil
struck, dice = {}, {}
end
local spread = nil
if template and not res.unstable then
local per = {}
for _, d in ipairs(dice) do per[d.plan] = (per[d.plan] or 0) + 1 end
spread = {}
for k, a in ipairs(aims) do spread[k] = { aim = a, hits = per[k] or 0 } end
struck, dice = {}, {}
end
onAttackRolled(player, res)
__nqs_mundane_bus.try(function()
local crit = false
for i, f in ipairs(faces) do
if f == 6 and kinds[i] == "d6" and i ~= (ammoNeed and #kinds) then crit = true end
end
if template then crit = false end
__nqs_mundane_bus.hitRoll(attack, faces, {
passed = (res.hit or (res.hits or 0) > 0) and true or false, hits = res.hits or 0,
shock = res.shock, knockback = kb and (tonumber(CFG.knockback) or 1) or nil, crit = crit or nil,
unstable = res.unstable and true or nil, precision = res.precise,
ammo = res.ammo, spared = res.spared or nil, state = res.state,
}, res.target, res.targets, player)
end)
if not attack.melee and not hasTrait(p, TRAIT.smoke) then
for _, a in ipairs(struck) do ACTIVATION.hitTarget(a, attack) end
end
local self1 = not res.unstable and not template and R.cursed(p)
and (attack.melee and melee1 or not attack.melee and (faces[1] or 0) == 1)
ACTIVATION.traitHits(struck, attack, player, self1)
local wound = {}
for _, d in ipairs(dice) do
local plan = plans[d.plan]
if plan then
wound[#wound + 1] = d
plan.hits = (plan.hits or 0) + 1
end
end
if R.drag(p) and struck[1] and not res.unstable and not blasted and not spread then
local aim1 = struck[1]
ACTIVATION.onClose(attack.seq, function() ACTIVATION.drag(attack, aim1, player) end)
end
local knock = kb and not R.blast(p) and struck[1] and ACTIVATION.knockFrom(attack) or nil
if knock and #wound > 0 and plans[1] then plans[1].knock = knock end
local seq = #wound > 0 and { plans = plans, dice = wound, blaze = R.blaze(p, w), weapon = name,
attackSeq = attack.seq } or nil
if res.unstable then
ACTIVATION.unstable(roll, seq and function() ACTIVATION.woundRoll(seq, player) end)
elseif seq then
ACTIVATION.woundAfter(roll, seq, player)
end
if knock and not (plans[1] and plans[1].knock) then
ACTIVATION.seqWait(attack.seq, struck[1].obj)
ACTIVATION.knockAfter(struck[1].obj, knock, roll)
end
if blasted then
return ACTIVATION.blast(attack, { roll = roll, hit = res.hit, face = faces[1] or 1,
shock = res.shock, rf = rf, color = color, what = what }, player)
end
if spread and #spread > 0 then
return ACTIVATION.later(roll, function() ACTIVATION.eachHit(attack, spread, { label = "Template" }, player) end)
end
if #wound == 0 then ACTIVATION.seqDone(attack.seq) end
end
if #kinds == 0 then return landed({}, false) end
ACTIVATION.rolling(title, mod, modInk)
local function twin(faces, digital)
local f1 = faces[1] or 1
if not (rf and R.twin(p)) or (not template or wild) and not hits(f1)
or (wild or not template) and f1 == 1 and TRAIT_RULES.unstable(p) then
return landed(faces, digital)
end
local held = { title = title, mod = mod, modInk = modInk, kinds = shownKinds, faces = faces, hls = {} }
ACTIVATION.showDice(held)
ACTIVATION.later(held, function()
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", title = CFG.twinAsk, keep = true, yes = true,
done = function(yes, _, who)
if not yes then return landed(faces, digital) end
__nqs_mundane_bus.hitRoll(attack, faces, nil, attack.target, attack.targets, who or player,
"Twin-Linked")
ACTIVATION.rolling(title, mod, modInk)
local fk = {}
for k = 1, rf do fk[k] = "firepower" end
throwDice(rf, colorOf(who or player), function(again, digital2)
local all = {}
for i, f in ipairs(faces) do all[i] = f end
for k = 1, rf do all[fp0 + k] = again[k] or 1 end
ACTIVATION.sayAttack(VERB, what, "Firepower re-rolled", COL.value, digital2, { "Twin-Linked" })
landed(all, digital or digital2)
end, fk, title)
end })
end)
end
local function thrown(faces, digital)
local cac = attack.cacophony
if not (cac and not attack.melee and not template and hits(faces[1] or 1)) then return twin(faces, digital) end
local first = faces[1]
ACTIVATION.purple(string.format("%s - %s - %s: %s%d = Hit -- re-rolled || (%s's %s)", fighter.name, VERB, what,
lead, first, cac.name, cac.power))
local held = { title = title, mod = mod, modInk = modInk, kinds = kinds, faces = faces, hls = { COL.wyrdInk } }
ACTIVATION.showDice(held)
__nqs_mundane_bus.hitRoll(attack, faces, nil, attack.target, attack.targets, player, cac.power)
ACTIVATION.later(held, function()
ACTIVATION.rolling(title, mod, modInk)
throwDice(1, color, function(again, digital2)
local all = {}
for i, f in ipairs(faces) do all[i] = f end
all[1] = again[1] or 1
attack.cacRerolled = first
twin(all, digital or digital2)
end, "d6", title)
end)
end
throwDice(#kinds, color, function(faces, digital)
ACTIVATION.rerollHits(attack, { title = title, mod = mod, modInk = modInk, kinds = shownKinds, what = what,
lead = wild and "Unstable " or lead, hits = wild and function(f) return f ~= 1 end or hits,
color = color, template = template and not wild }, faces, digital, thrown)
end, kinds, title)
end
function ACTIVATION.unstable(roll, go)
ACTIVATION.later(roll, function()
local banner = { title = roll and roll.title, mod = roll and roll.mod, modInk = roll and roll.modInk,
faces = {}, lines = { "Unstable!" }, linesInk = COL.diceOut }
ACTIVATION.showDice(banner)
ACTIVATION.later(banner, function()
if go then return go() end
if ACTIVATION.roll == banner and not next(ACTIVATION.rollHover) then ACTIVATION.hideDice() end
end, CFG.unstableShow or 1.5)
end)
end
function ACTIVATION.blast(attack, shot, player)
local smoke = TRAIT_RULES.smoke(attack.stats)
local function ask(title, ink)
if smoke then return ACTIVATION.smokeShow(attack, title, ink) end
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", title = title, titleInk = ink, keep = true, yes = true,
blast = { attack = attack, shot = shot },
done = function(yes, _, who)
ACTIVATION.drawTarget()
local by = __nqs_mundane_bus.selection(player) and player or who or player
if yes then return ACTIVATION.blastGo(attack, shot, by) end
ACTIVATION.sayAttack("BLAST", shot.what, "called off -- nobody hit", COL.valueMod)
ACTIVATION.seqDone(attack.seq)
end })
ACTIVATION.drawTarget()
end
if shot.hit and smoke then return ACTIVATION.seqDone(attack.seq) end
if shot.hit then return ACTIVATION.later(shot.roll, function() ask(CFG.blastHit) end) end
ACTIVATION.later(shot.roll, function()
local title = "Scatter Distance"
ACTIVATION.rolling(title)
throwDice(1, shot.color, function(faces, digital)
local f = faces[1] or 1
local misfire = shot.face == 1 and f == 1
local ink = misfire and COL.valueMod or COL.value
shot.scatter = { f = f, misfire = misfire or nil }
local roll = { title = title, kind = "d6", faces = { f }, sum = f .. '"', sumInk = ink }
ACTIVATION.showDice(roll)
ACTIVATION.sayAttack("SCATTER", shot.what, string.format('%d"%s', f,
misfire and " -- " .. tostring(CFG.blastMisfire) or ""), ink, digital)
ACTIVATION.later(roll, function()
if misfire then return ask(CFG.blastMisfire, COL.valueMod) end
ask(string.format(CFG.blastScatter, f))
end)
end, "d6", title)
end)
end
function ACTIVATION.smokeShow(attack, title, ink)
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
local panel = { title = "Smoke", faces = {}, lead = title, leadInk = ink or COL.value }
ACTIVATION.showDice(panel)
Wait.time(function()
if ACTIVATION.roll == panel and not next(ACTIVATION.rollHover) then ACTIVATION.hideDice() end
end, tonumber(CFG.smokeShow) or 4.5)
ACTIVATION.seqDone(attack.seq)
end
function ACTIVATION.blastKnock(attack, list, player)
local n = TRAIT_RULES.knockback(attack.stats, weaponAt(attack.weapon)) or 6
local title = string.format("Knockback (%d+)", n)
local UP, MOD = COL.valueUp, COL.valueMod
ACTIVATION.rolling(title)
throwDice(#list, colorOf(player), function(faces, digital)
local hls, read, knocked, kinds = {}, {}, {}, {}
for i, f in ipairs(faces) do
local a = list[i].aim
local ok = f >= n
hls[i], read[i], kinds[i] = ok and UP or MOD, string.format("%s %d", a.name, f), "d6"
if ok then knocked[#knocked + 1] = a end
__nqs_mundane_bus.try(function()
local id = __nqs_mundane_bus.attackId(attack.seq)
__nqs_mundane_bus.test("Knockback", { f }, "D6", { direction = "gte", target = n,
weapon = attack.name and tostring(attack.name) or nil, target_fighter = a.name,
outcome = { passed = ok, knockback = ok and (tonumber(CFG.knockback) or 1) or nil },
attack_id = id, group = id, by = player })
end)
end
ACTIVATION.sayAttack("KNOCKBACK ROLLS", attack.name, table.concat(read, ", ") .. " = "
.. (#knocked > 0 and ACTIVATION.nameList(knocked) .. " knocked back" or "nobody knocked back"),
#knocked > 0 and UP or MOD, digital)
local roll = { title = title, kinds = kinds, faces = faces, hls = hls, sum = "∑" .. #knocked,
sumInk = #knocked > 0 and UP or MOD }
ACTIVATION.showDice(roll)
local knock = ACTIVATION.knockFrom(attack)
for _, a in ipairs(knocked) do
if ACTIVATION.seqWait(attack.seq, a.obj) then ACTIVATION.knockAfter(a.obj, knock, roll) end
end
ACTIVATION.seqDone(attack.seq)
end, "d6", title)
end
function ACTIVATION.drag(attack, aim, player)
local okO, gone = ACTIVATION.ask(aim.obj, "isOutOfAction")
local s = tonumber(aim.s)
if (okO and gone == true) or not s then return ACTIVATION.seqDone(attack.seq) end
local title = string.format("Drag (S%d)", s)
local UP, MOD = COL.valueUp, COL.valueMod
ACTIVATION.rolling(title)
throwDice(2, colorOf(player), function(faces, digital)
local f, fp = faces[1] or 1, faces[2] or 1
local ok = f >= s
local inches = (ACTIVATION.FIREPOWER[fp] or ACTIVATION.FIREPOWER[1]).hits
ACTIVATION.sayAttack("DRAG", attack.name, ok and string.format('%d vs S%d, %d" = %s dragged %d"', f, s, inches, aim.name, inches)
or string.format("%d vs S%d = not dragged", f, s), ok and UP or MOD, digital)
local roll = { title = title, kinds = { "d6", "firepower" }, faces = { f, fp }, hls = { ok and UP or MOD },
sum = ok and inches .. '"' or "-", sumInk = ok and UP or MOD }
if not ok then roll.kinds, roll.faces = { "d6" }, { f } end
ACTIVATION.showDice(roll)
__nqs_mundane_bus.try(function()
local id = __nqs_mundane_bus.attackId(attack.seq)
local dice = { { type = "D6", value = f, face = tostring(f), as = "drag" },
{ type = "FIREPOWER", value = fp, face = __nqs_mundane_bus.faceOf("FIREPOWER", fp), as = "inches" } }
__nqs_mundane_bus.test("Drag", nil, nil, { dice = dice, direction = "gte", target = s,
weapon = attack.name and tostring(attack.name) or nil, target_fighter = aim.name,
outcome = { passed = ok, inches = ok and inches or nil }, attack_id = id, group = id, by = player })
end)
if ok then
local t = ACTIVATION.knockFrom(attack)
t.inches = inches
if ACTIVATION.seqWait(attack.seq, aim.obj) then
ACTIVATION.later(roll, function() ACTIVATION.ask(aim.obj, "dragged", t) end)
end
end
ACTIVATION.seqDone(attack.seq)
end, { "d6", "firepower" }, title)
end
function ACTIVATION.blastCount(n) return n == 1 and CFG.blastOne or string.format(CFG.blastCount, n) end
function ACTIVATION.blastGo(attack, shot, player)
local list = {}
for k, a in ipairs(ACTIVATION.blastTargets(player)) do list[k] = { aim = a, hits = 1 } end
if shot.scatter then __nqs_mundane_bus.try(function()
local id, hit = __nqs_mundane_bus.attackId(attack.seq), {}
for k, x in ipairs(list) do hit[k] = tostring(x.aim.name) end
__nqs_mundane_bus.send({ kind = "scatter", weapon = attack.name and tostring(attack.name) or nil,
dice = { { type = "D6", value = shot.scatter.f, face = tostring(shot.scatter.f), as = "distance" } },
distance = shot.scatter.f, misfire = shot.scatter.misfire, hit = #hit > 0 and hit or nil,
attack_id = id, group = id, by = player })
end) end
if #list == 0 then ACTIVATION.sayAttack("BLAST", shot.what, "nobody selected -- nobody hit", COL.valueMod) end
ACTIVATION.eachHit(attack, list, { label = "Blast", auto = shot.shock, rf = shot.rf }, player)
end
function ACTIVATION.burstHits(name, profile, list, player)
local p = { SR = "E", LR = "-", S = "-", AP = "-", L = "1", traits = "" }
for k, v in pairs(type(profile) == "table" and profile or {}) do p[k] = tostring(v) end
local aims = {}
for k, x in ipairs(list) do aims[k] = x.aim end
local attack = { w = { name = name, profiles = { p } }, stats = p, name = name }
attack.seq = ACTIVATION.attackHeader(tostring(name):upper(), aims, player)
ACTIVATION.eachHit(attack, list, { label = name, plain = true }, player)
return attack.seq
end
function ACTIVATION.burst(a, player)
local b = type(a.burst) == "table" and a.burst or {}
local range = tonumber(b.range) or 3
local list = {}
for _, o in ipairs(ACTIVATION.allWithin(range)) do list[#list + 1] = { aim = o, hits = 1 } end
if #list == 0 then
chat(string.format('%s: %s -- nobody within %s"', fighter.name, a.label, string.format("%g", range)),
rgbOf(COL.valueMod))
return 0
end
ACTIVATION.burstHits(a.label, b.profile, list, player)
return #list
end
function ACTIVATION.toxicBlood(n, player)
local it = SKILL.with("toxicBlood")[1]
n = math.floor(tonumber(n) or 0)
if not it or n < 1 then return 0 end
local tb = type(it.toxicBlood) == "table" and it.toxicBlood or {}
local range = tonumber(tb.range) or 1
local around = ACTIVATION.nearestFirst(ACTIVATION.allWithin(range))
local tests = n == 1 and "an Agility test" or string.format("%d Agility tests", n)
if #around == 0 then
chat(string.format('%s\'s %s -- nobody within %s"', fighter.name, it.name, string.format("%g", range)),
rgbOf(COL.valueMod))
return 0
end
chat(string.format('%s\'s %s -- %s within %s" make%s %s', fighter.name, it.name, ACTIVATION.nameList(around),
string.format("%g", range), #around == 1 and "s" or "", tests), rgbOf(COL.valueMod))
local list, k = {}, 0
local function step()
k = k + 1
local o = around[k]
if not o then
if #list == 0 then
chat(string.format("%s's %s -- every test passed, nobody hit", fighter.name, it.name), rgbOf(COL.valueUp))
return
end
return ACTIVATION.later(ACTIVATION.roll, function() ACTIVATION.burstHits(it.name, tb.profile, list, player) end)
end
ACTIVATION.agilityFor(o, n, it.name, player, function(fails, roll)
if fails > 0 then list[#list + 1] = { aim = o, hits = fails } end
ACTIVATION.later(roll, step)
end)
end
step()
return #around
end
function ACTIVATION.agilityFor(o, n, why, player, done)
local need = clamp(math.floor(tonumber(CFG.agility) or 4), 2, 6)
local mod, how = math.floor(tonumber(o.agilityMod) or 0), o.agilityReroll
n = clamp(math.floor(tonumber(n) or 1), 1, ACTIVATION.MAX_SHOWN)
local title = string.format("%s: Agility Test (%d+)", tostring(o.name), math.max(1, need - mod))
local color = colorOf(player)
local kinds = {}
for i = 1, n do kinds[i] = "d6" end
local function read(faces, digital, rerolled)
local fails, hls, each = 0, {}, {}
for i, f in ipairs(faces) do
local ok = f + mod >= need
if not ok then fails = fails + 1 end
hls[i], each[i] = ok and COL.valueUp or COL.valueMod, tostring(f)
end
chat(string.format("%s - %s: %s - Agility Test (%d+%s%s): %s = %s%s", fighter.name, tostring(why), tostring(o.name),
need, mod ~= 0 and string.format(", %+d", mod) or "", rerolled and ", re-rolled " .. rerolled or "",
table.concat(each, ", "), fails == 0 and "passed" or string.format("%d failed", fails),
digital and " (rolled digitally)" or ""), rgbOf(fails == 0 and COL.valueUp or COL.valueMod))
ACTIVATION.showDice{ title = title, kinds = kinds, faces = faces, hls = hls,
sum = fails == 0 and "Passed" or "∑" .. fails, sumInk = fails == 0 and COL.valueUp or COL.valueMod }
__nqs_mundane_bus.try(function()
local okG, guid = pcall(function() return o.obj.getGUID() end)
__nqs_mundane_bus.test("Agility", faces, "D6", {
fighter = tostring(o.name), guid = okG and guid or nil, rolled_by = fighter.name,
direction = "gte", target = need, modifier = mod ~= 0 and mod or nil, why = tostring(why),
outcome = { passed = fails == 0, fails = fails }, reroll = rerolled and true or nil,
rerolled = rerolled, by = player,
})
end)
done(fails, ACTIVATION.roll)
end
ACTIVATION.rolling(title)
throwDice(n, color, function(faces, digital)
local idx = {}
for i, f in ipairs(faces) do
if (how == "ones" and f == 1) or (how == "all" and f + mod < need) then idx[#idx + 1] = i end
end
if #idx == 0 then return read(faces, digital) end
local hls = {}
for _, i in ipairs(idx) do hls[i] = COL.valueMod end
local held = { title = title, kinds = kinds, faces = faces, hls = hls }
ACTIVATION.showDice(held)
ACTIVATION.later(held, function()
ACTIVATION.rolling(title)
throwDice(#idx, color, function(again, digital2)
local all, was = {}, {}
for i, f in ipairs(faces) do all[i] = f end
for j, i in ipairs(idx) do was[j], all[i] = tostring(faces[i]), again[j] or 1 end
read(all, digital or digital2, table.concat(was, ", "))
end, "d6", title)
end)
end, "d6", title)
end
function ACTIVATION.eachHit(attack, list, o, player)
local R, w, p = TRAIT_RULES, attack.w or weaponAt(attack.weapon), attack.stats
list = ACTIVATION.nearestFirst(list, function(x) return x.aim end)
local k = 0
local step = nil
local function after(go)
local s = ACTIVATION.seqs[attack.seq]
local function onward() Wait.time(step, CFG.dicePause or CFG.diceShow) end
if not (go and s) then return onward() end
s.next = onward
if go(s) == false then s.next = nil; onward() end
end
function step()
k = k + 1
local a, hits = list[k] and list[k].aim, list[k] and math.floor(tonumber(list[k].hits) or 0)
if not a then
if o.rf then chat("Rapid Fire Blast Markers not included!", rgbOf(COL.valueMod)) end
if o.label == "Blast" and R.knockback(p, w) and #list > 0 then
return ACTIVATION.blastKnock(attack, list, player)
end
return ACTIVATION.seqDone(attack.seq)
end
ACTIVATION.line(string.format("%s %s vs %s %s", CFG.seqRule, o.label, a.name, CFG.seqRule), ACTIVATION.SEQ_INK)
if not (hasTrait(p, TRAIT.smoke) or o.plain) then ACTIVATION.hitTarget(a, attack) end
ACTIVATION.traitHits({ a }, attack, player)
local plan = hits > 0 and w and not R.noWound(p) and ACTIVATION.woundPlan(w, p, a) or nil
if not plan then return after(nil) end
plan.fight, plan.blaze, plan.hits, plan.auto = nil, R.blaze(p, w), hits, o.auto and hits or nil
if a.self or o.plain then plan.cover, plan.coverBy = nil, nil end
plan.seq, plan.color = attack.seq, colorOf(player)
if a.self or ACTIVATION.has(a.obj, "blastWound") then
after(function()
if not ACTIVATION.seqWait(attack.seq, a.obj) then return false end
ACTIVATION.ask(a.obj, "blastWound", plan)
end)
else
after(function(s)
s.pending = s.pending + 1
local dice = {}
for j = 1, math.min(hits, ACTIVATION.MAX_SHOWN) do dice[j] = { plan = 1, auto = o.auto or nil } end
ACTIVATION.woundRoll({ plans = { plan }, dice = dice, blaze = plan.blaze,
weapon = plan.weapon, attackSeq = attack.seq }, player)
end)
end
end
step()
end
function ACTIVATION.rerollHits(attack, o, faces, digital, go)
local how, idx = attack.reroll, {}
if how and not o.template then
for i = 1, attack.melee and #faces or math.min(1, #faces) do
local f = faces[i]
if (how == "ones" and f == 1) or (how == "all" and not o.hits(f)) then idx[#idx + 1] = i end
end
end
if #idx == 0 then return go(faces, digital) end
local read, hls = {}, {}
for _, i in ipairs(idx) do read[#read + 1], hls[i] = tostring(faces[i]), COL.valueMod end
ACTIVATION.sayAttack("HIT ROLLS", o.what, string.format("%s%s -- %s", o.lead, table.concat(read, ", "),
#idx == 1 and "re-rolled" or #idx .. " re-rolled"), COL.valueMod, digital, { TRAIT_RULES.REROLL[how] })
local held = { title = o.title, mod = o.mod, modInk = o.modInk, kinds = o.kinds, faces = faces, hls = hls }
ACTIVATION.showDice(held)
__nqs_mundane_bus.hitRoll(attack, faces, nil, attack.target, attack.targets, o.color,
TRAIT_RULES.REROLL[how] or tostring(how))
ACTIVATION.later(held, function()
ACTIVATION.rolling(o.title, o.mod, o.modInk)
throwDice(#idx, o.color, function(again, digital2)
local all = {}
for i, f in ipairs(faces) do all[i] = f end
for k, i in ipairs(idx) do
if k == 1 and not attack.melee then attack.rerolled = all[i] end
all[i] = again[k] or 1
end
attack.rerolls = #idx
go(all, digital or digital2)
end, "d6", o.title)
end)
end
function ACTIVATION.traitHits(struck, attack, player, self1)
local p = attack.stats
local cursed, flashed = TRAIT_RULES.cursed(p), TRAIT_RULES.flash(p)
if cursed and self1 then
local okG, me = pcall(function() return self.getGUID() end)
traitHit({ by = fighter.name, weapon = attack.name, color = colorOf(player), cursed = true, own = true,
seq = attack.seq, from = okG and me or nil })
end
if not (cursed or flashed) then return end
for _, a in ipairs(struck) do
ACTIVATION.seqTell(attack.seq, a.obj)
local okG, me = pcall(function() return self.getGUID() end)
local ok = ACTIVATION.ask(a.obj, "traitHit", { by = fighter.name, weapon = attack.name, color = colorOf(player),
cursed = cursed or nil, flash = flashed or nil, seq = attack.seq, from = okG and me or nil })
if not ok and flashed then ACTIVATION.ask(a.obj, "setCondition", { key = "blind", value = true }) end
end
end
ACTIVATION.fear = {}
function ACTIVATION.isFearsome()
return conditionCount("fearsome") > 0 or #SKILL.with("fearsome") > 0
end
function ACTIVATION.fearFirst(aim, player, go)
if not (aim and aim.fearsome) or fighter.activation ~= "active" or fighter.outOfAction
or ACTIVATION.isFearsome() or conditionCount("feared") > 0 or not statNumber("Wil") then
return go()
end
local ok, id = pcall(function() return aim.obj.getGUID() end)
id = ok and id or aim.name
local st = ACTIVATION.fear[id]
if st then
if st.done then return go() end
st.queue[#st.queue + 1] = go
return
end
local leader, own = ACTIVATION.outcastLeader("fearsome")
if leader then
ACTIVATION.fear[id] = { done = true, queue = {} }
chat(string.format("%s isn't afraid of %s -- %s", fighter.name, aim.name, ACTIVATION.outcastWhy(leader, own)),
rgbOf(COL.valueUp))
return go()
end
st = { queue = { go } }
ACTIVATION.fear[id] = st
local function finish()
st.done = true
local queue = st.queue
st.queue = {}
for _, f in ipairs(queue) do f() end
end
ACTIVATION.rollTest("Wil", player, { why = "Fearsome", done = function(test, roll)
if test.passed then
chat(string.format("%s stands up to %s", fighter.name, aim.name), rgbOf(COL.valueUp))
else
setCondition("feared", true)
chat(string.format("%s is Feared by %s -- WS %d+ until the end of their activation", fighter.name, aim.name,
statNumber("WS") or 6), rgbOf(COL.valueMod))
end
ACTIVATION.later(roll, finish)
end })
end
function ACTIVATION.endFear()
ACTIVATION.fear = {}
if conditionCount("feared") > 0 then setCondition("feared", false) end
end
function ACTIVATION.hitTarget(aim, attack)
if not aim then return end
ACTIVATION.seqTell(attack.seq, aim.obj)
local okG, me = pcall(function() return self.getGUID() end)
local ok = ACTIVATION.ask(aim.obj, "rangedHit", { by = fighter.name, weapon = attack.name,
seq = attack.seq, from = okG and me or nil })
if not ok and aim.status == "active" then
ACTIVATION.ask(aim.obj, "setStatus", "suppressed")
end
end
function ACTIVATION.knockFrom(attack)
local pos = positionOf(self)
local ok, guid = pcall(function() return self.getGUID() end)
return { from = ok and guid or nil, x = pos and pos.x, z = pos and pos.z, by = fighter.name, weapon = attack.name,
seq = attack.seq }
end
function ACTIVATION.knockAfter(obj, knock, roll)
ACTIVATION.later(roll, function() ACTIVATION.ask(obj, "knockback", knock) end)
end
function ACTIVATION.woundPlan(w, p, target)
if not (target and w and p) then return nil end
local plan = { weapon = TRAIT_RULES.name(w), target = target.name, t = target.t,
toxin = TRAIT_RULES.toxin(p) }
local okG, guid = pcall(function() return target.obj.getGUID() end)
local okS, mine = pcall(function() return self.getGUID() end)
plan.guid, plan.from, plan.by = okG and guid or nil, okS and mine or nil, fighter.name
plan.ap = TRAIT_RULES.apOf(w, p)
plan.cover, plan.coverBy = ACTIVATION.coverFor(w, p, target)
for k, v in pairs(TRAIT_RULES.hurts(w, p)) do plan[k] = v end
plan.noBlaze = target.immune and target.immune[TRAIT.blaze] or nil
plan.area = (TRAIT_RULES.blast(p) or TRAIT_RULES.template(p)) or nil
plan.close = TRAIT_RULES.hitStat(p) == "WS"
if TRAIT_RULES.graviton(p) then
plan.graviton = true
return plan
end
if not plan.toxin then
plan.s = TRAIT_RULES.strength(w, p)
if not (plan.s and plan.t) then return nil end
local jaw = tonumber(target.ironJaw) or 0
if jaw > 0 and TRAIT_RULES.noAp(w, p)
and (isMelee(p) or (fighter.status == "engaged" and hasTrait(p, TRAIT.light))) then
plan.t, plan.jaw = plan.t + jaw, jaw
end
plan.why = ACTIVATION.strengthWhy(w, p)
end
return plan
end
function ACTIVATION.strengthWhy(w, p)
local R, out = TRAIT_RULES, {}
if R.stabbing[w] and R.stab(p) > 0 then out[#out + 1] = "Backstab" end
if R.blows(p) > 0 then
for _, it in ipairs(SKILL.with("meleeS")) do
for trait in pairs(it.meleeS) do
if TRAIT[trait] and hasTrait(p, TRAIT[trait]) then out[#out + 1] = it.name break end
end
end
end
if R.lance(p, w) > 0 then out[#out + 1] = "Lance" end
if R.bull(p, w) > 0 then out[#out + 1] = "Bull Charge" end
if R.goliath(p, w) > 0 then out[#out + 1] = tostring(CFG.goliathGang.type) end
local steps = R.adjSteps(p, "S")
if steps ~= 0 then out[#out + 1] = string.format("S %+d set by hand", steps) end
local t = R.parts(p.S or "-")
if t and t.token and t.token:upper() == "S" then STAT.why("S", nil, out) end
return out
end
function ACTIVATION.jaw()
local n = 0
for _, it in ipairs(SKILL.with("ironJaw")) do n = math.max(n, tonumber(it.ironJaw) or 0) end
return n > 0 and n or nil
end
function ACTIVATION.later(roll, go, wait)
if not roll then return go() end
Wait.time(function()
local function free()
local r = ACTIVATION.roll
return r == nil or r == roll or not (r.held or r.rolling)
end
if free() or not Wait.condition then return go() end
Wait.condition(go, free, CFG.diceWait, go)
end, wait or CFG.dicePause or CFG.diceShow)
end
function ACTIVATION.woundAfter(roll, seq, player)
ACTIVATION.later(roll, function() ACTIVATION.woundRoll(seq, player) end)
end
function ACTIVATION.woundNeed(s, t)
if s >= 2 * t then return 2 end
if s > t then return 3 end
if s == t then return 4 end
if 2 * s <= t then return 6 end
return 5
end
function ACTIVATION.planNeed(plan)
local toxin = tonumber(plan.toxin)
return clamp(toxin or ACTIVATION.woundNeed(tonumber(plan.s), tonumber(plan.t)), 2, 6)
end
function ACTIVATION.woundTitle(list, blazed)
local t, tox, seen = {}, nil, {}
for _, plan in ipairs(list) do
tox = tox or tonumber(plan.toxin)
local v = tonumber(plan.t)
if v and not seen[v] then seen[v], t[#t + 1] = true, "T" .. v end
end
local jaw = #list == 1 and not tox and tonumber(list[1].jaw)
local title = tox and string.format("Wound Roll vs Toxin (%d+)", tox)
or "Wound Roll vs " .. table.concat(t, ", ") .. (jaw and " (Iron Jaw)" or "")
return title .. (blazed and " (Blaze)" or "")
end
function ACTIVATION.woundRoll(seq, player)
seq.hurt, seq.conc = seq.hurt or {}, seq.conc or {}
local plans, dice = seq.plans or {}, {}
for i, d in ipairs(seq.dice or {}) do
if i <= ACTIVATION.MAX_SHOWN and plans[d.plan] then dice[#dice + 1] = d end
end
if #dice == 0 then ACTIVATION.partDone(seq) return nil end
local UP, MOD = COL.valueUp, COL.valueMod
local list, seen, aims = {}, {}, {}
for _, d in ipairs(dice) do
if not seen[d.plan] then
seen[d.plan], list[#list + 1] = true, plans[d.plan]
aims[#aims + 1] = { name = tostring(plans[d.plan].target or "?") }
end
end
if list[1].graviton then return ACTIVATION.gravityOut(seq, dice, player) end
local keys = {}
for k in pairs(plans) do keys[#keys + 1] = k end
table.sort(keys)
local title = ACTIVATION.woundTitle(list, seq.blazed)
local kinds, thrown = {}, 0
for i, d in ipairs(dice) do
kinds[i] = "d6"
if not d.auto then thrown = thrown + 1 end
end
local function landed(got, digital)
local faces, hls, fx, half, n, gen, per, j, sh = {}, {}, {}, {}, 0, {}, {}, 0, 0
local stopped = nil
local trig = {}
local rd, sd, cc, bd = 0, 0, 0, 0
for k, v in pairs(seq.per or {}) do per[k] = v end
for i, d in ipairs(dice) do
local f = nil
if d.auto then f = 6 else j = j + 1; f = got[j] or 1 end
local ok = d.auto or (f ~= 1 and (f == 6 or f >= ACTIVATION.planNeed(plans[d.plan])))
local q = plans[d.plan]
local did = {}
if q.conc and f >= q.conc then
seq.conc[d.plan], cc = (seq.conc[d.plan] or 0) + 1, cc + 1
did.conc = true
end
if ok then
local h = { rend = q.rend ~= nil and f >= q.rend or nil,
shred = q.shred ~= nil and f >= q.shred or nil, precise = d.precise,
breach = q.breach ~= nil and f >= q.breach or nil }
seq.hurt[d.plan] = seq.hurt[d.plan] or {}
table.insert(seq.hurt[d.plan], h)
if h.rend then rd = rd + 1 end
if h.shred then sd = sd + 1 end
if h.breach then bd = bd + 1 end
did.rend, did.shred, did.breach = h.rend, h.shred, h.breach
end
local more = seq.blaze and not seq.blazed and f >= seq.blaze
if more and plans[d.plan].noBlaze then more, stopped = false, plans[d.plan] end
faces[i], hls[i] = f, ok and UP or MOD
if ok then n, per[d.plan] = n + 1, (per[d.plan] or 0) + 1 end
if d.auto then sh = sh + 1 end
if more then gen[#gen + 1] = d.plan end
did.blaze = more or nil
if next(did) or (ok and d.precise) then
trig[#trig + 1] = { die = i, rending = did.rend, breaching = did.breach, shred = did.shred,
concussive = did.conc, blaze = did.blaze, precision = ok and d.precise or nil }
end
fx[i] = ACTIVATION.effects(did)
half[i] = d.auto and "shock" or d.precise and "precise" or d.blazed and "blaze" or nil
end
local total = (seq.total or 0) + n
local plan = list[1]
local function weaponOf(q)
local wn = tostring(q.weapon or seq.weapon or "Weapon")
return seq.remote and q.by and tostring(q.by) .. "'s " .. wn or wn
end
local jaw = #list == 1 and not tonumber(plan.toxin) and tonumber(plan.jaw) or nil
local function wounds(k) return string.format("∑%d Wound%s", k, k == 1 and "" or "s") end
local function sText(q)
local tx = tonumber(q.toxin)
return tx and string.format("Toxin (%d+)", tx) or "S" .. tostring(tonumber(q.s) or "-")
end
local function tText(q)
local tq, jq = tonumber(q.t), not tonumber(q.toxin) and tonumber(q.jaw) or nil
if not tq then return nil end
return jq and string.format("T%d+%d", tq - jq, jq) or "T" .. tq
end
local what, body = nil, nil
if #list == 1 then
local sorted = {}
for i, f in ipairs(faces) do sorted[i] = f end
table.sort(sorted)
local read = {}
for i, f in ipairs(sorted) do read[i] = tostring(f) end
local tt = tText(plan)
what = string.format("%s %s%s = %d+", weaponOf(plan), sText(plan),
tt and " vs " .. tt or "", ACTIVATION.planNeed(plan))
body = table.concat(read, ", ")
else
local vs, read = {}, {}
for _, q in ipairs(list) do
local tt = tText(q)
vs[#vs + 1] = string.format("%s%s = %d+", tostring(q.target or "?"), tt and " " .. tt or "",
ACTIVATION.planNeed(q))
end
for i, f in ipairs(faces) do read[i] = string.format("%s %d", tostring(plans[dice[i].plan].target or "?"), f) end
what = string.format("%s %s vs %s", weaponOf(plan), sText(plan),
table.concat(vs, ", "))
body = table.concat(read, ", ")
end
body = body .. " = " .. (n > 0 and wounds(n) or "Failed to Wound")
if seq.blazed then
body = body .. " -- " .. wounds(total) .. " in all"
if #keys > 1 then
local each = {}
for i, k in ipairs(keys) do each[i] = string.format("%s %d", tostring(plans[k].target or "?"), per[k] or 0) end
body = body .. ": " .. table.concat(each, ", ")
end
end
local why = {}
for _, q in ipairs(list) do
for _, v in ipairs(q.why or {}) do
local has = false
for _, u in ipairs(why) do has = has or u == v end
if not has then why[#why + 1] = v end
end
end
if jaw then why[#why + 1] = "Iron Jaw" end
if sh > 0 then why[#why + 1] = string.format("Shock: %d automatic 6", sh) end
if #gen > 0 then
why[#why + 1] = string.format("Blaze (%d+): %d more Hit%s", seq.blaze, #gen, #gen == 1 and "" or "s")
end
if stopped then
why[#why + 1] = string.format("no Blaze on %s (%s)", tostring(stopped.target or "?"), tostring(stopped.noBlaze))
end
if rd > 0 then why[#why + 1] = "Rending: " .. rd end
if sd > 0 then why[#why + 1] = "Shred: " .. sd end
if bd > 0 then why[#why + 1] = "Breaching: " .. bd end
if cc > 0 then why[#why + 1] = "Concussive: " .. cc end
ACTIVATION.sayAttack(seq.blazed and "WOUND ROLLS (Blaze)" or "WOUND ROLLS", what, body, total > 0 and UP or MOD,
digital, why)
local roll = { title = title, kinds = kinds, faces = faces, hls = hls, tags = next(fx) and fx or nil,
half = next(half) and half or nil, sum = "∑" .. total, sumInk = total > 0 and UP or MOD }
if seq.shown then ACTIVATION.joinRolls(seq.shown, roll) end
seq.shown = roll
ACTIVATION.showDice(roll)
onWoundsRolled(player, { plan = plan, plans = list, faces = faces, need = ACTIVATION.planNeed(plan), wounds = n,
total = total, round = seq.blazed and 2 or 1, blaze = #gen, digital = digital })
__nqs_mundane_bus.try(function()
local targets, prec = nil, 0
if #list > 1 then
targets = {}
for k, q in ipairs(list) do targets[k] = tostring(q.target or "?") end
end
for _, x in ipairs(trig) do if x.precision then prec = prec + 1 end end
local rem = seq.remote
local id = rem and __nqs_mundane_bus.attackId(rem.seq, rem.from) or __nqs_mundane_bus.attackId(seq.attackSeq)
local wn = tostring(plan.weapon or seq.weapon or "Weapon")
__nqs_mundane_bus.send({
kind = "roll", action = "wound roll, " .. wn, label = seq.blazed and "Wound (Blaze)" or "Wound",
fighter = rem and plan.by and tostring(plan.by) or nil, guid = rem and rem.from or nil,
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
direction = "gte", weapon = wn, target = ACTIVATION.planNeed(plan),
outcome = { passed = n > 0, wounds = n, rending = rd > 0 and rd or nil, breaching = bd > 0 and bd or nil,
shred = sd > 0 and sd or nil, concussive = cc > 0 and cc or nil,
blaze = #gen > 0 and #gen or nil, precision = prec > 0 and prec or nil,
shock = sh > 0 and sh or nil, triggers = #trig > 0 and trig or nil },
strength = plan.s, ap = plan.ap, lethality = plan.l,
target_fighter = tostring(plan.target or "?"), targets = targets,
blaze_round = seq.blazed and true or nil,
attack_id = id, group = id, by = player,
})
end)
if #gen > 0 then
ACTIVATION.later(roll, function() ACTIVATION.blazeRound(seq, gen, total, per, player) end)
else
ACTIVATION.toSaves(seq, per, player, roll)
end
end
if thrown == 0 then landed({}, false) return seq end
ACTIVATION.rolling(title)
throwDice(thrown, colorOf(player), function(faces, digital) landed(faces, digital) end, "d6", title)
return seq
end
function ACTIVATION.blazeRound(seq, gen, total, per, player)
local again = { plans = seq.plans, blazed = true, total = total, per = per, weapon = seq.weapon, dice = {},
hurt = seq.hurt, conc = seq.conc, shown = seq.shown, attackSeq = seq.attackSeq,
remote = seq.remote }
for _, k in ipairs(gen) do again.dice[#again.dice + 1] = { plan = k, blazed = true } end
return ACTIVATION.woundRoll(again, player)
end
function ACTIVATION.joinRolls(a, b)
local out = { faces = {}, kinds = {}, hls = {}, tags = {}, half = {} }
local skip = math.max(0, #(a.faces or {}) + #(b.faces or {}) - ACTIVATION.MAX_SHOWN)
for _, r in ipairs({ a, b }) do
for i, f in ipairs(r.faces or {}) do
if r ~= a or i > skip then
local k = #out.faces + 1
out.faces[k] = f
out.kinds[k] = r.kinds and r.kinds[i] or r.kind or "d6"
out.hls[k] = r.hls and r.hls[i] or r.hl
out.tags[k] = r.tags and r.tags[i] or nil
out.half[k] = r.half and r.half[i] or nil
end
end
end
b.faces, b.kinds, b.hls = out.faces, out.kinds, out.hls
b.tags, b.half = next(out.tags) and out.tags or nil, next(out.half) and out.half or nil
return b
end
function rollWounds(plan, player)
if type(plan) ~= "table" then return nil end
local hits = clamp(math.floor(tonumber(plan.hits) or 0), 0, ACTIVATION.MAX_SHOWN)
local s, t, toxin = tonumber(plan.s), tonumber(plan.t), tonumber(plan.toxin)
if hits < 1 or not (toxin or (s and t)) then return nil end
local auto = clamp(math.floor(tonumber(plan.auto) or 0), 0, hits)
local dice = {}
for k = 1, hits do dice[k] = { plan = 1, auto = k <= auto or nil } end
ACTIVATION.woundRoll({ plans = { plan }, dice = dice, blaze = tonumber(plan.blaze), weapon = plan.weapon }, player)
return plan
end
function ACTIVATION.gravityOut(seq, dice, player)
local per = {}
for _, d in ipairs(dice) do per[d.plan] = (per[d.plan] or 0) + 1 end
for k, n in pairs(per) do
local plan = seq.plans[k]
local ok, obj = pcall(function() return plan.guid and getObjectFromGUID(plan.guid) end)
if ok and obj then
local t = {}
for key, v in pairs(plan) do t[key] = v end
t.hits, t.seq, t.color = n, seq.attackSeq, colorOf(player)
if ACTIVATION.seqWait(seq.attackSeq, obj) then ACTIVATION.ask(obj, "blastWound", t) end
end
end
ACTIVATION.partDone(seq)
return true
end
function blastWound(t)
if type(t) ~= "table" then return false end
local remote = { seq = t.seq, from = t.from }
if fighter.outOfAction then ACTIVATION.seqEnd(remote) return false end
ACTIVATION.seqJoin(remote)
if t.graviton then return ACTIVATION.gravityCheck(t, remote) end
local hits = clamp(math.floor(tonumber(t.hits) or 1), 1, ACTIVATION.MAX_SHOWN)
local auto = clamp(math.floor(tonumber(t.auto) or 0), 0, hits)
local dice = {}
for k = 1, hits do dice[k] = { plan = 1, auto = k <= auto or nil } end
return ACTIVATION.woundRoll({ plans = { t }, dice = dice, blaze = tonumber(t.blaze), weapon = t.weapon,
remote = remote }, t.color) ~= nil
end
function ACTIVATION.gravityCheck(t, remote)
local from = ACTIVATION.fromText(t)
local hits = clamp(math.floor(tonumber(t.hits) or 1), 1, ACTIVATION.MAX_SHOWN)
local function wounded(roll)
local list = {}
for i = 1, hits do list[i] = { ap = 0, l = t.l, dmg = t.dmg, graviton = true } end
ACTIVATION.later(roll, function()
takeSaves({ wounds = hits, list = list, ap = 0, l = t.l, dmg = t.dmg, seq = t.seq, from = t.from,
by = t.by, weapon = t.weapon, color = t.color, knockback = t.knock, area = t.area })
end)
end
local test = ACTIVATION.rollTest("S", t.color, { why = "Graviton Pulse", done = function(res, roll)
if res.passed then
chat(string.format("%s withstands %s", fighter.name, from), rgbOf(COL.valueUp))
ACTIVATION.later(roll, function() ACTIVATION.seqEnd(remote) end)
else
chat(string.format("%s is crushed by %s -- no armour save", fighter.name, from), rgbOf(COL.valueMod))
wounded(roll)
end
end })
if not test then wounded(nil) end
return true
end
function ACTIVATION.partDone(seq)
if seq.remote then return ACTIVATION.seqEnd(seq.remote) end
ACTIVATION.seqDone(seq.attackSeq)
end
function ACTIVATION.toSaves(seq, per, player, roll)
local plans, keys = seq.plans or {}, {}
local remote, sent = seq.remote, false
for k in pairs(plans) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
local plan, n = plans[k], math.floor(tonumber((per or {})[k]) or 0)
local conc = (seq.conc or {})[k] or 0
local told = (n > 0 or conc > 0) and plan.guid
if plan.knock and plan.guid and not told then
local okK, aim = pcall(function() return getObjectFromGUID(plan.guid) end)
if okK and aim then
if not remote then ACTIVATION.seqWait(seq.attackSeq, aim) end
ACTIVATION.knockAfter(aim, plan.knock, roll)
end
end
if told then
local list = {}
for i, h in ipairs((seq.hurt or {})[k] or {}) do
list[i] = { ap = (tonumber(plan.ap) or 0) + (h.rend and 1 or 0),
l = (tonumber(plan.l) or 0) + (h.shred and 1 or 0), dmg = plan.dmg,
precise = h.precise, rend = h.rend, shred = h.shred, breach = h.breach }
end
local ok, obj = pcall(function() return getObjectFromGUID(plan.guid) end)
if ok and obj then
if not remote then ACTIVATION.seqWait(seq.attackSeq, obj) end
sent = true
ACTIVATION.ask(obj, "takeSaves", { wounds = n, list = list, ap = plan.ap, l = plan.l,
seq = remote and remote.seq or seq.attackSeq,
dmg = plan.dmg, cover = plan.cover, coverBy = plan.coverBy, gas = plan.gas, web = plan.web,
concussion = conc > 0 and conc or nil, radphage = (plan.rad and n > 0) or nil,
knockback = plan.knock, weapon = plan.weapon, by = plan.by, from = plan.from, area = plan.area,
close = plan.close,
fight = plan.fight, color = colorOf(player) })
end
end
end
if not remote then ACTIVATION.seqDone(seq.attackSeq)
elseif not sent then ACTIVATION.seqEnd(remote) end
end
function attackOver(t)
ACTIVATION.seqDone(tonumber(type(t) == "table" and t.token or t))
end
function seqClosed(t)
if type(t) ~= "table" then return end
ACTIVATION.targeted[tostring(t.from) .. ":" .. tostring(t.seq)] = nil
ACTIVATION.juggEnd(t)
ACTIVATION.toxicEnd(t)
end
ACTIVATION.toxic = {}
function ACTIVATION.toxicNote(t, n)
n = math.floor(tonumber(n) or 0)
if n < 1 or #SKILL.with("toxicBlood") == 0 then return end
local okS, mine = pcall(function() return self.getGUID() end)
local color = t.color
if t.seq and t.from and not (okS and t.from == mine) then
local id = tostring(t.from) .. ":" .. tostring(t.seq)
local x = ACTIVATION.toxic[id] or { n = 0, color = color }
x.n = x.n + n
ACTIVATION.toxic[id] = x
elseif t.seq and ACTIVATION.seqs[t.seq] then
local id = "own:" .. tostring(t.seq)
local x = ACTIVATION.toxic[id]
if not x then
x = { n = 0, color = color }
ACTIVATION.toxic[id] = x
ACTIVATION.onClose(t.seq, function()
ACTIVATION.toxic[id] = nil
ACTIVATION.seqDone(t.seq)
ACTIVATION.later(ACTIVATION.roll, function() ACTIVATION.toxicBlood(x.n, x.color) end)
end)
end
x.n = x.n + n
else
ACTIVATION.later(ACTIVATION.roll, function() ACTIVATION.toxicBlood(n, color) end)
end
end
function ACTIVATION.toxicEnd(t)
local id = tostring(t.from) .. ":" .. tostring(t.seq)
local x = ACTIVATION.toxic[id]
if not x then return end
ACTIVATION.toxic[id] = nil
ACTIVATION.later(ACTIVATION.roll, function() ACTIVATION.toxicBlood(x.n, x.color) end)
end
function takeSaves(t)
if type(t) ~= "table" or fighter.outOfAction then ACTIVATION.seqEnd(t) return false end
ACTIVATION.seqJoin(t)
local shown = ACTIVATION.roll and not ACTIVATION.roll.rolling and ACTIVATION.roll or nil
local from = ACTIVATION.fromText(t)
local function struck()
local conc = math.floor(tonumber(t.concussion) or 0)
if conc > 0 then ACTIVATION.timedCondition("concussion", conc, nil, from) end
if t.radphage then
local before = conditionCount("radphage")
if (setCondition("radphage", true) or 0) > before then
chat(string.format("%s gains Radphage from %s", fighter.name, from), rgbOf(COL.valueMod))
end
end
end
local n = clamp(math.floor(tonumber(t.wounds) or 0), 0, ACTIVATION.MAX_SHOWN)
local sv, none = ACTIVATION.saveOf(t)
local inv = ACTIVATION.invOf(t)
local cover = tonumber(t.cover)
local precise = n >= 1 and ACTIVATION.noArmour(t, 1) or nil
for i = 2, n do precise = precise and ACTIVATION.noArmour(t, i) and precise or nil end
if precise then sv, none, cover = nil, nil, nil end
local by = cover and t.coverBy and tostring(t.coverBy) or nil
if n >= 1 and cover and (cover > 0 or by) and sv then
local ok, obj = pcall(function() return t.from and getObjectFromGUID(t.from) end)
local q = { test = "question", cover = true, keep = true, pair = true, value = 0, coverBy = by,
title = "Save: Cover Bonus", obj = ok and obj or nil, ink = rgbOf(COL.valueMod) }
q.done = function(yes, _, who)
if not yes then
chat(string.format("%s - %s called off: no saves", fighter.name, from))
ACTIVATION.seqEnd(t)
return
end
struck()
ACTIVATION.rollSaves(t, q.value, who or t.color)
end
ACTIVATION.later(shown, function()
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck(q)
end)
return "asked"
end
struck()
if n < 1 then
ACTIVATION.knockSelf(t)
return false
end
if not (sv or inv) or (none and not inv and not (cover and cover > 0)) then
chat(string.format("%s has no save against %s%s -- %d Wound%s go%s through", fighter.name, from,
precise and " (" .. precise .. ")" or "", n, n == 1 and "" or "s", n == 1 and "es" or ""), rgbOf(COL.valueMod))
local all = {}
for i = 1, n do all[i] = ACTIVATION.wound(t, i) end
onSavesRolled(t.color, { wounds = n, saved = 0, through = n, faces = {}, by = t.by, weapon = t.weapon })
ACTIVATION.damage(t, all, shown, t.color)
return 0
end
Wait.time(function() ACTIVATION.rollSaves(t, 0, t.color) end, CFG.dicePause or CFG.diceShow)
return true
end
function ACTIVATION.fromText(t)
return string.format("%s's %s", tostring(t.by or "?"), tostring(t.weapon or "weapon"))
end
function ACTIVATION.knockSelf(t, roll)
local kb = type(t) == "table" and t.knockback
if type(kb) ~= "table" then return ACTIVATION.seqEnd(t) end
local function go() knockback(kb) end
if roll then return ACTIVATION.later(roll, go, CFG.diceShow) end
Wait.time(go, CFG.diceShow)
end
function ACTIVATION.wound(t, i)
return (type(t.list) == "table" and t.list[i]) or { ap = t.ap, l = t.l, dmg = t.dmg }
end
function ACTIVATION.noArmour(t, i)
local w = ACTIVATION.wound(t, i)
return w.precise and "Precision Shot" or w.breach and "Breaching" or w.graviton and "Graviton Pulse" or nil
end
function ACTIVATION.saveCtx(t)
local kind = t.close == true and "close" or t.close == false and "ranged" or nil
return TRAIT_RULES.saveContext(kind)
end
function ACTIVATION.saveOf(t)
if t.gas or t.web then return nil end
local sv = statNumber("Sv", ACTIVATION.saveCtx(t))
if sv then return sv end
return 7, true
end
function ACTIVATION.invOf(t)
local v, it = STAT.inv()
if t.gas then
for _, g in ipairs(SKILL.with("gasInv")) do
local n = tonumber(g.gasInv)
if n and not (v and v < n) then v, it = n, g end
end
end
return v, it
end
function ACTIVATION.apProof(name)
local low = " " .. tostring(name or ""):lower()
for _, it in ipairs(SKILL.with("noAp")) do
for _, word in ipairs(type(it.noAp) == "table" and it.noAp or { it.noAp }) do
if low:find("[^%a]" .. tostring(word):lower():gsub("%p", "%%%0")) then return it.name end
end
end
return nil
end
function ACTIVATION.rollSaves(t, cover, player)
if fighter.outOfAction then ACTIVATION.seqEnd(t) return nil end
local n = clamp(math.floor(tonumber(t.wounds) or 0), 0, ACTIVATION.MAX_SHOWN)
if n < 1 then ACTIVATION.seqEnd(t) return nil end
cover = tonumber(cover) or 0
local sv, none = ACTIVATION.saveOf(t)
local proof = ACTIVATION.apProof(t.weapon)
local function apOf(i) return proof and 0 or math.max(0, math.floor(tonumber(ACTIVATION.wound(t, i).ap) or 0)) end
local function precise(i) return ACTIVATION.noArmour(t, i) end
local function needOf(i) return sv and not precise(i) and sv + apOf(i) - cover or nil end
local function invFor(need)
local v, it = ACTIVATION.invOf(t)
if v and not (need and need <= v) then return v, it end
return nil
end
local function needText(k, inv) return string.format(inv and "Inv %d+" or "%d+", k) end
local parts, seen, v0 = {}, {}, nil
for i = 1, n do
local k = needOf(i)
local v = invFor(k)
if k and not seen[k] and not (none and cover <= 0 and v) then seen[k], parts[#parts + 1] = true, needText(k) end
v0 = v0 or v
end
if v0 then parts[#parts + 1] = needText(v0, true) end
local title = "Save Roll (" .. (#parts > 0 and table.concat(parts, ", ") or "no save") .. ")"
local UP, MOD = COL.valueUp, COL.valueMod
ACTIVATION.rolling(title)
throwDice(n, colorOf(player), function(faces, digital)
local hls, read, saved, burnt, mixed, failed = {}, {}, 0, nil, false, {}
local first, half = nil, {}
for i, f in ipairs(faces) do
local need = needOf(i)
local wd = ACTIVATION.wound(t, i)
half[i] = wd.precise and "precise" or wd.breach and "breach" or wd.rend and "rend" or wd.shred and "shred" or nil
local v, it = invFor(need)
local k = v or need
local ok = k ~= nil and f > CFG.saveFails and f >= k
if ok then saved = saved + 1 else failed[#failed + 1] = ACTIVATION.wound(t, i) end
hls[i] = ok and UP or MOD
local mark = v and needText(v, true) or need and needText(need)
or precise(i) or "no save"
first = first or mark
mixed = mixed or mark ~= first
read[i] = { f = f, mark = mark }
if v and it.burns and f == 1 and not burnt then
burnt = it
fighter.burnt = fighter.burnt or {}
fighter.burnt[it.key] = true
read[i].mark = mark .. ", burns out"
mixed = true
end
end
local through = #faces - saved
local each = {}
for i, r in ipairs(read) do each[i] = mixed and string.format("%d (%s)", r.f, r.mark) or tostring(r.f) end
local ap = apOf(1)
local aps, needs, apText, seenAp = {}, {}, {}, {}
for i = 1, #faces do
aps[i], needs[i] = apOf(i), needOf(i)
if aps[i] > 0 and not seenAp[aps[i]] then seenAp[aps[i]], apText[#apText + 1] = true, tostring(aps[i]) end
end
local some, all = false, true
for i = 1, #faces do some, all = some or precise(i) or false, all and precise(i) or false end
local mods = {}
if not all then
if #apText > 0 and not proof then mods[#mods + 1] = "AP -" .. table.concat(apText, "/-") end
if cover > 0 then mods[#mods + 1] = "Cover +" .. cover end
end
local head = (not all and sv and not none) and string.format("Sv%d+", sv) or "no Sv"
local one = needOf(1)
if #mods > 0 then
head = head .. " w. " .. table.concat(mods, ", ") .. (one and not mixed and " = " .. needText(one) or "")
end
local invItem = select(2, ACTIVATION.invOf(t))
if v0 or burnt then head = head .. " / " .. needText(tonumber((burnt or {}).inv) or v0, true) end
local why = {}
if not all and sv and not none then STAT.why("Sv", ACTIVATION.saveCtx(t), why) end
if t.gas then why[#why + 1] = "Gas" elseif t.web then why[#why + 1] = "Web" end
local said = {}
for i = 1, #faces do
local r = precise(i)
if r and not said[r] then said[r], why[#why + 1] = true, r end
end
if proof and not all then why[#why + 1] = proof .. ": AP ignored" end
local by = burnt or (v0 and invItem)
if by then why[#why + 1] = by.name end
local byInv = not mixed and first and first:find("^Inv") and not all and sv and not none
local body = table.concat(each, ", ") .. (byInv and " (" .. first .. ")" or "")
.. " = " .. (through == 0 and "Saved" or string.format("∑%d Wound%s through", through, through == 1 and "" or "s"))
ACTIVATION.sayAttack("SAVE ROLLS", tostring(t.weapon or "Weapon") .. ": " .. head, body,
through == 0 and UP or MOD, digital, why)
if burnt then
chat(string.format("%s's %s burns out -- no invulnerable save for the rest of the battle",
fighter.name, burnt.name), rgbOf(MOD))
SKILL.drawBurnt()
ui.drawStats()
end
local kinds = {}
for i = 1, #faces do kinds[i] = "d6" end
ACTIVATION.showDice{ title = title, kinds = kinds, faces = faces, hls = hls, half = next(half) and half or nil,
sum = through == 0 and "Saved" or "∑" .. through, sumInk = through == 0 and UP or MOD }
local shown = ACTIVATION.roll
onSavesRolled(player, { wounds = #faces, saved = saved, through = through, faces = faces, need = needOf(1),
needs = needs, aps = aps,
inv = v0, cover = cover, ap = ap, burnt = burnt and burnt.name or nil,
precise = some or nil,
by = t.by, weapon = t.weapon, digital = digital })
__nqs_mundane_bus.try(function()
local sources, thru = {}, nil
if not all and sv and not none then STAT.why("Sv", ACTIVATION.saveCtx(t), sources) end
if cover > 0 and not all then sources[#sources + 1] = "Cover" end
if by and by.name then sources[#sources + 1] = tostring(by.name) end
if proof and not all then sources[#sources + 1] = tostring(proof) end
for k = 1, #faces do thru = thru or precise(k) end
local id = __nqs_mundane_bus.attackId(t.seq, t.from)
__nqs_mundane_bus.send({
kind = "roll", action = "save", label = "Save",
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
direction = "gte",
weapon = tostring(t.weapon or "Weapon"),
target = needOf(1), needs = needs, aps = aps,
outcome = { passed = through == 0, saved = saved, through = through },
saved = saved, through = through, cover = cover, ap = ap,
inv = v0,
burnt = burnt and burnt.name or nil,
sources = #sources > 0 and sources or nil,
removed_by = thru, gas = t.gas and true or nil, web = t.web and true or nil,
attack_id = id, group = id,
attacker = t.by and tostring(t.by) or nil,
by = player,
})
end)
ACTIVATION.damage(t, failed, shown, player)
end, "d6", title)
return true
end
function ACTIVATION.damage(t, failed, roll, player)
if fighter.outOfAction then return ACTIVATION.seqEnd(t) end
if #failed == 0 then return ACTIVATION.knockSelf(t, roll) end
if not (t.web or t.dodged or t.area) and #SKILL.with("dodge") > 0 and fighter.wounds.current > 0 then
return ACTIVATION.dodge(t, failed, roll, player)
end
local from = ACTIVATION.fromText(t)
if t.web then
if fighter.wounds.current > 0 then ACTIVATION.toxicNote(t, #failed) end
ACTIVATION.timedCondition("webbed", 1, "S", from)
onDamaged(player, { lost = 0, injury = 0, webbed = true, by = t.by, weapon = t.weapon })
return ACTIVATION.knockSelf(t, roll)
end
ACTIVATION.juggWounded(t)
local bio = ACTIVATION.bioBooster()
local lost, inj, was, boosted, pair = 0, 0, fighter.wounds.current, nil, false
local toxic = 0
local pools = {}
for _, w in ipairs(failed) do
local d = math.max(0, math.floor(tonumber(w.dmg) or 1))
local l = math.max(0, math.floor(tonumber(w.l) or 0))
local cur = fighter.wounds.current
if cur > 0 then
toxic = toxic + 1
local now = math.max(0, cur - d)
lost = lost + cur - now
if now ~= cur then setWounds(now) end
if now == 0 then
if bio and not boosted then
boosted = bio
local less = math.max(0, l - (tonumber(bio.bioBooster) or 1))
pair, l = l > 0 and less == 0, less
end
inj = inj + l
if l > 0 then pools[#pools + 1] = l end
end
else
inj = inj + l
if l > 0 then pools[#pools + 1] = l end
end
end
if boosted then
fighter.burnt = fighter.burnt or {}
fighter.burnt[boosted.key] = true
SKILL.drawBurnt()
end
local left = fighter.wounds.current
local msg = lost > 0
and string.format("%s loses %d wound%s to %s -- %d left", fighter.name, lost, lost == 1 and "" or "s", from, left)
or string.format("%s %s %s", fighter.name, was == 0 and "is already at 0 wounds --" or "loses no wounds to", from)
if boosted then
msg = msg .. string.format(", %s: Lethality %d less", boosted.name, tonumber(boosted.bioBooster) or 1)
.. (pair and " -- 2 Injury dice, the better kept" or "")
end
if inj > 0 then msg = msg .. string.format(", %d %sInjury dice", inj, pair and "more " or "") end
chat(msg, rgbOf(COL.valueMod))
ACTIVATION.toxicNote(t, toxic)
onDamaged(player, { lost = lost, wounds = left, injury = inj, bio = boosted and boosted.name or nil, by = t.by,
weapon = t.weapon })
local function rest(r)
if inj < 1 then return ACTIVATION.knockSelf(t, r) end
ACTIVATION.later(r, function()
ACTIVATION.injure(inj, from, player, { weapon = t.weapon, done = function(r2) ACTIVATION.knockSelf(t, r2) end,
ended = function() ACTIVATION.seqEnd(t) end, back = t.fight and t or nil,
attack_id = __nqs_mundane_bus.attackId(t.seq, t.from),
pools = pools, first = pair and 2 or 1,
of = #pools + (pair and 1 or 0) })
end)
end
if pair then
ACTIVATION.later(roll, function()
ACTIVATION.injure(2, from, player, { weapon = t.weapon, best = boosted.name, done = rest,
ended = function() ACTIVATION.seqEnd(t) end, back = t.fight and t or nil,
attack_id = __nqs_mundane_bus.attackId(t.seq, t.from),
pools = { 2 }, first = 1, of = #pools + 1 })
end)
else
rest(roll)
end
end
function ACTIVATION.dodge(t, failed, roll, player)
local need = 7
for _, it in ipairs(SKILL.with("dodge")) do need = math.min(need, math.floor(tonumber(it.dodge) or 6)) end
local title = string.format("Dodge (%d+)", need)
ACTIVATION.later(roll, function()
if fighter.outOfAction then return ACTIVATION.seqEnd(t) end
ACTIVATION.rolling(title)
throwDice(#failed, colorOf(player), function(faces, digital)
local cur, hls, read, through, dodged = fighter.wounds.current, {}, {}, {}, 0
local id = __nqs_mundane_bus.attackId(t.seq, t.from)
for i, f in ipairs(faces) do
local w = failed[i]
read[i] = tostring(f)
local wasted = cur <= 0
if cur <= 0 then
hls[i], through[#through + 1] = COL.diceWasted, w
elseif f >= need then
hls[i], dodged = COL.valueUp, dodged + 1
else
hls[i], through[#through + 1] = COL.valueMod, w
cur = cur - math.max(0, math.floor(tonumber(w.dmg) or 1))
end
__nqs_mundane_bus.send({
kind = "roll", action = "dodge", label = "Dodge",
wound = i,
dice = __nqs_mundane_bus.diceArray({ f }, "D6"), direction = "gte", target = need,
weapon = t.weapon and tostring(t.weapon) or nil,
outcome = { passed = not wasted and f >= need, wasted = wasted or nil },
attack_id = id, group = id, attacker = t.by and tostring(t.by) or nil, by = player,
})
end
local UP, MOD = COL.valueUp, COL.valueMod
ACTIVATION.sayAttack("DODGE ROLLS", tostring(t.weapon or "Weapon"),
table.concat(read, ", ") .. " = " .. (dodged > 0 and string.format("%d Dodged", dodged) or "none Dodged"),
dodged > 0 and UP or MOD, digital)
local kinds = {}
for i = 1, #faces do kinds[i] = "d6" end
ACTIVATION.showDice{ title = title, kinds = kinds, faces = faces, hls = hls,
sum = dodged > 0 and "∑" .. dodged or "∑0", sumInk = dodged > 0 and UP or MOD }
t.dodged = true
ACTIVATION.damage(t, through, ACTIVATION.roll, player)
end, "d6", title)
end)
end
function ACTIVATION.bioBooster()
for _, it in ipairs(SKILL.with("bioBooster")) do
if not (fighter.burnt or {})[it.key] then return it end
end
return nil
end
function ACTIVATION.injure(n, from, player, o)
o = o or {}
local function ended() if o.ended then o.ended() end end
if fighter.outOfAction then return ended() end
n = clamp(math.floor(tonumber(n) or 0), 0, ACTIVATION.MAX_SHOWN)
if n < 1 then return ended() end
local color = colorOf(player)
local title = ACTIVATION.rollName("injury", n)
ACTIVATION.rolling(title)
throwDice(n, color, function(faces, digital)
local R, count = ACTIVATION.INJURY, {}
for i, f in ipairs(faces) do
local k = ACTIVATION.INJURY_DICE[f] or "serious"
count[k] = (count[k] or 0) + 1
end
local worst = nil
local order = o.best and { "injured", "serious", "out" } or { "out", "serious", "injured" }
for _, k in ipairs(order) do worst = worst or (count[k] and k) end
chat(string.format("%s - INJURY ROLLS - %s: %s%s%s", fighter.name, tostring(o.weapon or from),
ACTIVATION.injuryText(faces, worst), digital and " (rolled digitally)" or "",
o.best and " || (" .. tostring(o.best) .. ": the better kept)"
or (#faces > 1 and " || (the attacker's pick: the worst for " .. fighter.name .. ")" or "")),
rgbOf(COL.diceInjured))
ACTIVATION.showDice{ title = title, kind = "injury", faces = faces, result = worst }
local shown = ACTIVATION.roll
__nqs_mundane_bus.try(function()
local id = o.attack_id
local pools = __nqs_mundane_bus.injuryPools(faces, o.pools,
function(f) return ACTIVATION.INJURY_DICE[f] end, o.best ~= nil)
local first, of = tonumber(o.first) or 1, tonumber(o.of) or #pools
if of < first + #pools - 1 then of = first + #pools - 1 end
for k, p in ipairs(pools) do
local dice = __nqs_mundane_bus.diceArray(p.faces, "INJURY")
if dice[p.used] then dice[p.used].used = true end
__nqs_mundane_bus.send({
kind = "roll",
action = o.weapon and ("injury roll, " .. tostring(o.weapon)) or "injury roll",
label = of > 1 and string.format("Injury, wound %d of %d", first + k - 1, of) or "Injury",
dice = dice,
weapon = o.weapon and tostring(o.weapon) or nil,
chooser = o.best and "victim" or id and "attacker" or "auto",
outcome = { result = p.result, applied = worst, out_of_action = (worst == "out") and true or false },
attack_id = id, group = id,
attacker = from and tostring(from) or nil,
by = color or player,
})
end
end)
if fighter.outOfAction then return ended() end
if worst == "out" and o.back then
ACTIVATION.fightBackAsk(o.back, "Injury dice from " .. from)
return ended()
elseif worst == "out" then
setOutOfAction{ value = true, why = "Injury dice from " .. from }
elseif worst == "serious" and fighter.status ~= "seriously_injured" then
setStatus("seriously_injured")
end
if o.done and not fighter.outOfAction then o.done(shown) else ended() end
end, "injury", title)
end
function ACTIVATION.timedCondition(key, n, test, from)
local i = indexOf(CONDITIONS, key)
if not i then return 0 end
local label = CONDITIONS[i].label
local before = conditionCount(key)
local after = setCondition(key, test and math.max(before, 1) or before + n) or before
fighter.timed = fighter.timed or {}
if test then
if after < 1 then return 0 end
local has = false
for _, r in ipairs(fighter.timed) do has = has or (r.key == key and r.test ~= nil) end
if not has then table.insert(fighter.timed, { key = key, n = 1, test = test }) end
chat(string.format("%s is %s by %s -- no damage; a %s check at the end of their next activation frees them",
fighter.name, label, from, STAT.NAMES[test] or test), rgbOf(COL.valueMod))
else
local got = after - before
if got <= 0 then
if next(fighter.timed) == nil then fighter.timed = nil end
return 0
end
table.insert(fighter.timed, { key = key, n = got })
chat(string.format("%s gains %s%s from %s -- until the end of their next activation", fighter.name,
got > 1 and got .. "x " or "", label, from), rgbOf(key == "concussion" and COL.diceConc or COL.valueMod))
end
return after
end
function ACTIVATION.timedEnd(player)
local keep = {}
for _, r in ipairs(fighter.timed or {}) do
local i = indexOf(CONDITIONS, r.key)
local label = i and CONDITIONS[i].label or r.key
local has = conditionCount(r.key)
if r.test then
if has > 0 then
keep[#keep + 1] = r
ACTIVATION.rollTest(r.test, player, { why = label, done = function(test)
if not test.passed then
chat(string.format("%s stays %s", fighter.name, label), rgbOf(COL.valueMod))
return
end
for k, q in ipairs(fighter.timed or {}) do
if q == r then table.remove(fighter.timed, k) break end
end
if fighter.timed and next(fighter.timed) == nil then fighter.timed = nil end
setCondition(r.key, 0)
chat(string.format("%s breaks free -- no longer %s", fighter.name, label), rgbOf(COL.valueUp))
end })
end
elseif has > 0 then
setCondition(r.key, math.max(0, has - (tonumber(r.n) or 1)))
chat(string.format("%s's %s%s wears off", fighter.name, (tonumber(r.n) or 1) > 1 and r.n .. "x " or "", label),
rgbOf(COL.valueUp))
end
end
fighter.timed = next(keep) and keep or nil
end
function reloadWeapon(t, player)
if type(t) ~= "table" then return false end
local i, pi = tonumber(t.weapon), tonumber(t.profile)
local w = i and weaponAt(i)
local p = w and w.profiles and pi and w.profiles[pi]
if not p or TRAIT_RULES.ammoState(w, p) ~= "out" then return false end
local entry = ACTIONS[indexOf(ACTIONS, "reload") or 0]
if entry and fighter.activation == "active" and fighter.actionsLeft > 0 then
fighter.actionsLeft = math.max(0, fighter.actionsLeft - SKILL.cost(entry))
fighter.usedActions.reload = true
TRAIT_RULES.drawGlows()
ui.drawReady()
ui.drawActions()
onActionsChanged(fighter.actionsLeft)
end
local fast = #SKILL.with("fastReload") > 0
local list = fast and TRAIT_RULES.empties() or { { i = i, pi = pi, w = w, p = p } }
ACTIVATION.reloadNow(list, player, { say = function(names)
if fast then
ACTIVATION.sayAttack("RELOAD", "Fast Reload", ACTIVATION.nameList(names) .. " reloaded", COL.valueUp)
else
ACTIVATION.sayAttack("RELOAD", names[1].name, "reloaded", COL.valueUp)
end
end })
return true
end
function ACTIVATION.reloadNow(list, player, o)
o = o or {}
local R = TRAIT_RULES
local names, seen, scarce = {}, {}, {}
for _, e in ipairs(list) do
local need = R.scarce(e.p)
if need then
scarce[#scarce + 1] = { e = e, need = need }
else
setProfileState({ weapon = e.i, profile = e.pi, ammo = R.ammoNext(e.w, e.p, false) })
if not seen[e.w] then seen[e.w], names[#names + 1] = true, { name = TRAIT_RULES.name(e.w) } end
onReloadRolled(player, { weapon = e.i, profile = e.pi, reloaded = true })
do
local __wname = TRAIT_RULES.name(e.w)
__nqs_mundane_bus.send({
kind = "event", event = "reloaded",
fighter = fighter and fighter.name or nil,
weapon = __wname and tostring(__wname) or nil,
profile = e.pi,
scarce = false,
by = player,
})
end
end
end
if #names > 0 and o.say then o.say(names) end
if #scarce == 0 then return names, 0 end
local title = #scarce == 1 and TRAIT_RULES.name(scarce[1].e.w) .. " (Scarce)" or "Reload (Scarce)"
ACTIVATION.later(o.after, function()
ACTIVATION.rolling(title)
throwDice(#scarce, colorOf(player), function(faces, digital)
local hls, all = {}, true
for k, s in ipairs(scarce) do
local f, e = faces[k], s.e
local ok = f ~= nil and f >= s.need
hls[k], all = ok and COL.valueUp or COL.valueMod, all and ok
if f then
ACTIVATION.sayAttack("RELOAD", TRAIT_RULES.name(e.w), string.format("Scarce %d (%d+), %s", f, s.need,
ok and "reloaded" or "still OUT"), hls[k], digital)
if ok and R.ammoState(e.w, e.p) == "out" then
setProfileState({ weapon = e.i, profile = e.pi, ammo = R.ammoNext(e.w, e.p, false) })
end
onReloadRolled(player, { weapon = e.i, profile = e.pi, face = f, need = s.need, reloaded = ok,
digital = digital })
do
local __wname = TRAIT_RULES.name(e.w)
__nqs_mundane_bus.send({
kind = "roll",
action = __wname and ("ammo test, " .. tostring(__wname)) or "ammo test",
label = "Ammo", why = "Scarce",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray({ f }, "D6"),
direction = "gte",
weapon = __wname and tostring(__wname) or nil,
profile = e.pi,
target = s.need,
outcome = { passed = ok and true or false, reason = "scarce" },
by = player,
})
end
end
end
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, hls = hls, ammoDie = #scarce == 1 and 1 or nil,
ammoGoal = #scarce == 1 and scarce[1].need .. "+" or nil,
sum = all and "AM" or nil, sumInk = COL.valueUp, ammoState = not all and "out" or nil }
end, "d6", title)
end)
return names, #scarce
end
function ACTIVATION.reload(player)
local out = TRAIT_RULES.empties()
local one = out[1]
if one and (#out == 1 or #SKILL.with("fastReload") > 0) then
reloadWeapon({ weapon = one.i, profile = one.pi }, player)
onActionChosen(player, "reload")
return true
end
if one then
chat(string.format("%s has %d profiles out of ammo -- middle-click the OUT of the one to reload",
fighter.name, #out), rgbOf(COL.valueMod))
else
chat(string.format("%s has no weapon out of ammo -- nothing to reload", fighter.name), rgbOf(COL.valueMod))
end
return false
end
function ammoCheck(t)
t = type(t) == "table" and t or {}
if fighter.outOfAction or #TRAIT_RULES.empties() == 0 then return false end
local test = ACTIVATION.rollTest("Int", t.color, { why = "Distribute Ammo", done = function(test, roll)
local names = {}
if test.passed then
local out = TRAIT_RULES.empties()
if #out == 1 or (#out > 1 and #SKILL.with("fastReload") > 0) then
names = ACTIVATION.reloadNow(out, t.color, { after = roll, say = function(list)
chat(string.format("%s reloads %s%s", fighter.name, ACTIVATION.nameList(list),
t.by and t.by ~= fighter.name and " with " .. tostring(t.by) .. "'s ammo" or ""), rgbOf(COL.valueUp))
end })
elseif #out > 1 then
chat(string.format("%s may reload one of %d profiles that are out of ammo -- click the OUT of the one",
fighter.name, #out), rgbOf(COL.valueUp))
end
end
onAmmoChecked(test, names)
end })
return test ~= nil
end
function ACTIVATION.distribute(a, player)
local range = tonumber(a.distribute) or 0
local t = { by = fighter.name, color = colorOf(player) }
local names = {}
if ammoCheck(t) then names[1] = fighter.name end
for _, o in ipairs(ACTIVATION.friendsWithin(range)) do
local ok, took = ACTIVATION.ask(o.obj, "ammoCheck", t)
if ok and took then
names[#names + 1] = o.name
flash(o.obj, ACTIVATION.actionGlow(a.key, a.type))
end
end
return names
end
function recoveryTest(near)
if fighter.outOfAction then return nil end
near = type(near) == "table" and near.foes and near or ACTIVATION.surroundings()
local tend = fighter.usedActions.tend_wounds == true
local treated = tonumber(fighter.treated) or 0
local kit = near.helper and math.max(0, math.floor(tonumber(near.helper.assist) or 0)) or 0
fighter.recovery = { dice = math.min(ACTIVATION.MAX_DICE, 1 + (near.helper and 1 or 0) + kit + (tend and 1 or 0) + treated),
helper = near.helper and near.helper.name or nil, tend = tend or nil,
kit = kit > 0 and (near.helper.assistWith or "wargear") or nil,
treated = treated > 0 and treated or nil,
foes = #near.foes > 0 and ACTIVATION.nameList(near.foes) or nil }
ACTIVATION.draw()
return fighter.recovery.dice
end
function setTreated(on)
if type(on) == "table" then on = on.value end
local rec = fighter.recovery
if on == false then
if rec and rec.treated then
rec.dice, rec.treated = math.max(1, rec.dice - rec.treated), nil
ACTIVATION.draw()
end
fighter.treated = nil
return false
end
if fighter.outOfAction or fighter.status ~= "seriously_injured" then return false end
fighter.treated = (tonumber(fighter.treated) or 0) + 1
if rec and not rec.foes then
rec.dice, rec.treated = math.min(ACTIVATION.MAX_DICE, rec.dice + 1), (rec.treated or 0) + 1
ACTIVATION.draw()
end
return fighter.treated
end
function setRecoveryDice(n)
if not fighter.recovery then return nil end
if type(n) == "table" then n = n.value end
fighter.recovery.dice = clamp(math.floor(tonumber(n) or 1), 1, ACTIVATION.MAX_DICE)
ACTIVATION.draw()
return fighter.recovery.dice
end
function closeRecovery()
fighter.recovery = nil
ACTIVATION.draw()
return true
end
function rollRecovery(player)
local rec = fighter.recovery
if not rec or rec.foes or fighter.outOfAction then return nil end
closeRecovery()
fighter.treated = nil
local color = colorOf(player)
ACTIVATION.rolling("Recovery Test")
throwDice(rec.dice, color, function(faces, digital)
local R, best = ACTIVATION.INJURY, nil
for i, f in ipairs(faces) do
local k = ACTIVATION.INJURY_DICE[f] or "serious"
if not best or R[k].rank > R[best].rank then best = k end
end
local why = {}
if rec.helper then why[#why + 1] = rec.helper .. " assists" .. (rec.kit and " with " .. rec.kit or "") end
if rec.tend then why[#why + 1] = "Tend Wounds" end
if rec.treated then why[#why + 1] = rec.treated > 1 and ("Treat Ally x" .. rec.treated) or "Treat Ally" end
ACTIVATION.say("Recovery Test" .. (#why > 0 and (" (" .. table.concat(why, ", ") .. ")") or ""), {},
ACTIVATION.injuryText(faces, best), { color = color, digital = digital })
ACTIVATION.showDice{ title = "Recovery Test", kind = "injury", faces = faces, result = best }
__nqs_mundane_bus.try(function()
local pick = __nqs_mundane_bus.injuryPools(faces, nil, function(x) return ACTIVATION.INJURY_DICE[x] end, true)[1]
local dice = __nqs_mundane_bus.diceArray(faces, "INJURY")
if pick and dice[pick.used] then dice[pick.used].used = true end
__nqs_mundane_bus.test("Recovery", faces, "INJURY", {
dice = dice, sources = #why > 0 and why or nil, chooser = "auto",
composed = { dice = rec.dice, helper = rec.helper, kit = rec.kit, tend = rec.tend or nil,
treated = rec.treated },
outcome = { result = best }, by = color or player,
})
end)
__nqs_mundane_bus.within("cause", { roll = "Recovery" }, function()
if best == "out" then setOutOfAction(true)
elseif best == "injured" and fighter.status ~= "active" then setStatus("active") end
end)
onRecoveryRolled(player, best, faces)
end, "injury", "Recovery Test")
return rec.dice
end
function nerveCheck(player)
if fighter.outOfAction then return nil end
ACTIVATION.nerveLight(false)
local src = ACTIVATION.nerveSource()
ACTIVATION.openCheck({ value = src.value, own = src.own, found = src.value,
from = src.from and src.from.name, obj = src.from and src.from.obj })
return src.value
end
function knockback(t)
t = type(t) == "table" and t or {}
if fighter.outOfAction then ACTIVATION.seqEnd(t) return false end
ACTIVATION.seqJoin(t)
local inches = tonumber(CFG.knockback) or 1
local d = (string.format("%.1f", inches):gsub("%.0$", ""))
local title = t.by and (tostring(t.by) .. " triggered Knockback") or "Knockback"
ACTIVATION.showDice{ title = title, faces = {}, leadInk = COL.diceKnock,
lead = string.format('%s Knockback: %s"', CFG.knockMark or "", d):gsub("^ ", "") }
chat(string.format('%s is knocked back %s" by %s', fighter.name, d, ACTIVATION.fromText(t)), rgbOf(COL.diceKnock))
flash(self, rgbOf(COL.diceKnock))
ACTIVATION.seqEnd(t)
return inches
end
function dragged(t)
t = type(t) == "table" and t or {}
if fighter.outOfAction then ACTIVATION.seqEnd(t) return false end
ACTIVATION.seqJoin(t)
local inches = math.max(1, math.floor(tonumber(t.inches) or 1))
ACTIVATION.showDice{ title = t.by and (tostring(t.by) .. " triggered Drag") or "Drag", faces = {},
leadInk = COL.diceKnock, lead = string.format('Dragged: %d"', inches) }
chat(string.format('%s is dragged %d" towards %s by %s', fighter.name, inches, tostring(t.by or "?"),
ACTIVATION.fromText(t)), rgbOf(COL.diceKnock))
flash(self, rgbOf(COL.diceKnock))
ACTIVATION.seqEnd(t)
return inches
end
ACTIVATION.jugg = {}
function rangedHit(t)
t = type(t) == "table" and t or {}
if fighter.outOfAction or fighter.status ~= "active" then return false end
ACTIVATION.seqJoin(t)
if t.seq and t.from and #SKILL.with("juggernaut") > 0 then
local id = tostring(t.from) .. ":" .. tostring(t.seq)
ACTIVATION.jugg[id] = ACTIVATION.jugg[id] or { t = t }
return "waits"
end
return ACTIVATION.suppressHit(t)
end
function ACTIVATION.juggWounded(t)
local j = type(t) == "table" and ACTIVATION.jugg[tostring(t.from) .. ":" .. tostring(t.seq)]
if j then j.wounded = true end
end
function ACTIVATION.juggEnd(t)
local id = tostring(t.from) .. ":" .. tostring(t.seq)
local j = ACTIVATION.jugg[id]
if not j then return end
ACTIVATION.jugg[id] = nil
if fighter.outOfAction or fighter.status ~= "active" then return end
if j.wounded then return ACTIVATION.suppressHit(j.t) end
chat(string.format("%s shrugs off %s -- Juggernaut, no wound: not Suppressed", fighter.name,
j.t.by and (tostring(j.t.by) .. (j.t.weapon and ("'s " .. tostring(j.t.weapon)) or "")) or "the hit"),
rgbOf(COL.valueUp))
end
function ACTIVATION.suppressHit(t)
local hit = string.format("%s is hit by %s", fighter.name,
t.by and (tostring(t.by) .. (t.weapon and ("'s " .. tostring(t.weapon)) or "")) or "a ranged attack")
local cl = #SKILL.with("steel") > 0 and statNumber("Cl") or nil
if not cl then
local rgb = rgbOf(statusDef("suppressed").color)
setStatus({ key = "suppressed", quiet = true })
chat(hit .. " -- Suppressed", rgb)
flash(self, rgb)
return "suppressed"
end
local n = ACTIVATION.nerve
while n and not n.steel do n = n.held end
if n then return "asked" end
chat(hit .. " -- Cool check for Nerves Of Steel, or Suppressed", rgbOf(statusDef("suppressed").color))
ACTIVATION.openCheck({ title = "Nerves Of Steel", value = cl, own = cl, found = cl, steel = true, keep = true,
done = function()
if not fighter.outOfAction and fighter.status == "active" then setStatus("suppressed") end
end })
return "asked"
end
function traitHit(t)
if type(t) ~= "table" or fighter.outOfAction then return false end
ACTIVATION.seqJoin(t)
local name = fighter.name
local hit = t.by and (tostring(t.by) .. (t.weapon and ("'s " .. tostring(t.weapon)) or "")) or "a weapon"
if t.own then hit = string.format("their own %s (a natural 1)", tostring(t.weapon or "weapon")) end
local MOD = rgbOf(COL.valueMod)
local function curse()
if not t.cursed or fighter.outOfAction then return end
local test = ACTIVATION.rollTest("Wil", t.color, { why = "Cursed", done = function(res)
if res.passed then
chat(string.format("%s resists the curse of %s", name, hit), rgbOf(COL.valueUp))
else
setCondition("insanity", true)
chat(string.format("%s is cursed by %s -- Insanity", name, hit), MOD)
flash(self, MOD)
end
end })
if not test then chat(string.format("%s has no Willpower to test -- the curse of %s does nothing", name, hit), MOD) end
end
local function blind()
setCondition("blind", true)
local left = ACTIVATION.loseMark("Flash")
if left then
chat(string.format("%s is blinded by %s -- Blind, and loses %s", name, hit,
left > 0 and string.format("a Ready marker (%d left)", left) or "their Ready marker"), MOD)
else
fighter.noReady = true
chat(string.format("%s is blinded by %s -- Blind, and gets no Ready marker next round", name, hit), MOD)
end
flash(self, MOD)
end
if t.flash then
local mods, why = {}, "Flash"
for _, it in ipairs(SKILL.with("flashMod")) do
local m = tonumber(it.flashMod)
if m and m ~= 0 then mods[#mods + 1], why = m, why .. ", " .. it.name end
end
local test = ACTIVATION.rollTest("I", t.color, { why = why, mods = mods, done = function(res, roll)
if res.passed then
chat(string.format("%s looks away from %s in time -- not Blind", name, hit), rgbOf(COL.valueUp))
else
blind()
end
if t.cursed then ACTIVATION.later(roll, curse) end
end })
if not test then
blind()
curse()
end
else
curse()
end
onTraitHit(t)
return true
end
function ACTIVATION.openCheck(n)
local was = ACTIVATION.nerve
ACTIVATION.nerveLight(false)
if was then n.held = was.keep and was or was.held end
ACTIVATION.nerve = n
ACTIVATION.nerveLight(true)
ACTIVATION.draw()
return n
end
function groupActivation(player)
player = __nqs_mundane_bus.scripted(player) or player
if fighter.outOfAction then return nil end
ACTIVATION.nerveLight(false)
local group, far = ACTIVATION.groupOf(ACTIVATION.picked(player))
for _, o in ipairs(far) do group[#group + 1] = o end
local ld, minus, objs = statNumber("Ld"), math.max(0, #group - 1), {}
for i, o in ipairs(group) do objs[i] = o.obj end
local value = ld and ld - minus or nil
ACTIVATION.openCheck({ stat = "Ld", title = "Group Activation", group = group, objs = objs, minus = minus,
value = value, own = ld, found = value, ink = ACTIVATION.actionGlow("group_activation") })
if #group == 0 then
chat(string.format("%s has no Ready friend selected to group activate", fighter.name), rgbOf(COL.valueMod))
end
return value
end
function ACTIVATION.nerveLight(on)
local n = ACTIVATION.nerve
for _, o in ipairs(n and (n.objs or { n.obj }) or {}) do
if on then pcall(function() o.highlightOn(n.ink or rgbOf(statusDef("active").color)) end)
else pcall(function() o.highlightOff() end) end
end
end
function setNerveValue(n)
local nv = ACTIVATION.nerve
if not nv then return nil end
if type(n) == "table" then n = n.value end
if nv.cover then
nv.value = clamp(math.floor(tonumber(n) or nv.value or 0), 0, ACTIVATION.coverMax())
ACTIVATION.draw()
return nv.value
end
if nv.test == "question" then return nil end
n = math.floor(tonumber(n) or nv.value or 0)
if nv.test == "height" then
nv.value = clamp(n, 1, ACTIVATION.FALL_MAX)
else
nv.value = nv.group and clamp(n, 2, 12) or STAT.clamp("Cl", n)
nv.hand = nv.value ~= nv.found or nil
end
ACTIVATION.draw()
return nv.value
end
function closeNerve()
local n = ACTIVATION.nerve
ACTIVATION.nerveLight(false)
ACTIVATION.nerve = n and n.held or nil
ACTIVATION.nerveLight(true)
ACTIVATION.draw()
return true
end
function ACTIVATION.giveUp(player)
local n = ACTIVATION.nerve
if not n then return end
closeNerve()
if n.done then n.done(false, nil, player) end
end
function ACTIVATION.goOn(player)
local n = ACTIVATION.nerve
if not (n and n.test == "question") then return false end
closeNerve()
if n.done then n.done(true, nil, player) end
return true
end
function rollNerve(player)
local n = ACTIVATION.nerve
if not n or fighter.outOfAction then return nil end
if n.test == "height" then return ACTIVATION.fall(player) end
if n.test == "question" then ACTIVATION.goOn(player) return nil end
closeNerve()
if not n.value then return nil end
if n.group then return ACTIVATION.rollGroup(n, player) end
local test = { stat = "Cl", dice = 2, target = n.value, under = true, nerve = true, from = n.from,
steel = n.steel }
local color = colorOf(player)
local name = n.title or "Nerve Check"
local title = string.format("%s (%d)", name, n.value)
local leader, own = ACTIVATION.outcastLeader("nerve")
ACTIVATION.rolling(title)
throwDice(2, color, function(faces, digital)
local total = 0
for _, f in ipairs(faces) do total = total + f end
test.faces, test.total, test.digital = faces, total, digital
test.passed = statTestPasses(test, total)
if leader then test.passed, test.auto = true, leader end
local whose = n.hand and ", set by hand" or n.from and string.format(", %s's Cl", n.from) or ""
if leader then whose = whose .. ", passed: " .. ACTIVATION.outcastWhy(leader, own) end
ACTIVATION.say(string.format("%s (%d%s)", name, n.value, whose), faces, total,
{ ink = ACTIVATION.checkInk(test), color = color, digital = digital })
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, hl = ACTIVATION.checkInk(test) }
if not test.passed and not fighter.outOfAction and fighter.status == "active" then
setStatus("suppressed")
elseif n.steel and test.passed then
chat(string.format("%s keeps their nerve -- not Suppressed", fighter.name), rgbOf(COL.valueUp))
end
onNerveRolled(player, test)
__nqs_mundane_bus.send({
kind = "roll",
action = "Cool check", label = "Cool check",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
direction = "lte",
stat = "Cl",
target = n.value,
outcome = { passed = test.passed and true or false, total = total,
auto = test.auto, nerve = true,
steel = n.steel and true or nil },
from = n.from,
why = n.title and tostring(n.title) ~= "Nerve Check" and tostring(n.title) or "Nerve Check",
by = color or player,
})
end, "d6", title)
return test
end
function ACTIVATION.rollGroup(n, player)
local test = { stat = "Ld", dice = 2, target = n.value, under = true, group = true }
local color = colorOf(player)
local title = string.format("Group Activation (%d)", n.value)
local how = n.hand and ", set by hand"
or n.minus > 0 and string.format(", -%d for %d fighters", n.minus, #n.group) or ""
local icon = SKILL.with("groupReroll")[1]
local function sum(faces)
local total = 0
for _, f in ipairs(faces) do total = total + f end
return total
end
local function read(faces, digital, first)
local total = sum(faces)
test.faces, test.total, test.digital, test.rerolled = faces, total, digital, first
test.passed = statTestPasses(test, total)
ACTIVATION.say(string.format("Group Activation (Ld %d%s%s)", n.value, how,
first and string.format(", %s re-rolled %d", icon.name, first) or ""), faces, total,
{ ink = ACTIVATION.checkInk(test), color = color, digital = digital })
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, hl = ACTIVATION.checkInk(test) }
local taken, far = {}, {}
if test.passed and not fighter.outOfAction then
local near = nil
near, far = ACTIVATION.groupOf(n.objs)
local names = { fighter.name }
for _, o in ipairs(near) do names[#names + 1] = tostring(o.name) end
for _, o in ipairs(near) do
local ok, on = ACTIVATION.ask(o.obj, "setGroupActivated", { value = true, by = fighter.name,
group = names })
if ok and on == true then taken[#taken + 1] = o end
end
end
if #taken > 0 then
chat(string.format("%s %s group activated by %s", ACTIVATION.nameList(taken),
#taken == 1 and "is" or "are", fighter.name), rgbOf(statusDef("active").color))
for _, o in ipairs(taken) do flash(o.obj, ACTIVATION.actionGlow("group_activation")) end
end
if #far > 0 then
chat(string.format('%s %s more than %g" from %s -- not group activated', ACTIVATION.nameList(far),
#far == 1 and "is" or "are", CFG.groupRange or 3, fighter.name), rgbOf(COL.valueMod))
end
test.activated = {}
for i, o in ipairs(taken) do test.activated[i] = o.name end
onGroupRolled(player, test)
__nqs_mundane_bus.send({
kind = "roll",
action = "Leadership check", label = "Leadership check",
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
direction = "lte",
stat = "Ld",
target = n.value,
outcome = { passed = test.passed and true or false, total = test.total,
group_activation = true,
rerolled = test.rerolled,
activated = test.activated,
activated_count = #test.activated,
far_count = #far },
why = "Group Activation",
by = color or player,
})
end
ACTIVATION.rolling(title)
throwDice(2, color, function(faces, digital)
local total = sum(faces)
if not icon or statTestPasses(test, total) then return read(faces, digital) end
ACTIVATION.say(string.format("Group Activation (Ld %d%s)", n.value, how), faces, total,
{ ink = COL.valueMod, color = color, more = string.format(" -- re-rolled (%s)", icon.name) })
local held = { title = title, kind = "d6", faces = faces, hl = COL.valueMod }
ACTIVATION.showDice(held)
ACTIVATION.later(held, function()
if fighter.outOfAction then return end
ACTIVATION.rolling(title)
throwDice(2, color, function(again, digital2) read(again, digital or digital2, total) end, "d6", title)
end)
end, "d6", title)
return test
end
function ACTIVATION.gangParts(s)
local function trim(t) return t and (t:gsub("^%s+", ""):gsub("%s+$", "")) end
s = tostring(s or ""):lower()
local rest, brackets = s:match("^(.-)%s*%((.*)%)%s*$")
rest = rest or s
local name, variant = rest:match("^(.-):(.*)$")
name, variant = trim(name or rest), trim(variant)
if variant == "" then variant = nil end
return name, variant, trim(brackets)
end
function ACTIVATION.gangIs(g)
if type(g) ~= "table" or ACTIVATION.noGangRule() then return false end
local name, variant = ACTIVATION.gangParts(fighter.gangType)
local wantName, wantVariant = ACTIVATION.gangParts(g.type)
if wantName == "" or name ~= wantName then return false end
if variant ~= wantVariant and not (variant and not wantVariant and ACTIVATION.gangVariant(g, variant)) then
return false
end
local mine = tostring(fighter.gangType or ""):lower()
local unless = g.unless
if type(unless) ~= "table" then unless = CFG.corrupted end
for _, u in ipairs(type(unless) == "table" and unless or {}) do
if mine:find(tostring(u):lower(), 1, true) then return false end
end
return true
end
function ACTIVATION.gangVariant(g, variant)
for _, v in ipairs(type(g.variants) == "table" and g.variants or {}) do
local names = { v.type }
for _, n in ipairs(type(v.aka) == "table" and v.aka or {}) do names[#names + 1] = n end
for _, n in ipairs(names) do
n = tostring(n)
if n ~= "" and select(1, ACTIVATION.gangParts(n)) == variant then return v, tostring(v.type or n) end
end
end
end
function ACTIVATION.gangMod(g)
if not ACTIVATION.gangIs(g) then return 0 end
return math.floor(tonumber(g.mod) or 0), tostring(g.type)
end
function ACTIVATION.noGangRule(f)
local tags = ACTIVATION.tags(f)
for _, t in ipairs(type(CFG.noGangRule) == "table" and CFG.noGangRule or {}) do
if tags[tostring(t):lower()] then return true end
end
return false
end
function ACTIVATION.gangRule(key)
local g = CFG[key]
if ACTIVATION.gangIs(g) then return g end
return nil
end
function ACTIVATION.gangStat(key)
local n, why = 0, nil
local function add(g, mods)
local d = type(mods) == "table" and tonumber(mods[key]) or 0
if d ~= 0 then n, why = n + d, tostring(g.type) end
end
local g = ACTIVATION.gangNear and ACTIVATION.gangRule("delaqueGang")
if g then add(g, g.mods) end
g = ACTIVATION.charged() and ACTIVATION.gangRule("goliathGang")
if g then add(g, g.charge) end
return n, why
end
function ACTIVATION.delaqueCheck()
local g, on = ACTIVATION.gangRule("delaqueGang"), false
if g and not fighter.outOfAction then
local range, n = tonumber(g.range) or 0, 0
local all, me = ACTIVATION.everyone({ within = range })
for _, o in ipairs(me and all or {}) do
if not o.self and o.gang == me.gang and not o.hanger and ACTIVATION.within(me, o, range) then n = n + 1 end
end
on = n >= (tonumber(g.friends) or 1)
end
if on ~= (ACTIVATION.gangNear == true) then
ACTIVATION.gangNear = on or nil
ui.drawStats()
end
return on
end
function ACTIVATION.gangMoved(from)
ACTIVATION.delaqueCheck()
local g = ACTIVATION.gangRule("delaqueGang")
if not g then return end
local all = ACTIVATION.everyone({ within = tonumber(g.range) or 0, spots = from and { from } or nil })
local mine = ui.gangOf(self)
for _, o in ipairs(mine and all or {}) do
if not o.self and o.gang == mine then ACTIVATION.ask(o.obj, "checkGangRules") end
end
end
function checkGangRules() return ACTIVATION.delaqueCheck() end
function ACTIVATION.outcastLeader(what)
local g = ACTIVATION.gangRule("outcastGang")
if not (g and g[what]) then return nil end
if tostring(fighter.rank or ""):lower() == "leader" then return fighter.name, true end
local range = tonumber(g.range)
local all, me = ACTIVATION.everyone({ within = range })
for _, o in ipairs(me and all or {}) do
if not o.self and o.gang == me.gang and tostring(o.rank or ""):lower() == "leader" and not o.hanger
and ACTIVATION.within(me, o, range) then
return o.name
end
end
return nil
end
function ACTIVATION.outcastWhy(leader, own)
if own then return "Leader (Outcasts)" end
return string.format('Leader %s within %g" (Outcasts)', tostring(leader),
tonumber(type(CFG.outcastGang) == "table" and CFG.outcastGang.range) or 0)
end
function ACTIVATION.hasRule(name)
local want = SKILL.key(name)
for _, list in ipairs({ SKILL.parse(fighter.rules), fighter.skills or {}, fighter.wargear or {} }) do
for _, n in ipairs(list) do
if SKILL.key(tostring(n)) == want then return true end
end
end
return false
end
function ACTIVATION.extraArm()
local x = CFG.extraArm
if type(x) == "table" and x.rule and ACTIVATION.hasRule(x.rule) then return x end
return nil
end
function ACTIVATION.armBlocks(key)
if (key ~= "braced_shot" and key ~= "move" and key ~= "shoot") or fighter.activation ~= "active" then return nil end
local x = ACTIVATION.extraArm()
if not x then return nil end
local used, shots = fighter.usedActions or {}, {}
for _, s in ipairs(fighter.shots or {}) do shots[s] = true end
if key == "braced_shot" then
local before = used.move and "Move" or (used.shoot or shots.shoot) and "Shoot"
if before then
return string.format("%s can't take Braced Shot after a %s this activation (%s)", fighter.name, before, x.rule)
end
elseif used.braced_shot or shots.braced_shot then
return string.format("%s can't take %s after a Braced Shot this activation (%s)", fighter.name,
key == "move" and "Move" or "Shoot", x.rule)
end
return nil
end
function ACTIVATION.escher()
local g = CFG.escherGang
if not ACTIVATION.gangIs(g) then return nil end
local _, variant = ACTIVATION.gangParts(fighter.gangType)
if variant then return ACTIVATION.gangVariant(g, variant) end
return g, tostring(g.type)
end
ACTIVATION.AGILITY_RR = { ones = "RR1", all = "RR" }
ACTIVATION.AGILITY_BAR = { ones = "RR1", all = "RR failed" }
function ACTIVATION.agilityReroll()
local g, name = ACTIVATION.escher()
local how = g and g.agility
if how ~= "ones" and how ~= "all" then how, name = nil, nil end
if how == "all" then return how, name end
for _, it in ipairs(SKILL.with("agilityReroll")) do
local h = it.agilityReroll
if h == "all" then return h, it.name end
if h == "ones" and not how then how, name = h, it.name end
end
return how, name
end
function ACTIVATION.agilityMod()
local n, by = 0, {}
for _, it in ipairs(SKILL.with("agility")) do
local m = math.floor(tonumber(it.agility) or 0)
if m ~= 0 then n, by[#by + 1] = n + m, it.name end
end
return n, by
end
function ACTIVATION.agility(o, player)
if fighter.outOfAction then return nil end
o = o or {}
local need = clamp(math.floor(tonumber(CFG.agility) or 4), 2, 6)
local gear, by = ACTIVATION.agilityMod()
local mod = math.floor(tonumber(o.mod) or 0) + gear
local how, gang = ACTIVATION.agilityReroll()
if o.pass then how, gang = nil, nil end
local test = { need = need, mod = mod, why = o.why, gang = how and gang or nil, reroll = how }
local whys = {}
if o.why then whys[#whys + 1] = o.why end
for _, n in ipairs(by) do whys[#whys + 1] = n end
local why = #whys > 0 and ", " .. table.concat(whys, ", ") or ""
local title = o.pass and string.format("Agility Test (%s)", tostring(o.pass))
or string.format("Agility Test (%d+)", math.max(1, need - mod))
local firstTitle = how and string.format("%s - %s", title, ACTIVATION.AGILITY_BAR[how]) or title
local function read(f, digital, first)
test.face, test.total, test.digital, test.rerolled = f, f + mod, digital, first
test.passed = test.total >= need or o.pass ~= nil
local ink = test.passed and COL.valueUp or COL.valueMod
local body = mod == 0 and tostring(f)
or string.format("%d %s %d = %d", f, mod > 0 and "+" or "-", math.abs(mod), test.total)
if o.pass and test.total < need then body = body .. string.format(" -- passed (%s)", tostring(o.pass)) end
chat(string.format("%s - Agility Test (%d+%s%s): %s%s", fighter.name, need, why,
first and string.format(", %s re-rolled %d", gang, first) or "", body,
digital and " (rolled digitally)" or ""), rgbOf(ink))
ACTIVATION.showDice{ title = first and title or firstTitle, kind = "d6", faces = { f }, hl = ink }
__nqs_mundane_bus.try(function()
__nqs_mundane_bus.test("Agility", { f }, "D6", {
direction = "gte", target = need, modifier = mod ~= 0 and mod or nil,
modifiers = #by > 0 and by or nil, why = o.why, height = o.height,
outcome = { passed = test.passed and true or false, total = test.total,
auto = (o.pass and test.total < need) and tostring(o.pass) or nil },
reroll = first ~= nil or nil, reroll_why = first and gang or nil, by = player,
})
end)
__nqs_mundane_bus.within("cause", { roll = "Agility" }, function()
if o.done then o.done(test.passed, test, player) end
end)
onAgilityRolled(player, test)
end
ACTIVATION.later(o.after, function()
if fighter.outOfAction then return end
local color = colorOf(player)
ACTIVATION.rolling(firstTitle)
throwDice(1, color, function(faces, digital)
local f = faces[1] or 1
if not ((how == "ones" and f == 1) or (how == "all" and f + mod < need)) then return read(f, digital) end
chat(string.format("%s - Agility Test (%d+%s): %d -- re-rolled (%s)", fighter.name, need, why, f, gang),
rgbOf(COL.valueMod))
__nqs_mundane_bus.try(function()
__nqs_mundane_bus.test("Agility", { f }, "D6", {
direction = "gte", target = need, modifier = mod ~= 0 and mod or nil,
modifiers = #by > 0 and by or nil, why = o.why, height = o.height,
outcome = { rerolled = tostring(gang) }, by = player,
})
end)
local held = { title = firstTitle, kind = "d6", faces = { f }, hl = COL.valueMod }
ACTIVATION.showDice(held)
ACTIVATION.later(held, function()
if fighter.outOfAction then return end
ACTIVATION.rolling(title)
throwDice(1, color, function(again, digital2)
read(again[1] or 1, digital or digital2, f)
end, "d6", title)
end)
end, "d6", firstTitle)
end)
return test
end
function agilityTest(mod, player)
if type(mod) == "table" then mod = mod.value end
return ACTIVATION.agility({ mod = mod }, player)
end
function ACTIVATION.flying()
if ACTIVATION.tags().flying then return "Flying" end
local b, it = ACTIVATION.jumping()
if b and b.flying then return it.name end
return nil
end
function ACTIVATION.fallAsk(player)
if fighter.outOfAction then return nil end
local fly = ACTIVATION.flying()
if fly then
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", yes = true, title = CFG.flyAsk, item = fly,
done = function(yes)
if not yes or fighter.outOfAction then return end
chat(string.format("%s is Flying (%s) -- a fall does them no harm", fighter.name, fly), rgbOf(COL.valueUp))
end })
return "asked"
end
local wings = SKILL.with("jumpDown")[1]
if wings and #SKILL.with("noFall") == 0 then
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", yes = true, title = CFG.jumpDownAsk, item = wings.name,
done = function(yes)
ACTIVATION.wings = yes and wings.name or nil
fallingDown()
end })
return "asked"
end
return fallingDown()
end
function ACTIVATION.restrain(a, player, rgb)
local aim = ACTIVATION.target(player)
if not aim then
chat(string.format("%s: %s -- no enemy selected", fighter.name, a.label), rgbOf(COL.valueMod))
return nil
end
local r = type(a.restrain) == "table" and a.restrain or {}
local ok = ACTIVATION.ask(aim.obj, "restrained", { by = fighter.name, item = a.label, test = r.test,
fail = r.fail, freeBy = r.freeBy, color = colorOf(player) })
if not ok then
chat(string.format("%s: %s -- %s's card can't be restrained (too old)", fighter.name, a.label, aim.name),
rgbOf(COL.valueMod))
return nil
end
chat(string.format("%s tries to restrain %s", fighter.name, aim.name), rgb)
flash(aim.obj, ACTIVATION.actionGlow(a.key, a.type))
return aim.name
end
function ACTIVATION.enrage(a, player, rgb)
local e = type(a.enrage) == "table" and a.enrage or {}
local range = tonumber(e.range) or 6
local list = {}
for _, o in ipairs(ACTIVATION.wholeWithin(range)) do
if (not e.needReady or o.activation == "ready") and (not e.needStatus or o.status == e.needStatus) then
list[#list + 1] = o
end
end
if #list == 0 then
chat(string.format('%s: %s -- no Ready friend wholly within %s"', fighter.name, a.label,
string.format("%g", range)), rgbOf(COL.valueMod))
return {}
end
list = ACTIVATION.nearestFirst(list)
chat(string.format("%s enrages %s", fighter.name, ACTIVATION.nameList(list)), rgb)
local t = { by = fighter.name, item = a.label, dice = e.dice, stat = e.stat, color = colorOf(player),
needReady = e.needReady, needStatus = e.needStatus }
local names = {}
for k, o in ipairs(list) do
names[k] = o.name
local function go()
flash(o.obj, ACTIVATION.actionGlow(a.key, a.type))
ACTIVATION.ask(o.obj, "enraged", t)
end
if k == 1 then go() else Wait.time(go, (k - 1) * (tonumber(CFG.enrageGap) or 3)) end
end
return names
end
function restrained(t)
if type(t) ~= "table" or fighter.outOfAction then return false end
local why = string.format("%s by %s", tostring(t.item or "Restrain"), tostring(t.by or "an enemy"))
local function failed()
local key = t.fail and tostring(t.fail)
if not (key and indexOf(CONDITIONS, key)) then return end
if t.freeBy then
ACTIVATION.timedCondition(key, 1, tostring(t.freeBy),
string.format("%s's %s", tostring(t.by or "an enemy"), tostring(t.item or "Restrain")))
else
setCondition(key, true)
chat(string.format("%s gains %s (%s)", fighter.name, CONDITIONS[indexOf(CONDITIONS, key)].label, why),
rgbOf(COL.valueMod))
end
end
local test = tostring(t.test or "agility")
if test == "agility" then
return ACTIVATION.agility({ why = why, done = function(passed) if not passed then failed() end end }, t.color) ~= nil
end
return ACTIVATION.rollTest(test, t.color, { why = why,
done = function(res) if not res.passed then failed() end end }) ~= nil
end
function enraged(t)
if type(t) ~= "table" or fighter.outOfAction then return false end
if (t.needReady and fighter.activation ~= "ready") or (t.needStatus and fighter.status ~= t.needStatus) then
return false
end
local sides = clamp(math.floor(tonumber(t.dice) or 3), 1, 6)
local stat, item = tostring(t.stat or "M"), tostring(t.item or "Enrage")
local title = string.format("%s (D%d)", item, sides)
ACTIVATION.rolling(title)
throwDice(1, t.color, function(faces, digital)
local f = faces[1] or 1
local n = math.max(1, math.ceil(f * sides / 6))
local inch = stat == "M" and '"' or ""
ACTIVATION.showDice{ title = title, kind = "d6", faces = { f }, sum = "+" .. n .. inch, sumInk = COL.valueUp }
wyrdHex({ id = "enrage", value = { label = item, by = t.by, mods = { [stat] = n }, turn = true, gear = true } })
chat(string.format("%s - %s (D%d): %d = +%d%s %s until the end of the round%s", fighter.name, item, sides, f, n,
inch, stat, digital and " (rolled digitally)" or ""), rgbOf(COL.valueUp))
end, "d6", title)
return true
end
function ACTIVATION.checked(a, player, rgb)
local function go()
if a.heal then ACTIVATION.heal(a, player, rgb) end
end
local test = ACTIVATION.rollTest(tostring(a.check), player, { why = a.label, done = function(res, roll)
if res.passed then ACTIVATION.later(roll, go) end
end })
if not test then go() end
return test
end
function ACTIVATION.voidAsk(a, player)
if ACTIVATION.voidOk == a.key then
ACTIVATION.voidOk = nil
return false
end
if not ACTIVATION.aimsAt(a) then return false end
local soul = nil
for _, e in ipairs(ACTIVATION.targets(player, true)) do soul = soul or (e.voidSoul and e) end
if not soul then return false end
chat(string.format("%s has %s -- %s can't target them with %s", soul.name, soul.voidSoul, fighter.name, a.label),
rgbOf(COL.valueMod))
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", title = CFG.voidAsk, item = soul.voidSoul, obj = soul.obj,
ink = rgbOf(COL.valueMod),
done = function(yes, _, who)
if not yes then return end
ACTIVATION.voidOk = a.key
useAction(a.key, who or player)
ACTIVATION.voidOk = nil
end })
return true
end
function ACTIVATION.boost(a, rgb)
fighter.boosted = fighter.boosted or {}
fighter.boosted[a.key] = true
local parts = {}
for _, k in ipairs({ "M", "WS", "BS", "S", "T", "W", "I", "A", "Sv", "Ld", "Cl", "Wil", "Int" }) do
local n = tonumber(a.boost[k]) or 0
if n ~= 0 then parts[#parts + 1] = string.format("%+d %s", n, k) end
end
ui.drawStats()
chat(string.format("%s - %s: %s until their next activation", fighter.name, a.label, table.concat(parts, ", ")), rgb)
return true
end
function ACTIVATION.jumping()
local key = fighter.jumping
if not key then return nil end
for _, it in ipairs(SKILL.items()) do
if it.key == key and type(it.booster) == "table" then return it.booster, it end
end
return nil
end
function ACTIVATION.boosterAsk(player, go)
local it = SKILL.with("booster")[1]
if not (it and type(it.booster) == "table" and fighter.activation == "active") then return go() end
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", yes = true, title = CFG.jumpAsk, item = it.name,
done = function(yes)
if yes and fighter.activation == "active" then
local b, parts = it.booster, {}
fighter.jumping = it.key
local stats = ACTIVATION.modsText(b.mods)
if stats ~= "" then parts[#parts + 1] = stats end
if b.flying then parts[#parts + 1] = "Flying" end
local c = type(b.charge) == "table" and b.charge or {}
local charge = {}
if tonumber(c.hit) then charge[#charge + 1] = string.format("%+d to hit", tonumber(c.hit)) end
if tonumber(c.S) then charge[#charge + 1] = string.format("%+d S", tonumber(c.S)) end
if #charge > 0 then parts[#parts + 1] = "on the charge " .. table.concat(charge, ", ") end
if b.unstable then parts[#parts + 1] = "grenades and Template weapons Unstable" end
chat(string.format("%s uses their %s: %s this activation", fighter.name, it.name,
table.concat(parts, "; ")), rgbOf(COL.valueUp))
if not ACTIVATION.traitsCheck() then
ui.drawStats()
TRAIT_RULES.drawWeapons()
end
end
go()
end })
end
function ACTIVATION.insane(player, go)
if conditionCount("insanity") <= 0 then return go() end
local title, color = "Insanity", colorOf(player)
ACTIVATION.rolling(title)
throwDice(1, color, function(faces, digital)
local f = faces[1] or 1
ACTIVATION.showDice{ title = title, kind = "d6", faces = { f } }
ACTIVATION.say(title, { tostring(f) }, f, { color = color, digital = digital })
__nqs_mundane_bus.test("Insanity", { f }, "D6", { outcome = { result = f }, by = color or player })
onInsanityRolled(player, { face = f, digital = digital })
ACTIVATION.later(ACTIVATION.roll, go)
end, "d6", title)
end
function ACTIVATION.comedown(player, go)
local was = fighter.boosted
fighter.boosted = nil
if type(was) ~= "table" or next(was) == nil then return go() end
ui.drawStats()
local due = {}
for _, a in ipairs(select(2, SKILL.split())) do
if was[a.key] then
if type(a.reaction) == "table" then due[#due + 1] = a
else chat(string.format("%s - %s wears off", fighter.name, a.label)) end
end
end
if #due == 0 then return go() end
local function limit(a) return clamp(math.floor(tonumber(a.reaction.roll) or 1), 1, 5) end
local title = #due == 1 and string.format("%s (%d+)", due[1].label, limit(due[1]) + 1) or "Bad Reactions"
ACTIVATION.rolling(title)
throwDice(#due, colorOf(player), function(faces, digital)
local hls, lost, bad1 = {}, 0, nil
for i, a in ipairs(due) do
local f = faces[i] or 1
local bad = f <= limit(a)
local had = math.max(0, (tonumber(fighter.wounds.current) or 0) - lost)
local wounds = bad and math.min(had, math.max(0, math.floor(tonumber(a.reaction.wounds) or 1))) or 0
hls[i] = bad and COL.valueMod or COL.valueUp
chat(string.format("%s - %s (%d+): %d -- %s%s", fighter.name, a.label, limit(a) + 1, f,
not bad and "wears off, no harm done"
or had <= 0 and "a bad reaction, already at 0 wounds: Injury dice"
or string.format("a bad reaction, loses %d wound%s", wounds, wounds == 1 and "" or "s"),
digital and " (rolled digitally)" or ""), rgbOf(hls[i]))
lost = lost + wounds
if bad then
bad1 = bad1 or { label = a.label, n = 0 }
bad1.n = bad1.n + math.max(1, math.floor(tonumber(a.reaction.wounds) or 1))
end
onBoostEnded(player, { key = a.key, label = a.label, face = f, bad = bad, wounds = wounds, digital = digital })
__nqs_mundane_bus.try(function()
__nqs_mundane_bus.test(tostring(a.label), { f }, "D6", { why = "comedown", direction = "gte",
target = limit(a) + 1, outcome = { passed = not bad, bad = bad or nil, wounds = wounds },
by = player })
end)
end
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, hls = hls }
if bad1 and not fighter.outOfAction then
local failed = {}
for k = 1, bad1.n do failed[k] = { dmg = 1, l = 1 } end
return __nqs_mundane_bus.within("cause", { roll = tostring(bad1.label) }, function()
return ACTIVATION.damage({ by = fighter.name, weapon = bad1.label, dodged = true, after = go },
failed, ACTIVATION.roll, player)
end)
end
ACTIVATION.later(ACTIVATION.roll, go)
end, "d6", title)
end
function ACTIVATION.spring(player)
return ACTIVATION.agility({ why = "Spring Up", done = function(passed)
if not (passed and fighter.activation == "active" and fighter.lostAction) then return end
fighter.lostAction = nil
fighter.actionsLeft = math.min(2, fighter.actionsLeft + 1)
ui.drawReady()
ui.drawActions()
chat(string.format("%s springs up -- %d action%s left", fighter.name, fighter.actionsLeft,
fighter.actionsLeft == 1 and "" or "s"), rgbOf(statusDef("active").color))
onActionsChanged(fighter.actionsLeft)
end }, player)
end
function ACTIVATION.purple(msg) chat(msg, rgbOf(COL.wyrdInk)) end
function ACTIVATION.wyrdCan()
if fighter.outOfAction or fighter.status == "seriously_injured" then return false end
if fighter.category == "wyrd" then return true end
return SKILL.hasWyrd()
end
function ACTIVATION.wyrdState()
if type(fighter.wyrd) ~= "table" then fighter.wyrd = {} end
return fighter.wyrd
end
function ACTIVATION.wyrdMark()
local on = type(fighter.wyrd) == "table" and fighter.wyrd.power ~= nil
if (conditionCount("maintaining_power") > 0) ~= on and indexOf(CONDITIONS, "maintaining_power") then
setCondition("maintaining_power", on)
end
end
function ACTIVATION.wyrdDraw()
ACTIVATION.wyrdMark()
ACTIVATION.powerMark()
SKILL.drawWyrd()
ui.drawActions()
local fire = ACTIVATION.traitsNow()
if SKILL.arm(fighter) or fire ~= ACTIVATION.fireShown then
ACTIVATION.fireShown = fire
refresh()
return
end
ui.drawStats()
TRAIT_RULES.drawWeapons()
end
function ACTIVATION.traitsNow()
local b = ACTIVATION.jumping()
return table.concat({ ACTIVATION.fireOf() or "", ACTIVATION.mantleOn() or "",
(b and b.unstable) and "unstable" or "" }, "|")
end
function ACTIVATION.traitsCheck()
local now = ACTIVATION.traitsNow()
if now == ACTIVATION.fireShown then return false end
ACTIVATION.fireShown = now
refresh()
return true
end
function ACTIVATION.mantleOn()
if fighter.activation ~= "active" or fighter.outOfAction then return nil end
local it = SKILL.with("activeMelee")[1]
return it and tostring(it.activeMelee) or nil
end
function ACTIVATION.mantleTrait(p)
if not (p and isMelee(p)) then return nil end
local trait = ACTIVATION.mantleOn()
if not trait then return nil end
local word = trimText(trait:match("^([^%(]*)") or trait):lower()
if word ~= "" and ("," .. tostring(p.traits or "") .. ","):lower():find(",%s*" .. word:gsub("%p", "%%%0") .. "[%s,%(]") then
return nil
end
return trait
end
function ACTIVATION.powerOf(key)
for _, a in ipairs(select(2, SKILL.split())) do
if a.key == key and a.type == "wyrd" and a.kind == "skill" then return a end
end
end
function ACTIVATION.continuous(a) return tostring(a.cost or ""):upper():find("/C", 1, true) ~= nil end
function ACTIVATION.maintainable()
local w = fighter.wyrd
return type(w) == "table" and w.power and ACTIVATION.powerOf(w.power) or nil
end
function ACTIVATION.wyrdRefuses(a)
if not ACTIVATION.wyrdCan() then
return string.format("%s can't use Wyrd powers right now", fighter.name)
end
if a.key == "maintain_control_s" or a.key == "maintain_control_f" then
if not ACTIVATION.maintainable() then
return string.format("%s has no Continuous power in effect -- nothing to maintain", fighter.name)
elseif fighter.activation ~= "active" then
return string.format("%s can only maintain a power during their activation", fighter.name)
end
end
return nil
end
function ACTIVATION.wyrdExpire(how)
local w = fighter.wyrd
if type(w) ~= "table" or not w.power then return end
local a = ACTIVATION.powerOf(w.power)
ACTIVATION.unhex(w)
w.power, w.cast, w.held, w.flaming, w.choosing = nil, nil, nil, nil, nil
ACTIVATION.purple(string.format("%s's %s ends%s", fighter.name, a and a.label or "Wyrd power", how or ""))
end
function ACTIVATION.wyrdStart()
local w = fighter.wyrd
if type(w) ~= "table" then return end
w.cast, w.held, w.concentrate, w.locked = nil, nil, nil, nil
if next(w) == nil then fighter.wyrd = nil end
ACTIVATION.wyrdDraw()
end
function ACTIVATION.wyrdEnd()
ACTIVATION.disruptCancel("the activation is over")
local w = fighter.wyrd
if type(w) ~= "table" then return end
if w.power and not (w.held or (w.cast and CFG.powersLastNext)) then
ACTIVATION.wyrdExpire(" with their activation")
end
w.cast, w.held, w.concentrate, w.locked = nil, nil, nil, nil
if next(w) == nil then fighter.wyrd = nil end
ACTIVATION.wyrdDraw()
end
function ACTIVATION.wyrdDrop()
ACTIVATION.disruptCancel("they can't cast any more")
if type(fighter.wyrd) ~= "table" then return end
ACTIVATION.wyrdExpire()
fighter.wyrd = nil
ACTIVATION.wyrdDraw()
end
function getWyrd()
local w = fighter.wyrd or {}
return { power = w.power, cast = w.cast == true, held = w.held == true,
concentrate = w.concentrate == true, locked = w.locked == true,
flaming = w.flaming, choosing = w.choosing == true, visions = w.visions ~= nil,
hexes = RULES.copy(fighter.hexes or {}) }
end
function ACTIVATION.concentrate()
local w = ACTIVATION.wyrdState()
local mod = tonumber(CFG.concentrateMod) or 1
ACTIVATION.purple(w.concentrate
and string.format("%s is concentrating already (%+d)", fighter.name, mod)
or string.format("%s concentrates -- %+d to Willpower checks to manifest powers until their activation ends",
fighter.name, mod))
w.concentrate = true
end
function ACTIVATION.cast(a, player)
local color = colorOf(player)
local item, aim = ACTIVATION.item(a.key), nil
if item and item.target then
local why = nil
aim, why = ACTIVATION.aimFor(item, player)
if not aim then
ACTIVATION.purple(string.format("%s's %s: %s -- it will do nothing", fighter.name, a.label, why))
end
end
local function ended(r)
r.key, r.label, r.continuous = a.key, a.label, ACTIVATION.continuous(a)
onPowerCast(player, r)
end
local function attempt(disrupted)
local w = ACTIVATION.wyrdState()
local conc = w.concentrate and (tonumber(CFG.concentrateMod) or 1) or 0
local pen = disrupted and (tonumber(CFG.disruptMod) or -2) or 0
local why = a.label .. (disrupted and string.format(", disrupted %+d", pen) or "")
.. (conc ~= 0 and string.format(", Concentrate %+d", conc) or "")
local mods = {}
if pen ~= 0 then mods[#mods + 1] = pen end
if conc ~= 0 then mods[#mods + 1] = conc end
local test = ACTIVATION.rollTest("Wil", player, { why = why, mods = mods, natural = true, label = "Manifesting",
ink = COL.wyrdInk, done = function(test, roll)
local ok, n = test.passed == true, test.natural
if fighter.outOfAction or fighter.status == "seriously_injured" then ok = false end
ACTIVATION.purple(string.format("%s %s %s%s", fighter.name, ok and "manifests" or "fails to manifest", a.label,
n and string.format(" (a natural %d)", n) or ""))
if n then ACTIVATION.purple(string.format("%s suffers Perils of the Warp!", fighter.name)) end
if ok and ACTIVATION.continuous(a) then
local st = ACTIVATION.wyrdState()
if st.power and st.power ~= a.key then ACTIVATION.wyrdExpire() end
st.power, st.cast, st.held = a.key, true, nil
ACTIVATION.wyrdDraw()
end
if ok then ACTIVATION.manifest(a, player, aim, roll) end
ended({ manifested = ok, natural = n, disrupted = disrupted or false, face = test.faces and test.total })
end })
if not test then
ACTIVATION.purple(string.format("%s has no Willpower to cast %s with", fighter.name, a.label))
ended({ manifested = false, disrupted = disrupted or false })
end
end
local foes = ACTIVATION.wyrdCan() and ACTIVATION.disrupters() or {}
if #foes == 0 then return attempt(false) end
local pending = ACTIVATION.disrupts
if not pending then pending = { n = 0 }; ACTIVATION.disrupts = pending end
pending.n = pending.n + 1
local token = pending.n
local okG, guid = pcall(function() return self.getGUID() end)
local d = { objs = {}, left = 0, cast = attempt, label = a.label }
function d.result(res)
local foeName = tostring(res.name or "an enemy Wyrd")
if res.passed and res.natural == 2 then
ACTIVATION.purple(string.format("%s disrupts %s's %s (a natural 2) -- it is not manifested",
foeName, fighter.name, a.label))
ended({ manifested = false, disrupted = true, disruptedBy = foeName, natural = nil })
elseif res.passed then
ACTIVATION.purple(string.format("%s disrupts %s's %s -- %s's Willpower check is at %+d", foeName,
fighter.name, a.label, fighter.name, tonumber(CFG.disruptMod) or -2))
attempt(true)
else
ACTIVATION.purple(string.format("%s fails to disrupt %s's %s", foeName, fighter.name, a.label))
attempt(false)
end
end
pending[token] = d
for _, foe in ipairs(foes) do
local asked, took = ACTIVATION.ask(foe.obj, "disruptAsk", { by = okG and guid or nil, token = token,
caster = fighter.name, power = a.label, color = color })
if asked and took then
d.objs[#d.objs + 1], d.left = foe.obj, d.left + 1
d.names = d.names or {}
d.names[#d.names + 1] = foe
flash(foe.obj, rgbOf(COL.wyrdInk))
end
end
if d.left == 0 then
pending[token] = nil
return attempt(false)
end
ACTIVATION.purple(string.format("%s casts %s -- %s may disrupt it", fighter.name, a.label, ACTIVATION.nameList(d.names)))
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", skip = true, title = CFG.disruptWait, item = a.label, disrupt = token,
done = function() ACTIVATION.disruptSkip(token) end })
end
function ACTIVATION.disruptOver(token)
local pending = ACTIVATION.disrupts
local d = pending and pending[token]
if not d then return nil end
pending[token] = nil
local n = ACTIVATION.nerve
if n and n.disrupt == token then closeNerve() end
return d
end
function ACTIVATION.disruptCloseAll(d, token, but)
local okG, guid = pcall(function() return self.getGUID() end)
for _, obj in ipairs(d.objs) do
local okO, g = pcall(function() return obj.getGUID() end)
if not (but and okO and g == but) then
ACTIVATION.ask(obj, "disruptClose", { by = okG and guid or nil, token = token })
end
end
end
function ACTIVATION.disruptSkip(token)
local d = ACTIVATION.disruptOver(token)
if not d then return false end
ACTIVATION.disruptCloseAll(d, token)
ACTIVATION.purple(string.format("%s skips the disruption of %s", fighter.name, d.label))
d.cast(false)
return true
end
function ACTIVATION.disruptCancel(why)
local n = 0
for token, d in pairs(ACTIVATION.disrupts or {}) do
if type(d) == "table" and ACTIVATION.disruptOver(token) then
ACTIVATION.disruptCloseAll(d, token)
ACTIVATION.purple(string.format("%s's %s is called off -- %s", fighter.name, d.label, tostring(why or "the activation is over")))
n = n + 1
end
end
return n
end
function disruptClaim(t)
local pending = ACTIVATION.disrupts
local d = type(t) == "table" and pending and pending[t.token]
if not d or d.claimed then return false end
d.claimed = tostring(t.name or "an enemy Wyrd")
ACTIVATION.disruptCloseAll(d, t.token, t.from)
ACTIVATION.purple(string.format("%s tries to disrupt %s's %s", d.claimed, fighter.name, d.label))
return true
end
function disruptDecline(t)
local pending = ACTIVATION.disrupts
local d = type(t) == "table" and pending and pending[t.token]
if not d or d.claimed then return false end
d.left = d.left - 1
if d.left > 0 then return true end
ACTIVATION.disruptOver(t.token)
ACTIVATION.purple(string.format("Nobody disrupts %s's %s", fighter.name, d.label))
d.cast(false)
return true
end
function disruptResult(t)
local d = type(t) == "table" and ACTIVATION.disruptOver(t.token)
if not d then return false end
d.result(t)
return true
end
function disruptCast(t)
if type(t) ~= "table" or not ACTIVATION.wyrdCan() or not statNumber("Wil") then return false end
return ACTIVATION.disruptRoll(t)
end
function disruptAsk(t)
if type(t) ~= "table" or not ACTIVATION.wyrdCan() or not statNumber("Wil") then return false end
local okO, caster = pcall(function() return t.by and getObjectFromGUID(t.by) end)
caster = okO and caster or nil
if ACTIVATION.roll and not ACTIVATION.roll.rolling then ACTIVATION.hideDice() end
ACTIVATION.openCheck({ test = "question", yes = true, title = CFG.disruptAsk, item = tostring(t.power or "Wyrd power"),
obj = caster, ink = rgbOf(COL.wyrdInk), disruptBy = t.by, disruptToken = t.token,
done = function(yes)
if not caster then return end
if not yes then return ACTIVATION.ask(caster, "disruptDecline", { token = t.token }) end
local okG, me = pcall(function() return self.getGUID() end)
local ok, mine = ACTIVATION.ask(caster, "disruptClaim", { token = t.token, name = fighter.name,
from = okG and me or nil })
if not (ok and mine) then
ACTIVATION.purple(string.format("%s is too late to disrupt %s's %s", fighter.name,
tostring(t.caster or "the caster"), tostring(t.power or "power")))
return
end
if not ACTIVATION.disruptRoll(t) then
ACTIVATION.ask(caster, "disruptResult", { token = t.token, name = fighter.name, passed = false })
end
end })
return true
end
function disruptClose(t)
local n = ACTIVATION.nerve
if not (type(t) == "table" and n and n.disruptToken == t.token and n.disruptBy == t.by) then return false end
closeNerve()
return true
end
function ACTIVATION.disruptRoll(t)
local title = tostring(t.power or "Wyrd power")
local test = ACTIVATION.rollTest("Wil", t.color, { why = title, natural = true, label = "Disrupt", ink = COL.wyrdInk,
done = function(test, roll)
if test.natural then
ACTIVATION.purple(string.format("%s suffers Perils of the Warp!", fighter.name))
end
ACTIVATION.later(roll, function()
local okO, caster = pcall(function() return t.by and getObjectFromGUID(t.by) end)
if okO and caster then
ACTIVATION.ask(caster, "disruptResult", { token = t.token, name = fighter.name,
passed = test.passed == true, natural = test.natural })
end
end)
end })
return test ~= nil
end
function ACTIVATION.maintain(a, player)
local w = ACTIVATION.wyrdState()
local power = ACTIVATION.maintainable()
if a.key == "maintain_control_f" then w.locked = true end
ACTIVATION.wyrdDraw()
if not power then return end
local mod = a.key == "maintain_control_s" and (tonumber(CFG.maintainMod) or 3) or 0
local test = ACTIVATION.rollTest("Wil", player, { mods = mod ~= 0 and { mod } or {}, ink = COL.wyrdInk, label = "Maintaining",
why = power.label .. ", Maintain Control" .. (mod ~= 0 and string.format(" %+d", mod) or ""),
done = function(test)
if fighter.wyrd ~= w or w.power ~= power.key or fighter.activation ~= "active" then return end
if test.passed then
w.held = true
ACTIVATION.purple(string.format("%s keeps control of %s until the end of their next activation", fighter.name, power.label))
else
ACTIVATION.purple(string.format("%s loses control of %s -- it ends with their activation", fighter.name, power.label))
end
ACTIVATION.wyrdDraw()
end })
if not test then
ACTIVATION.purple(string.format("%s has no Willpower to maintain %s with", fighter.name, power.label))
end
end
ACTIVATION.STATLINE = { "M", "WS", "BS", "S", "T", "W", "I", "A", "Sv", "Ld", "Cl", "Wil", "Int" }
function ACTIVATION.item(key)
for _, it in ipairs(SKILL.owned()) do
if it.key == key and it.kind == "skill" and it.type == "wyrd" then return it end
end
end
function ACTIVATION.liveField(field)
for _, it in ipairs(SKILL.with(field)) do
if SKILL.live(it) then return it end
end
end
function ACTIVATION.hexId(key)
local ok, g = pcall(function() return self.getGUID() end)
return tostring(ok and g or fighter.name) .. ":" .. tostring(key)
end
function ACTIVATION.modsText(mods)
local parts = {}
for _, k in ipairs(ACTIVATION.STATLINE) do
local n = tonumber((mods or {})[k]) or 0
if n ~= 0 then
parts[#parts + 1] = string.format("%+d %s", STAT.better(k, n) and math.abs(n) or -math.abs(n), k)
end
end
return table.concat(parts, ", ")
end
function ACTIVATION.auraOf()
local it = ACTIVATION.wyrdCan() and ACTIVATION.liveField("aura")
if not it then return nil end
local a, lend = it.aura, nil
for _, k in ipairs(type(a.lend) == "table" and a.lend or {}) do
local n = statNumber(k)
if n then lend = lend or {}; lend[k] = n end
end
return { { id = ACTIVATION.hexId(it.key), label = it.name, side = a.side or "friends",
range = tonumber(a.range), mods = a.mods, lend = lend } }
end
function ACTIVATION.gearAuras()
if fighter.outOfAction then return nil end
local out = nil
local ok, guid = pcall(function() return self.getGUID() end)
for _, it in ipairs(SKILL.with("aura")) do
if it.kind == "wargear" and type(it.aura) == "table" then
out = out or {}
out[#out + 1] = { id = "gear_" .. it.key .. (ok and guid and "_" .. tostring(guid) or ""), label = it.name,
side = it.aura.side or "friends", range = tonumber(it.aura.range), mods = it.aura.mods,
gear = true, once = "gear_" .. it.key }
end
end
return out
end
function ACTIVATION.allAuras()
local power, gear = ACTIVATION.auraOf(), ACTIVATION.gearAuras()
if not gear then return power end
for _, a in ipairs(power or {}) do gear[#gear + 1] = a end
return gear
end
function ACTIVATION.powerMark()
local wy = fighter.wyrd
local want = ACTIVATION.allAuras() ~= nil or ACTIVATION.liveField("rerollHits") ~= nil
or (ACTIVATION.wyrdCan() and type(wy) == "table" and wy.visions ~= nil)
local ok, has = pcall(function() return self.hasTag(CFG.wyrdTag) end)
if not ok or has == want then return end
pcall(function()
if want then self.addTag(CFG.wyrdTag) else self.removeTag(CFG.wyrdTag) end
end)
end
function ACTIVATION.flameTrait(w)
local wy = fighter.wyrd
if not (w and type(wy) == "table" and wy.flaming and w.name == wy.flaming) then return nil end
local it = ACTIVATION.liveField("flaming")
return it and tostring(it.flaming) or nil
end
function ACTIVATION.fireOf()
local wy, it = fighter.wyrd, ACTIVATION.liveField("flaming")
if not (it and type(wy) == "table" and wy.flaming) then return nil end
return tostring(wy.flaming) .. "|" .. tostring(it.flaming)
end
function ACTIVATION.flame(slot)
local w, wy, it = weaponAt(slot), fighter.wyrd, ACTIVATION.liveField("flaming")
if not (w and it and type(wy) == "table" and TRAIT_RULES.melee(w)) then return false end
wy.choosing, wy.flaming = nil, w.name
ACTIVATION.purple(string.format("%s's %s gains %s (%s)", fighter.name, TRAIT_RULES.name(w), it.flaming, it.name))
ACTIVATION.wyrdDraw()
return true
end
function ACTIVATION.unhex(w)
for guid, id in pairs((type(w) == "table" and w.hexed) or {}) do
local okS, me = pcall(function() return self.getGUID() end)
if okS and me == guid then
wyrdHex({ id = id, value = false })
else
local ok, obj = pcall(function() return getObjectFromGUID(guid) end)
if ok and obj then ACTIVATION.ask(obj, "wyrdHex", { id = id, value = false }) end
end
end
if type(w) == "table" then w.hexed = nil end
end
function ACTIVATION.manifest(a, player, aim, roll)
local it = ACTIVATION.item(a.key)
if not it then return end
local P, name, st = ACTIVATION.purple, fighter.name, ACTIVATION.wyrdState()
local parts = {}
local stats = ACTIVATION.modsText(it.maintained)
if stats ~= "" then parts[#parts + 1] = stats end
if tonumber(it.meleeL) then parts[#parts + 1] = string.format("%+d L to melee weapons", tonumber(it.meleeL)) end
if type(it.weapon) == "table" and ACTIVATION.continuous(a) then
parts[#parts + 1] = "equipped with " .. tostring(it.weapon.name or it.name)
end
if it.rerollHits then parts[#parts + 1] = "enemies re-roll their ranged hits" end
if tonumber(it.void) then parts[#parts + 1] = string.format('at Long range to enemies within %s"', it.void) end
if #parts > 0 then
P(string.format("%s's %s: %s%s", name, it.name, table.concat(parts, ", "),
ACTIVATION.continuous(a) and " while it lasts" or ""))
end
if it.flaming then
local melee = {}
for i = 1, weaponCount() do
if TRAIT_RULES.melee(weaponAt(i)) then melee[#melee + 1] = i end
end
if #melee == 0 then
P(string.format("%s has no melee weapon for %s", name, it.name))
elseif #melee == 1 then
ACTIVATION.flame(melee[1])
else
st.choosing = true
P(string.format("%s: click a melee weapon to give it %s (%s)", name, tostring(it.flaming), it.name))
TRAIT_RULES.drawGlows()
end
end
if type(it.aura) == "table" then
local au, names = it.aura, ACTIVATION.auraPush()
local who = (au.side == "enemies" and "enemies" or au.side == "all" and "fighters" or "friends")
.. (tonumber(au.range) and string.format(' within %s"', au.range) or "")
local what = {}
for _, k in ipairs(type(au.lend) == "table" and au.lend or {}) do
if statNumber(k) then what[#what + 1] = string.format("%s %d", k, statNumber(k)) end
end
local text = #what > 0 and string.format("%s may use %s's %s", who, name, table.concat(what, " and "))
or string.format("%s to %s", ACTIVATION.modsText(au.mods), who)
P(string.format("%s's %s: %s while it lasts%s", name, it.name, text,
#names > 0 and " -- " .. ACTIVATION.nameList(names) or ""))
end
if type(it.area) == "table" then
local ar, names = it.area, ACTIVATION.areaHex(it)
local text = ar.oneAction and "one action when activated this round"
or ACTIVATION.modsText(ar.mods) .. " until the end of the round"
P(string.format("%s's %s: %s -- %s", name, it.name, text,
#names > 0 and ACTIVATION.nameList(names)
or string.format('nobody within %s"', tostring(ar.range or "range"))))
end
if type(it.visions) == "table" then
local key = tostring(it.visions.condition or "insanity")
local c = CONDITIONS[indexOf(CONDITIONS, key) or 0]
st.visions = { range = tonumber(it.visions.range) or 3, condition = key, label = it.name }
P(string.format('%s\'s %s: an enemy ending their activation within %s" of %s gains %s this round', name, it.name,
tostring(st.visions.range), name, c and c.label or key))
end
if type(it.target) == "table" then ACTIVATION.hexTarget(it, aim, player, roll) end
ACTIVATION.powerMark()
end
function ACTIVATION.hexTarget(it, aim, player, roll)
local tg, P = it.target, ACTIVATION.purple
if not aim then return end
local purple = rgbOf(COL.wyrdInk)
local function go()
if type(tg.hit) == "table" then
local s = tonumber(tg.hit.S)
P(string.format("%s's %s hits %s (S%s, AP %s, L%s)", fighter.name, it.name, aim.name, tostring(tg.hit.S or "-"),
tonumber(tg.hit.AP) and tonumber(tg.hit.AP) ~= 0 and tostring(tg.hit.AP) or "-", tostring(tg.hit.L or "-")))
flash(aim.obj, purple)
if s and aim.t then
local okG, guid = pcall(function() return aim.obj.getGUID() end)
local okS, mine = pcall(function() return self.getGUID() end)
local ap = tonumber(tg.hit.AP)
rollWounds({ hits = 1, s = s, t = aim.t, weapon = it.name, target = aim.name, by = fighter.name,
guid = okG and guid or nil, from = okS and mine or nil,
ap = ap and ap < 0 and -ap or 0 }, player)
end
return
end
if type(tg.base) == "table" then
local st = ACTIVATION.wyrdState()
local live = st.power == it.key
if live then ACTIVATION.unhex(st) end
local id = ACTIVATION.hexId(it.key)
local ok, took = ACTIVATION.ask(aim.obj, "wyrdHex", { id = id,
value = { label = it.name, by = fighter.name, base = tg.base, turn = not live or nil } })
if not (ok and took) then return end
local okG, guid = pcall(function() return aim.obj.getGUID() end)
if live and okG and guid then st.hexed = { [guid] = id } end
local set = {}
for _, k in ipairs(ACTIVATION.STATLINE) do
local n = tonumber(tg.base[k])
if n then set[#set + 1] = string.format("%s %d%s", k, n, STAT_ROLLS[k] and not STAT_ROLLS[k].under and "+" or "") end
end
P(string.format("%s's %s: %s's %s before modifiers%s", fighter.name, it.name, aim.name, table.concat(set, " and "),
live and " while it lasts" or " until the end of the round"))
flash(aim.obj, purple)
return
end
local ok = ACTIVATION.ask(aim.obj, "wyrdTarget", { by = fighter.name, power = it.name, color = colorOf(player),
suppress = tg.suppress, test = tg.test, ifReady = tg.ifReady, needReady = tg.needReady, fail = tg.fail,
needStatus = tg.needStatus, out = tg.out })
if ok then flash(aim.obj, purple) end
end
if not tg.roll then return ACTIVATION.later(roll, go) end
ACTIVATION.later(roll, function()
local test = ACTIVATION.rollTest(tostring(tg.roll), player, { why = it.name .. " vs " .. aim.name, ink = COL.wyrdInk,
done = function(test, r)
if test.passed then return ACTIVATION.later(r, go) end
P(string.format("%s's %s misses %s", fighter.name, it.name, aim.name))
end })
if not test then P(string.format("%s has no %s for %s", fighter.name, tostring(tg.roll), it.name)) end
end)
end
function wyrdTarget(t)
if type(t) ~= "table" or fighter.outOfAction then return false end
local P, name = ACTIVATION.purple, fighter.name
local power, by = tostring(t.power or "a Wyrd power"), tostring(t.by or "an enemy Wyrd")
if t.needStatus and fighter.status ~= t.needStatus then
P(string.format("%s isn't %s -- %s does nothing", name, statusDef(t.needStatus).label, power))
return false
end
if t.out then
__nqs_mundane_bus.within("cause", { action = power }, function()
setOutOfAction({ value = true, why = string.format("%s by %s", power, by) })
end)
return true
end
if t.needReady and fighter.activation ~= "ready" then
P(string.format("%s isn't Ready -- %s does nothing", name, power))
return false
end
if t.suppress then
if fighter.status == "active" then
setStatus({ key = "suppressed", quiet = true })
P(string.format("%s is Suppressed by %s's %s", name, by, power))
else
P(string.format("%s isn't Active -- %s's %s doesn't Suppress them", name, by, power))
end
end
local test = t.test
if test and t.ifReady and fighter.activation ~= "ready" then test = nil end
if not test then return true end
local function failed()
if t.fail == "unready" then
local left = fighter.activation == "ready" and ACTIVATION.loseMark(tostring(power))
if left then
P(string.format("%s loses %s (%s)", name,
left > 0 and string.format("a Ready marker, %d left", left) or "their Ready marker", power))
end
elseif t.fail and indexOf(CONDITIONS, t.fail) then
setCondition(t.fail, true)
P(string.format("%s gains %s (%s)", name, CONDITIONS[indexOf(CONDITIONS, t.fail)].label, power))
end
end
if test == "nerve" then
P(string.format("%s must take a Nerve Check (%s)", name, power))
nerveCheck(t.color)
elseif test == "agility" then
ACTIVATION.agility({ why = power, done = function(passed) if not passed then failed() end end }, t.color)
elseif not ACTIVATION.rollTest(tostring(test), t.color, { why = power, ink = COL.wyrdInk,
done = function(res) if not res.passed then failed() end end }) then
P(string.format("%s has no %s to test -- %s does nothing", name, tostring(test), power))
end
return true
end
function wyrdHex(t)
if type(t) ~= "table" or t.id == nil then return false end
local id = tostring(t.id)
if type(t.value) ~= "table" then
if not (fighter.hexes and fighter.hexes[id]) then return false end
fighter.hexes[id] = nil
if next(fighter.hexes) == nil then fighter.hexes = nil end
else
if fighter.outOfAction then return false end
fighter.hexes = fighter.hexes or {}
fighter.hexes[id] = RULES.copy(t.value)
end
ui.drawStats()
return true
end
function ACTIVATION.turnOver()
ACTIVATION.readyReliables()
local changed = false
for id, h in pairs(fighter.hexes or {}) do
if h.turn then fighter.hexes[id], changed = nil, true end
end
if fighter.hexes and next(fighter.hexes) == nil then fighter.hexes = nil end
local w = fighter.wyrd
if type(w) == "table" and w.visions then
w.visions = nil
if next(w) == nil then fighter.wyrd = nil end
ACTIVATION.powerMark()
end
if changed then ui.drawStats() end
end
function ACTIVATION.frozen()
for _, h in pairs(fighter.hexes or {}) do
if h.oneAction then return tostring(h.label or "a Wyrd power") end
end
return nil
end
function ACTIVATION.wyrdMoved()
if ACTIVATION.auraOf() then ACTIVATION.auraPush() end
if ACTIVATION.gearAuras() or fighter.gearHexed then ACTIVATION.gearPush() end
ACTIVATION.auraPull()
end
function setMaintained(t, player)
local key, on = t, player
if type(t) == "table" then key, on = t.key, t.value else player = nil end
local a = ACTIVATION.powerOf(tostring(key or ""))
if not (a and ACTIVATION.continuous(a)) then return nil end
local st = ACTIVATION.wyrdState()
if on == nil or type(on) ~= "boolean" then on = st.power ~= a.key end
if not on then
if st.power == a.key then
ACTIVATION.wyrdExpire(" (set by hand)")
ACTIVATION.wyrdDraw()
end
return false
end
if st.power == a.key then return true end
if not ACTIVATION.wyrdCan() then
ACTIVATION.purple(string.format("%s can't use Wyrd powers right now", fighter.name))
return false
end
if st.power then ACTIVATION.wyrdExpire() end
st.power, st.cast, st.held = a.key, fighter.activation == "active" or nil, nil
ACTIVATION.purple(string.format("%s maintains %s (set by hand)", fighter.name, a.label))
ACTIVATION.wyrdDraw()
ACTIVATION.manifest(a, player, nil, nil)
return true
end
function ACTIVATION.fightBackAsk(t, why)
local b = { from = t.from, by = t.by, why = why, state = "asking" }
ACTIVATION.back = b
local ok, obj = pcall(function() return t.from and getObjectFromGUID(t.from) end)
obj = ok and obj or nil
b.obj = obj
chat(string.format("%s is taken Out of Action by %s -- they may Fight Back first", fighter.name,
ACTIVATION.fromText(t)), rgbOf(COL.valueMod))
ACTIVATION.backQuestion(b, "Fight Back?",
"%s fights back -- one attack with a melee or Light weapon, then Out of Action")
local okG, me = pcall(function() return self.getGUID() end)
if obj and okG then ACTIVATION.ask(obj, "fightBackWait", { guid = me }) end
end
function ACTIVATION.backQuestion(b, title, said)
b.state = "asking"
ACTIVATION.openCheck({ test = "question", yes = true, keep = true, fightBack = true, title = title,
obj = b.obj, ink = rgbOf(COL.valueMod),
done = function(yes)
if ACTIVATION.back ~= b then return end
if not yes then return ACTIVATION.backOut() end
b.state = "armed"
chat(string.format(said, fighter.name), rgbOf(COL.valueMod))
TRAIT_RULES.drawGlows()
end })
TRAIT_RULES.drawGlows()
end
function ACTIVATION.extraWeapon(w)
for _, p in ipairs((type(w) == "table" and w.profiles) or {}) do
if (isMelee(p) or hasTrait(p, TRAIT.light)) and TRAIT_RULES.aa(p) then return true end
end
return false
end
function ACTIVATION.backDone()
local b = ACTIVATION.back
if not b then return false end
if not b.extra and not ACTIVATION.extraWeapon(b.weapon) then
for i = 1, weaponCount() do
local w = weaponAt(i)
if w and w ~= b.weapon and ACTIVATION.extraWeapon(w) then
b.extra, b.token, b.weapon = true, nil, nil
ACTIVATION.backQuestion(b, "Additional Attacks?",
"%s fights back with Additional Attacks -- then Out of Action")
return true
end
end
end
return ACTIVATION.backOut()
end
function ACTIVATION.backOut()
local b = ACTIVATION.back
if not b then return false end
ACTIVATION.back = nil
local n = ACTIVATION.nerve
if n and n.fightBack then closeNerve() end
setOutOfAction{ value = true, why = b.why }
TRAIT_RULES.drawGlows()
return true
end
ACTIVATION.backs = {}
function fightBackWait(t)
local g = type(t) == "table" and t.guid or t
local ok, obj = pcall(function() return g and getObjectFromGUID(g) end)
if not (ok and obj) then return false end
ACTIVATION.backs[tostring(g)] = obj
return true
end
function ACTIVATION.backsEnd()
local all = ACTIVATION.backs
if not next(all) then return end
ACTIVATION.backs = {}
local ok, me = pcall(function() return self.getGUID() end)
for _, obj in pairs(all) do ACTIVATION.ask(obj, "fightBackEnd", { from = ok and me or nil }) end
end
function fightBackEnd(t)
local b = ACTIVATION.back
local from = type(t) == "table" and t.from or nil
if not b or (from and b.from and from ~= b.from) or b.state == "striking" then return false end
return ACTIVATION.backOut()
end
function getFightBack() return ACTIVATION.back and ACTIVATION.back.state or nil end
function ACTIVATION.endQuestion()
local n = ACTIVATION.nerve
if n and n.test == "question" and not n.cover and not n.fightBack and not n.blast then closeNerve() end
end
function fallingDown(height)
local wings = ACTIVATION.wings
ACTIVATION.wings = nil
if fighter.outOfAction then return nil end
local chute = SKILL.with("noFall")[1]
if chute then
chat(string.format("%s has a %s -- a fall does them no harm", fighter.name, chute.name), rgbOf(COL.valueUp))
return 0
end
if type(height) == "table" then height = height.value end
local h = clamp(math.floor(tonumber(height) or (CFG.fallLevels or {})[1] or 3), 1, ACTIVATION.FALL_MAX)
ACTIVATION.openCheck({ test = "height", title = "Falling Down", stat = "Height", value = h, wings = wings })
return h
end
function ACTIVATION.fall(player)
local n = ACTIVATION.nerve
if not (n and n.test == "height") or fighter.outOfAction then return nil end
closeNerve()
local height = n.value
ACTIVATION.agility({ why = "Falling Down", pass = n.wings, height = height, done = function(passed, test, who)
__nqs_mundane_bus.within("cause", { action = "Falling Down" }, function()
ACTIVATION.land(height, passed, test, who or player)
end)
end }, player)
return height
end
function ACTIVATION.land(height, passed, test, player)
if fighter.outOfAction then return end
local levels = type(CFG.fallLevels) == "table" and CFG.fallLevels or {}
local low, high = tonumber(levels[1]) or 3, tonumber(levels[2]) or 6
local left = height - (passed and (tonumber(CFG.fallSave) or 3) or 0)
local level = left <= 0 and 0 or left < low and 1 or left <= high and 2 or 3
local catfall = #SKILL.with("catfall") > 0
local lowered = catfall and level > 1
if lowered then level = level - 1 end
local line = string.format('%s falls %g"', fighter.name, height)
if passed then line = line .. string.format(', counting as %g"', math.max(0, left)) end
if lowered then line = line .. ", a level less with Catfall" end
local fall = { height = height, counted = math.max(0, left), level = level, catfall = catfall,
passed = passed == true }
if level == 0 then
chat(line .. " -- no harm done", rgbOf(COL.valueUp))
onFallen(player, fall)
return
end
if level >= 2 then
local had = tonumber(fighter.wounds.current) or 0
line = line .. (had > 0 and " -- loses 1 wound" or " -- already at 0 wounds")
chat(line, rgbOf(COL.valueMod))
if had > 0 then setWounds(had - 1) end
else
chat(line, rgbOf(COL.valueMod))
end
onFallen(player, fall)
if level >= 3 then
setOutOfAction({ value = true, why = string.format('a fall of more than %g"', high) })
elseif level == 2 and ui.hpOut() then
ACTIVATION.later(test and ACTIVATION.roll, function() ACTIVATION.fallInjury(catfall, player) end)
else
ACTIVATION.fallEnd(catfall, player)
end
end
function ACTIVATION.fallInjury(catfall, player)
if fighter.outOfAction then return end
local color = colorOf(player)
local title = ACTIVATION.rollName("injury", 1)
ACTIVATION.rolling(title)
throwDice(1, color, function(faces, digital)
local k = ACTIVATION.INJURY_DICE[faces[1]] or "serious"
local R = ACTIVATION.INJURY[k]
ACTIVATION.say("Falling Down (Injury dice)", {}, R.short, { color = color, digital = digital })
ACTIVATION.showDice{ title = title, kind = "injury", faces = faces, result = k }
__nqs_mundane_bus.try(function()
local dice = __nqs_mundane_bus.diceArray(faces, "INJURY")
if dice[1] then dice[1].used = true end
__nqs_mundane_bus.test("Injury", faces, "INJURY", { dice = dice, why = "Falling Down", chooser = "auto",
outcome = { result = k }, by = color or player })
end)
__nqs_mundane_bus.within("cause", { action = "Falling Down" }, function()
if fighter.outOfAction then return end
if k == "out" then
setOutOfAction({ value = true, why = "injured by the fall" })
return
end
if k == "serious" and fighter.status ~= "seriously_injured" then setStatus("seriously_injured") end
ACTIVATION.fallEnd(catfall, player)
end)
end, "injury", title)
end
function ACTIVATION.fallEnd(catfall, player)
if fighter.outOfAction then return end
local function down()
if fighter.outOfAction then return end
if fighter.status == "active" then setStatus("suppressed") end
if fighter.activation == "active" then completeActivation(player) end
end
if not catfall or fighter.status ~= "active" then return down() end
ACTIVATION.agility({ why = "Catfall", after = ACTIVATION.roll, done = function(passed)
if not passed then return down() end
chat(string.format("%s lands on their feet -- not Suppressed", fighter.name), rgbOf(COL.valueUp))
end }, player)
end
ACTIVATION.SHORT = { M = "Mov" }
function ACTIVATION.actionTitle(a, parts, short)
if a.distanceTitle then return a.distanceTitle end
local name = string.format("%s (%s)", a.label, SKILL.costOf(a) or "")
if not parts or #parts == 0 then return name end
local t = name .. " - " .. table.concat(parts, " + ")
if short and not SKILL.titleFits(t) then t = name .. " - " .. table.concat(short, " + ") end
return t
end
function ACTIVATION.moveBy(a, player, rgb, head)
if type(a.lines) == "table" and not a.distance then
ACTIVATION.showDice{ title = ACTIVATION.actionTitle(a), faces = {}, lines = a.lines }
chat(head .. " - " .. table.concat(a.lines, ", "), rgb)
return nil
end
local stats, full, short, total, dice, scaled = {}, {}, {}, 0, 0, false
local list = type(a.distance) == "table" and a.distance or {}
for _, d in ipairs(list) do
local what, times = tostring(d[1] or d.stat or ""), tonumber(d[2] or d.times) or 1
local x = times ~= 1 and string.format("%g x ", times) or ""
full[#full + 1] = x .. (STAT.NAMES[what] or what)
short[#short + 1] = x .. (ACTIVATION.SHORT[what] or what)
if what:upper() == "D6" then
dice = dice + math.max(0, math.floor(times))
else
local v = statNumber(what) or 0
total, scaled = total + times * v, scaled or times ~= 1
stats[#stats + 1] = string.format("%s%g%s", x, v, (what == "M" or #list == 1) and '"' or "")
end
end
local title = ACTIVATION.actionTitle(a, #list == 1 and full or short, short)
local function show(faces, digital)
local sum = total
for _, f in ipairs(faces) do sum = sum + f end
local lead = #stats > 0 and table.concat(stats, " + ") or nil
local result = nil
if #stats + #faces > 1 or scaled or #faces > 0 then
if #faces > 0 then lead, result = lead and lead .. " +", string.format('= %g"', sum)
else lead = string.format('%s = %g"', lead, sum) end
end
ACTIVATION.showDice{ title = title, kind = "d6", faces = faces, lead = lead, sum = result, inline = true }
chat(string.format('%s - %g"%s', head, sum, digital and " (rolled digitally)" or ""), rgb)
if #faces > 0 then
__nqs_mundane_bus.send({
kind = "roll",
action = tostring(a.key or "move"),
fighter = fighter and fighter.name or nil,
dice = __nqs_mundane_bus.diceArray(faces, "D6"),
direction = nil,
outcome = { inches = sum, base = total, dice_sum = sum - total },
label = a.label and tostring(a.label) or nil,
by = player,
})
end
return sum
end
if dice == 0 then return show({}) end
ACTIVATION.rolling(title)
throwDice(math.min(dice, ACTIVATION.MAX_SHOWN), colorOf(player), show, "d6", title)
return nil
end
function ACTIVATION.escape(a, player)
if fighter.outOfAction then return false end
local need = tonumber(a.escape) or 3
local title = string.format("%s (%d+)", a.label, need)
ACTIVATION.rolling(title)
throwDice(1, colorOf(player), function(faces, digital)
local face = tonumber(faces[1]) or 1
local cold = face >= need
local ink = cold and COL.valueUp or COL.valueMod
ACTIVATION.showDice{ title = title, kind = "d6", faces = { face }, hl = ink, inline = true,
sum = cold and "Out Cold" or "Out of Action", sumInk = ink }
chat(string.format("%s - %s: %d (%d+)%s", fighter.name, a.label, face, need,
digital and " (rolled digitally)" or ""), rgbOf(ink))
__nqs_mundane_bus.test(tostring(a.label), { face }, "D6", { direction = "gte", target = need,
outcome = { passed = cold, result = cold and "out_cold" or "out_of_action" }, by = player })
__nqs_mundane_bus.within("cause", { roll = tostring(a.label) }, function()
setOutOfAction{ value = true, why = a.label, cold = cold }
end)
end, "d6", title)
return true
end
function ACTIVATION.coup(player, again)
if fighter.outOfAction then return false end
local aim = again and again.aim or ACTIVATION.target(player)
local s = statNumber("S") or 0
local mod, gang = ACTIVATION.gangMod(CFG.coupGang)
local what = again and "Coup de Grace (Cut-Throat)" or "Coup de Grace"
local tags = {}
if mod ~= 0 then tags[#tags + 1] = string.format("%+d", mod) end
if again then tags[#tags + 1] = "Cut-Throat" end
local title = "Coup de Grace" .. (#tags > 0 and " (" .. table.concat(tags, ", ") .. ")" or "")
local color = colorOf(player)
ACTIVATION.coupThrow({ title = title, s = s, mod = mod, color = color, done = function(f, mine, digital, roll)
local r = { face = f, s = s, mod = mod ~= 0 and mod or nil, total = mine, digital = digital,
rerolled = again ~= nil or nil }
local own = string.format("%d + %dS%s = %d", f, s,
mod ~= 0 and string.format(" %s %d %s", mod > 0 and "+" or "-", math.abs(mod), gang) or "", mine)
local duel = { player = player, aim = aim, r = r, own = own, what = what, color = color }
if not aim then
announce(string.format("%s - Coup de Grace: %s%s", fighter.name, own,
digital and " (rolled digitally)" or ""), color)
__nqs_mundane_bus.test("Coup de Grace", { f }, "D6", { strength = s, modifier = mod ~= 0 and mod or nil,
outcome = { total = mine }, by = color or player })
ACTIVATION.showDice(roll)
onCoupRolled(player, r)
elseif again then
local ink = mine >= again.foe.total and COL.valueUp or COL.valueMod
roll.hls, roll.sumInk = { ink }, ink
ACTIVATION.showDice(roll)
ACTIVATION.coupEnd(duel, again.foe)
else
ACTIVATION.showDice(roll)
ACTIVATION.later(roll, function() ACTIVATION.coupAsk(duel) end)
end
end })
return true
end
function ACTIVATION.coupThrow(o)
ACTIVATION.rolling(o.title)
throwDice(1, o.color, function(faces, digital)
local f = faces[1] or 1
local total = f + o.s + o.mod
local lead = string.format("%d Strength +", o.s)
if o.mod ~= 0 then
lead = string.format("%d Strength %s %d +", o.s, o.mod > 0 and "+" or "-", math.abs(o.mod))
end
o.done(f, total, digital, { title = o.title, kind = "d6", faces = { f }, sum = "∑" .. total, lead = lead })
end, "d6", o.title)
end
function ACTIVATION.coupAsk(duel)
if fighter.outOfAction then return end
local pending = ACTIVATION.coups
if not pending then pending = { n = 0 }; ACTIVATION.coups = pending end
pending.n = pending.n + 1
local token = pending.n
pending[token] = function(foe) ACTIVATION.coupEnd(duel, foe) end
local okG, guid = pcall(function() return self.getGUID() end)
local aim, warn = duel.aim, rgbOf(COL.valueMod)
local can = ACTIVATION.has(aim.obj, "coupDefend")
local asked, took = false, nil
if can then
asked, took = ACTIVATION.ask(aim.obj, "coupDefend", { by = okG and guid or nil, token = token,
attacker = fighter.name, total = duel.r.total, color = duel.color })
end
if not (asked and took) then
pending[token] = nil
chat(string.format(can and "%s's card couldn't roll -- its die is rolled on %s's card"
or "%s's card is out of date and can't roll for itself -- its die is rolled on %s's card"
.. " (cards are brought up to date by the Controller's next round, or by importing again)",
aim.name, fighter.name), warn)
return ACTIVATION.coupHere(duel)
end
Wait.time(function()
if not pending[token] then return end
pending[token] = nil
chat(string.format("%s's card didn't answer -- its die is rolled on %s's card", aim.name, fighter.name), warn)
ACTIVATION.coupHere(duel)
end, (tonumber(CFG.diceWait) or 45) + 15)
end
function ACTIVATION.coupHere(duel)
local aim, mine = duel.aim, duel.r.total
local s = tonumber(aim.s) or 0
ACTIVATION.coupThrow({ title = "Coup de Grace: " .. aim.name, s = s, mod = 0, color = duel.color,
done = function(f, theirs, digital, roll)
local ink = theirs > mine and COL.valueUp or COL.valueMod
roll.hls, roll.sumInk = { ink }, ink
ACTIVATION.showDice(roll)
ACTIVATION.coupEnd(duel, { face = f, s = s, total = theirs, digital = digital, roll = roll })
end })
end
function ACTIVATION.coupEnd(duel, foe)
local aim, r, player = duel.aim, duel.r, duel.player
local ff, foeS, theirs = tonumber(foe.face) or 1, tonumber(foe.s) or 0, tonumber(foe.total) or 0
r.target, r.foeFace, r.foeS, r.foeTotal, r.out = aim.name, ff, foeS, theirs, r.total >= theirs
local reroll = not r.out and not r.rerolled and #SKILL.with("cutThroat") > 0
local ink = r.out and COL.valueUp or COL.valueMod
chat(string.format("%s - %s vs %s: %s against %d + %dS = %d%s%s", fighter.name, duel.what, aim.name, duel.own,
ff, foeS, theirs, r.out and "" or reroll and " -- rolled again with Cut-Throat"
or string.format(" -- %s holds on", aim.name), (r.digital or foe.digital) and " (rolled digitally)" or ""),
rgbOf(ink))
__nqs_mundane_bus.try(function()
local okG, guid = pcall(function() return aim.obj.getGUID() end)
local dice = __nqs_mundane_bus.diceArray({ r.face, ff }, "D6")
if dice[1] and dice[2] then dice[1].as, dice[2].as = "attacker", "defender" end
__nqs_mundane_bus.test("Coup de Grace", nil, nil, {
dice = dice, strength = r.s, modifier = r.mod, target_fighter = aim.name, target_guid = okG and guid or nil,
target_strength = foeS, reroll = r.rerolled, reroll_why = r.rerolled and "Cut-Throat" or nil,
outcome = { passed = r.out, total = r.total, foe_total = theirs, out_of_action = r.out,
cut_throat = reroll or nil },
by = duel.player or duel.color,
})
end)
if r.out then
ACTIVATION.ask(aim.obj, "setOutOfAction", { value = true, why = "Coup de Grace by " .. fighter.name })
end
onCoupRolled(player, r)
if reroll then
local theirRoll = { face = ff, s = foeS, total = theirs, digital = foe.digital }
local function go() ACTIVATION.coup(player, { aim = aim, foe = theirRoll }) end
if foe.roll then ACTIVATION.later(foe.roll, go) else Wait.time(go, CFG.dicePause or CFG.diceShow) end
end
end
function coupDefend(t)
if type(t) ~= "table" or not tonumber(t.total) or fighter.outOfAction then return false end
local s, mine = statNumber("S") or 0, tonumber(t.total)
ACTIVATION.coupThrow({ title = "Coup de Grace by " .. tostring(t.attacker or "?"), s = s, mod = 0, color = t.color,
done = function(f, total, digital, roll)
local ink = total > mine and COL.valueUp or COL.valueMod
roll.hls, roll.sumInk = { ink }, ink
ACTIVATION.showDice(roll)
local okO, by = pcall(function() return t.by and getObjectFromGUID(t.by) end)
if okO and by then
ACTIVATION.ask(by, "coupResult", { token = t.token, face = f, s = s, total = total, digital = digital })
end
end })
return true
end
function coupResult(t)
local pending = ACTIVATION.coups
local f = type(t) == "table" and pending and pending[t.token]
if not f then return false end
pending[t.token] = nil
f(t)
return true
end
function statTestPasses(test, total)
if test.under then return total <= test.target end
return total >= test.target
end
function getLooks()
local t = {}
for _, k in ipairs(MODEL.LOOKS_KEYS) do t[k] = looks[k] end
return t
end
function setLooks(t)
applyLooks(t)
pcall(function() self.setGMNotes(MODEL.notesWithLooks(self.getGMNotes(), MODEL.formatLooks(getLooks()))) end)
if ui.built then refresh() end
return getLooks()
end
function reloadLooks()
local ok, notes = pcall(function() return self.getGMNotes() end)
applyLooks(ok and MODEL.parseLooks(notes) or nil)
if ui.built then refresh() end
return getLooks()
end
function clearLooks()
pcall(function() self.setGMNotes(MODEL.notesWithLooks(self.getGMNotes(), nil)) end)
return reloadLooks()
end
function setAsset(params)
if type(params) ~= "table" or not params.name then return false end
dynamicAssets[params.name] = params.url or ""
refresh()
return true
end
function showUI(flag)
ui.visible = (flag ~= false)
if ui.built then setAttr("mundaRoot", "active", ui.visible) else refresh() end
return ui.visible
end
function toggleUI() return showUI(not ui.visible) end
function RULES.fetch()
local ok, objs = pcall(function() return getObjectsWithTag(CFG.controllerTag) end)
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
local okC, t = ACTIVATION.ask(obj, "getRules")
if okC and type(t) == "table" then return t end
end
return nil
end
function loadRules()
local function rest()
local out = {}
for part in pairs(RULES.PARTS) do out[part] = RULES.copy(RULES[part]) end
for _, k in ipairs({ "performanceMode", "performanceFor", "qualityFor" }) do out.cfg[k] = nil end
return out
end
local before = rest()
if not RULES.use(RULES.fetch()) then return false end
if RULES.same(before, rest()) then return true end
SKILL.arm(fighter)
if ui.built then ui.why = "rules"; refresh() end
return true
end
__nqs_mundane_bus.card = { setFighter = setFighter }
__nqs_mundane_bus.card.STATE = { hp = true, status = true, condition = true, out_of_action = true }
function __nqs_mundane_bus.try(fn, ...)
local ok, err = pcall(fn, ...)
if not ok and not __nqs_mundane_bus.card.failed then
__nqs_mundane_bus.card.failed = true
pcall(function() log("Mundane card: a bus publish failed, the game goes on: " .. tostring(err)) end)
end
end
function __nqs_mundane_bus.who(p)
if p == nil or p == "" or p == "nil" then return nil end
if type(p) == "table" and p.scripted then return p.by or p.color end
local ok, n = pcall(function()
local pl = p
if type(p) == "string" then
pl = nil
for _, q in ipairs(Player.getPlayers()) do if q.color == p then pl = q end end
if not pl then return p end
end
local s = pl.steam_name
if type(s) == "string" and s ~= "" then return s end
return pl.color
end)
if ok and type(n) == "string" and n ~= "" then return n end
return type(p) == "string" and p or nil
end
function __nqs_mundane_bus.clickerColor(clicker)
local c = __nqs_mundane_bus.card
return colorOf(clicker or c.by or c.last)
end
function __nqs_mundane_bus.send(ev)
local c = __nqs_mundane_bus.card
if ev.fighter == nil and fighter then ev.fighter = fighter.name end
local clicker = c.by or ev.by
if clicker ~= nil then c.last = clicker end
ev.by = __nqs_mundane_bus.who(clicker)
if ev.player == nil then ev.player = __nqs_mundane_bus.clickerColor(clicker) end
if ev.kind == "state_change" and c.STATE[ev.field or ""] and ev.attack_id == nil and ev.cause == nil
and not ev.replay then
if c.attack and os.time() - (c.attackAt or 0) <= (tonumber(CFG.seqStale) or 120) then
ev.attack_id = c.attack
elseif c.cause then ev.cause = c.cause end
end
__nqs_mundane_bus.emit(ev)
end
function __nqs_mundane_bus.test(label, faces, die, ev)
ev = ev or {}
ev.kind, ev.label = "roll", label
ev.action = ev.action or tostring(label):lower()
ev.dice = ev.dice or __nqs_mundane_bus.diceArray(faces or {}, die or "D6")
if type(ev.outcome) ~= "table" or next(ev.outcome) == nil then
local total = 0
for _, f in ipairs(faces or {}) do total = total + (tonumber(f) or 0) end
ev.outcome = { total = total }
end
__nqs_mundane_bus.send(ev)
end
function __nqs_mundane_bus.readiness(why)
if not fighter then return end
local c = __nqs_mundane_bus.card
local now = fighter.activation or "activated"
local key = now .. "|" .. tostring(fighter.grouped == true) .. "|" .. tostring(fighter.readyMarks)
if c.readyKey ~= nil and c.readyKey ~= key then
__nqs_mundane_bus.send({ kind = "state_change", action = "readiness", field = "readiness",
from = c.ready, to = now, grouped = fighter.grouped and true or nil,
ready_marks = tonumber(fighter.readyMarks), why = why or c.why })
end
c.readyKey, c.ready = key, now
end
__nqs_mundane_bus.card.ATTACKS = { fight = true, shoot = true, braced_shot = true, aimed_shot = true }
function __nqs_mundane_bus.action(player, key, params, target, free)
local a = ACTIONS[indexOf(ACTIONS, key) or 0] or SKILL.action(key)
if not params and __nqs_mundane_bus.card.ATTACKS[tostring(key)] then return end
local aims = a and not params and ACTIVATION.aimsAt(a)
if target == nil and aims then
local names = {}
for i, e in ipairs(ACTIVATION.targets(player, true, a.heal ~= nil)) do names[i] = tostring(e.name) end
if aims == "one" then target = names[1]
elseif #names > 0 then params = params or {}; params.targets = names end
end
if free == nil and a and not params then free = SKILL.cost(a) == 0 or nil end
__nqs_mundane_bus.send({ kind = "action", action = a and a.label and tostring(a.label) or tostring(key),
key = tostring(key), target = target, params = params, free = free, by = player })
end
function publishState()
local n = 0
local function put(ev)
ev.kind, ev.replay = "state_change", true
ev.action = ev.action or ev.field
__nqs_mundane_bus.send(ev)
n = n + 1
end
put({ field = "status", to = fighter.status })
put({ field = "hp", to = tonumber(fighter.wounds.current) or 0, max = tonumber(fighter.wounds.max) })
put({ field = "out_of_action", to = fighter.outOfAction == true, out_cold = fighter.outCold or nil })
for key, k in pairs(fighter.conditions or {}) do
local i = indexOf(CONDITIONS, key)
put({ field = "condition", key = tostring(key), to = tonumber(k) or 1,
label = i and CONDITIONS[i].label or nil })
end
put({ field = "readiness", to = fighter.activation or "activated", grouped = fighter.grouped and true or nil,
ready_marks = tonumber(fighter.readyMarks) })
put({ field = "actions_left", to = tonumber(fighter.actionsLeft) or 0, activation = fighter.activation })
for i = 1, 10 do
local w = weaponAt(i)
for k, p in ipairs(w and type(w.profiles) == "table" and w.profiles or {}) do
local st = (p.ammo == "out" or p.ammo == "jam" or p.ammo == "spent") and p.ammo or nil
if st or p.reliableUsed then
put({ field = "weapon", weapon = tostring(TRAIT_RULES.name(w) or w.name or i),
profile = tostring(p.name or k), to = st or "fine",
reliable_used = p.reliableUsed and true or nil })
end
end
end
for key, on in pairs(fighter.burnt or {}) do
if on then put({ field = "item", item = tostring(key), to = "burnt" }) end
end
for key, on in pairs(fighter.usedOnce or {}) do
if on then put({ field = "item", item = tostring(key), to = "used" }) end
end
return n
end
function __nqs_mundane_bus.scripted(t)
if type(t) ~= "table" or not (type(t.targets) == "table" or t.by ~= nil) then return nil end
return { targets = type(t.targets) == "table" and t.targets or {}, by = t.by ~= nil and tostring(t.by) or nil,
color = type(t.color) == "string" and t.color or nil, scripted = true }
end
function __nqs_mundane_bus.selection(player)
if type(player) ~= "table" or not player.scripted then return nil end
local out = {}
for _, g in ipairs(player.targets or {}) do
local ok, obj = pcall(function() return getObjectFromGUID(tostring(g)) end)
if ok and obj then out[#out + 1] = obj end
end
return true, out
end
function __nqs_mundane_bus.attackId(seq, from)
if seq == nil or seq == "" then return nil end
if from == nil or from == "" then
local ok, g = pcall(function() return self.getGUID() end)
from = ok and g or "?"
end
return tostring(from) .. ":" .. tostring(seq)
end
function __nqs_mundane_bus.within(field, v, fn)
local c = __nqs_mundane_bus.card
local was = c[field]
c[field] = v
local ok, r = pcall(fn)
c[field] = was
if not ok then error(r, 0) end
return r
end
function __nqs_mundane_bus.hitRoll(attack, faces, outcome, target, targets, by, why)
local b = attack.bus or {}
local id = __nqs_mundane_bus.attackId(attack.seq)
local names
if type(targets) == "table" and #targets > 0 then
names = {}
for i, n in ipairs(targets) do names[i] = tostring(n) end
end
__nqs_mundane_bus.send({
kind = "roll", action = "hit roll", label = "Hit",
dice = __nqs_mundane_bus.hitDice(faces, b.kinds or {}, b.ammo),
direction = "gte", weapon = b.weapon, target = b.need,
target_fighter = target ~= nil and tostring(target) or nil, targets = names,
outcome = outcome or { rerolled = why or "re-roll" },
reroll = b.reroll and true or nil, reroll_why = b.reroll,
attack_id = id, group = id, by = by,
})
if not outcome then b.reroll = why or "re-roll" return end
local f = b.ammo and faces[b.ammo]
if f and b.ammoNeed then
__nqs_mundane_bus.send({
kind = "roll", action = "ammo roll", label = "Ammo",
dice = { { type = "D6", value = f, face = tostring(f), as = "ammo" } },
direction = "gte", weapon = b.weapon, target = b.ammoNeed,
outcome = { passed = f >= b.ammoNeed, spared = outcome.spared, state = outcome.state },
attack_id = id, group = id, by = by,
})
end
end
function __nqs_mundane_bus.hitDice(faces, kinds, ammo)
local out = {}
for i, f in ipairs(faces) do
if i ~= ammo then
local fp = kinds[i] == "firepower"
out[#out + 1] = { type = fp and "FIREPOWER" or "D6", value = f,
face = fp and __nqs_mundane_bus.faceOf("FIREPOWER", f) or tostring(f),
as = fp and "firepower" or "hit" }
end
end
return out
end
function __nqs_mundane_bus.injuryPools(faces, sizes, kindOf, best)
local rank = best and { injured = 1, serious = 2, out = 3 } or { out = 1, serious = 2, injured = 3 }
local all, sum = {}, 0
for i, n in ipairs(sizes or {}) do all[i], sum = n, sum + n end
if sum < #faces then all[#all + 1] = #faces - sum end
local pools, at = {}, 1
for _, n in ipairs(all) do
if at > #faces then break end
local p = { faces = {} }
for _ = 1, n do
if at > #faces then break end
p.faces[#p.faces + 1] = faces[at]
at = at + 1
end
for i, f in ipairs(p.faces) do
local k = kindOf(f) or "serious"
if not p.used or rank[k] < rank[p.result] then p.used, p.result = i, k end
end
pools[#pools + 1] = p
end
return pools
end
for _, name in ipairs({ "send", "test", "hitRoll", "readiness", "action" }) do
local fn = __nqs_mundane_bus[name]
__nqs_mundane_bus[name] = function(...) __nqs_mundane_bus.try(fn, ...) end
end
function __nqs_mundane_bus.statChanged(field, key, from, to)
if field == "statline" then
from, to = from ~= nil and tostring(from) or nil, to ~= nil and tostring(to) or nil
end
if from == to then return end
__nqs_mundane_bus.send({
kind = "state_change", action = field,
fighter = fighter and fighter.name or nil,
field = field, key = tostring(key), from = from, to = to,
})
end
function setFighter(data)
local done = __nqs_mundane_bus.card.setFighter(data)
__nqs_mundane_bus.card.hp = fighter.wounds.current
__nqs_mundane_bus.card.actionsLeft = fighter.actionsLeft
__nqs_mundane_bus.card.readyKey = nil
__nqs_mundane_bus.readiness()
return done
end
function onStatusChanged(key, label)
end
function onActionChosen(player, key)
__nqs_mundane_bus.action(player, key)
end
function onActionsChanged(left)
local c, to = __nqs_mundane_bus.card, tonumber(left) or 0
if c.actionsLeft ~= nil and c.actionsLeft ~= to then
__nqs_mundane_bus.send({
kind = "state_change", action = "actions_left",
fighter = fighter and fighter.name or nil,
field = "actions_left", from = c.actionsLeft, to = to,
activation = fighter and fighter.activation or nil,
})
end
c.actionsLeft = to
__nqs_mundane_bus.readiness()
end
function onConditionChanged(key, count, before)
end
function onWoundsChanged(current, max)
local c, to = __nqs_mundane_bus.card, tonumber(current) or 0
if c.hp ~= nil and c.hp ~= to then
__nqs_mundane_bus.send({
kind = "state_change", action = "hp",
fighter = fighter and fighter.name or nil,
field = "hp", from = c.hp, to = to, max = tonumber(max),
})
end
c.hp = to
end
function onWeaponAttack(player, attack)
end
function onAttackRolled(player, r)
end
function onWoundsRolled(player, r)
end
function onSavesRolled(player, r)
end
function onDamaged(player, r)
end
function onTraitHit(t)
end
function onReloadRolled(player, r)
end
function onAmmoChecked(test, reloaded)
end
function onBoostEnded(player, r)
end
function onInsanityRolled(player, r)
end
function onProfileChanged(weapon, profile, p)
end
function onStatRoll(player, test)
end
function onRecoveryRolled(player, result, faces)
end
function onNerveRolled(player, test)
end
function onGroupRolled(player, test)
end
function onAgilityRolled(player, test)
end
function onFallen(player, fall)
end
function onPowerCast(player, r)
end
function onCoupRolled(player, r)
end
function onFirepowerRolled(player, fp)
end
function onInjuriesRolled(player, results, faces)
end
function checkLineOfSight(targetObject)
return nil
end
function onSave()
return JSON.encode({
fighter = fighter,
visible = ui.visible,
importId = ui.importId,
})
end
function onLoad(savedState)
local restored = nil
if savedState and savedState ~= "" then
local ok, data = pcall(function() return JSON.decode(savedState) end)
if ok and type(data) == "table" then restored = data end
end
if restored and restored.visible ~= nil then ui.visible = restored.visible end
local fresh = type(IMPORTED) == "table" and IMPORTED.fighter
and not (restored and restored.importId == IMPORTED.id)
local data = fresh and IMPORTED.fighter or (restored and restored.fighter)
ui.importId = fresh and IMPORTED.id or (restored and restored.importId)
ACTIVATION.imported = type(IMPORTED) == "table" and type(IMPORTED.fighter) == "table"
and RULES.copy(IMPORTED.fighter) or nil
local okN, notes = pcall(function() return self.getGMNotes() end)
applyLooks(okN and MODEL.parseLooks(notes) or nil)
local wait = ui.buildTurn()
if wait > 0 then ui.hold = true end
Wait.frames(function()
RULES.use(RULES.fetch())
ui.fetchPlaying()
setFighter(data)
currentBase()
engage.spot = positionOf(self)
ACTIVATION.powerMark()
end, 1)
if wait > 0 then
Wait.time(function()
ui.hold = nil
if ui.holdPending then ui.holdPending = nil; refresh() end
end, wait)
end
end
function onPickUp(playerColor)
if not engage.pending then engage.spot = positionOf(self) or engage.spot end
end
function onDrop(playerColor)
engage.token, engage.pending = engage.token + 1, true
local token, frames, from = engage.token, 0, engage.spot
local function go()
if token ~= engage.token then return end
local okH, held = pcall(function() return self.held_by_color end)
if okH and held then return end
if CFG.autoEngage then checkEngagement() end
ACTIVATION.wyrdMoved()
ACTIVATION.gangMoved(from)
end
Wait.condition(go, function()
frames = frames + 1
if token ~= engage.token then return true end
local ok, still = pcall(function() return self.resting end)
return frames > 2 and (not ok or still == true)
end, CFG.engageSettle, go)
end
]=]

-- ===========================================================================
-- Everything below this line is updater/updater.lua, pasted unchanged.
-- ===========================================================================

--[[ =========================================================================
  SELF-UPDATE BLOCK for keeping tools hosted via Github up to date.
  Source: https://github.com/Antaresx101/TTS_tools   (MIT)

  When using any of my tools with this functionality, in TabletopSimulator,
  typing "!update" in the chat as the host will automatically update all such
  tools in the session with the newest version (if it isn´t on it already).

  A tool is one file. Where it has an on-screen UI, that layout travels
  inside the script and goes on when the object loads, so an update is one
  download and one write, and cannot leave half a tool behind.

  Nothing happens until you ask. Loading a mod sends no requests and changes no
  scripts, it is triggered manually always.
========================================================================== ]]

-- CONFIG -- running someone else's tool and want it left exactly where it is:
-- Stop Updates permanently: set SELF_UPDATE to false and nothing below ever runs.
-- Adopting the block: set the three TOOL_ values.
-- Forking the repo: change REPO_BASE, the only string here that names a host.
local SELF_UPDATE    = false
local REPO_BASE      = "https://raw.githubusercontent.com/feuerfritas/antares-tts-tools/main"
local TOOL_ID        = "mundane-importer"
local TOOL_VERSION   = "3.1.0"                 -- bumped with manifest.json
local TOOL_SIGNATURE = "TTS-SELFUPDATE:mundane-importer"

-- Fixed conventions. MIN_BYTES only has to be large enough to throw out error
-- pages and truncated bodies; any file carrying this block is usually bigger
-- than that. scripts/validate.py enforces it at publish time.
local MIN_BYTES     = 1024
local APPLY_TIMEOUT = 20                       -- seconds to wait for a safe moment
local UI_FRAMES     = 5                        -- frames a layout takes to go live
local SPREAD        = 8                        -- seconds to smear checks across
local CHAT_COMMAND  = "!update"                -- host types it, every copy hears
local LABEL         = "[" .. TOOL_ID .. "] "   -- four tools, four named voices

local function report(msg)   -- host console only; never chat for everyone
  print("[" .. TOOL_ID .. " " .. TOOL_VERSION .. "] " .. msg)
end

local function url(file)     -- ?ts= defeats the ~5 minute raw.github cache
  return REPO_BASE .. "/tools/" .. TOOL_ID .. "/" .. file .. "?ts=" .. os.time()
end

-- Plain X.Y.Z only; a suffix such as "-rc1" is ignored. Each part has to stay
-- under 1000, which holds for every version this repo will ever publish.
local function rank(v)
  local a, b, c = string.match(tostring(v), "^(%d+)%.(%d+)%.(%d+)")
  return (tonumber(a) or 0) * 1000000 + (tonumber(b) or 0) * 1000 + (tonumber(c) or 0)
end

-- Every release newer than this copy, newest first, as the lines that hang
-- under the update message: a copy that sat out three releases sees all
-- three on update, thats why the manifest carries a history. Notes are one string
-- or a list of them; anything else renders as nothing.
local function whatsNew(m)
  local out = ""
  local function add(r)
    if type(r) ~= "table" or rank(r.version) <= rank(TOOL_VERSION) then return end
    local notes = type(r.notes) == "string" and { r.notes } or r.notes
    if type(notes) ~= "table" then return end
    for _, n in ipairs(notes) do out = out .. "\n  - " .. tostring(n) end
  end
  add(m.stable)
  for _, r in ipairs(type(m.history) == "table" and m.history or {}) do add(r) end
  return out
end

-- One message per tool: three dice rollers on a table are three scripts that
-- cannot see each other, so the first to speak leaves what it said here and
-- the rest read it and keep quiet. Two strings named after this tool are all
-- the block does with Global: one for an install, one for whichever answer.
local GLOBAL_KEY = "SELFUPDATE_" .. string.gsub(TOOL_ID, "%W", "_")
local function once(suffix, value, msg)
  local key = GLOBAL_KEY .. suffix
  local ok, said = pcall(function() return Global.getVar(key) end)
  if ok and said == value then return end
  pcall(function() Global.setVar(key, value) end)
  broadcastToAll(msg, {0.6, 0.9, 0.6})
end

-- Writes the new script and reloads only while the object is idle. If it never
-- goes idle we still write, and the new script starts on the next load. The
-- tool's UI rides inside the script, so there is nothing else here to write.
local function apply(code, version, notes)
  local function idle()
    return self.held_by_color == nil and not self.isSmoothMoving()
       and not self.spawning
  end
  local function commit(withReload)
    -- Carry the tool's own saved state across the reload, if it keeps any.
    pcall(function()
      if type(onSave) == "function" then self.script_state = onSave() end
    end)
    self.setLuaScript(code)              -- WRITE: the only script write, on self
    once("", version, LABEL .. "updated to v" .. version .. notes)
    if withReload then
      self.reload()                  -- self is invalid after this line
    else
      report("v" .. version .. " written; it starts on the next load")
    end
  end
  Wait.condition(function() commit(true) end, idle, APPLY_TIMEOUT,
                 function() commit(false) end)
end

-- The loop guard: writing back what is already running would reload forever.
-- One file is the whole tool now, so one comparison covers it.
local function install(code, version, notes)
  if code == self.getLuaScript() then
    return report("already running this code")
  end
  apply(code, version, notes)
end

local function onPayload(req, version, notes)
  if req.is_error or req.response_code ~= 200 then return end   -- silently
  local code = req.text or ""
  -- Three of the four gates: long enough, signed for this tool, and whole.
  -- The loop guard is the fourth. Any failure leaves the object as it is.
  if #code < MIN_BYTES then return report("rejected: shorter than MIN_BYTES") end
  if not string.find(code, TOOL_SIGNATURE, 1, true) then
    return report("rejected: TOOL_SIGNATURE missing")
  end
  -- The block's last function, named in halves so this line cannot match
  -- itself: the payload carries this file too, and a search for the whole
  -- literal would find the search. Finding the real one proves the body
  -- arrived to its last line rather than stopping somewhere in the middle.
  if not string.find(code, "function Updater_" .. "stateVersion", 1, true) then
    return report("rejected: cut short before the end of the block")
  end
  install(code, version, notes)
end

-- Answers: the repository is not there (offline, blocked, moved, private, 404),
-- or nothing needs fetching because this copy is the published one.
-- Once per tool per asking, either way. A manifest that arrives but will not
-- parse goes to the host console instead: the repository is alive so it´s on that author.
local function onManifest(req)
  if req.is_error or req.response_code ~= 200 then
    return once("_ANSWER", "offline", LABEL .. "could not reach its repository ("
                .. tostring(req.error or req.response_code) .. ")")
  end
  local ok, m = pcall(JSON.decode, req.text)
  if not ok or type(m) ~= "table" or type(m.stable) ~= "table" then
    return report("manifest unreadable")
  end
  local version = tostring(m.stable.version)
  if rank(version) <= rank(TOOL_VERSION) then            -- nothing to fetch
    return once("_ANSWER", "current", LABEL .. "up to date at v" .. TOOL_VERSION)
  end
  local notes = whatsNew(m)
  WebRequest.get(url("tool.lua"), function(r) onPayload(r, version, notes) end)
end

-- Seconds to hold this object's request for: over 0, under SPREAD, the same
-- number every session for any one object. Folded by hand because this Lua
-- rejects tonumber(guid, 36), and math.random belongs to the tool above.
local function stagger()
  local guid, n = tostring(self.getGUID() or ""), 0
  for i = 1, #guid do n = (n * 31 + string.byte(guid, i)) % 100003 end
  return (n % (SPREAD * 100 - 1) + 1) / 100
end

-- One check, now. The chat command calls this, and so can the tool above:
-- from its own code, or from Global with obj.call("Updater_check"). The tool
-- needs no call of its own for the command below to work.
function Updater_check()
  if not SELF_UPDATE then return end
  -- A fresh ask, a fresh answer: every copy clears the flag in this frame,
  -- long before the first reply can come back.
  pcall(function() Global.setVar(GLOBAL_KEY .. "_ANSWER", "") end)
  Wait.time(function() WebRequest.get(url("manifest.json"), onManifest) end,
            stagger())
end

-- The tool's UI, spliced in above this block as TOOL_XML by scripts/validate.py
-- and applied here rather than kept on the object. One file, one write: an
-- update cannot land half a tool, because there are no halves. The tool's own
-- onLoad runs first, so whatever it registers - the custom assets a layout
-- names by image="", for one - is in place before the layout that wants them.
-- A tool with no UI declares no TOOL_XML and this does nothing at all.
local toolLoad = onLoad
function onLoad(saved)
  if type(toolLoad) == "function" then toolLoad(saved) end
  if not TOOL_XML then return end
  self.UI.setXml(TOOL_XML)                        -- WRITE: the only UI write
  -- setXml is queued, and the elements it creates are not addressable in this
  -- frame or the next: setValue and setAttribute on them do nothing, and say
  -- nothing. A tool that fills its layout in at load does that from onUIReady
  -- and never has to guess a delay of its own - this is the only place that
  -- number lives, so getting it wrong is one edit rather than one per tool.
  if type(onUIReady) == "function" then Wait.frames(onUIReady, UI_FRAMES) end
end

-- Chat reaches object scripts, not just the Global one, so every copy on the
-- table hears the host's command for itself and checks itself: no object ever
-- speaks to another, and nothing has to be added to the Global script. The
-- only thing read out of chat is whether the line is exactly CHAT_COMMAND from
-- someone with admin. Whatever onChat the tool above defined is captured here
-- and still called with everything, so this cannot eat a tool's own commands.
local toolChat = onChat
function onChat(message, player)
  if SELF_UPDATE and message == CHAT_COMMAND and player and player.admin then
    Updater_check()
  end
  if type(toolChat) == "function" then return toolChat(message, player) end
end

-- Optional migration hook. Returns the version that wrote the saved state and
-- the version running now; do any migrating in the tool above, not here.
function Updater_stateVersion(saved)
  local ok, t = pcall(JSON.decode, saved or "")
  local v = (ok and type(t) == "table") and t.version or nil
  return v, TOOL_VERSION
end
