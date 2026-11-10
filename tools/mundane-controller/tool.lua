-- TTS-SELFUPDATE:mundane-controller
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
local CONTROLLER_NAME = "Mundane Controller"
local VERSION = "?"
local TEAM_TAG = "Mundane Team_"
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
local DICE = {
URL = { d6 = "https://steamusercontent-a.akamaihd.net/ugc/14438694407390139777/F5A3307604C00D6896ACC7B82B6735BD024137EA/", firepower = "https://steamusercontent-a.akamaihd.net/ugc/14511214079636238699/82E750A272596F79249868C7DD4611B69FF6D099/", injury = "https://steamusercontent-a.akamaihd.net/ugc/14681495304683522636/208E2C4C0EF8613F91ACC93C75BDDF1493D6926E/" },
PLAIN = "Die_6",
BELOW = 150, DROP = 4, SPIN = 18, PUSH = 3, STEP = 1.4, SCALE = 1,
SORT = "thrown", TURN = { d6 = 0, firepower = 180, injury = 180 },
APART = 4,
JOIN = 1, NEXT = 1.5, WAIT = 12, MAX = 20,
FALL = 0.3, KICK = 10,
TAG = "Mundane Dice",
NAMES = { d6 = "D6", firepower = "Firepower Dice", injury = "Injury Dice" },
CHART = { firepower = RULES.firepower, injury = RULES.injuryDice },
}
local PANEL = { scale = "0.65 0.65 0.65" }
local STAND = { ANGLE = 30, EDGE = 0.1, UP = 0.08 }
local TEXT_DETAIL = 0.625
local DIE_ICON = "https://steamusercontent-a.akamaihd.net/ugc/12001738551517573707/F2E806437431BEE65DD78832C9C5A286D327A301/"
local ART = {
EDGE = "https://steamusercontent-a.akamaihd.net/ugc/13432909356284909624/B129FFCF81BACF983676DFEE7F7E71473280818C/",
FRAME = "https://steamusercontent-a.akamaihd.net/ugc/14782607483565015523/5A66DA23DFB6BD38FFD1692D8E5F435717D1134D/",
GEAR = "https://steamusercontent-a.akamaihd.net/ugc/15954717134150489158/6BDE2A9CBC8AAB39A1F736EC3D0FE7F48135CB60/",
GLOW = "https://steamusercontent-a.akamaihd.net/ugc/10558683540636189568/3D8BEC2610F94004B0610B97A0918B132C8CC70F/",
EDGE_ART = 2, FRAME_SIZE = 1.25,
}
local LOOK = {
GOLD = "#D6AC5E",
FILL = "#141312",
TEXT = "#ECE6D8",
DIM = "#AAA08C",
NOTE = "#D4CAB2",
HEAD = "#FFD696",
NUMBER = "#FFC46E",
GLOW = "#FFAA3C8C",
DIAMOND = "#2C2F31|#3A3E41|#232527|#2C2F31",
RULE = "#D6AC5EA0",
RULE_TEXT = "#ECE6D88C",
SEP = "#D6AC5E5A",
LINE = 3, ACCENT = 6, THIN = 1.5, EDGE = 2,
HOVER = "#00000000|#FFFFFF14|#FFFFFF26|#00000000",
}
LOOK.BUTTONS = {
plain = { fill = "#18191A", line = LOOK.GOLD, ink = LOOK.TEXT },
gold = { fill = LOOK.GOLD, line = LOOK.GOLD, ink = "#181614" },
red = { fill = "#461210", line = "#E65040", ink = "#FFE2D6" },
dim = { fill = "#18191A", line = "#8A7143", ink = LOOK.DIM },
}
local DEPLOY = {
SIZES = { 36, 48 },
MESH = {
{ apart = 12 },
{ apart = 9 },
{ apart = 6 },
{ "https://steamusercontent-a.akamaihd.net/ugc/10092366485938643157/EC4AE7C3A22A7992247C69CB6DACFEDC84E9D9D1/" },
{ [36] = "https://steamusercontent-a.akamaihd.net/ugc/11206213002289756367/4DF70CBC090DC00C5E9D858DECDC1596D1AC6DC7/", [48] = "https://steamusercontent-a.akamaihd.net/ugc/14901986283498053462/860B9F2091FEC5F9F208A65E4283AE2E44B59C26/" },
{ [36] = "https://steamusercontent-a.akamaihd.net/ugc/13098037441717208909/3DC8C380D146624771AFEFDDAAFECB2BF927589D/", [48] = "https://steamusercontent-a.akamaihd.net/ugc/14622491162696696273/939F03CD3519AB9EB6CE1AC54A7D3473C80C4343/" },
},
ZONE = "https://steamusercontent-a.akamaihd.net/ugc/17711522206232040145/473C795DE47225D6B3AE455CD0DAE400D1BF1AD7/",
BASE = 36,
COLLIDER = "https://steamusercontent-a.akamaihd.net/ugc/9590185350319248742/E1ACACACB191CDC4F0211AC33E42B34B043DBD19/",
TINT = { r = 0x81 / 255, g = 0, b = 1, a = 100 / 255 },
MATERIAL = 3,
TURN = 90, STEP = 0.5,
TAG = "Mundane Deployment",
turn = 0, tall = 1,
objs = {},
}
local HOMEBREW = {
SETS = {
{ id = "slow_dice", off = "Fast Dice Speed", name = "Slow Dice Speed", gameplay = true,
offDesc = "A roll that follows another (the Wound roll after the Hit roll, the saves after it) waits 3 s.",
desc = "A roll that follows another (the Wound roll after the Hit roll, the saves after it) waits 4.5 s.",
rules = { cfg = { dicePause = 4.5 } } },
{ id = "pre_measure", off = "No Pre-Measuring", name = "Allow Pre-Measuring", gameplay = true,
offDesc = "Nothing shows who is in range before an action is taken: distances are judged by eye.",
desc = "The cursor on Group Activation or Distribute Ammo highlights friendly fighters within range.",
rules = { cfg = { preMeasure = true } } },
{ id = "performance", off = "Quality Mode", name = "Performance Mode", gameplay = true,
offDesc = "The UI Card dynamically rotates with the camera.",
desc = "The UI Card updates once after rotating the camera.",
perPlayer = { on = "performanceFor", off = "qualityFor" },
rules = { cfg = { performanceMode = true } } },
{ id = "long_powers", off = "RAW Continuous Powers", name = "Long Continuous Powers",
offDesc = "A Continuous Power lasts until the end of the Wyrd's activation (if not Maintain Control (S)).",
desc = "A Continuous Power lasts until the end of the Wyrd's next activation.",
rules = { cfg = { powersLastNext = true } } },
{ id = "shock_natural", off = "Modified Shock/Knockback", name = "Natural Shock/Knockback",
offDesc = "The Hit roll's modifiers count for Shock (X+) and Knockback (X+): (6+) with +1 to hit triggers on a 5.",
desc = "Only the die counts for Shock (X+) and Knockback (X+): (6+) triggers on a natural 6 alone.",
rules = { cfg = { shockNatural = true } } },
{ id = "rapid_one_hit", off = "Rapid Fire has Hit-Rolls", name = "Rapid Fire has 1 Hit-Roll",
offDesc = "A Shock hit at Rapid Fire makes every hit's Wound roll an automatic 6.",
desc = "A Shock hit at Rapid Fire makes only the first hit's Wound roll an automatic 6.",
rules = { cfg = { rapidOneHit = true } } },
{ id = "unstable_one", off = "Unstable: Rapid Fire", name = "Unstable: One Hit",
offDesc = "A natural 1 on an Unstable weapon's Hit roll: every hit the Firepower dice show goes to the shooter.",
desc = "A natural 1 on an Unstable weapon's Hit roll: 1 hit on the shooter.",
rules = { cfg = { unstableAll = false } } },
{ id = "hand_heavy", off = "Hand Weapon (no melee / no light)", name = "Hand Weapon (no melee)",
offDesc = "A fighter with neither a Melee nor a Light weapon fights with a Hand Weapon (E, S, AP -, L 1, Melee).",
desc = "A fighter with no Melee weapon fights with a Hand Weapon (E, S, AP -, L 1, Heavy, Melee), Light weapons or not.",
rules = { cfg = { handWeapon = { light = false, profiles = {
{ SR = "E", LR = "-", S = "S", AP = "-", L = "1", traits = "Heavy, Melee" } } } } } },
},
on = {},
pick = {},
page = false,
colours = {},
scope = "me",
you = nil,
HEAD = 84, FOOT = 80, ACCENT = 46, SUB = 40, SUB_FONT = 22, DIV_UP = 24,
TITLE = 50, TITLE_FONT = 30, BACK = { -150, 24, -46, 64 }, BACK_FONT = 18,
RADIO_W = 316, RADIO_H = 38, RADIO_GAP = 14, RADIO_FONT = 19,
DESC = 62, DESC_W = 640, DESC_H = 40, DESC_FONT = 17, SEP_UP = 8, SEP_W = 620,
APPLY_W = 520, APPLY_H = 48, APPLY_UP = 24, APPLY_FONT = 22,
SCOPE_W = 220, SCOPE_H = 32, SCOPE_FONT = 17,
}
local PANEL_W, PANEL_H = 1480, 714
local LAYOUT = {
SIDES = { { 10, 70, 500, 642 }, { 980, 70, 1470, 642 } },
MID = { 554, 10, 926, 642 },
SIDE_CUT = { 40, 40, 40, 40 }, SIDE_ACCENT = 46,
MID_CUT = { 56, 56, 20, 20 }, MID_ACCENT = 40,
LINKS = { 210, 470 }, LINK_DOT = 7,
RAIL = { 656, 704 }, RAIL_GAP = 8, RAIL_CUT = 16, RAIL_FONT = 18, FEEDBACK_W = 44, MARK = "✉", MARK_FONT = 24, MARK_DETAIL = 2,
SIDE = {
NAME = 44, NAME_W = 380, NAME_H = 64, NAME_FONT = 32, NAME_MIN = 14,
NAME_RULE = 78, RULE_W = 300,
VP_HEAD = 118, VP = 218, VP_FONT = 150, VP_HIT = { 90, 300 }, HEAD_FONT = 24,
HINT = 200, HINT_GAP = 44, HINT_FONT = 30,
VP_RULE = 308,
ROLE = { -95, 328, 95, 366 }, ROLE_CUT = 10, ROLE_FONT = 22,
BOTTLE = 424, HEAD_W = 240,
DICE = 496, LD_X = -112, LD_FONT = 30, VAL_X = -32, ROLL_X = 58,
PLATE = { -170, 396, 170, 552 }, PLATE_CUT = 14,
SPLIT = {
X = 116, GANG = 406, GANG_W = 150, GANG_FONT = 16,
XBTN = { 76, 394, 100, 418 }, XFONT = 16,
HEAD = 434, HEAD_FONT = 20, HEAD_W = 190,
DICE = 500, R = 30, LD_X = -78, LD_FONT = 24, VAL_X = -16, VAL_FONT = 26, ROLL_X = 58,
PLATE = { -104, 388, 104, 546 }, RULE = { 396, 538 },
},
},
ROUND = {
INFO_H = 30, INFO_CUT = 14, INFO_GAP = 8, INFO_FONT = 17,
CAPTION = 94, CAPTION_FONT = 46, RULE_IN = 32, RULE_GAP = 92,
GEAR = 342, GEAR_SIZE = 320, GLOW_SIZE = 260, RING = 116, FONT = 222, DROP = 6, HIT = 240,
END = { -100, 542, 100, 590 }, END_CUT = 12, END_FONT = 24,
NOTE = 616, NOTE_W = 320, NOTE_H = 46, NOTE_FONT = 21,
},
}
function STAND.point(x, y, up)
local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
local a = math.rad(STAND.ANGLE)
local along = (y + PANEL_H / 2) * k
up = up or 0
return -x * k, STAND.EDGE + along * math.sin(a) + up * math.cos(a), -along * math.cos(a) + up * math.sin(a)
end
function STAND.place()
local x, y, z = STAND.point(0, 0, STAND.UP)
PANEL.position = string.format("%.6g %.6g %.6g", x * 100, z * 100, -y * 100)
PANEL.rotation = string.format("%g 0 180", STAND.ANGLE)
end
STAND.place()
local turn = 0
local vp, vpNames = { 0, 0 }, { "Player 1", "Player 2" }
local TEAM = {
gangs = { {}, {} },
NAMES = { "Alpha", "Omega" },
shown = {},
tagged = {},
dropper = {},
drops = 0,
told = nil,
hover = { token = 0 },
LINGER = 0.6,
}
local SHAPE = {
parts = {},
CUT = { 12, 0, 12, 0 },
MIN = 9,
}
function SHAPE.at(x, y)
return string.format('offsetXY="%g %g"', x - PANEL_W / 2, PANEL_H / 2 - y)
end
function SHAPE.line(a, b, w, color, e0, e1, id)
local dx, dy = b[1] - a[1], b[2] - a[2]
local len = math.sqrt(dx * dx + dy * dy)
if len < 1e-6 then return "" end
e0, e1 = e0 or 0, e1 or 0
local x = (a[1] + b[1]) / 2 + dx / len * (e1 - e0) / 2
local y = (a[2] + b[2]) / 2 + dy / len * (e1 - e0) / 2
local deg = math.deg((math.atan2 or math.atan)(-dy, dx))
if deg > 90 then deg = deg - 180 elseif deg <= -90 then deg = deg + 180 end
local art = ART.EDGE ~= ""
return string.format('<%s%s %s width="%g" height="%g"%s%s color="%s" raycastTarget="false" />',
art and "Image" or "Panel", id and (' id="' .. id .. '"') or "", SHAPE.at(x, y), len + e0 + e1,
art and w * ART.EDGE_ART or w, math.abs(deg) > 1e-6 and string.format(' rotation="0 0 %g"', deg) or "",
art and ' image="mundaneEdge"' or "", color)
end
function SHAPE.lines(pts, w, color, closed, id)
local n = #pts
local function past(i)
if not closed and (i == 1 or i == n) then return 0 end
local p, q, r = pts[(i - 2) % n + 1], pts[i], pts[i % n + 1]
local ax, ay, bx, by = q[1] - p[1], q[2] - p[2], r[1] - q[1], r[2] - q[2]
local cos = (ax * bx + ay * by) / math.max(1e-9, math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by)))
local turn = math.min(math.acos(math.max(-1, math.min(1, cos))), math.rad(120))
return w / 2 * math.tan(turn / 2) + 0.1 * w
end
local out = {}
for i = 1, closed and n or n - 1 do
local j = i % n + 1
out[#out + 1] = SHAPE.line(pts[i], pts[j], w, color, past(i), past(j), id and (id .. "Line_" .. (#out + 1)))
end
return table.concat(out), #out
end
function SHAPE.path(box, cut)
local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
local tl, tr, br, bl = cut[1], cut[2], cut[3], cut[4]
local pts = {}
for _, p in ipairs({ { x0 + tl, y0 }, { x1 - tr, y0 }, { x1, y0 + tr }, { x1, y1 - br },
{ x1 - br, y1 }, { x0 + bl, y1 }, { x0, y1 - bl }, { x0, y0 + tl } }) do
local last = pts[#pts]
if not (last and last[1] == p[1] and last[2] == p[2]) then pts[#pts + 1] = p end
end
if pts[1][1] == pts[#pts][1] and pts[1][2] == pts[#pts][2] then pts[#pts] = nil end
return pts
end
function SHAPE.fill(box, cut, color, id)
local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
local top, bottom = math.max(cut[1], cut[2]), math.max(cut[3], cut[4])
local out = {}
local function piece(at, w, h, turned)
out[#out + 1] = string.format('<Panel%s %s width="%g" height="%g"%s color="%s" />',
id and string.format(' id="%sFill_%d"', id, #out + 1) or "", at, w, h,
turned and ' rotation="0 0 45"' or "", color)
end
local function rect(a, b, c, d)
if c - a > 0 and d - b > 0 then piece(SHAPE.at((a + c) / 2, (b + d) / 2), c - a, d - b) end
end
rect(x0, y0 + math.max(0, top - 0.5), x1, y1 - math.max(0, bottom - 0.5))
rect(x0 + cut[1], y0, x1 - cut[2], y0 + top)
rect(x0 + cut[4], y1 - bottom, x1 - cut[3], y1)
for k, c in ipairs(cut) do
if c > 0 then
local x = (k == 1 or k == 4) and x0 + c or x1 - c
local y = k <= 2 and y0 + c or y1 - c
piece(SHAPE.at(x, y), c * math.sqrt(2), c * math.sqrt(2), true)
end
end
return table.concat(out), #out
end
SHAPE.CORNERS = {
function(b) return b[1], b[2], 0, 1, 1, 0 end,
function(b) return b[3], b[2], -1, 0, 0, 1 end,
function(b) return b[3], b[4], 0, -1, -1, 0 end,
function(b) return b[1], b[4], 1, 0, 0, -1 end,
}
function SHAPE.accents(box, cut, which, len)
local out = {}
for _, k in ipairs(which) do
local px, py, ux, uy, vx, vy = SHAPE.CORNERS[k](box)
local c = cut[k]
out[#out + 1] = SHAPE.lines({ { px + (c + len) * ux, py + (c + len) * uy }, { px + c * ux, py + c * uy },
{ px + c * vx, py + c * vy }, { px + (c + len) * vx, py + (c + len) * vy } }, LOOK.ACCENT, LOOK.GOLD, false)
end
return table.concat(out)
end
function SHAPE.shape(box, cut, look, w, id)
local fill, fills = SHAPE.fill(box, cut, look.fill, id)
local line, lines = "", 0
if w then line, lines = SHAPE.lines(SHAPE.path(box, cut), w, look.line, true, id) end
if id then SHAPE.parts[id] = { fills = fills, lines = lines, fill = look.fill, line = look.line } end
return fill .. line
end
function SHAPE.panel(box, cut, which, len)
return SHAPE.shape(box, cut, { fill = LOOK.FILL, line = LOOK.GOLD }, LOOK.LINE) ..
SHAPE.accents(box, cut, which, len)
end
function SHAPE.dot(x, y, r, color)
return string.format('<Panel %s width="%g" height="%g" rotation="0 0 45" color="%s" />',
SHAPE.at(x, y), r * math.sqrt(2), r * math.sqrt(2), color)
end
SHAPE.EM = {}
for chars, em in pairs({ [" ijlI.,|'"] = 0.278, ["ft():-!;[]/"] = 0.333, r = 0.389, ['"'] = 0.474, z = 0.5,
["acekpsvxy0123456789J"] = 0.556, ["+"] = 0.584, ["bdghnopquFLTZ?"] = 0.611,
["EPSVXY"] = 0.667, ["ABCDHKNRU&"] = 0.722, ["wGOQ"] = 0.778, M = 0.833, ["m%"] = 0.889,
W = 0.944, ["@"] = 0.975 }) do
for c in chars:gmatch(".") do SHAPE.EM[c] = em end
end
SHAPE.SIGNS = { { "︎", "" }, { "✉", "G" }, { "●", "n" }, { "○", "n" }, { "°", "r" }, { "▲", "W" }, { "▼", "W" } }
function SHAPE.width(s, size)
s = tostring(s or "")
for _, sign in ipairs(SHAPE.SIGNS) do s = s:gsub(sign[1], sign[2]) end
local n = 0
for c in s:gmatch(".") do n = n + (SHAPE.EM[c] or 0.611) end
return n * (size or 1)
end
function SHAPE.fit(text, w, h, max, min)
min = min or SHAPE.MIN
local lines = nil
for size = max, min, -1 do
lines = {}
for given in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
local first = #lines + 1
for word in given:gmatch("%S+") do
local cur = #lines >= first and lines[#lines]
if cur and SHAPE.width(cur .. " " .. word, size) <= w then lines[#lines] = cur .. " " .. word
else lines[#lines + 1] = word end
end
end
local fits = #lines * size * 1.2 <= h
for _, l in ipairs(lines) do fits = fits and SHAPE.width(l, size) <= w end
if fits then return table.concat(lines, "\n"), size end
end
return table.concat(lines, "\n"), min
end
function SHAPE.fitLine(text, w, max, min)
local em = SHAPE.width(text)
if em <= 0 then return text, max end
return text, math.max(min or SHAPE.MIN, math.min(max, math.floor(w / em)))
end
function SHAPE.esc(s)
return (tostring(s or ""):gsub("&", "and"):gsub("[<>]", ""))
end
function SHAPE.font(size, detail)
local fs = math.max(1, math.floor(size * (detail or TEXT_DETAIL) + 0.5))
return fs, size / fs
end
function SHAPE.sized(size, w, h, detail)
local fs, sc = SHAPE.font(size, detail)
return string.format('width="%.6g" height="%.6g" fontSize="%d" scale="%.9g %.9g 1"', w / sc, h / sc, fs, sc, sc)
end
function SHAPE.size(id, size)
local fs, sc = SHAPE.font(size)
self.UI.setAttribute(id, "fontSize", string.format("%d", fs))
self.UI.setAttribute(id, "scale", string.format("%.9g %.9g 1", sc, sc))
end
function SHAPE.text(x, y, w, h, text, size, ink, id, extra, detail, bare)
return string.format('<Text%s%s %s %s fontStyle="Bold" alignment="MiddleCenter"%s color="%s" raycastTarget="false">%s</Text>',
id and (' id="' .. id .. '"') or "", extra or "", SHAPE.at(x, y), SHAPE.sized(size, w, h, detail),
bare and "" or ' horizontalOverflow="Overflow" verticalOverflow="Overflow"', ink, SHAPE.esc(text))
end
function SHAPE.hit(id, fn, x, y, w, h)
return string.format('<Button id="%s" %s width="%g" height="%g" colors="%s" onClick="%s" />',
id, SHAPE.at(x, y), w, h, LOOK.HOVER, fn)
end
function SHAPE.button(t)
local b = t.box
local x, y, w, h = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2, b[3] - b[1], b[4] - b[2]
local look = type(t.look) == "table" and t.look or LOOK.BUTTONS[t.look or "plain"]
local text, size = t.label or "", t.size
if t.fit ~= false then text, size = SHAPE.fitLine(text, w - 16, t.size) end
local out = SHAPE.shape(b, t.cut or SHAPE.CUT, look, t.line ~= false and LOOK.EDGE or nil, t.id)
if t.id then
local p = SHAPE.parts[t.id]
p.box, p.txt, p.w, p.h, p.size, p.fit = b, t.txt, w - 16, h - 4, t.size, t.fit ~= false
end
return out .. SHAPE.text(x, y, w - 8, h, text, size, look.ink, t.txt, nil, t.detail, t.bare) ..
(t.fn and SHAPE.hit(t.btn, t.fn, x, y, w, h) or "")
end
function SHAPE.paint(id, look, text)
local p = SHAPE.parts[id]
if not p then return end
look = type(look) == "table" and look or LOOK.BUTTONS[look] or {}
if text and p.txt then
local shown, size = text, p.size
if p.fit then shown, size = SHAPE.fitLine(text, p.w, p.size) end
setLabel(p.txt, shown)
SHAPE.size(p.txt, size)
end
if look.fill and look.fill ~= p.fill then
for k = 1, p.fills do self.UI.setAttribute(id .. "Fill_" .. k, "color", look.fill) end
p.fill = look.fill
end
if look.line and look.line ~= p.line then
for k = 1, p.lines do self.UI.setAttribute(id .. "Line_" .. k, "color", look.line) end
p.line = look.line
end
if look.ink and p.txt then self.UI.setAttribute(p.txt, "color", look.ink) end
end
local RESET = {
LABEL = "Reset Fighters",
ASK = "Click again to reset",
WAIT = 4,
ASKING = "red",
asking = false, token = 0,
}
local SETUP = {
ROWS = {
{ label = "Map Size", map = true },
{ label = "Roll for Deployment", key = "deployment", say = "Deployment", deploy = true,
results = { "Sniping Range", "Face Off", "Stand Off", "Ambush", "Free for All", "Chance Encounter" } },
{ label = "Roll for Objective", key = "objective", say = "Objective",
results = { "King of the Hive", "Turf War", "Tunnel Clash", "Object Lesson", "Flank 'em", "Burn Them Out" } },
{ label = "Roll for Crews", key = "crews", say = "Crew",
results = { "Hybrid (3 + D3) - Reinforcements (5) - D3 per Round", "Custom (10)", "Hybrid (3 + 4)",
"Attacker: Hybrid (4 + 4)  ||  Defender: Custom (3) - Reinforcements (7) - D3 per Round",
"Custom (5)", "Hybrid (D3 + 5)" },
button = { [1] = "Hybrid (3 + D3)\nReinforcements (5) - D3 per Round",
[4] = "Attacker: Hybrid (4 + 4)\nDefender: Custom (3) - Reinforcements (7) - D3 per Round" } },
{ label = "Determine Attacker | Defender", key = "sides", rollOff = true },
{ label = "Choose Crews" },
{ label = "Gang Tactics" },
{ label = "Deployment (Defender starts)" },
{ label = "Start Game", start = true },
},
attacker = 1,
map = 36,
rolled = {},
rolling = {},
HEAD = 48, HEAD_FONT = 30,
TOP = 76, BOTTOM = 18, INSET = 26, GAP = 7, CUT = 12,
FONT = 18, START_FONT = 22,
TOOL_W = 34, TOOL_GAP = 6, TOOL_CUT = 6, TOOL_FONT = 13, ARROW_FONT = 10,
ATTACKER = "#E0B830", DEFENDER = "#2BB3AD",
SAY = { 1, 0.85, 0.4 },
}
function SETUP.place(k)
local col, n = LAYOUT.MID, #SETUP.ROWS
local x0, x1 = col[1] + SETUP.INSET, col[3] - SETUP.INSET
local h = (col[4] - SETUP.BOTTOM - SETUP.TOP - (n - 1) * SETUP.GAP) / n
local y0 = SETUP.TOP + (k - 1) * (h + SETUP.GAP)
if not SETUP.ROWS[k].deploy then return { x0, y0, x1, y0 + h } end
local tw, g = SETUP.TOOL_W, SETUP.TOOL_GAP
return { x0, y0, x1 - 2 * (tw + g), y0 + h },
{ turn = { x1 - 2 * tw - g, y0, x1 - tw - g, y0 + h },
up = { x1 - tw, y0, x1, y0 + h / 2 - 2 },
down = { x1 - tw, y0 + h / 2 + 2, x1, y0 + h } }
end
function SETUP.side(n)
local team = TEAM.of(n)
if team then return "Team " .. team end
local name = trim(tostring(vpNames[n] or ""))
return name ~= "" and name or ("Player " .. n)
end
function SETUP.reminder()
for _, row in ipairs(SETUP.ROWS) do
local text = row.key == "crews" and row.results[SETUP.rolled.crews or 0]
if text then
local out = {}
for part in (text .. "||"):gmatch("(.-)||") do
local each = part:match("Reinforcements %(%d+%) %- (%S+) per Round")
if each then
local who = trim(part):match("^(%a+):")
out[#out + 1] = (who and who .. ": " or "") .. "Reinforcements - " .. each
end
end
return #out > 0 and table.concat(out, ", ") or nil
end
end
end
function SETUP.view(k)
local row = SETUP.ROWS[k]
local text = row.label
local face = row.key and SETUP.rolled[row.key]
if row.map then text = string.format('Map Size: %d" x %d"', SETUP.map, SETUP.map)
elseif SETUP.rolling[k] then text = "Rolling..."
elseif face and row.rollOff then text = SETUP.side(face) .. " chooses"
elseif face then text = row.say .. ": " .. (row.button and row.button[face] or row.results[face])
elseif row.start then text = text:upper()
end
local b = SETUP.place(k)
return SHAPE.fit(text, b[3] - b[1] - 16, b[4] - b[2] - 4, row.start and SETUP.START_FONT or SETUP.FONT)
end
function SETUP.note()
local R, text = LAYOUT.ROUND, SETUP.reminder()
local fitted, size = SHAPE.fit(text or "", R.NOTE_W, R.NOTE_H, R.NOTE_FONT)
return fitted, size, text ~= nil
end
function SETUP.xml()
local col = LAYOUT.MID
local out = { string.format('<Panel id="setupPanel" active="%s" width="%d" height="%d" color="#00000000">',
tostring(turn < 1), PANEL_W, PANEL_H),
SHAPE.text((col[1] + col[3]) / 2, SETUP.HEAD, col[3] - col[1] - 80, SETUP.HEAD_FONT * 1.4, "GAME SETUP",
SETUP.HEAD_FONT, LOOK.HEAD) }
local cut = { SETUP.CUT, 0, SETUP.CUT, 0 }
for k, row in ipairs(SETUP.ROWS) do
local box, tools = SETUP.place(k)
local text, size = SETUP.view(k)
out[#out + 1] = SHAPE.button({ box = box, cut = cut, look = row.start and "gold" or "plain", label = text,
size = size, fit = false, fn = row.start and "onAdvanceTurn" or "onSetup",
btn = "setupBtn_" .. k, txt = "setupTxt_" .. k })
if tools then
local square = { 0, 0, 0, 0 }
out[#out + 1] = SHAPE.button({ box = tools.turn, cut = { SETUP.TOOL_CUT, 0, SETUP.TOOL_CUT, 0 }, label = "90°",
size = SETUP.TOOL_FONT, fit = false, fn = "onDeployTool", btn = "deployTurn" })
out[#out + 1] = SHAPE.button({ box = tools.up, cut = square, label = "▲", size = SETUP.ARROW_FONT,
fit = false, fn = "onDeployTool", btn = "deployUp" })
out[#out + 1] = SHAPE.button({ box = tools.down, cut = square, label = "▼", size = SETUP.ARROW_FONT,
fit = false, fn = "onDeployTool", btn = "deployDown" })
end
end
out[#out + 1] = "</Panel>"
return table.concat(out, "\n")
end
function SETUP.draw(k)
local text, size = SETUP.view(k)
SHAPE.size("setupTxt_" .. k, size)
setLabel("setupTxt_" .. k, text)
end
function SETUP.drawAll()
for k in ipairs(SETUP.ROWS) do SETUP.draw(k) end
end
function SETUP.role(n)
if n == SETUP.attacker then return "Attacker", SETUP.ATTACKER end
return "Defender", SETUP.DEFENDER
end
function SETUP.swap()
SETUP.attacker = 3 - SETUP.attacker
for n = 1, 2 do
local word, fill = SETUP.role(n)
SHAPE.paint("vpRole_" .. n, { fill = fill }, word:upper())
end
printToAll(string.format("%sAttacker: %s -- Defender: %s", CHAT_PREFIX, SETUP.side(SETUP.attacker),
SETUP.side(3 - SETUP.attacker)), SETUP.SAY)
end
function DEPLOY.find()
local out = {}
for _, o in ipairs(DEPLOY.objs or {}) do
if not (o.isDestroyed and o.isDestroyed()) then out[#out + 1] = o end
end
if #out > 0 then return out end
local ok, list = pcall(function() return getObjectsWithTag(DEPLOY.TAG) end)
DEPLOY.objs = ok and type(list) == "table" and list or {}
return DEPLOY.objs
end
function DEPLOY.remove()
local any = false
local ok, list = pcall(function() return getObjectsWithTag(DEPLOY.TAG) end)
for _, o in ipairs(ok and type(list) == "table" and list or {}) do
any = true
pcall(function() o.destruct() end)
end
for _, o in ipairs(DEPLOY.objs or {}) do
pcall(function() if not o.isDestroyed() then any = true; o.destruct() end end)
end
DEPLOY.objs = {}
return any
end
function DEPLOY.model(face)
local mesh = DEPLOY.MESH[face] or {}
if mesh.apart then return DEPLOY.ZONE, DEPLOY.COLLIDER, SETUP.map / DEPLOY.BASE, mesh.apart end
if mesh[1] == nil then return mesh[SETUP.map] or "", DEPLOY.COLLIDER, 1 end
return mesh[1], DEPLOY.COLLIDER, 1
end
function DEPLOY.turned(x, z, yaw)
local a = math.rad(yaw)
return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)
end
function DEPLOY.spawn(face, name)
DEPLOY.remove()
local url, collider, stretch, apart = DEPLOY.model(face)
if url == "" or not spawnObject then
printToAll(string.format('%sNo deployment model for %s on a %d" x %d" map yet.', CHAT_PREFIX, name or "?",
SETUP.map, SETUP.map), { 0.7, 0.7, 0.7 })
return {}
end
local spots = apart and { { apart, 0 }, { -apart, 180 } } or { { 0, 0 } }
for _, spot in ipairs(spots) do
local x, z = DEPLOY.turned(0, spot[1], DEPLOY.turn)
local ok, o = pcall(spawnObject, {
type = "Custom_Model",
position = { x, 0, z },
rotation = { 0, (DEPLOY.turn + spot[2]) % 360, 0 },
scale = { stretch, DEPLOY.tall, 1 },
sound = false,
callback_function = function(obj)
pcall(function()
obj.setLock(true)
obj.setName("Deployment: " .. (name or ""))
obj.setColorTint(DEPLOY.TINT)
end)
end,
})
if ok and o then
pcall(function()
o.setCustomObject({ mesh = url, collider = collider, type = 0, material = DEPLOY.MATERIAL, cast_shadows = false })
end)
pcall(function() o.setLock(true) end)
pcall(function() o.addTag(DEPLOY.TAG) end)
DEPLOY.objs[#DEPLOY.objs + 1] = o
end
end
return DEPLOY.objs
end
function DEPLOY.again()
for _, row in ipairs(SETUP.ROWS) do
local face = row.deploy and SETUP.rolled[row.key]
if face then return DEPLOY.spawn(face, row.results[face]) end
end
return {}
end
function SETUP.rollOff(k, color)
SETUP.rolling[k] = true
SETUP.draw(k)
DICE.request({ kinds = { "d6", "d6" }, apart = DICE.APART, inOrder = true, color = color,
done = function(faces, digital)
local how = digital and " (rolled digitally)" or ""
if faces[1] == faces[2] then
DICE.announce(string.format("%sRoll-off: %s and %s both roll %d -- rolled again%s", CHAT_PREFIX,
SETUP.side(1), SETUP.side(2), faces[1], how), SETUP.SAY)
return SETUP.rollOff(k, color)
end
local win = faces[1] > faces[2] and 1 or 2
local was = SETUP.rolled[SETUP.ROWS[k].key]
SETUP.rolling[k] = nil
SETUP.rolled[SETUP.ROWS[k].key] = win
SETUP.draw(k)
DICE.announce(string.format("%s%s chooses%s", CHAT_PREFIX, SETUP.side(win), how), SETUP.SAY)
if was ~= win then SETUP.busAttacker(color) end
end })
end
local BOTTLE = {
due = {},
hand = {},
seen = {},
R = 38,
ICON = 0.78,
FONT = 32,
HAND = "#F0C060",
UP = "#6EE07A",
HINT = "[ NO NAME SET ]",
HOW = { "Move a scribed Model", "beneath this panel to", "set the Gangname" },
ZONE = 140,
}
function BOTTLE.diamond(id, n, x, y, label, fn, ink, r, font)
r = r or BOTTLE.R
local side = r * math.sqrt(2)
local frame = nil
if ART.FRAME ~= "" then
frame = string.format('<Image %s width="%g" height="%g" rotation="0 0 45" image="mundaneFrame" color="%s"' ..
' raycastTarget="false" />', SHAPE.at(x, y), side * ART.FRAME_SIZE, side * ART.FRAME_SIZE, LOOK.GOLD)
else
frame = (SHAPE.lines({ { x, y - r }, { x + r, y }, { x, y + r }, { x - r, y } }, LOOK.EDGE, LOOK.GOLD, true))
end
return string.format('<Button id="%s_%s" %s width="%g" height="%g" rotation="0 0 45" colors="%s" onClick="%s" />',
id, tostring(n), SHAPE.at(x, y), side, side, LOOK.DIAMOND, fn) ..
frame .. SHAPE.text(x, y, side, side, label, font or BOTTLE.FONT, ink or LOOK.TEXT, id .. "Txt_" .. tostring(n))
end
function BOTTLE.nameView(n)
local S = LAYOUT.SIDE
local team = TEAM.of(n)
local text = team and ("Team " .. team) or BOTTLE.named(n) and trim(tostring(vpNames[n])):upper()
or BOTTLE.HINT
local size = math.floor(math.min(S.NAME_FONT, (S.NAME_W - 24) / math.max(0.01, SHAPE.width(text))))
return text, math.max(S.NAME_MIN, size)
end
local function group(id, on, inner)
return string.format('<Panel id="%s" active="%s" width="%d" height="%d" color="#00000000">\n%s\n</Panel>',
id, tostring(on), PANEL_W, PANEL_H, inner)
end
local function halfXml(n, h, gang)
local S, P = LAYOUT.SIDE, LAYOUT.SIDE.SPLIT
local box = LAYOUT.SIDES[n]
local hx, top = (box[1] + box[3]) / 2 + (h == 1 and -P.X or P.X), box[2]
local sfx = n .. "_" .. h
local slot = { gang = gang or "", sfx = sfx }
local v, will = BOTTLE.valueOf(slot)
local name = trim(tostring(gang or "")):upper()
local _, gsize = SHAPE.fitLine(name, P.GANG_W, P.GANG_FONT)
local dy = top + P.DICE
local roll = BOTTLE.diamond("bottleRoll", sfx, hx + P.ROLL_X, dy, DIE_ICON == "" and "D" or "", "onBottleRoll",
nil, P.R, P.VAL_FONT)
if DIE_ICON ~= "" then
local s = P.R * math.sqrt(2) * BOTTLE.ICON
roll = roll .. string.format('<Image id="bottleRollIcon_%s" %s width="%g" height="%g" image="mundaneDie"' ..
' raycastTarget="false" />', sfx, SHAPE.at(hx + P.ROLL_X, dy), s, s)
end
local pc = S.PLATE_CUT
local plate = { hx + P.PLATE[1], top + P.PLATE[2], hx + P.PLATE[3], top + P.PLATE[4] }
local xb = { hx + P.XBTN[1], top + P.XBTN[2], hx + P.XBTN[3], top + P.XBTN[4] }
local xml = table.concat({
string.format('<Button id="teamArea_%s" %s width="%g" height="%g" colors="#00000000|#00000000|#00000000|#00000000" />',
sfx, SHAPE.at((plate[1] + plate[3]) / 2, (plate[2] + plate[4]) / 2), plate[3] - plate[1], plate[4] - plate[2]),
group("bottle_" .. sfx, BOTTLE.litOf(gang), SHAPE.shape(plate, { pc, pc, pc, pc }, LOOK.BUTTONS.red, LOOK.EDGE)),
SHAPE.text(hx, top + P.GANG, P.GANG_W, P.GANG_FONT * 1.4, name, gsize, LOOK.TEXT, "bottleGang_" .. sfx),
SHAPE.text(hx, top + P.HEAD, P.HEAD_W, P.HEAD_FONT * 1.4, "BOTTLE CHECK", P.HEAD_FONT, LOOK.TEXT),
SHAPE.hit("bottleHead_" .. sfx, "onBottleHead", hx, top + P.HEAD, P.HEAD_W, P.HEAD_FONT * 1.4),
SHAPE.text(hx + P.LD_X, dy, 50, P.LD_FONT * 1.3, "Ld", P.LD_FONT, LOOK.TEXT),
BOTTLE.diamond("bottleVal", sfx, hx + P.VAL_X, dy, v and tostring(v) or "-", "onBottleValue",
BOTTLE.ink(sfx, will), P.R, P.VAL_FONT),
roll,
group("teamXg_" .. sfx, false, SHAPE.button({ box = xb, cut = { 6, 0, 6, 0 }, look = "red", label = "X",
size = P.XFONT, fit = false, fn = "onTeamRemove", btn = "teamX_" .. sfx })),
}, "\n")
return (xml:gsub('(<Button id="[%w_]-_' .. sfx .. '")', '%1 onMouseEnter="onTeamEnter" onMouseExit="onTeamExit"'))
end
local function sideXml(n)
local S, box = LAYOUT.SIDE, LAYOUT.SIDES[n]
local cx, top = (box[1] + box[3]) / 2, box[2]
local function rule(dy, color)
return (SHAPE.lines({ { cx - S.RULE_W / 2, top + dy }, { cx + S.RULE_W / 2, top + dy } }, LOOK.THIN, color))
end
local function across(b) return { cx + b[1], top + b[2], cx + b[3], top + b[4] } end
local named = BOTTLE.named(n)
local name, size = BOTTLE.nameView(n)
local word, fill = SETUP.role(n)
local v, will = BOTTLE.value(n)
local slots, team = BOTTLE.slots(n)
local L = TEAM.gangs[n] or {}
local P = S.SPLIT
local hintW = box[3] - box[1] - 60
local rx, dy = cx + S.ROLL_X, top + S.DICE
local roll = BOTTLE.diamond("bottleRoll", n, rx, dy, DIE_ICON == "" and "D" or "", "onBottleRoll")
if DIE_ICON ~= "" then
local s = BOTTLE.R * math.sqrt(2) * BOTTLE.ICON
roll = roll .. string.format('<Image id="bottleRollIcon_%d" %s width="%g" height="%g" image="mundaneDie"' ..
' raycastTarget="false" />', n, SHAPE.at(rx, dy), s, s)
end
local c, pc = S.ROLE_CUT, S.PLATE_CUT
return table.concat({
SHAPE.panel(box, LAYOUT.SIDE_CUT, { 1, 2, 3, 4 }, LAYOUT.SIDE_ACCENT),
string.format('<InputField id="vpName_%d" %s %s fontStyle="Bold"' ..
' characterLimit="40" textAlignment="MiddleCenter" textColor="%s" colors="#00000000|#FFFFFF0D|#FFFFFF14|#00000000"' ..
' text="%s" onEndEdit="onVpName" />', n, SHAPE.at(cx, top + S.NAME), SHAPE.sized(size, S.NAME_W, S.NAME_H),
LOOK.TEXT, xmlEsc(name)),
rule(S.NAME_RULE, LOOK.RULE),
group("vpShow_" .. n, named,
SHAPE.text(cx, top + S.VP_HEAD, S.RULE_W, S.HEAD_FONT * 1.4, "VICTORY POINTS", S.HEAD_FONT, LOOK.TEXT) ..
SHAPE.text(cx, top + S.VP, S.RULE_W, S.VP_FONT * 1.2, tostring(vp[n]), S.VP_FONT, LOOK.TEXT, "vpText_" .. n) ..
SHAPE.hit("vpBtn_" .. n, "onVp", cx, top + (S.VP_HIT[1] + S.VP_HIT[2]) / 2, S.RULE_W, S.VP_HIT[2] - S.VP_HIT[1])),
group("vpHint_" .. n, not named,
SHAPE.text(cx, top + S.HINT - S.HINT_GAP, hintW, S.HINT_FONT * 1.3, BOTTLE.HOW[1], S.HINT_FONT, LOOK.DIM) ..
SHAPE.text(cx, top + S.HINT, hintW, S.HINT_FONT * 1.3, BOTTLE.HOW[2], S.HINT_FONT, LOOK.DIM) ..
SHAPE.text(cx, top + S.HINT + S.HINT_GAP, hintW, S.HINT_FONT * 1.3, BOTTLE.HOW[3], S.HINT_FONT, LOOK.DIM)),
rule(S.VP_RULE, LOOK.RULE_TEXT),
SHAPE.button({ box = across(S.ROLE), cut = { c, c, c, c }, look = { fill = fill, ink = LOOK.BUTTONS.gold.ink },
line = false, label = word:upper(), size = S.ROLE_FONT, fn = "onSwapRoles", btn = "vpRoleBtn_" .. n,
id = "vpRole_" .. n, txt = "vpRoleTxt_" .. n }),
group("bottleOne_" .. n, not team, table.concat({
group("bottle_" .. n, BOTTLE.lit(n), SHAPE.shape(across(S.PLATE), { pc, pc, pc, pc }, LOOK.BUTTONS.red, LOOK.EDGE)),
SHAPE.text(cx, top + S.BOTTLE, S.HEAD_W, S.HEAD_FONT * 1.4, "BOTTLE CHECK", S.HEAD_FONT, LOOK.TEXT),
SHAPE.hit("bottleHead_" .. n, "onBottleHead", cx, top + S.BOTTLE, S.HEAD_W, S.HEAD_FONT * 1.4),
SHAPE.text(cx + S.LD_X, dy, 60, S.LD_FONT * 1.3, "Ld", S.LD_FONT, LOOK.TEXT),
BOTTLE.diamond("bottleVal", n, cx + S.VAL_X, dy, v and tostring(v) or "-", "onBottleValue",
BOTTLE.ink(tostring(n), will)),
roll,
}, "\n")),
group("bottleTwo_" .. n, team ~= nil, table.concat({
(SHAPE.lines({ { cx, top + P.RULE[1] }, { cx, top + P.RULE[2] } }, LOOK.THIN, LOOK.RULE)),
halfXml(n, 1, team and slots[1].gang or (L[1] and L[1].gang)),
halfXml(n, 2, team and slots[2].gang or (L[2] and L[2].gang)),
}, "\n")),
}, "\n")
end
local function roundView()
local R, text = LAYOUT.ROUND, tostring(turn)
local half = math.sqrt((SHAPE.width(text) / 2) ^ 2 + 0.36 ^ 2)
return text, math.floor(math.min(R.FONT, R.RING * 0.92 / half))
end
local function columnXml()
local R, col = LAYOUT.ROUND, LAYOUT.MID
local cx, gy = (col[1] + col[3]) / 2, R.GEAR
local number, size = roundView()
local note, noteSize, noteOn = SETUP.note()
local iy = col[2] + R.INFO_GAP
local ix = LAYOUT.MID_CUT[1] + R.INFO_GAP * (math.sqrt(2) - 1) - R.INFO_CUT
local out = {
SHAPE.panel(col, LAYOUT.MID_CUT, { 1, 2 }, LAYOUT.MID_ACCENT),
string.format('<Panel id="turnView" active="%s" width="%d" height="%d" color="#00000000">',
tostring(turn >= 1), PANEL_W, PANEL_H),
SHAPE.button({ box = { col[1] + ix, iy, col[3] - ix, iy + R.INFO_H }, cut = { R.INFO_CUT, R.INFO_CUT, 0, 0 },
look = FEEDBACK.showing() == "info" and "plain" or "dim", label = "Supported Mechanics", size = R.INFO_FONT,
fn = "onInfo", btn = "infoBtn", id = "info", txt = "infoTxt" }),
SHAPE.text(cx, R.CAPTION, 2 * R.RULE_GAP, R.CAPTION_FONT * 1.3, "ROUND", R.CAPTION_FONT, LOOK.HEAD, "turnCaption"),
(SHAPE.lines({ { col[1] + R.RULE_IN, R.CAPTION }, { cx - R.RULE_GAP, R.CAPTION } }, LOOK.THIN, LOOK.GOLD)),
(SHAPE.lines({ { cx + R.RULE_GAP, R.CAPTION }, { col[3] - R.RULE_IN, R.CAPTION } }, LOOK.THIN, LOOK.GOLD)),
}
if ART.GLOW ~= "" then
out[#out + 1] = string.format('<Image %s width="%g" height="%g" image="mundaneGlow" color="%s" raycastTarget="false" />',
SHAPE.at(cx, gy), R.GLOW_SIZE, R.GLOW_SIZE, LOOK.GLOW)
end
if ART.GEAR ~= "" then
out[#out + 1] = string.format('<Image %s width="%g" height="%g" image="mundaneGear" color="%s" raycastTarget="false" />',
SHAPE.at(cx, gy), R.GEAR_SIZE, R.GEAR_SIZE, LOOK.GOLD)
end
out[#out + 1] = SHAPE.text(cx, gy - R.DROP, 2 * R.RING + 60, R.FONT * 1.25, number, size, LOOK.NUMBER, "turnText")
out[#out + 1] = SHAPE.hit("turnBack", "onAdvanceTurn", cx, gy, R.HIT, R.HIT)
out[#out + 1] = SHAPE.button({ box = { cx + R.END[1], R.END[2], cx + R.END[3], R.END[4] },
cut = { R.END_CUT, 0, R.END_CUT, 0 }, look = "red", label = "END ROUND", size = R.END_FONT,
fn = "onAdvanceTurn", btn = "turnBtn", txt = "endRoundTxt" })
out[#out + 1] = SHAPE.text(cx, R.NOTE, R.NOTE_W, R.NOTE_H, note, noteSize, LOOK.NOTE, "roundNote",
' active="' .. tostring(noteOn) .. '"')
out[#out + 1] = "</Panel>"
out[#out + 1] = SETUP.xml()
return table.concat(out, "\n")
end
local function linksXml()
local L, out = LAYOUT, {}
for _, y in ipairs(L.LINKS) do
for _, span in ipairs({ { L.SIDES[1][3], L.MID[1] }, { L.MID[3], L.SIDES[2][1] } }) do
out[#out + 1] = (SHAPE.lines({ { span[1], y }, { span[2], y } }, LOOK.LINE, LOOK.GOLD))
out[#out + 1] = SHAPE.dot((span[1] + span[2]) / 2, y, L.LINK_DOT, LOOK.GOLD)
end
end
return table.concat(out, "\n")
end
local function railXml(x0, x1, list)
local L, n, fixed, shared = LAYOUT, #list, 0, 0
for _, b in ipairs(list) do
if b.w then fixed = fixed + b.w else shared = shared + 1 end
end
local w = (x1 - x0 - (n - 1) * L.RAIL_GAP - fixed) / math.max(1, shared)
local out, x = {}, x0
for k, b in ipairs(list) do
local bw = b.w or w
b.box = { x, L.RAIL[1], x + bw, L.RAIL[2] }
b.cut = { 0, 0, k == n and L.RAIL_CUT or 0, k == 1 and L.RAIL_CUT or 0 }
b.size = b.size or L.RAIL_FONT
out[#out + 1] = SHAPE.button(b)
x = x + bw + L.RAIL_GAP
end
return table.concat(out, "\n")
end
local function railsXml()
local L, out = LAYOUT, {}
for n, side in ipairs(L.SIDES) do
out[#out + 1] = railXml(side[1], side[3], {
{ label = "Roll Dice", fn = "onRollDiceBtn", btn = "rollDiceBtn_" .. n },
{ label = "Roll Firepower", fn = "onRollFirepowerBtn", btn = "rollFirepowerBtn_" .. n },
{ label = "Roll Injuries", fn = "onRollInjuriesBtn", btn = "rollInjuriesBtn_" .. n } })
end
out[#out + 1] = railXml(L.MID[1], L.MID[3], {
{ label = RESET.asking and RESET.ASK or RESET.LABEL, look = RESET.asking and RESET.ASKING or "plain",
fn = "onResetFighters", btn = "resetFighters", id = "resetFighters", txt = "resetFightersTxt" },
{ label = L.MARK, size = L.MARK_FONT, fit = false, w = L.FEEDBACK_W, detail = L.MARK_DETAIL, bare = true,
look = FEEDBACK.showing() == "feedback" and "gold" or "plain", fn = "onFeedback", btn = "feedbackBtn", id = "feedback",
txt = "feedbackMark" },
{ label = HOMEBREW.button(), fn = "onHomebrewOpen", btn = "homebrewBtn", id = "homebrewBtn",
txt = "homebrewBtnTxt" } })
local fb = SHAPE.parts.feedback
out[#out + 1] = SHAPE.text((fb.box[1] + fb.box[3]) / 2, (fb.box[2] + fb.box[4]) / 2, L.FEEDBACK_W,
L.RAIL[2] - L.RAIL[1], "", L.RAIL_FONT, fb.fill == LOOK.GOLD and LOOK.BUTTONS.gold.ink or LOOK.TEXT, "feedbackText")
return table.concat(out, "\n")
end
local function playXml()
return group("playSection", not HOMEBREW.page,
table.concat({ sideXml(1), sideXml(2), columnXml(), linksXml(), railsXml() }, "\n"))
end
local function hbText(s)
return (tostring(s or ""):gsub("&", "and"):gsub("[<>]", ""))
end
local function hbLook(set, k)
local on = HOMEBREW.pick[set.id] == true
local chosen = on == (k == 2)
local desc = on and set.desc or set.offDesc
if set.perPlayer then
local who = HOMEBREW.target()
desc = desc .. (who and (" (" .. who .. " only)") or " (everyone)")
end
return chosen and "gold" or "plain", (chosen and "● " or "○ ") .. hbText(k == 2 and set.name or set.off),
hbText(desc)
end
local function hbScopeLook(k)
local chosen = (HOMEBREW.scope == "all") == (k == 2)
return chosen and "gold" or "plain", (chosen and "● " or "○ ") .. (k == 1 and "Just me" or "Everyone")
end
function HOMEBREW.box()
local L = LAYOUT
return { L.SIDES[1][1], L.MID[2], L.SIDES[2][3], L.RAIL[2] }
end
function HOMEBREW.outline()
local L, b = LAYOUT, HOMEBREW.box()
local top, sc, mc, rc = L.SIDES[1][2], L.SIDE_CUT[1], L.MID_CUT[1], L.RAIL_CUT
local rise = top - b[2]
local sx0, sx1 = L.MID[1] + mc - rise, L.MID[3] - mc + rise
return {
{ b[1], top + sc }, { b[1] + sc, top }, { sx0, top }, { L.MID[1] + mc, b[2] },
{ L.MID[3] - mc, b[2] }, { sx1, top }, { b[3] - sc, top }, { b[3], top + sc },
{ b[3], b[4] - rc }, { b[3] - rc, b[4] }, { b[1] + rc, b[4] }, { b[1], b[4] - rc },
}, sc, rc, sx0, sx1
end
function HOMEBREW.columns()
local cols = { {}, {} }
for i, set in ipairs(HOMEBREW.SETS) do
local col = cols[set.gameplay and 1 or 2]
col[#col + 1] = i
end
return cols
end
function HOMEBREW.rows(col, n)
local rows = 0
for k, i in ipairs(col) do
if n and k == n then return rows end
rows = rows + (HOMEBREW.SETS[i].perPlayer and 2 or 1)
end
return rows
end
function HOMEBREW.step()
local H, box, cols = HOMEBREW, HOMEBREW.box(), HOMEBREW.columns()
return (box[4] - H.FOOT - LAYOUT.SIDES[1][2] - H.HEAD) / math.max(1, HOMEBREW.rows(cols[1]), HOMEBREW.rows(cols[2]))
end
function HOMEBREW.shapeXml()
local L, H, b = LAYOUT, HOMEBREW, HOMEBREW.box()
local pts, sc, rc, sx0, sx1 = HOMEBREW.outline()
local top, len = L.SIDES[1][2], L.MID_ACCENT
local rise = top - b[2]
local body, cut = { b[1], top, b[3], b[4] }, { sc, sc, rc, rc }
local fill = SHAPE.fill(body, cut, LOOK.FILL) ..
SHAPE.fill({ sx0, b[2], sx1, top + 1 }, { rise, rise, 0, 0 }, LOOK.FILL)
local line = SHAPE.lines(pts, LOOK.LINE, LOOK.GOLD, true)
local accents = SHAPE.accents(body, cut, { 1, 2, 3, 4 }, H.ACCENT)
for _, c in ipairs({ { sx0, -1 }, { sx1, 1 } }) do
local x, way = c[1], c[2]
accents = accents .. SHAPE.lines({ { x + way * len, top }, { x, top }, { x - way * rise, b[2] },
{ x - way * (rise + len), b[2] } }, LOOK.ACCENT, LOOK.GOLD, false)
end
return fill .. line .. accents
end
function HOMEBREW.desc(i)
local H = HOMEBREW
local _, _, desc = hbLook(H.SETS[i], 1)
return SHAPE.fit(desc, H.DESC_W, H.DESC_H, H.DESC_FONT)
end
local function homebrewXml()
local H, box = HOMEBREW, HOMEBREW.box()
local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
local cx, step, top = (x0 + x1) / 2, HOMEBREW.step(), LAYOUT.SIDES[1][2]
local _, _, _, sx0, sx1 = HOMEBREW.outline()
local room = sx1 - sx0 - 2 * (top - y0 - H.TITLE + H.TITLE_FONT * 0.4) - 4 * LOOK.LINE
local title = "SETTINGS"
local _, size = SHAPE.fitLine(title, room, H.TITLE_FONT)
local out = {
HOMEBREW.shapeXml(),
SHAPE.text(cx, y0 + H.TITLE, room, H.TITLE_FONT * 1.4, title, size, LOOK.HEAD),
SHAPE.button({ box = { x1 + H.BACK[1], top + H.BACK[2], x1 + H.BACK[3], top + H.BACK[4] }, label = "BACK",
size = H.BACK_FONT, fn = "onHomebrewBack", btn = "homebrewBack" }),
(SHAPE.lines({ { cx, top + H.DIV_UP }, { cx, y1 - H.FOOT } }, LOOK.THIN, LOOK.SEP)),
}
for c, col in ipairs(HOMEBREW.columns()) do
local mx = x0 + (c - 0.5) * (x1 - x0) / 2
out[#out + 1] = SHAPE.text(mx, top + H.SUB, H.DESC_W, H.SUB_FONT * 1.4, c == 1 and "GAMEPLAY / PERFORMANCE" or "HOMEBREW RULES",
H.SUB_FONT, LOOK.HEAD)
for n, i in ipairs(col) do
local set, y = H.SETS[i], top + H.HEAD + HOMEBREW.rows(col, n) * step
for k = 1, 2 do
local look, label = hbLook(set, k)
local bx = k == 1 and mx - H.RADIO_GAP / 2 - H.RADIO_W or mx + H.RADIO_GAP / 2
local id = string.format("hbOpt_%d_%d", i, k)
out[#out + 1] = SHAPE.button({ box = { bx, y, bx + H.RADIO_W, y + H.RADIO_H }, look = look, label = label,
size = H.RADIO_FONT, fn = "onHomebrewOption", btn = id, id = id, txt = id .. "Txt" })
end
local desc, dsize = HOMEBREW.desc(i)
out[#out + 1] = SHAPE.text(mx, y + H.DESC, H.DESC_W, H.DESC_H, desc, dsize, LOOK.DIM, "hbDesc_" .. i)
local span = set.perPlayer and 2 or 1
if set.perPlayer then
for k = 1, 2 do
local look, label = hbScopeLook(k)
local bx = k == 1 and mx - H.RADIO_GAP / 2 - H.SCOPE_W or mx + H.RADIO_GAP / 2
local id = "hbScope_" .. k
out[#out + 1] = SHAPE.button({ box = { bx, y + step, bx + H.SCOPE_W, y + step + H.SCOPE_H }, look = look,
label = label, size = H.SCOPE_FONT, fn = "onHomebrewScope", btn = id, id = id, txt = id .. "Txt" })
end
end
if n < #col then
out[#out + 1] = (SHAPE.lines({ { mx - H.SEP_W / 2, y + span * step - H.SEP_UP },
{ mx + H.SEP_W / 2, y + span * step - H.SEP_UP } }, LOOK.THIN, LOOK.SEP))
end
end
end
out[#out + 1] = SHAPE.button({ box = { cx - H.APPLY_W / 2, y1 - H.APPLY_UP - H.APPLY_H, cx + H.APPLY_W / 2,
y1 - H.APPLY_UP }, look = HOMEBREW.applyLook(), label = "APPLY SETTINGS", size = H.APPLY_FONT,
fn = "onHomebrewApply", btn = "homebrewApply", id = "homebrewApply", txt = "homebrewApplyTxt" })
return group("homebrewPage", H.page, table.concat(out, "\n"))
end
local function panelXml()
SHAPE.parts = {}
return string.format([[
<Defaults>
  <Panel rectAlignment="MiddleCenter"/>
  <Image rectAlignment="MiddleCenter"/>
  <Text rectAlignment="MiddleCenter"/>
  <Button rectAlignment="MiddleCenter"/>
  <InputField rectAlignment="MiddleCenter"/>
</Defaults>
<Panel id="controllerPanel" position="%s" rotation="%s" scale="%s" width="%d" height="%d" color="#00000000">
%s
%s
</Panel>]], PANEL.position, PANEL.rotation, PANEL.scale, PANEL_W, PANEL_H, playXml(), homebrewXml())
end
local function panelAssets()
local out = {}
for _, a in ipairs({ { "mundaneEdge", ART.EDGE }, { "mundaneFrame", ART.FRAME }, { "mundaneGear", ART.GEAR },
{ "mundaneGlow", ART.GLOW }, { "mundaneDie", DIE_ICON } }) do
if a[2] ~= "" then out[#out + 1] = { name = a[1], url = a[2] } end
end
return out
end
function onVp(player, value, id)
if TEAM.refuse(player) then return end
local n = tonumber(tostring(id or ""):match("^vpBtn_(%d)$"))
if not (n and vp[n]) or not BOTTLE.named(n) then return end
local was = vp[n]
vp[n] = math.max(0, vp[n] + (tostring(value) == "-2" and -1 or 1))
setLabel("vpText_" .. n, tostring(vp[n]))
if vp[n] ~= was then SETUP.busVp(n, was, player and player.color or nil) end
end
function onVpName(player, value, id)
local n = tonumber(tostring(id or ""):match("^vpName_(%d)$"))
if not (n and vpNames[n]) then return end
if TEAM.refuse(player) then BOTTLE.drawSide(n) return end
local name = trim(tostring(value or ""))
local shown = BOTTLE.nameView(n)
if name ~= BOTTLE.HINT and name:lower() ~= shown:lower() and name:lower() ~= trim(tostring(vpNames[n])):lower() then
vpNames[n] = name
TEAM.gangs[n] = {}
BOTTLE.forget(n)
TEAM.apply(true)
SETUP.busGang(n, player and player.color or nil)
end
BOTTLE.drawSide(n)
SETUP.drawAll()
end
function BOTTLE.key(name) return trim(tostring(name or "")):lower() end
function BOTTLE.gangName(obj)
local tag = gangOf(obj)
if not tag then return nil end
for _, pre in ipairs({ GANG_TAG, OLD_TAGS[1], OLD_TAGS[2] }) do
if tag:sub(1, #pre) == pre then return tag:sub(#pre + 1) end
end
return tag
end
function BOTTLE.fighters(name)
local key, out = BOTTLE.key(name), {}
if key == "" then return out end
for _, obj in ipairs(getAllObjects()) do
if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) and BOTTLE.key(BOTTLE.gangName(obj)) == key then
local ok, info = callIfHas(obj, "engageInfo")
info = ok and type(info) == "table" and info or {}
local ld, gone = tonumber(info.ld), info.out
if not ld then
local okF, f = callIfHas(obj, "getFighter")
if okF and type(f) == "table" then
ld = tonumber(tostring((f.stats or {}).Ld or ""):match("%d+"))
gone = gone or f.outOfAction
end
end
if not gone and (ld or info.name) then
out[#out + 1] = { name = info.name or obj.getName(), ld = ld, loner = info.loner == true,
will = tonumber(info.ironWill) or 0 }
end
end
end
return out
end
function BOTTLE.best(list)
local all, will = true, 0
for _, f in ipairs(list) do
if not f.loner then all = false end
will = will + (f.will or 0)
end
local best, who = nil, nil
for _, f in ipairs(list) do
if f.ld and (all or not f.loner) and (not best or f.ld > best) then best, who = f.ld, f.name end
end
return best, who, will
end
function BOTTLE.target(name)
local best, who, will = BOTTLE.best(BOTTLE.fighters(name))
if not best then return nil, 0, nil end
local target = math.min(12, best + will)
will = target - best
who = who and (who .. "'s Ld") or "Ld"
if will > 0 then who = string.format("%s %d +%d Iron Will", who, best, will) end
return target, will, who
end
function BOTTLE.slots(n)
local team = TEAM.of(n)
if team then
local L = TEAM.gangs[n]
return { { gang = L[1].gang, sfx = n .. "_1" }, { gang = L[2].gang, sfx = n .. "_2" } }, team
end
return { { gang = vpNames[n], sfx = tostring(n) } }
end
function BOTTLE.slotOf(id)
local n, h = tostring(id or ""):match("_(%d)_(%d)$")
if not n then n = tostring(id or ""):match("_(%d)$") end
n = tonumber(n)
if not n or not vpNames[n] then return nil end
if h then
local list = BOTTLE.slots(n)
return n, #list == 2 and list[tonumber(h)] or nil
end
return n, { gang = vpNames[n], sfx = tostring(n) }
end
function BOTTLE.forget(n)
for _, k in ipairs({ tostring(n), n .. "_1", n .. "_2" }) do BOTTLE.hand[k] = nil end
end
function BOTTLE.valueOf(s)
if BOTTLE.hand[s.sfx] then return BOTTLE.hand[s.sfx], 0 end
local target, will = BOTTLE.target(s.gang)
return target, will
end
function BOTTLE.value(n) return BOTTLE.valueOf({ gang = vpNames[n], sfx = tostring(n) }) end
function BOTTLE.ink(sfx, will)
return BOTTLE.hand[tostring(sfx)] and BOTTLE.HAND or (will or 0) > 0 and BOTTLE.UP or LOOK.TEXT
end
function BOTTLE.litOf(gang)
local key = BOTTLE.key(gang)
return key ~= "" and BOTTLE.due[key] == "due"
end
function BOTTLE.lit(n) return BOTTLE.litOf(vpNames[n]) end
function BOTTLE.named(n)
local key = BOTTLE.key(vpNames[n])
return key ~= "" and key ~= ("player " .. n)
end
function BOTTLE.drawSlot(s)
self.UI.setAttribute("bottle_" .. s.sfx, "active", tostring(BOTTLE.litOf(s.gang)))
local v, will = BOTTLE.valueOf(s)
setLabel("bottleValTxt_" .. s.sfx, v and tostring(v) or "-")
self.UI.setAttribute("bottleValTxt_" .. s.sfx, "color", BOTTLE.ink(s.sfx, will))
end
function BOTTLE.draw(n)
for _, s in ipairs(BOTTLE.slots(n)) do BOTTLE.drawSlot(s) end
end
function BOTTLE.drawSide(n)
local text, size = BOTTLE.nameView(n)
self.UI.setAttribute("vpName_" .. n, "text", text)
local S = LAYOUT.SIDE
for a, v in SHAPE.sized(size, S.NAME_W, S.NAME_H):gmatch('(%w+)="([^"]*)"') do
self.UI.setAttribute("vpName_" .. n, a, v)
end
self.UI.setAttribute("vpShow_" .. n, "active", tostring(BOTTLE.named(n)))
self.UI.setAttribute("vpHint_" .. n, "active", tostring(not BOTTLE.named(n)))
local slots, team = BOTTLE.slots(n)
self.UI.setAttribute("bottleOne_" .. n, "active", tostring(team == nil))
self.UI.setAttribute("bottleTwo_" .. n, "active", tostring(team ~= nil))
if team then
for _, sl in ipairs(slots) do
local name = trim(tostring(sl.gang or "")):upper()
local _, size = SHAPE.fitLine(name, S.SPLIT.GANG_W, S.SPLIT.GANG_FONT)
SHAPE.size("bottleGang_" .. sl.sfx, size)
setLabel("bottleGang_" .. sl.sfx, name)
end
end
BOTTLE.draw(n)
end
function BOTTLE.newTurn()
BOTTLE.due, BOTTLE.hand = {}, {}
for n = 1, 2 do BOTTLE.draw(n) end
end
function BOTTLE.spot(n)
local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
local b = LAYOUT.SIDES[n] or LAYOUT.SIDES[1]
local x, _, z = STAND.point((b[1] + b[3]) / 2 - PANEL_W / 2, -PANEL_H / 2)
local d = BOTTLE.ZONE * k
return x, z + d / 2, (b[3] - b[1]) * k, d
end
function BOTTLE.modelsOn(n)
local out = {}
if not (Physics and Physics.cast and self.positionToWorld) then return out end
local x, z, w, d = BOTTLE.spot(n)
local p = self.positionToWorld({ x, 0, z })
local okS, sc = pcall(function() return self.getScale() end)
sc = okS and type(sc) == "table" and sc or {}
local okR, rot = pcall(function() return self.getRotation() end)
local hits = Physics.cast({ origin = { p.x, p.y + 1.5, p.z }, direction = { 0, 1, 0 }, type = 3,
size = { w * (sc.x or 1), 3, d * (sc.z or 1) }, orientation = okR and rot or nil, max_distance = 0 }) or {}
for _, hit in ipairs(hits) do
local o = hit.hit_object
if o and o ~= self and BOTTLE.gangName(o) then out[#out + 1] = o end
end
return out
end
function BOTTLE.tick()
if HOMEBREW.page then return end
for n = 1, 2 do
local now, fresh = {}, {}
for _, o in ipairs(BOTTLE.modelsOn(n)) do
now[o] = true
if not (BOTTLE.seen[n] or {})[o] then fresh[#fresh + 1] = o end
end
BOTTLE.seen[n] = now
local function drop(o)
local ok, guid = pcall(function() return o.getGUID() end)
return ok and TEAM.dropper[guid] or nil
end
table.sort(fresh, function(a, b) return ((drop(a) or {}).at or 0) < ((drop(b) or {}).at or 0) end)
for _, o in ipairs(fresh) do
local g = BOTTLE.gangName(o)
local color = (drop(o) or {}).color
local before, otherTeam = TEAM.of(n), TEAM.of(3 - n)
local wasName = { trim(tostring(vpNames[1] or "")), trim(tostring(vpNames[2] or "")) }
local moved, joined, bumped = TEAM.placed(n, g, color)
BOTTLE.forget(n)
local team = TEAM.of(n)
TEAM.shown[n] = team
BOTTLE.drawSide(n)
TEAM.shown[3 - n] = TEAM.of(3 - n)
BOTTLE.drawSide(3 - n)
SETUP.drawAll()
pcall(function() o.highlightOn({ 0.9, 0.8, 0.4 }, 1) end)
if moved and otherTeam then TEAM.say(moved, "leaving", otherTeam) end
if bumped and before then TEAM.say(bumped, "leaving", before) end
if team then
if joined then TEAM.say(joined, "joining", team) end
else
printToAll(string.format("%s%s play on the %s.", CHAT_PREFIX, g, n == 1 and "left" or "right"),
{ 0.9, 0.8, 0.4 })
end
TEAM.apply(true)
for m = 1, 2 do
if trim(tostring(vpNames[m] or "")) ~= wasName[m] then SETUP.busGang(m, color) end
end
end
end
end
BOTTLE.POLL, BOTTLE.soonToken = 2, 0
function BOTTLE.soon()
BOTTLE.soonToken = BOTTLE.soonToken + 1
local token = BOTTLE.soonToken
Wait.time(function() if token == BOTTLE.soonToken then BOTTLE.tick() end end, 0.5)
end
function onObjectDrop(color, obj)
local ok, guid = pcall(function() return obj.getGUID() end)
if ok and guid then
TEAM.drops = TEAM.drops + 1
TEAM.dropper[guid] = { color = color, at = TEAM.drops }
end
BOTTLE.soon()
end
function onObjectPickUp() BOTTLE.soon() end
function onObjectDestroy() BOTTLE.soon() end
function TEAM.who(color)
if type(color) ~= "string" or color == "" or color == "Grey" then return nil end
local ok, p = pcall(function() return Player[color] end)
if not (ok and p) then return nil end
local okS, steam = pcall(function() return p.steam_id end)
return { steam = okS and steam or nil, color = color }
end
function TEAM.same(a, b)
if a.steam and b.steam then return a.steam == b.steam end
return a.color ~= nil and a.color == b.color
end
function TEAM.here(e)
if not (e.steam or e.color) then return false end
local ok, players = pcall(function() return Player.getPlayers() end)
for _, p in ipairs(ok and type(players) == "table" and players or {}) do
local okP, steam, color = pcall(function() return p.steam_id, p.color end)
if okP and (e.steam and steam and tostring(steam) == tostring(e.steam) or not e.steam and color == e.color) then
return true
end
end
return false
end
function TEAM.of(n)
local L = TEAM.gangs[n] or {}
local a, b = L[1], L[2]
if not (a and b and (a.steam or a.color) and (b.steam or b.color)) or TEAM.same(a, b) then return nil end
return TEAM.NAMES[n]
end
function TEAM.leave(m, who, key)
local L, out, went = TEAM.gangs[m] or {}, {}, nil
for _, e in ipairs(L) do
if (who and (who.steam or who.color) and TEAM.same(e, who)) or BOTTLE.key(e.gang) == key then went = went or e
else out[#out + 1] = e end
end
if not went then return nil end
TEAM.gangs[m] = out
vpNames[m] = out[1] and out[1].gang or ("Player " .. m)
BOTTLE.forget(m)
return went
end
function TEAM.placed(n, gang, color)
local key = BOTTLE.key(gang)
local who = nil
for m = 1, 2 do
for _, e in ipairs(TEAM.gangs[m] or {}) do
if BOTTLE.key(e.gang) == key and (e.steam or e.color) then who = { steam = e.steam, color = e.color } end
end
end
who = who or TEAM.who(color)
local new = { gang = gang, steam = who and who.steam, color = who and who.color }
local L = TEAM.gangs[n] or {}
if #L == 0 and BOTTLE.named(n) then L = { { gang = vpNames[n] } } end
TEAM.gangs[n] = L
for _, e in ipairs(L) do
if BOTTLE.key(e.gang) == key then
if who and not (e.steam or e.color) then e.steam, e.color = new.steam, new.color end
return nil
end
end
if who then
for i, e in ipairs(L) do
if TEAM.same(e, new) then
L[i] = new
if i == 1 then vpNames[n] = gang end
return TEAM.leave(3 - n, nil, key)
end
end
end
local moved = TEAM.leave(3 - n, nil, key)
local mate = who and L[1] and TEAM.here(L[1]) and L[1]
if mate then
local bumped = L[2]
TEAM.gangs[n] = { mate, new }
vpNames[n] = mate.gang
return moved, new, bumped
end
TEAM.gangs[n] = { new }
vpNames[n] = gang
return moved
end
function TEAM.colorOf(e)
if not e then return nil end
if e.steam then
local ok, players = pcall(function() return Player.getPlayers() end)
for _, p in ipairs(ok and type(players) == "table" and players or {}) do
local okP, steam, color = pcall(function() return p.steam_id, p.color end)
if okP and steam and tostring(steam) == tostring(e.steam) and type(color) == "string" and color ~= "Grey" then
return color
end
end
end
return e.color
end
function TEAM.say(e, verb, team)
local color = TEAM.colorOf(e)
local who = color and ("Player " .. color) or trim(tostring(e and e.gang or "?"))
local rgb = { 0.9, 0.8, 0.4 }
if color and stringColorToRGB then
local ok, c = pcall(stringColorToRGB, color)
if ok and type(c) == "table" then rgb = { c.r or c[1], c.g or c[2], c.b or c[3] } end
end
printToAll(string.format("%s%s %s Team %s.", CHAT_PREFIX, who, verb, team), rgb)
end
function TEAM.tag()
local want, touch = {}, {}
for n = 1, 2 do
local team = TEAM.of(n)
for _, e in ipairs(team and TEAM.gangs[n] or {}) do want[BOTTLE.key(e.gang)] = team end
end
for k in pairs(want) do touch[k] = true end
for k in pairs(TEAM.tagged) do touch[k] = true end
if next(touch) == nil then return end
local ok, objs = pcall(function() return getObjectsWithTag(IMPORT_TAG) end)
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do
local key = BOTTLE.key(BOTTLE.gangName(obj))
if touch[key] then
local tag = want[key] and (TEAM_TAG .. want[key]) or nil
local okT, tags = pcall(function() return obj.getTags() end)
for _, t in ipairs(okT and type(tags) == "table" and tags or {}) do
if type(t) == "string" and t:sub(1, #TEAM_TAG) == TEAM_TAG and t ~= tag then
pcall(function() obj.removeTag(t) end)
end
end
if tag then pcall(function() if not obj.hasTag(tag) then obj.addTag(tag) end end) end
end
end
TEAM.tagged = want
end
function TEAM.apply(quiet)
for n = 1, 2 do
local team, was = TEAM.of(n), TEAM.shown[n]
if team ~= was then
TEAM.shown[n] = team
BOTTLE.drawSide(n)
SETUP.drawAll()
local side = n == 1 and "left" or "right"
if quiet then
elseif team then
printToAll(string.format("%s%s and %s play on the %s as Team %s.", CHAT_PREFIX, TEAM.gangs[n][1].gang,
TEAM.gangs[n][2].gang, side, team), { 0.9, 0.8, 0.4 })
else
printToAll(string.format("%sTeam %s no longer plays on the %s: %s play it alone.", CHAT_PREFIX, was, side,
trim(tostring(vpNames[n]))), { 0.9, 0.8, 0.4 })
end
end
end
TEAM.tag()
TEAM.tellCards()
end
function onTeamEnter(player, value, id)
local n, h = tostring(id or ""):match("_(%d)_(%d)$")
if not (n and TEAM.of(tonumber(n))) or TEAM.watcher(player) then return end
local sfx = n .. "_" .. h
TEAM.hover.token = TEAM.hover.token + 1
if TEAM.hover.shown == sfx then return end
TEAM.hideX()
TEAM.hover.shown = sfx
self.UI.setAttribute("teamXg_" .. sfx, "active", "true")
end
function onTeamExit(player, value, id)
TEAM.hover.token = TEAM.hover.token + 1
local token = TEAM.hover.token
Wait.time(function() if token == TEAM.hover.token then TEAM.hideX() end end, TEAM.LINGER)
end
function TEAM.hideX()
if not TEAM.hover.shown then return end
self.UI.setAttribute("teamXg_" .. TEAM.hover.shown, "active", "false")
TEAM.hover.shown = nil
end
function onTeamRemove(player, value, id)
if TEAM.refuse(player) then return end
if tostring(value) == "-2" or tostring(value) == "-3" then return end
local n, h = tostring(id or ""):match("_(%d)_(%d)$")
n, h = tonumber(n), tonumber(h)
if not (n and h and TEAM.of(n)) then return end
local team, L = TEAM.of(n), TEAM.gangs[n]
local gone = table.remove(L, h)
vpNames[n] = L[1].gang
BOTTLE.forget(n)
TEAM.hideX()
TEAM.say(gone, "leaving", team)
TEAM.apply(true)
end
function TEAM.playing()
local steams, colors, sides, people = {}, {}, 0, 0
for n = 1, 2 do
local known = false
for _, e in ipairs(TEAM.gangs[n] or {}) do
local k = e.steam and ("s" .. tostring(e.steam)) or e.color and ("c" .. e.color)
if k then
if not (steams[k] or colors[k]) then people = people + 1 end
if e.steam then steams[k] = true else colors[k] = true end
known = true
end
end
if known then sides = sides + 1 end
end
if sides < 2 or people < 2 then return nil end
local set = {}
for k in pairs(colors) do set[k:sub(2)] = true end
local ok, players = pcall(function() return Player.getPlayers() end)
for _, p in ipairs(ok and type(players) == "table" and players or {}) do
local okP, steam, color = pcall(function() return p.steam_id, p.color end)
if okP and type(color) == "string" and color ~= "Grey" and steam and steams["s" .. tostring(steam)] then
set[color] = true
end
end
local list = {}
for c in pairs(set) do list[#list + 1] = c end
table.sort(list)
return list
end
function TEAM.playingMsg()
local list = TEAM.playing()
return list and { colors = list } or { all = true }
end
function getPlaying() return TEAM.playingMsg() end
function TEAM.seated()
local ok, players = pcall(function() return Player.getPlayers() end)
for _, p in ipairs(ok and type(players) == "table" and players or {}) do
local okP, color, seated = pcall(function() return p.color, p.seated end)
if okP and seated and type(color) == "string" and color ~= "Grey" then return true end
end
return false
end
function TEAM.watcher(player)
if player == nil then return false end
local ok, color = pcall(function() return player.color end)
if not ok or type(color) ~= "string" or color == "" then return false end
if color == "Grey" then return TEAM.seated() end
local list = TEAM.playing()
if not list then return false end
for _, c in ipairs(list) do if c == color then return false end end
return true
end
TEAM.hinted, TEAM.HINT_EVERY = {}, 5
function TEAM.refuse(player)
if not TEAM.watcher(player) then return false end
local color = player.color
local now = os.clock()
if now - (TEAM.hinted[color] or -1e9) >= TEAM.HINT_EVERY then
TEAM.hinted[color] = now
local msg = color == "Grey" and "Spectators only watch. To play, sit at a colour and put one of your gang's " ..
"models in front of your side panel of the Mundane Controller."
or "You are watching this game. To play, put one of your gang's models in front of your side panel " ..
"of the Mundane Controller."
pcall(function() broadcastToColor(CHAT_PREFIX .. msg, color, { 0.9, 0.8, 0.4 }) end)
end
return true
end
function TEAM.tellCards(force)
local msg = TEAM.playingMsg()
local sig = msg.all and "all" or table.concat(msg.colors, ",")
if sig == TEAM.told and not force then return end
TEAM.told = sig
local ok, objs = pcall(function() return getObjectsWithTag(IMPORT_TAG) end)
for _, obj in ipairs(ok and type(objs) == "table" and objs or {}) do callIfHas(obj, "setPlaying", msg) end
end
local function seatsMoved() Wait.time(function() TEAM.tellCards() end, 0.5) end
function onPlayerChangeColor() seatsMoved() end
function onPlayerConnect() seatsMoved() end
function onPlayerDisconnect() seatsMoved() end
function BOTTLE.throw(n, color, done)
DICE.request({ kinds = { "d6", "d6" }, color = color, done = done })
end
DICE.lanes = {}
DICE.ORDER = { d6 = 1, firepower = 2, injury = 3 }
function DICE.lane(key)
key = LAYOUT.SIDES[key] and key or "main"
local l = DICE.lanes[key]
if not l then
l = { key = key, queue = {}, shown = {}, joinToken = 0 }
DICE.lanes[key] = l
end
return l
end
function DICE.request(req)
local l = DICE.lane(req.lane)
if l.busy or #l.queue > 0 then l.queue[#l.queue + 1] = req else DICE.start(req) end
end
function DICE.line(lane)
if not self.positionToWorld then return nil end
local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
local b = LAYOUT.SIDES[lane]
local x, _, z = STAND.point(b and (b[1] + b[3]) / 2 - PANEL_W / 2 or 0, -PANEL_H / 2)
z = z + DICE.BELOW * k
local ox = STAND.point(0, 0)
local rx = STAND.point(100, 0)
local ok, a, b = pcall(function()
return self.positionToWorld({ x, 0, z }), self.positionToWorld({ x + rx - ox, 0, z })
end)
if not (ok and a and b) then return nil end
local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
local dx, dz = (b.x or b[1]) - ax, (b.z or b[3]) - az
local len = math.sqrt(dx * dx + dz * dz)
if len < 1e-6 then dx, dz, len = 1, 0, 1 end
return { x = ax, y = ay, z = az }, { x = dx / len, z = dz / len }
end
function DICE.start(req)
local l = DICE.lane(req.lane)
DICE.clear(l)
l.busy, req.dice = req, {}
req.mid, req.dir = DICE.line(req.lane)
local real = req.mid ~= nil and spawnObject ~= nil and Wait ~= nil and Wait.condition ~= nil
for _, kind in ipairs(req.kinds) do
if real then DICE.spawn(req, kind) else req.dice[#req.dice + 1] = { kind = kind } end
end
if not real then return DICE.finish(req) end
Wait.condition(function() DICE.finish(req) end, function() return req.finished or DICE.settled(req) end,
DICE.WAIT, function() DICE.finish(req) end)
end
function DICE.spawn(req, kind)
local i = #req.dice + 1
local k = i - 1
local off = (k % 2 == 1 and 1 or -1) * math.ceil(k / 2) * DICE.STEP + (math.random() - 0.5) * 0.3
if req.apart then off = (k - (#req.kinds - 1) / 2) * req.apart end
local m, d, url, s = req.mid, req.dir, DICE.URL[kind] or "", DICE.SCALE
local entry = { kind = kind, from = { x = m.x + d.x * off, y = m.y + DICE.DROP, z = m.z + d.z * off } }
req.dice[i] = entry
local ok, o = pcall(spawnObject, {
type = url ~= "" and "Custom_Dice" or DICE.PLAIN,
position = { entry.from.x, entry.from.y, entry.from.z },
rotation = { math.random(0, 359), math.random(0, 359), math.random(0, 359) },
scale = { s, s, s },
callback_function = function(obj)
pcall(function()
obj.setName(DICE.NAMES[kind] or "D6")
obj.addTag(DICE.TAG)
obj.addTag("gang-roster-roll")
if url == "" and req.color and stringColorToRGB then
local c = stringColorToRGB(req.color)
obj.setColorTint({ 0.45 + 0.55 * c.r, 0.45 + 0.55 * c.g, 0.45 + 0.55 * c.b })
end
local function turn() return (math.random() * 0.5 + 0.5) * DICE.SPIN * (math.random() < 0.5 and -1 or 1) end
local av = { turn(), turn(), turn() }
local a, v = math.random() * 2 * math.pi, (math.random() * 0.5 + 0.5) * DICE.PUSH
local function go()
pcall(function()
if obj.isDestroyed and obj.isDestroyed() then return end
obj.setAngularVelocity(av)
if v > 0 then
local ok, now = pcall(function() return obj.getVelocity() end)
local fall = ok and type(now) == "table" and tonumber(now.y or now[2]) or 0
obj.setVelocity({ v * math.cos(a), fall, v * math.sin(a) })
end
end)
end
entry.kick = go
go()
if Wait and Wait.frames then Wait.frames(go, 2) end
end)
end,
})
if ok and o and url ~= "" then pcall(function() o.setCustomObject({ image = url, type = 1 }) end) end
entry.obj = ok and o or nil
end
function DICE.settled(req)
local all = true
for _, d in ipairs(req.dice) do
if d.obj then
local ok, down = pcall(function()
if d.obj.isDestroyed() then return true end
if d.obj.spawning or not d.kick then return false end
if not d.fell then
local p = d.obj.getPosition()
local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
local f = d.from
if (x - f.x) ^ 2 + (y - f.y) ^ 2 + (z - f.z) ^ 2 < DICE.FALL ^ 2 then
d.waited = (d.waited or 0) + 1
if d.waited % DICE.KICK == 0 then d.kick() end
return false
end
d.fell = true
d.kick()
return false
end
return d.obj.resting == true
end)
if not (ok and down) then all = false end
end
end
return all
end
function DICE.finish(req)
if req.finished then return end
req.finished = true
local list = {}
for i, d in ipairs(req.dice) do
local face = nil
if d.obj then
local ok, v = pcall(function() return d.obj.getValue() end)
face = ok and tonumber(v) or nil
end
d.face, d.digital, d.at = face or math.random(1, 6), face == nil, i
list[i] = d
end
local thrown = {}
for i, d in ipairs(list) do thrown[i] = d end
if DICE.SORT ~= "thrown" and not req.inOrder then
table.sort(list, function(a, b)
local ka, kb = DICE.ORDER[a.kind] or 9, DICE.ORDER[b.kind] or 9
if ka ~= kb then return ka < kb end
if a.face ~= b.face then
if DICE.SORT == "down" then return a.face > b.face end
return a.face < b.face
end
return a.at < b.at
end)
end
DICE.lineUp(req, list)
local l = DICE.lane(req.lane)
l.shown, l.busy = list, nil
DICE.deliver(req, thrown)
DICE.next(l)
end
function DICE.lineUp(req, list)
if not req.mid then return end
local low = nil
for _, d in ipairs(list) do
local ok, p = pcall(function() return d.obj.getPosition() end)
local y = ok and p and tonumber(p.y or p[2])
if y then low = math.min(low or y, y) end
end
local okR, r = pcall(function() return self.getRotation() end)
local yaw = (okR and r and tonumber(r.y or r[2])) or 0
local n, m, dir = #list, req.mid, req.dir
for i, d in ipairs(list) do
if d.obj then
local off = (i - (n + 1) / 2) * (req.apart or DICE.STEP)
pcall(function()
d.obj.setPositionSmooth({ m.x + dir.x * off, low or m.y + 1, m.z + dir.z * off }, false, true)
local rot = DICE.faceUp(d.obj, d.face, yaw + (DICE.TURN[d.kind] or 0))
if rot then d.obj.setRotationSmooth(rot, false, true) end
end)
end
end
Wait.time(function()
for _, d in ipairs(list) do
if d.obj then pcall(function() if not d.obj.isDestroyed() then d.obj.setLock(true) end end) end
end
end, 1.5)
end
function DICE.faceUp(o, face, yaw)
local ok, rv = pcall(function() return o.getRotationValues() end)
for _, r in ipairs(ok and type(rv) == "table" and rv or {}) do
local rot = r.rotation
if rot and tostring(r.value) == tostring(face) then
return { rot.x or rot[1] or 0, ((rot.y or rot[2] or 0) + yaw) % 360, rot.z or rot[3] or 0 }
end
end
end
function DICE.deliver(req, list)
local faces, digital = {}, false
for i, d in ipairs(list) do faces[i], digital = d.face, digital or d.digital end
if req.done then req.done(faces, digital, list) end
if req.from then
local ok, o = pcall(getObjectFromGUID, req.from)
if ok and o then
callIfHas(o, "onDiceThrown", { token = req.token, faces = faces, digital = digital })
end
end
if req.own then
DICE.say(req, list, digital)
DICE.bus(req, list, digital)
end
end
DICE.armed = false
DICE.held = nil
DICE.KINDS = { d6 = { "D6", "D6" }, firepower = { "Firepower", "FIREPOWER" }, injury = { "Injury", "INJURY" } }
function DICE.busSend(event, t)
event.seq = __nqs_mundane_bus.nextSeq()
event.t = t
__nqs_mundane_bus.publish(JSON.encode(event))
end
function DICE.busPlain(p)
local gang = LAYOUT.SIDES[p.lane] and SETUP.side(p.lane) or nil
DICE.busSend({ kind = "roll", label = "D6", gang = gang, side = p.lane,
dice = __nqs_mundane_bus.diceArray({ p.face }, "D6"), digital = p.digital or nil, player = p.color }, p.t)
end
function DICE.pairEnd(rearm)
local p = DICE.held
DICE.held = nil
DICE.armed = rearm and true or false
if p then DICE.busPlain(p) end
end
function DICE.bus(req, list, digital)
local t = Time.time
if #list == 1 and list[1].kind == "d6" and LAYOUT.SIDES[req.lane] then
local me = { lane = req.lane, face = list[1].face, color = req.color, t = t, digital = digital }
local other = DICE.held
if not DICE.armed then
DICE.busPlain(me)
return
end
if not other then DICE.held = me; return end
if other.lane == me.lane then
DICE.pairEnd(false)
DICE.busPlain(me)
return
end
DICE.held = nil
local a, b = (me.lane == 1) and me or other, (me.lane == 1) and other or me
local win = a.face ~= b.face and (a.face > b.face and 1 or 2) or nil
DICE.armed = (win == nil)
DICE.busSend({ kind = "roll", label = "Priority",
dice = __nqs_mundane_bus.diceArray({ a.face, b.face }, "D6"),
sides = { SETUP.side(1), SETUP.side(2) },
priority = win and { side = win, gang = SETUP.side(win) } or nil,
outcome = win and { winner = win } or { tie = true },
digital = (a.digital or b.digital) and true or nil,
player = req.color }, t)
return
end
DICE.pairEnd(false)
for _, kind in ipairs({ "d6", "firepower", "injury" }) do
local faces, best = {}, nil
for _, d in ipairs(list) do if d.kind == kind then faces[#faces + 1] = d.face end end
if #faces > 0 then
local outcome
if kind == "firepower" then
local hits, ammo = 0, false
for _, f in ipairs(faces) do
local c = DICE.CHART.firepower[f] or DICE.CHART.firepower[1]
hits, ammo = hits + c.hits, ammo or c.ammo == true
end
outcome = { hits = hits, ammo_checks = ammo or nil }
elseif kind == "injury" then
local results = {}
for i, f in ipairs(faces) do results[i] = DICE.CHART.injury[f] or "serious" end
outcome = { results = results }
end
DICE.busSend({ kind = "roll", label = DICE.KINDS[kind][1],
gang = LAYOUT.SIDES[req.lane] and SETUP.side(req.lane) or nil, side = req.lane,
dice = __nqs_mundane_bus.diceArray(faces, DICE.KINDS[kind][2]), outcome = outcome,
digital = digital or nil, player = req.color }, t)
end
end
end
function DICE.announce(msg, rgb)
if broadcastToAll then broadcastToAll(msg, rgb) else printToAll(msg, rgb) end
end
RULES.follow(function()
DICE.INJURY, DICE.LABEL, DICE.RANK = {}, {}, {}
for k, r in pairs(RULES.injury) do
DICE.INJURY[k], DICE.LABEL[k], DICE.RANK[k] = r.short or r.label, r.label or r.short, r.rank or 0
end
end)
function DICE.say(req, list, digital)
local d6, fp, inj, total, hits, ammo, best = {}, {}, {}, 0, 0, false, nil
for _, d in ipairs(list) do
if d.kind == "firepower" then
local f = DICE.CHART.firepower[d.face] or DICE.CHART.firepower[1]
fp[#fp + 1] = string.format("%d hit%s%s", f.hits, f.hits == 1 and "" or "s", f.ammo and " + Ammo" or "")
hits, ammo = hits + f.hits, ammo or f.ammo == true
elseif d.kind == "injury" then
local k = DICE.CHART.injury[d.face] or "serious"
inj[#inj + 1] = DICE.INJURY[k]
if not best or (DICE.RANK[k] or 0) > (DICE.RANK[best] or 0) then best = k end
else
d6[#d6 + 1], total = tostring(d.face), total + d.face
end
end
local parts = {}
if #d6 == 1 then parts[#parts + 1] = "a D6: " .. d6[1]
elseif #d6 > 1 then parts[#parts + 1] = string.format("%dD6: %s = %d", #d6, table.concat(d6, " + "), total) end
if #fp == 1 then
parts[#parts + 1] = "the Firepower dice: " .. fp[1]:gsub(" %+ Ammo$", " + Ammo check")
elseif #fp > 1 then
parts[#parts + 1] = string.format("%d Firepower dice: %s = %d hits%s", #fp, table.concat(fp, ", "), hits,
ammo and " -- Ammo check" or "")
end
if #inj > 0 then
parts[#parts + 1] = "Injury dice: " .. (#inj > 1 and table.concat(inj, ", ") .. " = " or "") .. DICE.LABEL[best]
end
local rgb = { 0.9, 0.9, 0.9 }
if req.color and stringColorToRGB then
local ok, c = pcall(stringColorToRGB, req.color)
if ok and c then rgb = c end
end
local who = CHAT_PREFIX .. (req.color or "Someone")
if LAYOUT.SIDES[req.lane] then who = "[" .. SETUP.side(req.lane) .. "]" end
DICE.announce(string.format("%s rolls %s%s", who, table.concat(parts, "; "),
digital and " (rolled digitally)" or ""), rgb)
end
function DICE.clear(l)
for _, d in ipairs(l.shown) do
if d.obj then pcall(function() if not d.obj.isDestroyed() then d.obj.destruct() end end) end
end
l.shown = {}
local keep = {}
for _, o in pairs(DICE.lanes) do
for _, d in ipairs(o.shown) do if d.obj then keep[d.obj] = true end end
for _, d in ipairs(o.busy and o.busy.dice or {}) do if d.obj then keep[d.obj] = true end end
end
pcall(function()
for _, o in ipairs(getObjectsWithTag(DICE.TAG)) do if not keep[o] then o.destruct() end end
end)
end
function DICE.next(l)
if #l.queue == 0 then return end
local function go()
if l.busy or #l.queue == 0 then return end
DICE.start(table.remove(l.queue, 1))
end
if l.shown[1] and l.shown[1].obj then Wait.time(go, DICE.NEXT) else go() end
end
function DICE.click(kind, player, lane)
local color = player and player.color or nil
local l = DICE.lane(lane)
local req = l.open
if req and req.color ~= color then
l.open = nil
DICE.request(req)
req = nil
end
if req then
if #req.kinds < DICE.MAX then req.kinds[#req.kinds + 1] = kind end
else
req = { kinds = { kind }, color = color, own = true, lane = lane }
l.open = req
end
l.joinToken = l.joinToken + 1
local t = l.joinToken
Wait.time(function()
if l.joinToken == t and l.open == req then
l.open = nil
DICE.request(req)
end
end, DICE.JOIN)
end
function throwDice(t)
t = type(t) == "table" and t or {}
local kind = DICE.ORDER[t.kind] and t.kind or "d6"
local kinds = {}
if type(t.kinds) == "table" and #t.kinds > 0 then
for i = 1, math.min(DICE.MAX, #t.kinds) do kinds[i] = DICE.ORDER[t.kinds[i]] and t.kinds[i] or "d6" end
end
for i = #kinds + 1, math.max(1, math.min(DICE.MAX, math.floor(tonumber(t.n) or 1))) do kinds[i] = kind end
DICE.request({ kinds = kinds, color = t.color, label = t.label, from = t.from, token = t.token })
return true
end
function DICE.side(id) return tonumber(tostring(id or ""):match("_(%d+)$")) end
function onRollDiceBtn(player, value, id) if TEAM.refuse(player) then return end DICE.click("d6", player, DICE.side(id)) end
function onRollFirepowerBtn(player, value, id) if TEAM.refuse(player) then return end DICE.click("firepower", player, DICE.side(id)) end
function onRollInjuriesBtn(player, value, id) if TEAM.refuse(player) then return end DICE.click("injury", player, DICE.side(id)) end
function onFighterOut(t)
t = type(t) == "table" and t or {}
local gang = trim(tostring(t.gang or ""))
local key = BOTTLE.key(gang)
if key == "" then return end
local due = not t.back and not BOTTLE.due[key]
if due then BOTTLE.due[key] = "due" end
local shown = false
for n = 1, 2 do
for _, sl in ipairs(BOTTLE.slots(n)) do
if BOTTLE.key(sl.gang) == key then shown = true; BOTTLE.drawSlot(sl) end
end
end
if not due then return end
__nqs_mundane_bus.emit({ kind = "state_change", field = "bottle_due", gang = gang, from = false, to = true,
cause = { action = "fighter_out", fighter = tostring(t.name or "") },
player = t.player and tostring(t.player) or nil })
printToAll(string.format("[%s] %s is Out of Action: %s must take a Bottle Check this round.%s", gang,
tostring(t.name or "A fighter"), gang,
shown and "" or " Put one of its models on the table in front of a side panel of the Mundane Controller."), { 1, 0.55, 0.2 })
end
function onBottleHead(player, value, id)
if TEAM.refuse(player) then return end
local n, sl = BOTTLE.slotOf(id)
if not n or tostring(value) == "-2" or tostring(value) == "-3" then return end
if not (sl and BOTTLE.named(n)) then
broadcastToAll(string.format("%sBottle Check: no gang on the %s yet -- put one of your gang's models on your " ..
"side panel of the Mundane Controller.", CHAT_PREFIX, n == 1 and "left" or "right"), { 1, 0.55, 0.2 })
return
end
local key = BOTTLE.key(sl.gang)
local on = BOTTLE.due[key] ~= "due"
BOTTLE.due[key] = on and "due" or nil
for m = 1, 2 do
for _, other in ipairs(BOTTLE.slots(m)) do
if BOTTLE.key(other.gang) == key then BOTTLE.drawSlot(other) end
end
end
printToAll(string.format("%sBottle Check for %s %s (set by hand)", CHAT_PREFIX, sl.gang,
on and "to take this round" or "no longer to take"), { 1, 0.55, 0.2 })
__nqs_mundane_bus.emit({ kind = "state_change", field = "bottle_due", gang = trim(tostring(vpNames[n])), side = n,
from = not on, to = on, why = "by hand", player = player and player.color or nil })
return on
end
function onBottleValue(player, value, id)
if TEAM.refuse(player) then return end
local n, sl = BOTTLE.slotOf(id)
if not sl then return end
local v = BOTTLE.valueOf(sl) or 7
BOTTLE.hand[sl.sfx] = math.max(2, math.min(12, v + (tostring(value) == "-2" and -1 or 1)))
BOTTLE.drawSlot(sl)
if BOTTLE.hand[sl.sfx] ~= v then
__nqs_mundane_bus.emit({ kind = "state_change", field = "leadership", gang = trim(tostring(sl.gang or SETUP.side(n))),
side = n, from = v, to = BOTTLE.hand[sl.sfx], why = "by hand", player = player and player.color or nil })
end
end
function onBottleRoll(player, value, id)
if TEAM.refuse(player) then return end
local n, sl = BOTTLE.slotOf(id)
if not n then return end
if not (sl and BOTTLE.named(n)) then
broadcastToAll(string.format("%sBottle Check: no gang on the %s yet -- put one of your gang's models on your " ..
"side panel of the Mundane Controller.", CHAT_PREFIX, n == 1 and "left" or "right"), { 1, 0.55, 0.2 })
return
end
local gang = sl.gang
local target, who = BOTTLE.hand[sl.sfx], "set by hand"
if not target then
local _ = nil
target, _, who = BOTTLE.target(gang)
end
local key = BOTTLE.key(gang)
if BOTTLE.due[key] == "due" then BOTTLE.due[key] = "done" end
BOTTLE.drawSlot(sl)
local color = player and player.color or nil
BOTTLE.throw(n, color, function(faces, digital)
local total = faces[1] + faces[2]
local verdict = nil
if not target then
verdict = "no Ld to test against (set one on the Ld diamond)"
elseif total <= target then
verdict = string.format("needs %d or less%s: PASS -- the gang holds its nerve",
target, who and (" (" .. who .. ")") or "")
else
verdict = string.format("needs %d or less%s: FAIL%s -- %s of %s must leave the battlefield",
target, who and (" (" .. who .. ")") or "", total == 12 and " (a natural 12)" or "",
total == 12 and "2 models" or "1 model", gang)
end
DICE.announce(string.format("[%s] Bottle Check (2D6): %d + %d = %d, %s%s", gang, faces[1], faces[2], total,
verdict, digital and " (rolled digitally)" or ""),
(target and total <= target) and { 0.3, 1, 0.4 } or { 1, 0.35, 0.3 })
__nqs_mundane_bus.emit({
kind = "roll", action = "bottle check",
gang = gang,
dice = __nqs_mundane_bus.diceArray({ faces[1], faces[2] }, "D6"),
direction = target and "lte" or nil,
target = target,
outcome = {
passed = target and (total <= target) or nil,
total = total,
natural_12 = (total == 12) and true or nil,
models_leaving = (target and total > target) and (total == 12 and 2 or 1) or nil,
},
player = color,
})
end)
end
local function everyFighter(fn, arg)
local skip, updated = {}, 0
local ok, importers = pcall(function() return getObjectsWithTag(IMPORTER_TAG) end)
for _, imp in ipairs(ok and type(importers) == "table" and importers or {}) do
local okU, list = callIfHas(imp, "upgradeCards")
for _, guid in ipairs(okU and type(list) == "table" and list or {}) do
if not skip[guid] then skip[guid], updated = true, updated + 1 end
end
end
local done = 0
for _, obj in ipairs(getAllObjects()) do
if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) and not skip[obj.getGUID()] then
if callIfHas(obj, fn, arg) then done = done + 1 end
end
end
return done, updated
end
local function updatedNote(n)
return n > 0 and string.format(" (%d older card(s) brought up to date first -- press again for them)", n) or ""
end
local function drawTurn()
self.UI.setAttribute("setupPanel", "active", tostring(turn < 1))
self.UI.setAttribute("turnView", "active", tostring(turn >= 1))
local number, size = roundView()
setLabel("turnText", number)
SHAPE.size("turnText", size)
local text, noteSize, on = SETUP.note()
self.UI.setAttribute("roundNote", "active", tostring(on))
SHAPE.size("roundNote", noteSize)
setLabel("roundNote", text)
end
function onAdvanceTurn(player, value, id)
if TEAM.refuse(player) then return end
if tostring(id) == "turnBack" and tostring(value) ~= "-2" then return end
if tostring(value) == "-2" then
local was = turn
if turn > 0 then BOTTLE.newTurn() end
turn = math.max(0, turn - 1)
drawTurn()
if was == 1 then DEPLOY.again() end
DICE.pairEnd(false)
if turn ~= was then SETUP.busRound(was, player and player.color or nil) end
return
end
turn = turn + 1
drawTurn()
BOTTLE.newTurn()
local n, up = everyFighter("setReady", true)
if turn == 1 then
everyFighter("resetReliable")
DEPLOY.remove()
end
printToAll(string.format("%sRound %d: %d fighter(s) readied%s.", CHAT_PREFIX, turn, n, updatedNote(up)),
{ 0.3, 1, 0.4 })
if turn == 1 then SETUP.busStart(player and player.color or nil) end
DICE.pairEnd(true)
__nqs_mundane_bus.emit({
kind = "state_change", action = "ready_all", field = "ready_all",
round = turn, n = n,
player = player and player.color or nil,
})
end
function onSetup(player, value, id)
if TEAM.refuse(player) then return end
local k = tonumber(tostring(id or ""):match("^setupBtn_(%d+)$"))
local row = k and SETUP.ROWS[k]
if row and row.deploy and tostring(value) == "-2" then
if not DEPLOY.remove() then DEPLOY.again() end
return
end
if row and row.map then
SETUP.nextMap(k)
return SETUP.busMap(player and player.color or nil)
end
if not row or tostring(value) ~= "-1" or SETUP.rolling[k] then return end
if row.rollOff then return SETUP.rollOff(k, player and player.color or nil) end
if not row.results then return end
SETUP.rolling[k] = true
SETUP.draw(k)
DICE.request({ kinds = { "d6" }, color = player and player.color or nil, done = function(faces, digital)
local was = SETUP.rolled[row.key]
SETUP.rolling[k] = nil
SETUP.rolled[row.key] = faces[1]
SETUP.draw(k)
DICE.announce(string.format("%s%s: %s%s", CHAT_PREFIX, row.say, row.results[faces[1]],
digital and " (rolled digitally)" or ""), SETUP.SAY)
if row.deploy then DEPLOY.spawn(faces[1], row.results[faces[1]]) end
if was ~= faces[1] then SETUP.busRow(k, player and player.color or nil) end
end })
end
function SETUP.nextMap(k)
local i = 1
for n, size in ipairs(DEPLOY.SIZES) do if size == SETUP.map then i = n end end
SETUP.map = DEPLOY.SIZES[i % #DEPLOY.SIZES + 1]
SETUP.draw(k)
if #DEPLOY.find() > 0 then DEPLOY.again() end
end
function onDeployTool(player, value, id)
if TEAM.refuse(player) then return end
id = tostring(id or "")
local by = 0
if id == "deployTurn" then DEPLOY.turn, by = (DEPLOY.turn + DEPLOY.TURN) % 360, DEPLOY.TURN
elseif id == "deployUp" then DEPLOY.tall = DEPLOY.tall + DEPLOY.STEP
elseif id == "deployDown" then DEPLOY.tall = math.max(DEPLOY.STEP, DEPLOY.tall - DEPLOY.STEP)
else return end
for _, o in ipairs(DEPLOY.find()) do
pcall(function()
if by ~= 0 then
local p, r = o.getPosition(), o.getRotation()
local x, z = DEPLOY.turned(p.x or p[1] or 0, p.z or p[3] or 0, by)
o.setPosition({ x, p.y or p[2] or 0, z })
o.setRotation({ 0, ((r.y or r[2] or 0) + by) % 360, 0 })
end
local sc = o.getScale()
o.setScale({ sc.x or sc[1] or 1, DEPLOY.tall, sc.z or sc[3] or 1 })
end)
end
end
function onSwapRoles(player, value, id)
if TEAM.refuse(player) then return end
if tostring(value) == "-1" then
SETUP.swap()
SETUP.busAttacker(player and player.color or nil)
end
end
function SETUP.busRow(k, color, replay)
local row = SETUP.ROWS[k]
local face = row and row.results and SETUP.rolled[row.key]
if not face then return end
__nqs_mundane_bus.emit({ kind = "setup", field = row.key, to = row.results[face], face = face,
player = color, replay = replay })
end
function SETUP.busMap(color, replay)
__nqs_mundane_bus.emit({ kind = "setup", field = "map", to = SETUP.map, player = color, replay = replay })
end
function SETUP.busAttacker(color, replay)
__nqs_mundane_bus.emit({ kind = "setup", field = "attacker", to = SETUP.attacker,
gang = SETUP.side(SETUP.attacker), player = color, replay = replay })
end
function SETUP.busGang(n, color, replay)
__nqs_mundane_bus.emit({ kind = "setup", field = "gang", side = n, to = trim(tostring(vpNames[n] or "")),
player = color, replay = replay })
end
function SETUP.busVp(n, was, color, replay)
__nqs_mundane_bus.emit({ kind = "state_change", field = "vp", side = n, from = was, to = vp[n],
player = color, replay = replay })
end
function SETUP.busStart(color, replay)
__nqs_mundane_bus.emit({ kind = "setup", field = "start", round = 1, player = color, replay = replay })
end
function SETUP.busRound(was, color)
__nqs_mundane_bus.emit({ kind = "state_change", field = "round", from = was, to = turn, player = color })
end
function publishState()
Wait.frames(function()
for k in ipairs(SETUP.ROWS) do SETUP.busRow(k, nil, true) end
SETUP.busMap(nil, true)
if SETUP.rolled.sides or SETUP.attacker ~= 1 then SETUP.busAttacker(nil, true) end
for n = 1, 2 do if BOTTLE.named(n) then SETUP.busGang(n, nil, true) end end
for n = 1, 2 do SETUP.busVp(n, nil, nil, true) end
if turn >= 1 then
SETUP.busStart(nil, true)
__nqs_mundane_bus.emit({ kind = "state_change", action = "ready_all", field = "ready_all",
round = turn, replay = true })
end
end, 1)
end
function RESET.draw()
SHAPE.paint("resetFighters", RESET.asking and RESET.ASKING or "plain", RESET.asking and RESET.ASK or RESET.LABEL)
end
function onResetFighters(player, value, id)
if TEAM.refuse(player) then return end
if tostring(value) ~= "-1" then return end
RESET.token = RESET.token + 1
if not RESET.asking then
RESET.asking = true
RESET.draw()
local token = RESET.token
Wait.time(function()
if token == RESET.token and RESET.asking then RESET.asking = false; RESET.draw() end
end, RESET.WAIT)
return
end
RESET.asking = false
RESET.draw()
local n, up = everyFighter("resetFighter")
printToAll(string.format("%s%d fighter(s) reset to how they were imported%s.", CHAT_PREFIX, n, updatedNote(up)),
{ 1, 0.7, 0.2 })
end
function onClearConditions(player, value, id)
if TEAM.refuse(player) then return end
local n, up = everyFighter("clearConditions")
printToAll(string.format("%sConditions cleared on %d fighter(s)%s.", CHAT_PREFIX, n, updatedNote(up)),
{ 1, 0.7, 0.2 })
end
RULES.custom, RULES.active = {}, {}
function RULES.stack(a, b)
local out = RULES.copy(type(a) == "table" and a or {})
if type(b) ~= "table" then return out end
for part, kind in pairs(RULES.PARTS) do
local o, t = b[part], out[part]
if type(o) ~= "table" then
elseif type(t) ~= "table" or kind == "list" then
out[part] = RULES.copy(o)
elseif kind == "map" or kind == "values" then
local d = RULES.DEFAULT[part]
for k, v in pairs(o) do
local was = t[k]
if type(v) == "table" and type(was) == "table" and not RULES.isList(v) and not RULES.isList(was) then
for f, x in pairs(v) do t[k][f] = RULES.copy(x) end
else
t[k] = RULES.copy(v)
if type(v) == "table" and not RULES.isList(v) and type(d[k]) == "table"
and not RULES.isList(d[k]) and (was == false or (type(was) == "table" and RULES.isList(was))) then
for f in pairs(d[k]) do if v[f] == nil then t[k][f] = false end end
end
end
end
else
for _, e in ipairs(o) do t[#t + 1] = RULES.copy(e) end
end
end
return out
end
function HOMEBREW.overrides()
local out = RULES.copy(RULES.custom)
for _, set in ipairs(HOMEBREW.SETS) do
if HOMEBREW.on[set.id] then out = RULES.stack(out, set.rules) end
end
for _, set in ipairs(HOMEBREW.SETS) do
local own = set.perPlayer and HOMEBREW.colours[set.id]
if own and next(own) then
local yes, no = {}, {}
for colour, v in pairs(own) do
local list = v and yes or no
list[#list + 1] = colour
end
table.sort(yes); table.sort(no)
out = RULES.stack(out, { cfg = { [set.perPlayer.on] = yes, [set.perPlayer.off] = no } })
end
end
return out
end
RULES.STAGGER = 1
function RULES.push(gap)
gap = tonumber(gap) or 0
local cards = {}
for _, obj in ipairs(getAllObjects()) do
if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) and hasFunction(obj, "loadRules") then cards[#cards + 1] = obj end
end
for k, obj in ipairs(cards) do
if gap <= 0 or k == 1 then
callIfHas(obj, "loadRules")
else
Wait.time(function()
local ok, gone = pcall(function() return obj.isDestroyed() end)
if not (ok and gone) then callIfHas(obj, "loadRules") end
end, (k - 1) * gap)
end
end
return #cards
end
function RULES.sansTurning(over)
local out = RULES.copy(over or {})
if type(out.cfg) == "table" then
for _, k in ipairs({ "performanceMode", "performanceFor", "qualityFor" }) do out.cfg[k] = nil end
if next(out.cfg) == nil then out.cfg = nil end
end
return out
end
function RULES.refresh()
local now = HOMEBREW.overrides()
if RULES.same(now, RULES.active) then return false, 0 end
local turning = RULES.same(RULES.sansTurning(now), RULES.sansTurning(RULES.active))
RULES.active = now
RULES.use(now)
return true, RULES.push(not turning and RULES.STAGGER or 0)
end
function getRules()
return RULES.copy(RULES.active)
end
function setRules(t)
RULES.custom = RULES.copy(type(t) == "table" and t or {})
local changed, n = RULES.refresh()
if changed then
printToAll(string.format("%sRules changed: %s -- %d fighter(s) told.", CHAT_PREFIX,
next(RULES.active) and "the table's own" or "the rules as written", n), { 1, 0.7, 0.2 })
end
return changed
end
function HOMEBREW.find(id)
for i, set in ipairs(HOMEBREW.SETS) do
if set.id == id then return i, set end
end
end
function HOMEBREW.button()
local n = #HOMEBREW.list()
return n > 0 and string.format("Settings (%d on)", n) or "Settings"
end
function HOMEBREW.target()
return HOMEBREW.scope == "me" and HOMEBREW.you or nil
end
function HOMEBREW.chosen(set, colour)
local own = colour and HOMEBREW.colours[set.id]
if own and own[colour] ~= nil then return own[colour] == true end
return HOMEBREW.on[set.id] == true
end
function HOMEBREW.changed()
for _, set in ipairs(HOMEBREW.SETS) do
local want = HOMEBREW.pick[set.id] == true
if set.perPlayer then
local who = HOMEBREW.target()
if who then
if want ~= HOMEBREW.chosen(set, who) then return true end
elseif want ~= (HOMEBREW.on[set.id] == true) or next(HOMEBREW.colours[set.id] or {}) then
return true
end
elseif want ~= (HOMEBREW.on[set.id] == true) then return true end
end
return false
end
function HOMEBREW.applyLook()
return HOMEBREW.changed() and "gold" or "plain"
end
function HOMEBREW.draw(i)
local set = HOMEBREW.SETS[i]
for k = 1, 2 do
local look, label = hbLook(set, k)
SHAPE.paint(string.format("hbOpt_%d_%d", i, k), look, label)
if set.perPlayer then
local sl, slabel = hbScopeLook(k)
SHAPE.paint("hbScope_" .. k, sl, slabel)
end
end
local desc, size = HOMEBREW.desc(i)
setLabel("hbDesc_" .. i, desc)
SHAPE.size("hbDesc_" .. i, size)
SHAPE.paint("homebrewApply", HOMEBREW.applyLook())
end
function HOMEBREW.show(on)
HOMEBREW.page = on == true
HOMEBREW.pick, HOMEBREW.scope = {}, "me"
for id in pairs(HOMEBREW.on) do HOMEBREW.pick[id] = true end
for _, set in ipairs(HOMEBREW.SETS) do
if set.perPlayer then HOMEBREW.pick[set.id] = HOMEBREW.chosen(set, HOMEBREW.you) or nil end
end
for i in ipairs(HOMEBREW.SETS) do HOMEBREW.draw(i) end
self.UI.setAttribute("playSection", "active", tostring(not HOMEBREW.page))
self.UI.setAttribute("homebrewPage", "active", tostring(HOMEBREW.page))
SHAPE.paint("homebrewBtn", "plain", HOMEBREW.button())
end
function HOMEBREW.say(what, changed, told)
printToAll(string.format("%sHomebrew: %s -- %s.", CHAT_PREFIX, what,
changed and string.format("%d fighter(s) told", told) or "no change to the rules"), { 1, 0.7, 0.2 })
end
function HOMEBREW.apply()
local what = {}
for _, set in ipairs(HOMEBREW.SETS) do
local want = HOMEBREW.pick[set.id] == true
local who = set.perPlayer and HOMEBREW.target()
if who then
if want ~= HOMEBREW.chosen(set, who) then
local own = HOMEBREW.colours[set.id] or {}
if want == (HOMEBREW.on[set.id] == true) then own[who] = nil else own[who] = want end
HOMEBREW.colours[set.id] = next(own) and own or nil
what[#what + 1] = hbText((want and set.name or set.off) .. " for " .. who)
end
elseif want ~= (HOMEBREW.on[set.id] == true) or (set.perPlayer and HOMEBREW.colours[set.id]) then
HOMEBREW.on[set.id] = want or nil
HOMEBREW.colours[set.id] = nil
what[#what + 1] = hbText((want and set.name or set.off) .. (set.perPlayer and " for everyone" or ""))
end
end
HOMEBREW.show(false)
if #what == 0 then return false end
local changed, told = RULES.refresh()
HOMEBREW.say(table.concat(what, ", "), changed, told)
return true
end
function HOMEBREW.switch(id, on)
local i, set = HOMEBREW.find(id)
if not i then return false end
if on == nil then on = not HOMEBREW.on[id] end
if (HOMEBREW.on[id] == true) == (on == true) then return false end
HOMEBREW.on[id] = on == true or nil
HOMEBREW.pick[id] = HOMEBREW.on[id]
HOMEBREW.draw(i)
SHAPE.paint("homebrewBtn", "plain", HOMEBREW.button())
local changed, told = RULES.refresh()
HOMEBREW.say(hbText(on and set.name or set.off), changed, told)
return true
end
function HOMEBREW.list()
local out = {}
for _, set in ipairs(HOMEBREW.SETS) do
if HOMEBREW.on[set.id] then out[#out + 1] = set.id end
end
return out
end
function HOMEBREW.at(player)
local ok, colour = pcall(function() return player.color end)
if ok and type(colour) == "string" and colour ~= "" then HOMEBREW.you = colour end
end
function onHomebrewOpen(player, value, id)
if TEAM.refuse(player) then return end
HOMEBREW.at(player)
HOMEBREW.show(true)
end
function onHomebrewBack(player, value, id) if TEAM.refuse(player) then return end HOMEBREW.show(false) end
function onHomebrewOption(player, value, id)
if TEAM.refuse(player) then return end
local i, k = tostring(id or ""):match("^hbOpt_(%d+)_([12])$")
i = tonumber(i)
local set = i and HOMEBREW.SETS[i]
if not set then return end
HOMEBREW.at(player)
HOMEBREW.pick[set.id] = k == "2" or nil
HOMEBREW.draw(i)
end
function onHomebrewScope(player, value, id)
if TEAM.refuse(player) then return end
local k = tostring(id or ""):match("^hbScope_([12])$")
if not k then return end
HOMEBREW.at(player)
HOMEBREW.scope = k == "2" and "all" or "me"
for i, set in ipairs(HOMEBREW.SETS) do
if set.perPlayer then HOMEBREW.draw(i) end
end
end
function onHomebrewApply(player, value, id)
if TEAM.refuse(player) then return end
HOMEBREW.at(player)
HOMEBREW.apply()
end
function onFeedback(player, value, id)
FEEDBACK.open(PANEL, PANEL_H)
end
function onInfo(player, value, id)
if FEEDBACK.INFO_URL == "" then
return printToAll(CHAT_PREFIX .. "No instructions page yet.", { 0.8, 0.8, 0.8 })
end
FEEDBACK.open(PANEL, PANEL_H, "info")
end
FEEDBACK.BEYOND = 6.5
function FEEDBACK.spot()
local x, _, z = STAND.point(0, PANEL_H / 2)
local dx0, _, dz0 = STAND.point(0, PANEL_H / 2 - 100)
local ok, a, b = pcall(function()
return self.positionToWorld({ x, 0, z }), self.positionToWorld({ dx0, 0, dz0 })
end)
if not (ok and a and b) then return nil end
local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
local dx, dz = (b.x or b[1]) - ax, (b.z or b[3]) - az
local len = math.sqrt(dx * dx + dz * dz)
if len < 1e-6 then dx, dz, len = 0, 1, 1 end
dx, dz = dx / len, dz / len
return { ax - dx * FEEDBACK.BEYOND, ay + FEEDBACK.LIFT, az - dz * FEEDBACK.BEYOND },
{ FEEDBACK.TILT, math.deg((math.atan2 or math.atan)(dx, dz)) + FEEDBACK.TURN, 0 }
end
function FEEDBACK.draw(on)
local look = (on == true or on == "feedback") and "gold" or "plain"
pcall(function()
SHAPE.paint("feedback", look)
self.UI.setAttribute("feedbackText", "color", LOOK.BUTTONS[look].ink)
SHAPE.paint("info", on == "info" and "plain" or "dim")
end)
end
function getHomebrew()
local out = {}
for _, set in ipairs(HOMEBREW.SETS) do
out[#out + 1] = { id = set.id, name = set.name, off = set.off, on = HOMEBREW.on[set.id] == true }
end
return out
end
function setHomebrew(t)
t = type(t) == "table" and t or {}
local on = t.value
if on ~= nil then on = on == true end
return HOMEBREW.switch(t.id, on)
end
function onSave()
return JSON.encode({ version = VERSION, turn = turn, vp = vp, vpNames = vpNames, bottle = BOTTLE.due, rules = RULES.custom,
teams = { gangs = TEAM.gangs, tagged = TEAM.tagged },
homebrew = HOMEBREW.list(), homebrewColours = HOMEBREW.colours, setup = { attacker = SETUP.attacker, rolled = SETUP.rolled, map = SETUP.map,
deployTurn = DEPLOY.turn, deployTall = DEPLOY.tall } })
end
function onLoad(saved)
if Updater_stateVersion then
local _ = nil
_, VERSION = Updater_stateVersion(saved)
end
local ok, data = pcall(function() return JSON.decode(saved or "") end)
if ok and type(data) == "table" then
turn = tonumber(data.turn) or turn
for i = 1, 2 do
vp[i] = tonumber((data.vp or {})[i]) or vp[i]
vpNames[i] = (data.vpNames or {})[i] or vpNames[i]
end
if type(data.bottle) == "table" then BOTTLE.due = data.bottle end
local teams = type(data.teams) == "table" and data.teams or {}
for i = 1, 2 do
local L = {}
for _, e in ipairs(type(teams.gangs) == "table" and type(teams.gangs[i]) == "table" and teams.gangs[i] or {}) do
if type(e) == "table" and type(e.gang) == "string" and #L < 2 then
L[#L + 1] = { gang = e.gang, steam = e.steam, color = e.color }
end
end
TEAM.gangs[i] = L
end
if type(teams.tagged) == "table" then TEAM.tagged = teams.tagged end
if type(data.rules) == "table" then RULES.custom = data.rules end
if type(data.setup) == "table" then
SETUP.attacker = data.setup.attacker == 2 and 2 or 1
for _, size in ipairs(DEPLOY.SIZES) do
if tonumber(data.setup.map) == size then SETUP.map = size end
end
DEPLOY.turn = tonumber(data.setup.deployTurn) or DEPLOY.turn
DEPLOY.tall = math.max(DEPLOY.STEP, tonumber(data.setup.deployTall) or DEPLOY.tall)
SETUP.rolled = {}
for _, row in ipairs(SETUP.ROWS) do
local face = row.key and tonumber((data.setup.rolled or {})[row.key])
if face and (row.rollOff and (face == 1 or face == 2) or row.results and row.results[face]) then
SETUP.rolled[row.key] = face
end
end
end
if type(data.homebrew) == "table" then
HOMEBREW.on = {}
for _, id in ipairs(data.homebrew) do
if HOMEBREW.find(id) then HOMEBREW.on[id] = true end
end
end
HOMEBREW.colours = {}
for id, own in pairs(type(data.homebrewColours) == "table" and data.homebrewColours or {}) do
local _, set = HOMEBREW.find(id)
if set and set.perPlayer and type(own) == "table" then
local keep = {}
for colour, v in pairs(own) do
if type(colour) == "string" and type(v) == "boolean" then keep[colour] = v end
end
HOMEBREW.colours[id] = next(keep) and keep or nil
end
end
end
RULES.active = HOMEBREW.overrides()
RULES.use(RULES.active)
HOMEBREW.page, HOMEBREW.pick = false, {}
for id in pairs(HOMEBREW.on) do HOMEBREW.pick[id] = true end
pcall(function() if not self.hasTag(CONTROLLER_TAG) then self.addTag(CONTROLLER_TAG) end end)
TEAM.shown = { TEAM.of(1), TEAM.of(2) }
self.UI.setXml(panelXml(), panelAssets())
TEAM.tag()
if TEAM.playingMsg().all then TEAM.told = "all" else TEAM.tellCards(true) end
Wait.time(BOTTLE.tick, BOTTLE.POLL, -1)
if next(RULES.active) then Wait.frames(function() RULES.push(RULES.STAGGER) end, 2) end
end

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
local TOOL_ID        = "mundane-controller"
local TOOL_VERSION   = "3.1.0"                 -- bumped with manifest.json
local TOOL_SIGNATURE = "TTS-SELFUPDATE:mundane-controller"

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
