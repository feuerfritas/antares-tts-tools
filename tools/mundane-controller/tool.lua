-- TTS-SELFUPDATE:mundane-controller
--
-- ==============================================================
--  MUNDANE CONTROLLER (N26) by Antares77
--
--  The table's game, on one panel: in the middle column, before the game
--  the setup (the scenario, objective and crews rolled, Attacker and
--  Defender, then "Start Game"), then the round -- End Round readies every
--  fighter for the next; either side a player's panel with their gang, their
--  victory points and the gang's Bottle Check, due once one of its fighters
--  has gone Out of Action this round. Every roll the fighter cards make (and
--  its own Roll Dice / Roll Firepower / Roll Injuries buttons, under the
--  side panels) falls in a line under the panel (see DICE).
--
--  The fighter cards find it by its tag (CONTROLLER_TAG): they have it
--  throw their dice (throwDice), tell it when a fighter goes Out of
--  Action (onFighterOut) and ask it for the table's own rules (getRules:
--  see RULES) -- the homebrew rules chosen on the panel's Settings
--  page (see HOMEBREW) are those rules. Cards older than the Mundane
--  Importer's are brought up to date by the importer, when there is one on
--  the table, before this calls on every fighter.
-- ==============================================================

-- NQS fork, see TTSModfile.yaml `forked: true`:
-- `__nqs_mundane_bus.publish(json)` is the publish-to-game-recorder helper
-- the MR !27 ACTIVATION patches call from the gang-level event sites
-- (bottle check, group activation open). The code is inlined here as the
-- Mundane Importer (e4e1fb) carries an identical copy; see that file for
-- the reasons we did not reach for `require(...)` -- any edit to the body
-- must land in both copies in the same commit. See CHANGELOG.md
-- [Unreleased] "Changed -- MI3".
if __nqs_mundane_bus == nil then
  __nqs_mundane_bus = { __seq = 0 }

  function __nqs_mundane_bus.publish(json_string)
    for _, obj in ipairs(getObjectsWithTag("gamerecorder")) do
      pcall(obj.call, "bus_publish", json_string)
    end
  end

  -- A monotonic per-publisher sequence number. See the Mundane Importer's
  -- copy of this block for the full header.
  function __nqs_mundane_bus.nextSeq()
    __nqs_mundane_bus.__seq = __nqs_mundane_bus.__seq + 1
    return __nqs_mundane_bus.__seq
  end

  function __nqs_mundane_bus.diceArray(faces, kind)
    local out = {}
    for i, f in ipairs(faces) do
      out[i] = { type = kind or "D6", value = f, face = tostring(f) }
    end
    return out
  end

  -- No `stamp_guid` here: a Controller event is gang-level, not a
  -- fighter's. See the Mundane Importer's copy for the full header.
  function __nqs_mundane_bus.emit(event)
    event.seq = __nqs_mundane_bus.nextSeq()
    event.t = Time.time
    if __nqs_mundane_bus.stamp_guid and event.guid == nil then event.guid = self.getGUID() end
    __nqs_mundane_bus.publish(JSON.encode(event))
  end
end

local CONTROLLER_NAME = "Mundane Controller"
local VERSION         = "?"   -- the running version, handed over by the updater block

--@@SHARED_BEGIN
-- ══════════════════════════════════════════════════════════════
--  Shared: the same in the Mundane Importer and the Mundane
--  Controller (copied in whole from Mundane_Shared.lua, where it is kept)
-- ══════════════════════════════════════════════════════════════

-- What concerns no gang in particular (turns, conditions cleared on the
-- table, a gang yet to be named) starts with this in chat -- as the
-- cards' lines do (their CFG.infoPrefix is the same [Info]). A line about
-- one gang starts with its name, "[Goliaths] ".
local CHAT_PREFIX = "[Info] "

-- Tag added to every model that receives a card, so other scripts can find them.
local IMPORT_TAG = "Mundane Import"

-- The Mundane Importer's own tag, put on it when it loads: the Controller
-- asks it to bring older cards up to date (its upgradeCards) before it
-- calls on every fighter.
local IMPORTER_TAG = "Mundane Importer"

-- The Mundane Controller's own tag, put on it when it loads: a fighter's
-- card has whatever carries it throw its dice (throwDice) and tells it
-- when the fighter goes Out of Action (onFighterOut). The card's
-- CFG.controllerTag is the same.
local CONTROLLER_TAG = "Mundane Controller"

-- The tag naming the gang a model was last imported for (the gang's name
-- from the roster export follows), so the models of one gang can be found
-- together -- the importer's "Apply UI to the whole Gang" / "Reset UI for
-- the whole Gang" work on them, the Controller's Bottle Check counts them.
-- No " - " in it: TTS won't take one in a tag typed by hand, and players
-- can put a model in a gang themselves ("Mundane Gang_Goliaths").
-- The card has the same (CFG.gangTag).
local GANG_TAG = "Mundane Gang_"
-- earlier versions' tags: removed on import. The first two were gang tags
-- and still count as one until then (see gangOf; the card's
-- CFG.oldGangTags).
local OLD_TAGS = { "Mundane Gang - ", "Mundane Controller_", "Mundane Gang: ", "Mundane Owner: " }

local function trim(s)
    s = (s or ""):gsub("^%s+", "")
    return (s:gsub("%s+$", ""))
end

-- A model's gang tag, if it has one -- or its gang tag from before GANG_TAG
-- (OLD_TAGS[1] / [2]), until it is imported again.
local function gangOf(obj)
    local ok, tags = pcall(function() return obj.getTags() end)
    for _, pre in ipairs({ GANG_TAG, OLD_TAGS[1], OLD_TAGS[2] }) do
        for _, t in ipairs(ok and tags or {}) do
            if t:sub(1, #pre) == pre and #t > #pre then return t end
        end
    end
end

-- obj.call(fn, arg), protected, only if `obj`'s script has the global
-- function `fn` (its text is looked at first): a call to a function a
-- script lacks -- a model with no card yet, a card older than the function
-- -- makes TTS log "Lua Error <fn>: Object reference not set to an
-- instance of an object", which no pcall hides. Something that can't hand
-- over its script is called anyway. Whether it ran, and what it returned.
--   Looking means copying the whole script out of TTS -- a fighter card's
-- is most of a megabyte, and a new turn asks every one. So a script that
-- carries MUNDA_STAMP (a mark it sets anew each time it loads: the cards,
-- this script) is read once: every function it has is noted (KNOWN, by
-- GUID) and holds for as long as its mark stays the same -- a reload, a
-- card brought up to date, gives it a new one.
MUNDA_STAMP = table.concat({ os.time(), os.clock(), math.random(1, 999999999) }, "-")
local KNOWN = {}
local function callIfHas(obj, fn, arg)
    local okG, guid = pcall(function() return obj.getGUID() end)
    guid = okG and type(guid) == "string" and guid or nil
    local known, has = guid and KNOWN[guid], nil
    if known then
        local ok, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
        if ok and stamp ~= nil and stamp == known.stamp then has = known.fns[fn] == true else KNOWN[guid] = nil end
    end
    if has == nil then
        local ok, script = pcall(function() return obj.getLuaScript() end)
        has = not (ok and type(script) == "string") or script:find("function " .. fn .. "(", 1, true) ~= nil
        if ok and type(script) == "string" and guid and script:find("MUNDA_STAMP", 1, true) then
            local okV, stamp = pcall(function() return obj.getVar("MUNDA_STAMP") end)
            if okV and stamp ~= nil then
                local fns = {}
                for name in script:gmatch("function ([%w_]+)%(") do fns[name] = true end
                KNOWN[guid] = { stamp = stamp, fns = fns }
            end
        end
    end
    if not has then return false end
    return pcall(function() return obj.call(fn, arg) end)
end

-- ── The panel's look ─────────────────────────────────────────────

-- How finely the panel's text is drawn: the panel is built this many times
-- its size and shown scaled back down, so every glyph has that many times
-- the texels -- sharper up close (1 = built at its own size).
local PANEL_DETAIL = 2

-- The parchment picture behind the panel (the AoS Coherency Tool's, by
-- Antares77), hosted on the Steam Cloud.
local PANEL_BG = "https://steamusercontent-a.akamaihd.net/ugc/12352082712112839381/58ABA6CE8570F5CB9E72C7E53BE4BE3A2CD8C9F7/"
local BG_RATIO = 1847 / 1337           -- the parchment picture's height / width

-- The panel's look (after the AoS Coherency Tool by Antares77): an
-- anthracite border round a parchment field with its
-- picture, anthracite type, and buttons that are a white wash over the
-- picture with a soft bevel. A lit button -- Import, Apply, the chosen
-- background, the Controller's bars and plates -- is anthracite with a
-- pale label.
local INK, PALE, PAPER = "#293133", "#F2F1EC", "#E6E5E1"
local WASH  = "#FFFFFF40|#FFFFFF73|#FFFFFF26|#FFFFFF26"
local LIT   = "#293133E6|#3A4447E6|#1C2224E6|#29313366"
local RED   = "#7A2020D9|#963030D9|#5A1515D9|#7A202066"
local BEVEL = ' outline="#29313366" outlineSize="2 2"'
local function colors(c) return string.format("%s|%s|%s|%s", c, c, c, c) end

local function xmlEsc(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- A text or button label changed in place: TTS takes a button's label as
-- its "text" attribute, a text's as its value -- both are set.
local function setLabel(id, text)
    self.UI.setAttribute(id, "text", text)
    self.UI.setValue(id, text)
end

-- ── Where a panel lies on its object ─────────────────────────────

-- A point `x`, `y` panel units from the middle of a panel (position /
-- rotation / scale like PANEL; the panel's own axes: x to the right, y up
-- as it reads), in its object's own space: local x and z. An object's UI
-- x / y lie along its local x / z, 100 UI units to a local unit; a panel
-- turned half round ("0 0 180") reads the right way up from the object's
-- +z side.
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

-- ── Feedback ─────────────────────────────────────────────────────

-- The header's Feedback button (top right) and the tablet it puts up: a
-- TTS Tablet showing the feedback form (FEEDBACK.URL), locked, lying past
-- the panel's top edge and tilted towards the players so it is easy to
-- read. The importer and the Controller share it: one form, one tablet --
-- either one's button takes it away again, or moves it to its own panel.
-- Both buttons are lit (anthracite, pale label) while the tablet shows the
-- form. The Controller's Supported Mechanics button puts the same tablet
-- up showing the instructions page (INFO_URL, the tablet named INFO_NAME)
-- instead: a press on either button while the tablet shows the other's
-- page turns it to this one's, where it stands.
local FEEDBACK = {
    MARK = "✉︎", TEXT = "Feedback",   -- the envelope its own text: with the word it leaves a wide gap
    W = 124, H = 30, MARK_W = 22,           -- the button, and the envelope's room in it (panel units)
    URL   = "https://docs.google.com/forms/d/e/1FAIpQLSdOTHX_jjUigf9HpH9mRPav5yBvyKPLSV9g1Q09N9dnUHUU7g/viewform?usp=publish-editor",
    NAME  = "Mundane Feedback",             -- the tablet's name
    INFO_URL  = "",                         -- the instructions page (empty: none yet)
    INFO_NAME = "Mundane Supported Mechanics",   -- the tablet's name while it shows that page
    TAG   = "Mundane Feedback",             -- the tablet's tag
    -- the tags of the tablets older scripts put up, one each: found and
    -- taken away like the shared one
    OLD   = { "Mundane Feedback_Mundane Importer", "Mundane Feedback_Mundane Controller" },
    -- where the tablet lies (see FEEDBACK.spot): from the point across this
    -- object's middle from the panel's top edge, PAST world units on along
    -- the panel's down direction (negative: back towards the panel's up)
    PAST  = -4.5,
    LIFT  = 2,      -- and this high above this object
    TILT  = 30,     -- leaned back this far (degrees)
    TURN  = 0,      -- turned this much more about the vertical, from the panel's down direction
}

-- Every feedback tablet on the table (the shared one, and any an older
-- script put up), as a list -- empty also outside TTS.
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

-- The feedback tablet, or nil.
function FEEDBACK.tablet()
    return FEEDBACK.tablets()[1]
end

-- What the tablet shows: "feedback" (the form), "info" (the instructions
-- page, told by the tablet's name) or nil (no tablet).
function FEEDBACK.showing()
    local tab = FEEDBACK.tablet()
    if not tab then return nil end
    local ok, name = pcall(function() return tab.getName() end)
    return (ok and name == FEEDBACK.INFO_NAME) and "info" or "feedback"
end

-- The name and the page of the tablet showing `what` ("feedback" / "info").
function FEEDBACK.page(what)
    if what == "info" then return FEEDBACK.INFO_NAME, FEEDBACK.INFO_URL end
    return FEEDBACK.NAME, FEEDBACK.URL
end

-- The button: a plain button with the envelope and the word over it, lit
-- while the tablet shows the form (FEEDBACK.draw changes it in place).
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

-- The button lit or not, in place, for what the tablet shows (`on`: as
-- FEEDBACK.showing says, or true / false from an older script: the form
-- or nothing).
function FEEDBACK.draw(on)
    on = on == true or on == "feedback"
    pcall(function()
        self.UI.setAttribute("feedbackBtn", "colors", on and LIT or WASH)
        self.UI.setAttribute("feedbackMark", "color", on and PALE or INK)
        self.UI.setAttribute("feedbackText", "color", on and PALE or INK)
    end)
end

-- Asked by the other script when it puts the tablet up, turns it to the
-- other page or takes it away, so all the buttons agree.
function feedbackLit(on)
    FEEDBACK.draw(on)
end

-- This script's buttons and every other importer's and Controller's lit
-- or not, for what the tablet shows (`what`: as FEEDBACK.showing says).
-- The form is passed on as true, which an older script also takes.
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

-- Where the tablet goes for a panel (position / rotation / scale like
-- PANEL) `h` tall: its centre and rotation in the world -- nil outside TTS.
-- It is reckoned from the point across this object's middle from the
-- panel's top edge, along the panel's down direction (PAST, TURN).
function FEEDBACK.spot(panel, h)
    local x, z = panelLocal(panel, 0, h / 2)              -- the panel's top edge
    local ux, uz = panelLocal(panel, 0, h / 2 + 100)      -- and on up the panel
    local ok, a, b = pcall(function()                     -- both across the middle
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

-- The tablet shows `url` -- left alone if it does already.
function FEEDBACK.show(tab, url)
    local ok, cur = pcall(function() return tab.Browser.url end)
    if not (ok and cur) then ok, cur = pcall(function() return tab.getValue() end) end
    if ok and cur == url then return end
    if not pcall(function() tab.Browser.url = url end) then pcall(function() tab.setValue(url) end) end
end

-- A button pressed: the tablet put up over a panel (PANEL) `h` tall,
-- showing `what` ("feedback", the default, or "info") -- or, when it is up
-- already (put up by either script), taken away if it shows that, else
-- turned to it where it stands. A press while the tablet is still
-- spawning does nothing.
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
    pcall(function() Wait.time(function() FEEDBACK.spawning = nil end, 5) end)   -- a spawn that never came back
    FEEDBACK.drawAll(what)
end

-- The whole panel round its content: the defaults, an anthracite border
-- (3) round the parchment field with its picture, and in it a column
-- (padding 9, rows 6 apart) of the header (40 tall: version and credit on
-- the left, the title in the middle) and then `t.body`, its rows; `t.over`
-- goes over the whole field. t = { id, position, rotation, scale, width,
-- height, title, version, body, over }.
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

-- The panel built PANEL_DETAIL times its size (every size in the XML
-- multiplied, font sizes kept whole) and scaled back down by the same, so
-- it covers the same table but its text has that many times the texels.
-- `root`: the id of the panel whose scale takes it back.
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
--@@SHARED_END

--@@RULES_BEGIN
-- ══════════════════════════════════════════════════════════════
--  Rules: the same in the fighter card and the Mundane Controller
--  (copied in whole from Mundane_Rules.lua, where it is kept)
-- ══════════════════════════════════════════════════════════════

-- The game's rules as data: every action, condition, skill, piece of
-- wargear and weapon accessory the card knows, the dice's faces, the
-- stats' limits, the weapon traits it reacts to and the ranges it
-- measures. Everything here is the default -- the N26 rules. A table's own
-- rules (homebrew) are kept by the Mundane Controller as overrides and laid
-- over these (see RULES.merge): the card asks the Controller for them when
-- it loads and whenever the Controller says they have changed. One table,
-- RULES; the card knows its parts by their old names too (ACTIONS =
-- RULES.actions, ...).
local RULES = {}

-- The kinds of action, each with its colour in A's panel: a colour of the
-- card's (a COL key) or one of its own ("#RRGGBB").
RULES.actionTypes = {
    movement = "actMovement",   -- Movement
    close    = "actClose",      -- Close Combat
    shooting = "actShooting",   -- Shooting
    utility  = "actUtility",    -- Utility
    wyrd     = "actWyrd",       -- Wyrd
}

-- Every action a fighter can take. `cost` is S (a simple action), D (a
-- double one) or F (a free one, which spends no action but still counts as
-- used), shown in the arrow's diamond
-- (a cost like "S/C" -- C: continuous, only shown -- or "S/D" spends as
-- its first letter, see the card's SKILL.cost); actions have no icons.
-- `type` picks its colour (actionTypes); one with none keeps the plain
-- toggle colour. Clicking one spends it (see the card's useAction) and
-- calls the onActionChosen stub -- what an action does is up to the rules
-- layer, but for four the card knows by their keys: treat_ally,
-- group_activation, coup_de_grace and reload (see useAction) -- and after
-- dash no ranged weapon can be fired, but for one with Assault (see the
-- card's TRAIT_RULES.shot). `distance`: how far the action moves its
-- fighter, a list of { stat, times } added up -- "D6" for a die thrown for
-- it -- shown over the stats and said with the action (see the card's
-- ACTIVATION.moveBy), the bar's title `distanceTitle` or the label, the
-- cost and what it adds up ("Dash (D) - Mov + I", "Crawl (D) - Strength").
-- `escape`: Desperate Escape's D6 -- on this or more the fighter goes Out
-- Cold rather than Out of Action (see the card's ACTIVATION.escape).
-- `targets`: "one" -- aimed at the one fighter its player has selected,
-- not taken while several are -- or "several" (the card knows Treat Ally,
-- Coup de Grace and the Wyrd powers with a target as "one", Group
-- Activation as "several"; see its ACTIVATION.aimsAt). Fight and the Shoot actions pay for the
-- weapons' attacks: taken from the panel, they light up the weapons they
-- are for, and the attack after them spends nothing more (see the card's
-- ACTIVATION.attackCost). `desc`, when filled in, shows over the stats
-- while the cursor is on the action.
RULES.actions = {
    { key = "move",             label = "Move",             cost = "S", type = "movement", desc = "",
      distance = { { "M", 1 } } },
    { key = "dash",             label = "Dash",             cost = "D", type = "movement", desc = "",
      distance = { { "M", 1 }, { "I", 1 } } },
    { key = "engage",           label = "Engage",           cost = "S", type = "close",    desc = "",
      distance = { { "D6", 1 } } },
    { key = "charge",           label = "Charge",           cost = "D", type = "close",    desc = "",
      distance = { { "M", 1 }, { "D6", 1 } } },
    { key = "coup_de_grace",    label = "Coup de Grace",    cost = "S", type = "close",    desc = "" },
    { key = "interact",         label = "Interact",         cost = "S", type = "utility",  desc = "" },
    { key = "shoot",            label = "Shoot",            cost = "S", type = "shooting", desc = "" },
    { key = "braced_shot",      label = "Braced Shot",      cost = "D", type = "shooting", desc = "" },
    { key = "aimed_shot",       label = "Aimed Shot",       cost = "D", type = "shooting", desc = "" },
    { key = "reload",           label = "Reload",           cost = "S", type = "shooting", desc = "" },
    { key = "treat_ally",       label = "Treat Ally",       cost = "S", type = "utility",  desc = "" },
    { key = "group_activation", label = "Group Activation", cost = "S", type = "utility",  desc = "" },
    { key = "fight",            label = "Fight",            cost = "D", type = "close",    desc = "" },
    { key = "retreat",          label = "Retreat",          cost = "D", type = "movement", desc = "",
      distance = { { "I", 1 } } },
    { key = "crawl",            label = "Crawl",            cost = "D", type = "movement", desc = "",
      distance = { { "S", 1 } } },
    { key = "desperate_escape", label = "Desperate Escape", cost = "D", type = "movement", desc = "",
      escape = 3 },
    { key = "tend_wounds",      label = "Tend Wounds",      cost = "D", type = "utility",  desc = "" },
    -- not an action of the rules: it opens the Recovery Test panel (see
    -- the card's recoveryTest). `always`: never dimmed, spends no action,
    -- never used
    { key = "recovery_test",    label = "Recovery Test",    cost = "RT", type = "utility", always = true, desc = "" },
    -- `wyrd`: not in any status's panel -- a fighter that can use Wyrd
    -- powers (a Wyrd, fighter.category "wyrd", or one with a Wyrd power)
    -- has these on its Special tab while Active, Suppressed or Engaged
    { key = "maintain_control_f", label = "Maintain Control", cost = "F", type = "wyrd", wyrd = true, desc = "" },
    { key = "maintain_control_s", label = "Maintain Control", cost = "S", type = "wyrd", wyrd = true, desc = "" },
    { key = "concentrate",        label = "Concentrate",      cost = "S", type = "wyrd", wyrd = true, desc = "" },
}

-- What A's panel offers in each status, as its two columns: `right` next to
-- A, `left` beyond it, each top to bottom (keys of actions; one that isn't
-- there is left out). A status can leave a column out.
-- (Suppressed is Active without the double actions.)
RULES.statusActions = {
    active = {
        left  = { "move", "dash", "engage", "charge", "coup_de_grace", "interact" },
        right = { "shoot", "braced_shot", "aimed_shot", "reload", "treat_ally", "group_activation" },
    },
    suppressed = {
        left  = { "move", "engage", "coup_de_grace", "interact" },
        right = { "shoot", "reload", "treat_ally", "group_activation" },
    },
    engaged = {
        right = { "fight", "retreat" },
    },
    seriously_injured = {
        right = { "crawl", "desperate_escape", "tend_wounds", "recovery_test" },
    },
}

-- C's panel: conditions, each a named toggle with its icon (the card's
-- ASSETS cond_<key>; `short` stands in until the icon exists). None stack
-- except those marked `stacks`, which count up one per click in the panel
-- and down one per click in the bar under the stats. Hovering one's icon
-- in that bar shows its name and `desc` over the stats; hovering it in
-- C's panel shows them only when `desc` is filled in.
--   mods  = what the condition does to the stats, per stack. The card shows
--           the lowered number (never past RULES.limits) and stat tests use it.
--   set   = stats the condition sets to a number, whatever the changes above
--           make of it ({ WS = 6 }: Feared); shown green / orange for better
--           / worse than it would be.
--   hitOnly = the fighter's attacks of a kind ("melee", "ranged") hit only
--           on this natural roll or more, whatever modifies them
--           ({ melee = 6 }: Blind).
-- What a condition does beyond changing stats is the card's
-- onConditionChanged's.
RULES.conditions = {
    { key = "intoxicated", label = "Intoxicated", short = "ITX", desc = "" },
    { key = "radphage",    label = "Radphage",    short = "RAD", desc = "",
      mods = { T = -1 } },                    -- -1 Toughness while active
    { key = "concussion",  label = "Concussion",  short = "CON", desc = "", stacks = true,
      mods = { I = -1 } },                    -- -1 Initiative per stack (min 1)
    { key = "shackled",    label = "Shackled",    short = "SHK", desc = "" },
    { key = "webbed",      label = "Webbed",      short = "WEB", desc = "" },
    { key = "insanity",    label = "Insanity",    short = "INS", desc = "" },
    -- put on a fighter hit by a Flash weapon (the card's traitHit): its
    -- melee attacks hit only on a natural 6
    { key = "blind",       label = "Blind",       short = "BLD", desc = "",
      set = { WS = 6 }, hitOnly = { melee = 6 } },
    -- put on a fighter by a Fearsome enemy (the card's rollAttack), gone when
    -- its activation is over
    { key = "feared",      label = "Feared",      short = "FEA", desc = "",
      set = { WS = 6 } },                     -- WS 6+ while active
    -- on a Wyrd while a Continuous power is in effect (the card puts it on and
    -- takes it off with the power)
    { key = "maintaining_power", label = "Maintaining Power", short = "PWR", desc = "" },
    -- nothing of its own: a reminder for a custom condition
    { key = "special",     label = "Special",     short = "SPC", desc = "" },
    -- `auto`: never toggled by hand (not in C's panel) -- a fighter has it
    -- while a skill or wargear of its that says `condition` works
    -- (Berserker; Fearsome, Horrific Appearance)
    { key = "frenzy",      label = "Frenzy",      short = "FRZ", desc = "", auto = true,
      mods = { A = 1 } },                     -- +1 Attacks
    -- an enemy that starts a fight against it makes a Willpower check
    -- first, and fails into Feared (the card's rollAttack) -- unless it is
    -- Fearsome itself
    { key = "fearsome",    label = "Fearsome",    short = "FSM", desc = "", auto = true },
}

-- Skills (fighter.skills: the names as the roster lists them), matched by
-- name in any case. They show by name in a row under the stats, each
-- capitalised word by word (Counter-attack -> Counter-Attack) -- or as
-- `short`, if given. Hovering a name shows the full name and `desc`.
-- `mods` is what the skill does to the stats, as the conditions' (+1 is one
-- higher: { I = 1 }): the card shows the changed number (never past
-- RULES.limits) in green where that is better, orange where worse, and
-- hovering the stat lights the skill's name up in that colour. A skill
-- that is really an action has `action`, its cost (S, D or F, or a
-- combination like "F/C", as in the actions) and `type` (its colour,
-- actionTypes): it also goes into A's panel, under the Special tab. One
-- with `costs` changes what actions cost its fighter ({ <action key> =
-- new cost }, see the card's SKILL.costOf): Inspiring makes Group
-- Activation free. A skill not listed here still shows, with no
-- description. What else a skill can say:
--   weapon     a weapon it arms its fighter with (name and profiles, as a
--              weapon of the roster's: Headbutt) -- a roster that lists a
--              weapon of that name already keeps its own, which then is
--              the skill's all the same: no use while the skills are
--              disabled;
--   meleeS     what it adds to the Strength of the melee profiles with a
--              trait, { <key in traits> = N } (Heavy Blows: +1 with Heavy);
--   secondary  how many attacks the second melee weapon of an activation
--              starts at, instead of one (Two-Weapon Fighter; see the
--              card's TRAIT_RULES.opening);
--   master     true: it always assists a friend and interferes with an
--              enemy in close combat, however many enemies it is fighting
--              itself (Combat Master; see the card's TRAIT_RULES.supportNear).
--   springUp   true: activated while Suppressed, it makes an Agility test
--              and, passing it, keeps both its actions (Spring Up; see the
--              card's activate);
--   catfall    true: a fall counts one level less for it (never less than
--              the lowest), and an Agility test then saves it from being
--              Suppressed by the fall (Catfall; see the card's fallingDown);
--   distance   for a skill that is an action: the inches it moves its
--              fighter, shown and said in chat when it is taken -- a list
--              of { stat, times }, added up (Sprint: M + 2x I), as the
--              actions' own `distance` is;
--   lines      for a skill or wargear that is an action: what it shows
--              over the stats when it is taken, a line each (Drop Rig's
--              Descend: '3" horizontally', '12" vertically'), and says
--              in chat after its name;
--   fearsome   true: as `condition = "fearsome"` -- an enemy that starts a
--              fight against it makes a Willpower check first, and fails
--              into the Feared condition (see the card's rollAttack) --
--              unless it is Fearsome itself;
--   ironJaw    N: against attacks with no AP (and Light weapons used while
--              engaged), it counts N higher in Toughness (Iron Jaw: 2; see
--              the card's woundPlan);
--   steel      true: hit by a ranged attack, it may make a Cool check to
--              keep from being Suppressed (Nerves Of Steel; see the card's
--              rangedHit);
--   unstoppable  true: activating with a wound lost, it makes a Willpower
--              check at once, and regains a wound when it passes;
--   bullCharge true: once it has taken the Charge action in an activation,
--              its melee profiles are +1 Strength and have Knockback (6+)
--              -- one with a Knockback of its own keeps that (Bull Charge;
--              see the card's TRAIT_RULES.bull);
--   biceps     true: a Heavy melee weapon it fights with still lets it use
--              a second weapon, one that isn't Heavy (Bulging Biceps; see
--              the card's TRAIT_RULES.secondaryOk);
--   rainOfBlows  true: its first round of close combat in an activation
--              over and still Engaged, it fights a second round, for free
--              (Rain Of Blows; see the card's TRAIT_RULES.fought);
--   dodge      N: each wound that goes through its saves, a D6 -- N or more
--              and that wound is dodged -- while it still has wounds to lose
--              (Dodge: 6; see the card's ACTIVATION.dodge);
--   counterAttack  true: attacking in melee outside its own activation
--              (fighting back), it makes two attacks, not one (Counter-
--              Attack; see the card's TRAIT_RULES.opening);
--   juggernaut true: hit by a ranged attack, it is Suppressed only once
--              the attack is over, and only if it lost a wound or had an
--              Injury dice rolled for it (Juggernaut; see the card's
--              rangedHit);
--   condition  a condition's key: the fighter has that condition while the
--              skill works -- wargear: always (Berserker: "frenzy";
--              Fearsome, Horrific Appearance: "fearsome");
--   backstab   true: its melee weapons have the Backstab trait -- one that
--              has it already adds 2 to its Strength, not 1 (Backstab; see
--              the card's TRAIT_RULES.stab);
--   cutThroat  true: its Coup de Grace, when the enemy rolls more, is
--              rolled again, once (Cut-Throat; see the card's
--              ACTIVATION.coup);
--   lieLow     true: while it is Suppressed it can't be the target of a
--              ranged attack from beyond the weapon's Short Range -- an
--              enemy about to shoot it from there is told so, and asked
--              whether to go on (Lie Low; see the card's rollAttack);
--   shoots     N: it may make N Shoot actions in an activation, not one
--              (Fast Shot: 2) -- Shoot only, so never a second shot with a
--              Heavy weapon, which is a Braced Shot;
--   gunfighter true: its Shoot with a Light weapon lets it fire a second
--              weapon with Light as part of that action, for no action of
--              its own (Gunfighter; see the card's TRAIT_RULES.shot);
--   hipShooting  true: its ranged weapons without Heavy have the Assault
--              trait (Hip-Shooting);
--   marksman   N: while it isn't Engaged, its ranged attacks on an enemy
--              beyond the weapon's Short Range but within its Long Range
--              are N better to hit (Marksman: 1; see the card's
--              TRAIT_RULES.marksman);
--   aimed      N: its Aimed Shot is N better to hit, not 1 (Sharpshooter: 2);
--   precise    true: a natural 6 on the hit die of its ranged attack with a
--              profile that has neither Blast nor Rapid Fire (N) leaves the
--              target no armour save against that hit's wound -- an
--              invulnerable save can still be made (Precision Shot; see the
--              card's ACTIVATION.attackDice and ACTIVATION.rollSaves);
--   fastReload true: its Reload reloads every profile that is out of ammo,
--              not one (Fast Reload; see the card's reloadWeapon);
--   ironWill   N: while it is on the table, its gang's Bottle Checks are
--              taken against N more (Iron Will: 1; see the Mundane
--              Controller's Bottle Check);
--   statuses   for one that is an action: the statuses it can be taken in
--              -- on the Special tab only then (Sprint: Active; Heal Ally,
--              Distribute Ammo: Active or Suppressed); none: any;
--   label      for a skill that is an action: what the action is called
--              on the Special tab, when not by the skill's own name
--              (Munitioneer: Distribute Ammo);
--   heal       N: its action gives the one ally its player has selected --
--              itself too -- N wounds back, unless Seriously Injured
--              (Medicate's Heal Ally: 1; see the card's ACTIVATION.heal);
--   distribute N: its action hands out ammo -- every fighter of its gang
--              within N inches with a weapon out of ammo makes an
--              Intelligence check at once, and reloads on passing it
--              (Munitioneer: 6; see the card's ACTIVATION.distribute);
--   aka        other names the roster may list it under (a list: another
--              spelling finds the same entry);
--   when       a status's key: its `mods` count only while the fighter is
--              in that status (Mesh Armour: "engaged");
--   once       true, for one that is an action: it can be taken once a
--              game -- dimmed from then on, until the Mundane Controller's
--              Start Game (the Stimm-Slug);
--   boost      for one that is an action: what taking it does to the
--              stats, as `mods`, until the fighter is next activated
--              ({ M = 2, S = 2, T = 2 }: the Stimm-Slug);
--   reaction   what that boost costs as it ends: { roll = N, wounds = W }
--              -- a D6 as the fighter activates, W wounds lost on N or
--              less (see the card's ACTIVATION.comedown);
--   noFall     true: a fall does nothing to it -- no Agility test, no
--              wound, never Suppressed (Grav Chute; see the card's
--              fallingDown);
--   assist     N: a friend's Recovery test it assists is rolled with N
--              more Injury dice on top of the assist's own (Medicae Kit:
--              1; see the card's recoveryTest);
--   inv        N: an invulnerable save of N+ -- never worsened by AP, never
--              bettered by cover or anything else that betters a save; each
--              wound takes whichever of the two saves is better (see the
--              card's takeSaves) (Refractor Field: 5);
--   burns      true: the first natural 1 on a save taken with its `inv`
--              burns it out for the rest of the battle -- its name turns
--              grey, and a left click on it switches it back on or off
--              (Refractor Field; the Bio-Booster, which is used up so);
--   bioBooster N: the first time in the battle a wound that goes through
--              brings the fighter to 0 wounds, that wound's Lethality is N
--              less -- down to 0: two Injury dice of their own instead, the
--              better kept -- and the item is used up (`burns`: grey, a
--              left click puts it back; see the card's ACTIVATION.damage)
--              (Bio-Booster: 1);
--   noAp       words a weapon's name may start with (a list, any case):
--              hits from such a weapon have no AP against it (Reflec
--              Shroud: Las, Plasma, Melta);
--   immune     weapon traits (RULES.traits keys) that do nothing to it,
--              and conditions (keys) it never gets (Hazard Suit: Blaze,
--              Radphage);
--   gasInv     N: an invulnerable save of N+ against Gas weapons only
--              (Respirator: 5);
--   flashMod   N: added to the Initiative check it makes when hit by a
--              Flash weapon (Photo-Goggles: -2; see the card's traitHit);
--   agility    N: added to every Agility test it makes, and shown with A's
--              Agility Test (Heavy Carapace Armour: -1; see the card's
--              ACTIVATION.agility);
--   agilityReroll  "all": a failed Agility test of its is re-rolled once,
--              the second result standing -- "ones": a natural 1 is
--              (Tentacles: "all"; the better of it and a gang's re-roll
--              counts, never both; see the card's ACTIVATION.agilityReroll);
--   spends     true: taking its `once` action uses the item up for the
--              battle -- its name grey under the stats, its `mods` no
--              longer counting (Needle Spines once its Fire Spines is
--              taken; the Mundane Controller's Start Game gives it back);
--   burst      { range, profile = { S, AP, L, traits } }: its action hits
--              every other fighter within `range` inches, base to base --
--              friend or foe -- once, automatically, with that profile,
--              nearest first; the Wound roll, saves and Injury dice
--              follow as for any hit (Needle Spines' Fire Spines);
--   toxicBlood { range, profile }: each wound of an attack that goes
--              through its saves -- until it is down to 0 wounds -- counts;
--              once that attack is over, every other fighter within
--              `range` makes that many Agility tests, each failed one an
--              automatic hit with the profile, resolved nearest first, as
--              `burst` (Toxic Blood; see the card's ACTIVATION.toxicBlood);
--   voidSoul   true: an enemy or friendly Wyrd casting a power while it is
--              among the fighters selected is asked first -- go on, or
--              call the power off (Void Soul; see the card's useAction);
--   jumpDown   true: its Falling Down, from A's Special tab, first asks
--              whether it jumps down -- yes: its Agility test passes
--              whatever the die (Wing Membranes; see the card's
--              ACTIVATION.fallAsk);
--   activeMelee  a trait its melee profiles gain during its activation --
--              never one that has the trait already (Pyromantic Mantle:
--              "Blaze (5+)");
--   booster    as its fighter activates it is asked whether to use the
--              item; yes: until that activation is over, `mods` (never
--              past a stat's highest), the Flying subtype with `flying`,
--              on the charge `charge` -- { hit = to hit with every weapon,
--              S = to its Strength } -- and with `unstable` grenades and
--              Template weapons gain Unstable (Jump Booster; see the card's
--              ACTIVATION.boosterAsk);
--   refraction { moved, still }: a ranged attack on it (one with a hit
--              die) asks whether it moved in its last activation -- the
--              hit roll is `moved` worse, or `still` (Refraction Cloak: -1,
--              -2; see the card's ACTIVATION.cloaked);
--   check      a stat: its action does what it does only once the fighter
--              passes a check of that stat (Servo-Medicae's Auto-Medicate:
--              Int, then `heal`);
--   restrain   { test, fail, freeBy }: its action aimed at the one enemy
--              selected: the enemy makes the test ("agility", or a stat),
--              and gains condition `fail` on failing it -- with `freeBy`, a
--              stat: until a check of it, passed at the end of one of its
--              activations, frees it, as a Web hit's (Magnacles' Restrain:
--              Agility, Webbed, S; see the card's restrained);
--   enrage     { range, dice, stat, needReady, needStatus }: its action has
--              every friend completely within `range` inches -- its whole
--              base -- that is Ready (`needReady`) and in status
--              `needStatus` roll a D`dice`, one after the other, and add it
--              to `stat` until the end of the round (Corpse Grinder Cult
--              Icon's Enrage; see the card's enraged);
--   wyrdPower  (wargear) the importer gives its fighter the Wyrd subtype and
--              this Wyrd power, where the roster doesn't already (Conduit
--              Of Ozostium: Force Blast).
--   A wargear item's `aura` (below) is always in effect, shown in the plain
-- colours, not purple (Seven-Pointed Talisman).
-- What a Wyrd power (`type = "wyrd"`) does once manifested -- nothing
-- before: a power that fails, or is disrupted out of it, does none of it.
-- "While in effect" is for a Continuous power, until it ends (see the
-- card's ACTIVATION.cast); "until the end of the turn", until the fighter
-- is next readied (the Mundane Controller's next turn). Ranges are base to
-- base. Only an Active fighter can be Suppressed.
--   maintained { stat = N }: what it does to its Wyrd's own stats while in
--              effect, as `mods` (Quickening: +3 M, +2 I) -- shown purple;
--   overLimit  true: those may take a stat past its highest (RULES.limits);
--   weapon     (Continuous) the Wyrd is equipped with it only while in
--              effect (Force Blast, Scouring);
--   flaming    a trait one melee weapon of the Wyrd's gains while in
--              effect: its melee weapons light up purple, and the first
--              one clicked is the one (Flaming Weapon: "Blaze (5+)");
--   meleeL     N: its melee profiles' L, that much higher while in effect
--              (Warp Strength: 1);
--   target     what it does to the one enemy the player has selected as
--              it is cast (none selected, or too far: nothing):
--                range   inches (none: any distance);
--                roll    a stat the Wyrd tests first, nothing on a fail
--                        (Assail: "BS");
--                suppress  the enemy is Suppressed;
--                test    the test the enemy makes ("Cl", "Wil", "agility",
--                        "nerve" -- a Nerve Check, Suppressed on a fail);
--                ifReady the test only while the enemy has its Ready
--                        marker; needReady: nothing at all without it;
--                fail    what a failed test does: "unready" (it loses its
--                        Ready marker) or a condition's key ("insanity");
--                hit     a hit of { S, AP, L }: the Wound roll follows;
--                base    stats set to these, before any modifier, while in
--                        effect (Paroxysm: BS and WS 6+);
--                needStatus  only an enemy in this status; out: it goes Out
--                        of Action (Eternal Slumber);
--   area       what it does at once, until the end of the turn, to every
--              fighter of `side` ("friends", "enemies", "all") within
--              `range` -- and the Wyrd itself with `self`: `mods` (as a
--              condition's: Warp Shield, Sv one better) or `oneAction`
--              (one action when activated, Suppressed or not: Freeze Time);
--   aura       what it does while in effect to every fighter of `side`
--              within `range` (none: anywhere) -- as they come and go:
--              `mods`, or `lend` (stats it lends them where its own are
--              better: Unbreakable Will, Wil and Cl);
--   rerollHits true: while in effect, enemies re-roll every ranged hit
--              die that hits, once (Cacophony Of Silence);
--   void       N: while in effect, an enemy within N inches shooting the
--              Wyrd counts it as at Long range, never Short (A Perfect Void);
--   visions    { range, condition }: until the end of the turn, an enemy
--              ending its activation within range gains the condition
--              (Maddening Visions).
-- A fighter's skills do nothing while it is at 0 wounds, Seriously Injured
-- or Out of Action (the card's SKILL.off).
RULES.skills = {
    { name = "Counter-Attack", desc = "", counterAttack = true },
    { name = "Inspiring",      desc = "", costs = { group_activation = "F" } },
    { name = "Juggernaut",     desc = "", juggernaut = true },
    -- savant
    { name = "Fast Reload",    desc = "", fastReload = true },
    { name = "Iron Will",      desc = "", ironWill = 1 },
    { name = "Medicate",       desc = "", action = "S", type = "utility", label = "Heal Ally", heal = 1,
      statuses = { "active", "suppressed" } },
    { name = "Munitioneer",    desc = "", action = "S", type = "utility",
      label = "Distribute Ammo", distribute = 6, statuses = { "active", "suppressed" } },   -- within 6"
    -- agility
    { name = "Catfall",        desc = "", catfall = true },
    { name = "Dodge",          desc = "", dodge = 6 },
    { name = "Spring Up",      desc = "", springUp = true },
    { name = "Sprint",         desc = "", action = "D", type = "movement", statuses = { "active" },
      distance = { { "M", 1 }, { "I", 2 } } },   -- M + 2x I
    -- brawn
    { name = "Bull Charge",        desc = "", bullCharge = true },
    { name = "Bulging Biceps",     desc = "", biceps = true },
    -- close combat
    { name = "Berserker",          desc = "", condition = "frenzy" },
    { name = "Combat Master",      desc = "", master = true },
    { name = "Headbutt",           desc = "", weapon = { name = "Headbutt", profiles = {
        { SR = "E", LR = "-", S = "S+1", AP = "-", L = "1", traits = "Additional Attack (1), Melee" } } } },
    { name = "Heavy Blows",        desc = "", meleeS = { heavy = 1 } },
    { name = "Rain Of Blows",      desc = "", rainOfBlows = true },
    { name = "Two-Weapon Fighter", desc = "", secondary = 2 },
    { name = "Fearsome",           desc = "", condition = "fearsome" },
    { name = "Iron Jaw",           desc = "", ironJaw = 2 },
    { name = "Nerves Of Steel",    desc = "", steel = true },
    { name = "Unstoppable",        desc = "", unstoppable = true },
    -- cunning
    { name = "Backstab",   desc = "", backstab = true },
    { name = "Cut-Throat", desc = "", cutThroat = true },
    { name = "Lie Low",    desc = "", lieLow = true },
    -- shooting
    { name = "Fast Shot",    desc = "", shoots = 2 },
    { name = "Gunfighter",   desc = "", gunfighter = true },
    { name = "Hip-Shooting", desc = "", hipShooting = true },
    { name = "Marksman",     desc = "", marksman = 1 },
    { name = "Sharpshooter", desc = "", aimed = 2 },
    { name = "Precision Shot", desc = "", precise = true },
    -- Wyrd powers: actions on the Special tab, whatever the status
    -- ("/C": continuous -- it stays in effect, see the card's
    -- ACTIVATION.cast). What one does once manifested (see the card's
    -- ACTIVATION.manifest), as the fields above the list explain; one with
    -- none of them does nothing the card knows of.
    { name = "Force Blast",          desc = "", action = "F/C", type = "wyrd",
      weapon = { name = "Force Blast", profiles = {
        { SR = '8"', LR = '12"', S = "2", AP = "-1", L = "1", traits = "Knockback (3+)" } } } },
    { name = "Flaming Weapon",       desc = "", action = "F/C", type = "wyrd", flaming = "Blaze (5+)" },
    { name = "Freeze Time",          desc = "", action = "D",   type = "wyrd",
      area = { range = 12, side = "all", oneAction = true } },
    { name = "Weapon Jinx",          desc = "", action = "S",   type = "wyrd" },
    { name = "Terrify",              desc = "", action = "D",   type = "wyrd",
      target = { range = 18, suppress = true, test = "Cl", ifReady = true, fail = "unready" } },
    { name = "Quickening",           desc = "", action = "S/C", type = "wyrd",
      maintained = { M = 3, I = 2 }, overLimit = true },
    { name = "Hypnosis",             desc = "", action = "S",   type = "wyrd" },
    { name = "Unbreakable Will",     desc = "", action = "F/C", type = "wyrd",
      aura = { range = 9, side = "friends", lend = { "Wil", "Cl" } } },
    { name = "Zealot",               desc = "", action = "S/C", type = "wyrd" },
    { name = "Mind Control",         desc = "", action = "S",   type = "wyrd" },
    { name = "Assail",               desc = "", action = "S",   type = "wyrd",
      target = { roll = "BS", suppress = true } },
    { name = "Force Wave",           desc = "", action = "S",   type = "wyrd" },
    { name = "Catalyst",             desc = "", action = "F/C", type = "wyrd" },
    { name = "Hypnotic Gaze",        desc = "", action = "D",   type = "wyrd",
      target = { range = 9, needReady = true, test = "agility", fail = "unready" } },
    { name = "The Horror",           desc = "", action = "S",   type = "wyrd",
      target = { range = 12, test = "nerve" } },
    { name = "Leech Essence",        desc = "", action = "S",   type = "wyrd",
      target = { range = 12, hit = { S = 3, AP = -1, L = 1 } } },
    { name = "Paroxysm",             desc = "", action = "S/C", type = "wyrd",
      target = { range = 9, base = { BS = 6, WS = 6 } } },
    { name = "Aura Of Despair",      desc = "", action = "F/C", type = "wyrd",
      aura = { side = "enemies", mods = { Cl = -1 } } },
    { name = "Hallucinations",       desc = "", action = "S",   type = "wyrd",
      target = { range = 12, test = "Wil", fail = "insanity" } },
    { name = "Crush",                desc = "", action = "F",   type = "wyrd" },
    { name = "Force Field",          desc = "", action = "S/C", type = "wyrd" },
    { name = "Terrible Truths",      desc = "", action = "S",   type = "wyrd",
      target = { range = 6, test = "Wil", fail = "insanity" } },
    { name = "Psychotic Lure",       desc = "", action = "S",   type = "wyrd" },
    { name = "Deceitful Thoughts",   desc = "", action = "D",   type = "wyrd",
      target = { range = 6, test = "Wil" } },
    { name = "Cacophony Of Silence", desc = "", action = "S/C", type = "wyrd", rerollHits = true },
    { name = "A Perfect Void",       desc = "", action = "F/C", type = "wyrd", void = 10 },
    { name = "Eternal Slumber",      desc = "", action = "S",   type = "wyrd",
      target = { range = 3, needStatus = "seriously_injured", out = true } },
    { name = "Scouring",             desc = "", action = "F/C", type = "wyrd",
      weapon = { name = "Scouring", profiles = {
        { SR = "T", LR = "-", S = "2", AP = "-", L = "1", traits = "Blaze (5+), Template" } } } },
    { name = "Levitation",           desc = "", action = "F/C", type = "wyrd", maintained = { M = 3 } },
    { name = "Warp Strength",        desc = "", action = "F/C", type = "wyrd", maintained = { S = 2 }, meleeL = 1 },
    { name = "Warp Shield",          desc = "", action = "S",   type = "wyrd",
      area = { range = 3, side = "friends", self = true, mods = { Sv = -1 } } },
    { name = "Maddening Visions",    desc = "", action = "S",   type = "wyrd",
      visions = { range = 3, condition = "insanity" } },
}

-- Wargear (fighter.wargear: the names as the roster lists them), just as
-- the skills -- shown by name in its own row, under the skills' (in the
-- headers colour); `short`, `desc`, `mods`, `action` / `type`, `costs`
-- and the rest work the same -- but wargear never stops working: at 0
-- wounds its fighter still has all of it, its actions on the Special tab
-- too (only a Seriously Injured fighter takes none of those). The
-- roster's statline already counts what armour and mounts do: `mods` are
-- only for what it doesn't.
RULES.wargear = {
    { name = "Bio-Booster",            desc = "", aka = { "Bio Booster", "Biobooster" },
      bioBooster = 1, burns = true },
    { name = "Bomb Delivery Rats",     desc = "" },
    { name = "Cult Icon",              desc = "", groupReroll = true },   -- a failed Group Activation check re-rolled once
    { name = "Carapace Armour - Heavy", desc = "", aka = { "Heavy Carapace Armour", "Heavy Carapace", "Carapace Armour (Heavy)" },
      agility = -1 },
    { name = "Chaos Familiar",         desc = "" },
    { name = "Dirt Bike",              desc = "" },
    { name = "Drop Rig",               desc = "", action = "S", type = "utility", label = "Descend",
      lines = { '3" horizontally', '12" vertically' } },
    { name = "Grapnel Launcher",       desc = "", action = "D", type = "utility", label = "Grapnel",
      lines = { '12" straight', "end on higher level" } },
    { name = "Grav Chute",             desc = "", noFall = true },
    { name = "Hazard Suit",            desc = "", immune = { "blaze", "radphage" } },
    { name = "Medicae Kit",            desc = "", assist = 1 },
    { name = "Mesh Armour",            desc = "", aka = { "Mesh Armor" },
      mods = { Sv = -1 }, when = "engaged" },       -- a save one better in close combat
    { name = "Reflec Shroud",         desc = "", noAp = { "Las", "Plasma", "Melta" } },
    { name = "Photo-Goggles",          desc = "", aka = { "Photo Goggles" }, flashMod = -2 },
    { name = "Refractor Field",        desc = "", aka = { "Refractor Shield" }, inv = 5, burns = true },
    { name = "Respirator",             desc = "", gasInv = 5 },
    { name = "Stimm-Slug Stash",       desc = "", aka = { "Stim-Slug Stash" },
      action = "F", type = "utility", label = "Stimm-Slug", once = true,
      boost = { M = 2, S = 2, T = 2 }, reaction = { roll = 1, wounds = 1 } },
    -- Outcasts: the Ozostium artefacts
    { name = "Seven-Pointed Breastplate", desc = "" },      -- Sv +1: the roster's statline, once it has it
    { name = "Conduit Of Ozostium",    desc = "", wyrdPower = "Force Blast" },
    { name = "Gloves Of Ozostium",     desc = "", wyrdPower = "Flaming Weapon" },
    { name = "Seven-Pointed Talisman", desc = "", mods = { Cl = 1 },
      aura = { range = 6, side = "all", mods = { Cl = 1 } } },   -- every fighter within 6", and the bearer
    -- Outcasts: mutations (the roster lists them as wargear)
    { name = "Void Soul",              desc = "", voidSoul = true },
    { name = "Extra Appendage",        desc = "" },         -- +1 A: the roster's statline
    { name = "Horrific Appearance",    desc = "", condition = "fearsome" },
    { name = "Massive Claws",          desc = "" },         -- the roster's weapon
    { name = "Needle Spines",          desc = "", mods = { Sv = -1 }, when = "engaged",   -- a save one better in close combat
      action = "S", type = "utility", label = "Fire Spines", once = true, spends = true,
      statuses = { "active", "suppressed" },
      burst = { range = 3, profile = { S = "-", AP = "-", L = "1", traits = "Toxin (3+)" } } },
    { name = "Tentacles",              desc = "", agilityReroll = "all" },
    { name = "Toxic Blood",            desc = "",
      toxicBlood = { range = 1, profile = { S = "-", AP = "-", L = "1", traits = "Toxin (3+)" } } },
    { name = "Wing Membranes",         desc = "", jumpDown = true },
    -- Ironhead Squats
    { name = "Exo Suit",               desc = "", aka = { "Exo-Suit" }, immune = { "blaze", "radphage" } },
    -- Cawdor
    { name = "Book Of The Redemption", desc = "" },
    { name = "Pyromantic Mantle",      desc = "", activeMelee = "Blaze (5+)" },
    -- Delaque
    { name = "Psychomancer's Harness", desc = "", aka = { "Psychomancers Harness" } },   -- movement: the table's
    -- Orlock
    { name = "Jump Booster",           desc = "", aka = { "Jump-Booster" },
      booster = { mods = { M = 3 }, flying = true, charge = { hit = 1, S = 1 }, unstable = true } },
    -- Van Saar
    { name = "Augurspex",              desc = "" },
    { name = "Refraction Cloak",       desc = "", refraction = { moved = -1, still = -2 } },
    { name = "Servo-Medicae",          desc = "", aka = { "Servo Medicae" },
      action = "F", type = "utility", label = "Auto-Medicate", check = "Int", heal = 1,
      statuses = { "active", "suppressed" } },
    { name = "Vox Array",              desc = "", costs = { group_activation = "F" } },
    -- Palanite Enforcers
    { name = "Magnacles",              desc = "", action = "D", type = "close", label = "Restrain",
      statuses = { "engaged" }, restrain = { test = "agility", fail = "webbed", freeBy = "S" } },
    -- Corpse Grinder Cults
    { name = "Corpse Grinder Cult Icon", desc = "", action = "S", type = "utility", label = "Enrage",
      statuses = { "active" },
      enrage = { range = 6, dice = 3, stat = "M", needReady = true, needStatus = "active" } },
}

-- Weapon accessories. The roster names a weapon with its accessories in
-- brackets after it ("Lasgun (Mono-Sight)"): those listed here -- found in
-- any case, hyphens and spaces aside (Infra-Sight, Infrasight) -- are
-- taken out of the name the card shows and put after the traits of the
-- weapon's profiles instead. What most of them do is in the roster's
-- profile already; what one can say for the card to do:
--   aimed   N: an Aimed Shot with the weapon is N better to hit, not 1
--           (Mono-Sight: 2) -- not on top of a skill's (Sharpshooter): the
--           better of the two counts;
--   coverShort / coverLong  N: added to the cover a target within the
--           weapon's Short Range / beyond it (within Long Range) is asked
--           about (Las-Projector: Short -1, Telescopic Sight: Long -1) --
--           shown orange on its card, the accessory named in its bar;
--   aka     other names the roster may list it under (a list).
RULES.accessories = {
    { name = "Focusing Crystal" },
    { name = "Hotshot Las Pack" },
    { name = "Infra-Sight" },
    { name = "Las-Projector", coverShort = -1 },
    { name = "Mono-Sight", aimed = 2 },
    { name = "Suspensors" },
    { name = "Telescopic Sight", coverLong = -1 },
}

-- How each stat is tested (see the card's rollStat): the number of D6. M
-- and A are rolled but never tested. `under`: pass on a total at or below
-- the stat, otherwise at or above it. Roll-under stats also drop any "+"
-- on the card: a target rolled under reads "9", not "9+".
RULES.statRolls = {
    I   = { dice = 1, under = true  },
    T   = { dice = 1, under = true  },
    S   = { dice = 1, under = true  },
    Ld  = { dice = 2, under = true  },
    Wil = { dice = 2, under = true  },
    Int = { dice = 2, under = true  },
    Cl  = { dice = 2, under = true  },
    BS  = { dice = 1, under = false },
    WS  = { dice = 1, under = false },
    Sv  = { dice = 1, under = false },
}

-- The lowest and highest number each stat can show, whatever changes it:
-- a number set by hand, a condition, a skill, wargear or a weapon never
-- takes it past them. M is in inches; WS, BS and Sv are rolled at or over,
-- so 2+ (a save 3+) is the best they get and 6+ the worst. A right click on
-- a stat steps it up to its highest, then round to its lowest -- for
-- adjusting the statline by hand in play. `default`: any other (W).
RULES.limits = {
    M  = { 1, 12 },
    WS = { 2, 6 },  BS = { 2, 6 },  Sv = { 3, 6 },
    S  = { 1, 10 }, T  = { 1, 10 }, I  = { 1, 10 }, A = { 1, 10 },
    Ld = { 4, 10 }, Cl = { 4, 10 }, Wil = { 4, 10 }, Int = { 4, 10 },
    default = { 1, 10 },
}

-- The weapon traits the card reacts to, as Lua patterns (lower case,
-- matched against a whole comma-separated trait). N is a single digit.
RULES.traits = {
    melee     = "melee",
    smoke     = "smoke",              -- a hit with it doesn't Suppress (nor does Melee) and never wounds
    unstable  = "unstable",
    unwieldy  = "unwieldy",
    light     = "light",
    rapidFire = "rapid fire%s*%(%s*%d%+?%s*%)",   -- Rapid Fire (N) / (N+)
    paired    = "paired",               -- Paired (N)             (names only:
    additional = "additional attacks?", -- Additional Attack(s) (N)  see the card's TRAIT_RULES.number)
    backstab  = "backstab",           -- +1 S against an enemy a friend is fighting too
    combi    = "combi",
    limited   = "limited",
    singleShot = "single shot",
    shield    = "shield",
    parry     = "parry",
    reliable  = "reliable",
    ammo      = "ammo",               -- Ammo (N+): a D6 after shooting, OUT below N (the card's TRAIT_RULES.ammoNeed)
    scarce    = "scarce",             -- Scarce (N+): a reload needs a D6 of N or more (the card's TRAIT_RULES.scarce)
    heavy     = "heavy",              -- a Braced Shot, and no Aimed Shot (in melee: Heavy Blows)
    assault   = "assault",            -- after a Dash, one Shoot with it, for no action
    toxin     = "toxin",              -- Toxin (N+)  (the card's TRAIT_RULES.toxin)
    shock     = "shock",              -- Shock (N+): a hit roll of N+ wounds automatically, as a 6
    knockback = "knockback",          -- Knockback (N+): a hit roll of N+ knocks the target back (once an attack)
    blast     = "blast[^,]*",         -- Blast (3") / (5"): its Knockback a D6 for each fighter caught, once it is over
    cursed    = "cursed",             -- a target hit makes a Willpower check, failed: Insanity
    flash     = "flash",              -- ranged: no Wound roll; the target hit is Blind and loses its Ready marker
    graviton  = "graviton pulse",     -- ranged: no Wound roll
    lance     = "lance",              -- melee: +1 S on the charge for a Mounted fighter
    lanceBomb = "lance%-bomb",        -- melee: its first hit in a game spends it (SPENT, a click readies it again)
    template  = "template",           -- ranged: no hit roll, every enemy selected is hit
    drag      = "drag",               -- a hit, not Out of Action: a D6 at least its S drags it a Firepower die's inches
    twinLinked = "twin%-linked",      -- a hit at RF: the Firepower dice may be re-rolled
    blaze     = "blaze",              -- Blaze (N+): a Wound roll of N+ makes one more hit, which hits by itself
    -- what a wound does (the card's TRAIT_RULES.hurts; N without a number: 6)
    damage    = "damage",             -- Damage (N): a wound through takes N wounds off (without it: 1)
    rending   = "rending",            -- Rending (N+): a natural N+ to wound (Shock's 6 too) -- that wound's AP one worse
    breaching = "breaching",          -- Breaching (N+): N+ to wound -- no armour save against that wound
    shred     = "shred",              -- Shred (N+): N+ to wound -- that wound's Lethality one higher
    concussive = "concussive",        -- Concussive (N+): each N+ to wound -- a stack of Concussion
    gas       = "gas",                -- no armour save (a Respirator: 5+ invulnerable against it)
    web       = "web",                -- no armour save, no damage: Webbed instead
    radphage  = "rad%-?phage",        -- Rad-Phage: a wound -- the Radphage condition
}

-- The dice with faces of their own (the Mundane Controller's custom dice
-- show them): injuryDice, what each face of an Injury dice stands for --
-- rolled for a Recovery test: 1-2 Injury, 3-5 Serious Injury, 6 Out of
-- Action -- and firepower, the hits on each face of a Firepower dice, the
-- 1 also an Ammo check.
RULES.injuryDice = { "injured", "injured", "serious", "serious", "serious", "out" }
RULES.injury = {   -- each result: its name, and how good it is (the best die is kept)
    -- `short`: how chat writes it ("Recovery Test: Inj")
    out     = { label = "Out of Action",  rank = 1, short = "OOA" },
    serious = { label = "Serious Injury", rank = 2, short = "S. Inj" },
    injured = { label = "Injury",         rank = 3, short = "Inj" },
}
RULES.firepower = { { hits = 1, ammo = true }, { hits = 1 }, { hits = 1 }, { hits = 2 }, { hits = 2 }, { hits = 3 } }

-- The rule numbers among the card's settings (copied into its CFG):
--   engageRange   Engaged, automatically: when a fighter is put down, it
--                 and every enemy whose base is within this many inches of
--                 its base become Engaged (see the card's checkEngagement).
--   nerveRanges   Nerve Check: a friend of one of these ranks (fighter.rank)
--                 within its range in inches, base to base, and in sight
--                 lends its Cl when that is higher -- the best one counts.
--   nerveOutRange A fighter going Out of Action: its friends within this
--                 many inches (base to base, sight or not) must take a
--                 Nerve Check. A Prospect only shakes other Prospects;
--   nerveOutNone  one tagged with any of these (its role line:
--                 "Cyber-mastiff • Pet") shakes nobody;
--   nerveOutFoes  true: enemies within range test too.
--   groupRange    Group Activation: of the Ready friends the player has
--                 selected, those within this many inches, base to base,
--                 are the ones a passed check takes along (see the card's
--                 groupActivation).
--   preMeasure    true: pre-measuring is allowed -- the cursor on Group
--                 Activation in A's panel highlights every friend within
--                 groupRange, on Distribute Ammo every friend within its
--                 range.
--   agility       Agility test: one D6, passed on this or more;
--   escherGang    House Escher's rules: they go to the fighters of a gang
--                 of this `type` (the type as the roster names it under the
--                 gang's name, any case; a variant of the gang, named after
--                 a colon, "House Escher: Wyld Hunt", is not of the type --
--                 it has its own gang rule) -- unless the gang is any of
--                 `unless`, which the roster names in brackets after the
--                 type ("House Escher (Malstrain Corrupted)"). `agility`:
--                 "ones" -- an Agility test's natural 1 is re-rolled, "all"
--                 -- a failed one is. A gang of one of the `variants` (its
--                 `type` or any of its `aka` named after the colon:
--                 "House Escher: Wyld Hunt") has that variant's rules
--                 instead, the house's own not at all: `agility` as above,
--                 `toxinShred` N -- every weapon profile with Toxin (N+)
--                 and no Shred gains Shred (N+).
--   coupGang      Coup de Grace: the fighters of a gang of this `type` add
--                 `mod` to their own roll (read as escherGang's type is).
--   corrupted     the gangs no gang rule below goes to (named in brackets
--                 after the type, as escherGang's `unless`) -- one with an
--                 `unless` of its own goes by that instead;
--   noGangRule    nor does any of them go to a fighter tagged with one of
--                 these (its role line: "Agitator • Hanger-on, Support"),
--                 escherGang's and coupGang's neither. Like escherGang, each
--                 goes to the house itself, never to a variant of it:
--   delaqueGang   a fighter with at least `friends` friends within `range`
--                 inches, base to base (Out of Action, or tagged with
--                 noGangRule, don't count), has its stats changed by `mods`;
--   goliathGang   once a fighter has taken the Charge action, its stats are
--                 changed by `charge` until its activation is over -- and a
--                 melee profile going by its Strength that attacks on the
--                 charge without that action (as Lance or Bull Charge
--                 would) has the S of `charge` added too;
--   palaniteGang  a fighter's actions cost what `costs` says while it is in
--                 status `status` (none: in any);
--   outcastGang   a fighter within `range` inches of a Leader of its gang,
--                 base to base (the Leader itself too), passes its Nerve
--                 Checks whatever the dice say (`nerve`) and makes no
--                 Willpower check against a Fearsome enemy (`fearsome`).
--   extraArm      a fighter with this `rule` (the roster's "Rules:" line, or
--                 a skill or wargear of that name) takes Braced Shot for
--                 `cost` -- but not after a Move or a Shoot in the same
--                 activation, nor either of those after it (Fast Shot
--                 neither: it is more Shoots);
--   fixedMove     a fighter tagged with one of these (Mounted) has its M
--                 changed by no wargear (the Stimm-Slug) and no Wyrd power
--                 (Quickening, an enemy's) -- a number set by hand still is;
--   readyMarks    the Ready markers a fighter tagged with one of these keys
--                 gets each round, if more than one (a Spyrer: 2): it may
--                 activate that many times, S half lit while one is left
--                 after the first; losing a Ready marker takes one of them.
--   fallSave     Falling Down: a passed Agility test takes this many
--                 inches off the height fallen;
--   fallLevels    what is left then decides what the fall does -- less than
--                 the first: Suppressed (if Active), and an activation ends; up to the
--                 second: a wound lost as well (at 0 wounds an Injury dice);
--                 more: Out of Action (see the card's fallingDown).
--   disruptRange  Wyrd powers: an enemy Wyrd within this many inches (base to
--                 base) of the caster may try to disrupt the
--                 cast (see the card's ACTIVATION.cast);
--   disruptMod    a passed disrupt takes this off the caster's Willpower
--                 check (it may go below the lowest Wil);
--   concentrateMod  Concentrate adds this to Willpower checks to manifest
--                 powers until the activation ends;
--   maintainMod   Maintain Control (S) adds this to its Willpower check
--                 (Maintain Control (F) adds nothing);
--   powersLastNext  how long a Continuous power lasts. false: until the end
--                 of its Wyrd's activation, unless a Maintain Control passed
--                 during it holds it -- then until the end of the next
--                 activation, and so on, each Maintain Control passed in an
--                 activation holding it through that activation's end. true:
--                 a power cast lasts through the end of that activation
--                 without one, and then goes the same way.
--   shockNatural  Shock (N+) and Knockback (N+): false -- the hit roll
--                 with its modifiers must reach N (Shock (6+) with +1 to
--                 hit: a 5 does); true -- the die's own roll.
--   knockback     Knockback (N+): how many inches the target is knocked
--                 back, shown on its card once the attack is over -- the
--                 players move the model (see the card's knockback).
--   rapidOneHit   Shock (N+) on a Rapid Fire shot: false -- every hit the
--                 Firepower dice give shares the hit roll, so every one of
--                 them wounds automatically; true -- only the first does.
--   unstableAll   Unstable: a natural 1 on a ranged hit die (after any
--                 re-roll) hits the shooting fighter instead. false -- with
--                 one hit, whatever the Firepower dice show; true -- with
--                 every hit the Firepower dice give at Rapid Fire (one
--                 without). A melee attack is always one hit.
--   saveFails    a save roll of this or less always fails, whatever the
--                 save (2: a natural 1 or 2);
--   dicePause     seconds a roll that follows another waits after that one
--                 showed (the Wound roll after the Hit roll, the saves
--                 after the Wound roll ...); the last roll of all stays
--                 the card's diceShow seconds whatever this says.
--   coverShort, coverLong  what cover adds to a save roll against a ranged
--                 attack from within the weapon's Short Range, and from
--                 beyond it (within Long Range) -- a weapon with only one of
--                 the two in inches ("T", "-") always gives that one's (see
--                 the card's takeSaves);
--   coverTemplate what cover adds against a ranged attack with neither
--                 range in inches (a Template's "T").
--   handWeapon    the weapon every fighter fights with that has nothing
--                 else to fight with (name and profiles, as a weapon of the
--                 roster's). `light` true: a fighter with a Melee or a Light
--                 weapon has something to fight with; false: only a Melee
--                 weapon counts (see the card's SKILL.hand).
RULES.cfg = {
    engageRange   = 1,
    nerveRanges   = { leader = 12, champion = 6 },
    nerveOutRange = 3,
    nerveOutNone  = { "pet" },
    nerveOutFoes  = false,
    groupRange    = 3,
    preMeasure    = false,
    agility       = 4,
    escherGang    = { type = "House Escher", agility = "ones",
                      unless = { "Chaos Corrupted", "Genestealer Corrupted", "Genestealer Infected",
                                 "Malstrain Corrupted" },
                      variants = { { type = "Wyld Hunt", agility = "all" },
                                   { type = "Chymist Cult", toxinShred = 6 } } },
    coupGang      = { type = "Genestealer Cults", mod = 1 },
    corrupted     = { "Chaos Corrupted", "Genestealer Corrupted", "Genestealer Infected", "Malstrain Corrupted" },
    noGangRule    = { "hanger-on" },
    delaqueGang   = { type = "House Delaque", range = 3, friends = 2, mods = { Ld = 1, Wil = 1 } },
    goliathGang   = { type = "House Goliath", charge = { S = 1 } },
    palaniteGang  = { type = "Palanite Enforcers", costs = { group_activation = "F" }, status = "active" },
    outcastGang   = { type = "Outcasts", range = 6, nerve = true, fearsome = true },
    readyMarks    = { spyrer = 2 },
    extraArm      = { rule = "Extra Arm", cost = "S" },
    fixedMove     = { "mounted" },
    fallSave    = 3,
    fallLevels    = { 3, 6 },
    disruptRange  = 18,
    disruptMod    = -2,
    concentrateMod = 1,
    maintainMod   = 3,
    powersLastNext = false,
    shockNatural  = false,
    knockback     = 1,
    rapidOneHit   = false,
    unstableAll   = false,
    saveFails     = 2,
    coverShort    = 1,
    coverLong     = 2,
    coverTemplate = 1,
    dicePause     = 3,
    handWeapon    = { light = true, name = "Hand Weapon", profiles = {
        { SR = "E", LR = "-", S = "S", AP = "-", L = "1", traits = "Melee" } } },
}

-- ── Overrides ────────────────────────────────────────────────
-- A table's own rules are a table of overrides, part by part, laid over
-- the defaults above (RULES.merge); a part left out stays as it is. Each
-- part takes them as it is shaped (RULES.PARTS):
--   "key" / "name"  (actions, conditions / skills, wargear, accessories) a
--       list of entries, each found by its `key` (a skill, wargear or
--       accessory by its `name`, any case):
--         one not there yet is added, at the end;
--         one that is there has the fields given changed, the rest kept
--         (a field set to false is removed);
--         `replace = true`: it is replaced by the one given, as a whole;
--         `disabled = true`: it is taken out.
--   "map"  (actionTypes, statusActions, statRolls, limits, traits, injury)
--       by key: a value replaces the default's -- a table of fields (not a
--       list) has its fields laid over the default's instead, as above --
--       false takes the key out, a new key is added.
--   "values"  (cfg) as a map, but only the keys already there, and false
--       is a value.
--   "list"  (injuryDice, firepower) the whole list, replaced.
-- For example:
--   {
--     actions    = { { key = "hide", label = "Hide", cost = "S", type = "utility" },
--                    { key = "dash", cost = "S" },
--                    { key = "coup_de_grace", disabled = true } },
--     statusActions = { active = { left = { "move", "dash", "engage", "charge", "interact", "hide" } } },
--     limits     = { M = { 1, 14 } },
--     firepower  = { { hits = 1, ammo = true }, { hits = 1 }, { hits = 2 }, { hits = 2 }, { hits = 3 }, { hits = 3 } },
--     cfg        = { nerveRanges = { leader = 18 } },
--   }
RULES.PARTS = {
    actionTypes = "map",   actions  = "key",  statusActions = "map", conditions = "key",
    skills      = "name",  wargear  = "name", statRolls     = "map", limits     = "map",
    traits      = "map",   injury   = "map",  injuryDice    = "list", firepower = "list",
    cfg         = "values", accessories = "name",
}

-- A copy of `v` all the way down (tables are never shared with it).
function RULES.copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = RULES.copy(x) end
    return t
end

-- Whether `a` and `b` hold the same, all the way down.
function RULES.same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not RULES.same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Whether table `t` is a list (or empty): replaced whole, never merged.
function RULES.isList(t) return t[1] ~= nil or next(t) == nil end

-- The fields of `over` laid over table `into` (copies): false removes one.
function RULES.lay(into, over)
    for k, v in pairs(over) do
        if v == false then into[k] = nil else into[k] = RULES.copy(v) end
    end
    return into
end

-- An entry's id in a part of kind "key" / "name" (see RULES.PARTS).
function RULES.id(kind, e)
    if type(e) ~= "table" then return nil end
    if kind == "name" then return e.name ~= nil and tostring(e.name):lower() or nil end
    return e.key
end

-- The rules the overrides `over` make: a fresh table of every part (see
-- RULES.PARTS), the defaults with `over` laid over them. Anything it
-- doesn't understand is passed over; nil or {} gives the defaults.
function RULES.merge(over)
    local out = RULES.copy(RULES.DEFAULT)
    if type(over) ~= "table" then return out end
    for part, kind in pairs(RULES.PARTS) do
        local o, t = over[part], out[part]
        if type(o) ~= "table" then
            -- not overridden
        elseif kind == "list" then
            out[part] = RULES.copy(o)
        elseif kind == "map" or kind == "values" then
            for k, v in pairs(o) do
                if kind == "values" and t[k] == nil then
                    -- not a setting of the rules: left alone
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
                local at
                for i, x in ipairs(id ~= nil and t or {}) do
                    if RULES.id(kind, x) == id then at = i break end
                end
                if id == nil then
                    -- no key / name: nothing to go by
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

-- Functions that work out what follows from the rules (see RULES.follow).
RULES.followers = {}

-- Runs `fn` now, and again every time the rules in force change.
function RULES.follow(fn)
    RULES.followers[#RULES.followers + 1] = fn
    fn()
end

-- Puts the rules the overrides `over` make in force (RULES.merge): each
-- part that differs is changed in place -- the tables stay the same
-- tables, so whatever holds one sees the change -- and then every
-- RULES.follow function runs. Returns whether anything changed.
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

-- The defaults, as written above, for RULES.merge to start from.
RULES.DEFAULT = {}
for part in pairs(RULES.PARTS) do RULES.DEFAULT[part] = RULES.copy(RULES[part]) end
--@@RULES_END

-- ══════════════════════════════════════════════════════════════
--  Settings
-- ══════════════════════════════════════════════════════════════

-- The dice. Every roll -- a fighter card's (its stat tests, A's Special
-- tab, Recovery tests, Nerve Checks, attacks, reloads: see throwDice), a
-- Bottle Check, the Roll Dice / Roll Firepower / Roll Injuries buttons --
-- is thrown here (this object's own rolls also said on everyone's screen):
-- dropped from DROP (world units) above the table, tumbling (SPIN radians
-- a second, at least half of it about every axis) and pushed up to PUSH
-- (world units a second) sideways, any way, in a line BELOW panel units
-- out from the panel's bottom edge, on the table (see DICE.line): under
-- the column's middle -- the Roll Dice / Firepower / Injuries buttons'
-- under the side panel they were clicked on, each line on its own.
-- Once they rest they are lined up side by side, STEP apart, in the order
-- they were thrown (SORT "thrown"; "up" / "down" line them up by face
-- instead -- only on the table: the card and chat always get them in the
-- order thrown), the rolled face up and every die of a kind turned the
-- same way (TURN[kind] degrees more about the vertical: the Firepower and
-- Injury dice's symbols towards the players), locked -- and stay there until
-- the next roll (a save keeps them too). A roll asked for while one is still
-- falling waits for it, and NEXT seconds more so the last can be seen.
-- Clicks on the buttons within JOIN seconds of each other add to one roll
-- (up to MAX dice), thrown once no click has come for JOIN seconds. WAIT:
-- the longest the dice are waited for before they are read as they lie.
-- A die counts as down only once it has fallen FALL world units from where
-- it spawned and rests again (TTS can hold a fresh die still in mid-air,
-- "resting", for a moment); until it falls it is kicked again every KICK
-- frames, and once more as it starts to fall (see DICE.settled).
--   URL: the custom dice's art, one image per kind (TTS's D6 template with
-- the faces drawn on). Until set, TTS's own D6 (PLAIN) is thrown, in the
-- roller's colour. A Firepower or Injury dice is
-- read from its number through CHART (the rules' RULES.firepower /
-- RULES.injuryDice, as the cards read them). SCALE: the dice's size.
local DICE = {
    URL   = { d6 = "https://steamusercontent-a.akamaihd.net/ugc/14438694407390139777/F5A3307604C00D6896ACC7B82B6735BD024137EA/", firepower = "https://steamusercontent-a.akamaihd.net/ugc/14511214079636238699/82E750A272596F79249868C7DD4611B69FF6D099/", injury = "https://steamusercontent-a.akamaihd.net/ugc/14681495304683522636/208E2C4C0EF8613F91ACC93C75BDDF1493D6926E/" },
    PLAIN = "Die_6",
    BELOW = 150, DROP = 4, SPIN = 18, PUSH = 3, STEP = 1.4, SCALE = 1,
    SORT  = "thrown", TURN = { d6 = 0, firepower = 180, injury = 180 },
    APART = 4,              -- a roll-off's two dice: this far apart, each on its side's side
    JOIN = 1, NEXT = 1.5, WAIT = 12, MAX = 20,
    FALL  = 0.3, KICK = 10,
    TAG   = "Mundane Dice",
    NAMES = { d6 = "D6", firepower = "Firepower Dice", injury = "Injury Dice" },
    CHART = { firepower = RULES.firepower, injury = RULES.injuryDice },
}

-- The Controller's panel on this object: how big it shows (its panel
-- units at 0.65 of the object's UI units; its size: see PANEL_W / PANEL_H)
-- -- and where it sits and how it is turned, worked out from STAND (see
-- STAND.place, after the layout).
local PANEL = { scale = "0.65 0.65 0.65" }

-- How the panel stands: inclined ANGLE degrees, so the players see it
-- better -- its bottom edge on the near side (the object's +z side, where it
-- reads the right way up: turned half round), its top edge raised further
-- off. The object's origin lies on the table right under the middle of the
-- bottom edge, which is EDGE local units over it: the panel tilts, and the
-- object turns, about that edge. The panel itself lies UP local units off
-- that face (STAND.point's `up`), just clear of the frame's floor. The frame
-- the panel lies in (the object's model) is made for the same numbers.
local STAND = { ANGLE = 30, EDGE = 0.1, UP = 0.08 }

-- How many texels the panel's text gets: every text is made at this many
-- times its size and shown scaled back to it (font sizes are whole numbers,
-- so the scale takes up the rest -- it always shows at its own size). TTS
-- draws text from a picture of its letters made at that size, with no
-- smaller copies for the distance: text made big is crisp close up but
-- thins out and shimmers from across the table; made small it is softer
-- close up and steadier and easier to read further away. 1: made at its
-- own size; 2: twice (sharp up close only); 0.5: half.
local TEXT_DETAIL = 0.625

-- The die on the Bottle Check's roll button -- the fighter card's own
-- (its ASSETS stat_die), so both look alike. Empty: a "D" instead.
local DIE_ICON = "https://steamusercontent-a.akamaihd.net/ugc/12001738551517573707/F2E806437431BEE65DD78832C9C5A286D327A301/"

-- The panel's other pictures, as its own UI assets. EDGE and FRAME are the
-- fighter card's (its ASSETS edge_line and diamond_frame), which every
-- player has loaded already: EDGE is every line on the panel -- a white
-- line with soft, clear margins, EDGE_ART times as tall as the line it
-- draws, which the GPU draws smoothly at any distance where a thin plain
-- panel would break up and shimmer -- and FRAME the border round each of
-- the Bottle Check's diamonds, FRAME_SIZE times the diamond (the card's
-- LAY.frameArt). GEAR is the gear round the round's number (its outline,
-- a thin ring inside and a faint disc, white) and GLOW the soft glow
-- behind it (white); both are tinted. An empty link: drawn without it --
-- the lines as thin plain panels, the diamonds with plain lines round
-- them, no gear and no glow (the round's number still shows).
local ART = {
    EDGE  = "https://steamusercontent-a.akamaihd.net/ugc/13432909356284909624/B129FFCF81BACF983676DFEE7F7E71473280818C/",
    FRAME = "https://steamusercontent-a.akamaihd.net/ugc/14782607483565015523/5A66DA23DFB6BD38FFD1692D8E5F435717D1134D/",
    GEAR  = "https://steamusercontent-a.akamaihd.net/ugc/15954717134150489158/6BDE2A9CBC8AAB39A1F736EC3D0FE7F48135CB60/",
    GLOW  = "https://steamusercontent-a.akamaihd.net/ugc/10558683540636189568/3D8BEC2610F94004B0610B97A0918B132C8CC70F/",
    EDGE_ART = 2, FRAME_SIZE = 1.25,
}

-- The panel's look: gold lines on near-black panels. LINE, ACCENT and THIN
-- are the weights (panel units) of an outline, of the heavier accent on a
-- panel's cut corners and of a thin rule; EDGE a button's outline. A
-- button looks like one of BUTTONS: its fill, its outline and its label's
-- ink. Every fill is opaque: a shape is pieced together from parts that
-- overlap (see SHAPE.fill), which a see-through colour would show.
local LOOK = {
    GOLD   = "#D6AC5E",
    FILL   = "#141312",     -- every panel
    TEXT   = "#ECE6D8",
    DIM    = "#AAA08C",     -- what only explains: how to name a side, a homebrew set
    NOTE   = "#D4CAB2",     -- the reminder of reinforcements under End Round
    HEAD   = "#FFD696",     -- "ROUND", "GAME SETUP", "SETTINGS" and its columns' headers
    NUMBER = "#FFC46E",     -- the round
    GLOW   = "#FFAA3C8C",   -- behind the round
    DIAMOND = "#2C2F31|#3A3E41|#232527|#2C2F31",   -- the Bottle Check's diamonds (resting, hovered, pressed)
    RULE   = "#D6AC5EA0",   -- the thin rule under a gang's name
    RULE_TEXT = "#ECE6D88C",   -- ... and over its part (Attacker / Defender)
    SEP    = "#D6AC5E5A",   -- ... and between two homebrew sets
    LINE = 3, ACCENT = 6, THIN = 1.5, EDGE = 2,
    HOVER  = "#00000000|#FFFFFF14|#FFFFFF26|#00000000",   -- a clear button over a shape: a light tint on hover
}
LOOK.BUTTONS = {
    plain = { fill = "#18191A", line = LOOK.GOLD, ink = LOOK.TEXT },
    gold  = { fill = LOOK.GOLD, line = LOOK.GOLD, ink = "#181614" },   -- a choice made, Start Game, Apply
    red   = { fill = "#461210", line = "#E65040", ink = "#FFE2D6" },   -- End Round, a Bottle Check to take
    dim   = { fill = "#18191A", line = "#8A7143", ink = LOOK.DIM },    -- Supported Mechanics, out of the way
}

-- The deployment's model: rolled on the setup's Roll for Deployment, a
-- see-through custom model of the deployment zones is put on the table
-- (locked). MESH[face of the D6] says which: { apart = N } -- the one
-- model ZONE (made for a BASE" map, stretched along its own x alone -- not
-- z, not up -- to the map size chosen) put down twice, N" from the middle
-- of the table either way along z, the second turned half round; { link }
-- -- one model for every map size, as it is, in the middle (0, 0, 0); or
-- { [36] = link, [48] = link } -- one per map size, in the middle.
-- COLLIDER is the one collider every model shares (stretched with a
-- stretched one). Empty link: no model for it; chat says so.
-- It is Cardboard (MATERIAL) tinted TINT (8100FF at alpha 100), turned TURN degrees at a time
-- about the middle of the table and stretched up / down by STEP (of its
-- own height, never below STEP) by the small buttons beside the row --
-- kept for the next one (saved). A right click on the row takes it away,
-- and the next puts it back; Start Game takes it away, and going back from
-- round 1 to the setup puts it back. SIZES: the map sizes the setup's Map
-- Size goes through, in turn.
local DEPLOY = {
    SIZES = { 36, 48 },
    MESH = {
        { apart = 12 },                 -- 1 Sniping Range (ZONE, twice)
        { apart = 9 },                  -- 2 Face Off (ZONE, twice)
        { apart = 6 },                  -- 3 Stand Off (ZONE, twice)
        { "https://steamusercontent-a.akamaihd.net/ugc/10092366485938643157/EC4AE7C3A22A7992247C69CB6DACFEDC84E9D9D1/" },                         -- 4 Ambush
        { [36] = "https://steamusercontent-a.akamaihd.net/ugc/11206213002289756367/4DF70CBC090DC00C5E9D858DECDC1596D1AC6DC7/", [48] = "https://steamusercontent-a.akamaihd.net/ugc/14901986283498053462/860B9F2091FEC5F9F208A65E4283AE2E44B59C26/" },       -- 5 Free for All
        { [36] = "https://steamusercontent-a.akamaihd.net/ugc/13098037441717208909/3DC8C380D146624771AFEFDDAAFECB2BF927589D/", [48] = "https://steamusercontent-a.akamaihd.net/ugc/14622491162696696273/939F03CD3519AB9EB6CE1AC54A7D3473C80C4343/" },       -- 6 Chance Encounter
    },
    ZONE = "https://steamusercontent-a.akamaihd.net/ugc/17711522206232040145/473C795DE47225D6B3AE455CD0DAE400D1BF1AD7/",                          -- Sniping Range, Face Off, Stand Off: the one zone, put down twice
    BASE = 36,
    COLLIDER = "https://steamusercontent-a.akamaihd.net/ugc/9590185350319248742/E1ACACACB191CDC4F0211AC33E42B34B043DBD19/",
    TINT = { r = 0x81 / 255, g = 0, b = 1, a = 100 / 255 },
    MATERIAL = 3,           -- TTS's custom model materials: 0 Plastic, 1 Wood, 2 Metal, 3 Cardboard
    TURN = 90, STEP = 0.5,
    TAG  = "Mundane Deployment",
    turn = 0, tall = 1,     -- how the last one stood: turned, and stretched up (saved)
    objs = {},              -- the models last put down
}

-- Homebrew: the table's own rules, as named sets, each a choice between
-- the rules as written and the set's -- two radio buttons on the panel's
-- second page, Settings (the button under the column opens it, Back
-- leaves it as it was), where "Apply Settings" puts every choice in
-- force at once -- kept with the Controller. The page has two columns:
-- Gameplay on the left (how the game plays at the table, not its rules),
-- Homebrew Rules on the right. Each of SETS:
--   id     what a save knows it by (the same however the set is renamed)
--   gameplay  true: in the Gameplay column (else under Homebrew Rules)
--   off    the first button: the rules as written -- about 20 letters fit
--          at full size (a longer label shrinks)
--   name   the second: the set's rules
--   offDesc  under them while the first is chosen: what the rules as
--          written do, a line or two
--   desc   the same while the second is chosen: what the set does
--   rules  the overrides the set makes, in the format of the rules (see the
--          overrides in RULES: actions, conditions, skills, wargear, limits,
--          cfg, ...). Sets that are on are laid over each other in this
--          order (each column shows its own in this order too), so where
--          two change the same thing the later one wins --
--          but sets that add different actions, change different limits
--          and so on just add up.
-- (An "&" in a name or description reads "and", a "<" or ">" is dropped:
-- TTS shows what is escaped as it is.)
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
        { id = "unstable_all", off = "Unstable: One Hit", name = "Unstable: Rapid Fire",
          offDesc = "A natural 1 on an Unstable weapon's Hit roll: 1 hit on the shooter.",
          desc = "A natural 1 on an Unstable weapon's Hit roll: every hit the Firepower dice show goes to the shooter.",
          rules = { cfg = { unstableAll = true } } },
        { id = "hand_heavy", off = "Hand Weapon (no melee / no light)", name = "Hand Weapon (no melee)",
          offDesc = "A fighter with neither a Melee nor a Light weapon fights with a Hand Weapon (E, S, AP -, L 1, Melee).",
          desc = "A fighter with no Melee weapon fights with a Hand Weapon (E, S, AP -, L 1, Heavy, Melee), Light weapons or not.",
          rules = { cfg = { handWeapon = { light = false, profiles = {
              { SR = "E", LR = "-", S = "S", AP = "-", L = "1", traits = "Heavy, Melee" } } } } } },
    },
    on = {},                -- id -> true, for the sets that are on (saved)
    pick = {},              -- id -> true: the page's choice, until applied
    page = false,           -- the Settings page shows (not saved)
    -- the page (see homebrewXml), in panel units: the whole of the main
    -- page's outline, as one shape (HOMEBREW.outline: both side panels, the
    -- column's top rising between them, the buttons' row under them, nothing
    -- between) -- split down the middle into its two columns by a thin rule
    -- (from DIV_UP under the side panels' top to FOOT over the page's
    -- bottom), each column's header (SUB down from the side panels' top,
    -- SUB_FONT) over its sets, which run from HEAD under the side panels'
    -- top to FOOT over the page's bottom, sharing that out (each set's step,
    -- the same in both columns, see HOMEBREW.step); the cut corners accented
    -- ACCENT along the edges; the title in the column's top (TITLE down from
    -- it, TITLE_FONT or smaller to fit) and Back (BACK: from the page's
    -- right edge and the side panels' top); each set's radio buttons
    -- (RADIO_W x RADIO_H, RADIO_GAP apart) over its description (DESC down
    -- from the buttons' top, DESC_W x DESC_H, up to DESC_FONT) and a thin
    -- rule (SEP_UP over the next set's buttons, SEP_W wide) before the next
    -- in its column; Apply (APPLY_W x APPLY_H, its bottom APPLY_UP over the
    -- page's).
    HEAD = 84, FOOT = 80, ACCENT = 46, SUB = 40, SUB_FONT = 22, DIV_UP = 24,
    TITLE = 50, TITLE_FONT = 30, BACK = { -150, 24, -46, 64 }, BACK_FONT = 18,
    RADIO_W = 316, RADIO_H = 38, RADIO_GAP = 14, RADIO_FONT = 19,
    DESC = 62, DESC_W = 640, DESC_H = 40, DESC_FONT = 17, SEP_UP = 8, SEP_W = 620,
    APPLY_W = 520, APPLY_H = 48, APPLY_UP = 24, APPLY_FONT = 22,
}

-- Where everything lies on the panel, in panel units from its top left
-- corner -- x across, y down, as it reads (SHAPE.at turns a point into an
-- offset from the panel's middle). A box is { x0, y0, x1, y1 }; a shape's
-- corners are cut off (chamfered) by `cut` = { top left, top right, bottom
-- right, bottom left } (0: square). The panel: the two players' side
-- panels (SIDES, left and right) either side of the column (MID), which
-- shows the round -- or, before round 1, the game's setup (SETUP) -- every
-- panel's corners cut and the cuts accented (ACCENT along the edges either
-- side); the column joined to each side panel by two links (LINKS: their
-- y; a small diamond in each one's middle, LINK_DOT from its middle to a
-- tip); and under each of the three a row of buttons (RAIL: their top and
-- bottom; RAIL_GAP apart, RAIL_FONT, the outer corners cut RAIL_CUT; the
-- Feedback button FEEDBACK_W wide, its envelope MARK at MARK_FONT, made at
-- MARK_DETAIL whatever TEXT_DETAIL is -- the bare sign, without the
-- text-style selector the shared FEEDBACK.MARK carries, and with TTS's own
-- text overflow: so it sits in the button's middle). The Settings
-- page takes the place of all of it (see HOMEBREW).
local PANEL_W, PANEL_H = 1480, 714
local LAYOUT = {
    SIDES = { { 10, 70, 500, 642 }, { 980, 70, 1470, 642 } },
    MID   = { 554, 10, 926, 642 },
    SIDE_CUT = { 40, 40, 40, 40 }, SIDE_ACCENT = 46,
    MID_CUT  = { 56, 56, 20, 20 }, MID_ACCENT = 40,       -- only the column's top two corners accented
    LINKS = { 210, 470 }, LINK_DOT = 7,
    RAIL = { 656, 704 }, RAIL_GAP = 8, RAIL_CUT = 16, RAIL_FONT = 18, FEEDBACK_W = 44, MARK = "✉", MARK_FONT = 24, MARK_DETAIL = 2,
    -- in a side panel, down from its top and across from its middle: the
    -- gang's name (NAME_W x NAME_H, NAME_FONT or smaller to fit, never
    -- below NAME_MIN) over a thin rule (NAME_RULE, RULE_W wide); "VICTORY
    -- POINTS" (VP_HEAD) and the points (VP; VP_HIT: the top and bottom of
    -- what a click on them takes) -- or, while the side has no gang, how to
    -- give it one (HINT: the middle of its three lines, HINT_GAP apart); a
    -- thin rule (VP_RULE); the side's part (ROLE, cut ROLE_CUT); "BOTTLE
    -- CHECK" (BOTTLE, HEAD_W wide to click) over "Ld" and the two diamonds
    -- (DICE: their middle; LD_X, VAL_X, ROLL_X across), on a dark red plate
    -- while the check is to be taken (PLATE, cut PLATE_CUT)
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
    },
    -- in the column from round 1, down from the panel's top: "ROUND"
    -- (CAPTION) between two thin rules (from RULE_IN inside the column's
    -- edges to RULE_GAP from its middle); the gear (GEAR: its middle,
    -- GEAR_SIZE square) on its glow (GLOW_SIZE) with the round's number in
    -- it (FONT, smaller for more digits so they stay inside the gear's
    -- inner ring, RING from its middle; DROP above the gear's middle; HIT:
    -- the square a right click on it takes); End Round (END: across from
    -- the middle, and down); the reminder of reinforcements (NOTE: its
    -- middle, NOTE_W x NOTE_H, up to NOTE_FONT); over "ROUND", in the
    -- column's top, Supported Mechanics (INFO_H tall, its top corners cut
    -- INFO_CUT, INFO_GAP inside the column's top edge and its cut corners,
    -- INFO_FONT)
    ROUND = {
        INFO_H = 30, INFO_CUT = 14, INFO_GAP = 8, INFO_FONT = 17,
        CAPTION = 94, CAPTION_FONT = 46, RULE_IN = 32, RULE_GAP = 92,
        GEAR = 342, GEAR_SIZE = 320, GLOW_SIZE = 260, RING = 116, FONT = 222, DROP = 6, HIT = 240,
        END = { -100, 542, 100, 590 }, END_CUT = 12, END_FONT = 24,      -- its middle level with the Bottle Checks' "Ld"
        NOTE = 616, NOTE_W = 320, NOTE_H = 46, NOTE_FONT = 21,
    },
}

-- A point of the panel in this object's own space: `x`, `y` panel units
-- from the panel's middle along its own axes (x to the right, y up as it
-- reads), `up` local units off its face (towards whoever looks at it) --
-- local x, y (up) and z. The panel's up runs to -z and rises ANGLE
-- degrees; its x runs to -x (turned half round).
function STAND.point(x, y, up)
    local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
    local a = math.rad(STAND.ANGLE)
    local along = (y + PANEL_H / 2) * k                  -- up the panel from its bottom edge
    up = up or 0
    return -x * k, STAND.EDGE + along * math.sin(a) + up * math.cos(a), -along * math.cos(a) + up * math.sin(a)
end

-- PANEL's position and rotation from STAND: its middle where STAND.point
-- puts it (object UI: x / y along local x / z, 100 UI units to a local
-- unit, negative z up), inclined ANGLE about its own x after the half turn.
function STAND.place()
    local x, y, z = STAND.point(0, 0, STAND.UP)
    PANEL.position = string.format("%.6g %.6g %.6g", x * 100, z * 100, -y * 100)
    PANEL.rotation = string.format("%g 0 180", STAND.ANGLE)
end
STAND.place()

-- The turn it counts (0: the game hasn't started -- the column shows the
-- game's setup, see SETUP), and the two players' victory points and names.
local turn = 0
local vp, vpNames = { 0, 0 }, { "Player 1", "Player 2" }

-- ── Drawing the panel ────────────────────────────────────────────
-- TTS draws rectangles and turned squares only, so every shape on the panel
-- is pieced together from them (SHAPE.fill) and outlined with straight
-- lines (SHAPE.lines). A shape that changes colour in place has its pieces
-- named and noted in SHAPE.parts (see SHAPE.paint). Every size it writes is
-- in panel units; text is made at TEXT_DETAIL times its size (see
-- SHAPE.font).
local SHAPE = {
    parts = {},             -- id -> its pieces' count, label and colours as last drawn (see SHAPE.paint)
    CUT = { 12, 0, 12, 0 }, -- a button's corners: cut top left and bottom right
    MIN = 9,                -- the smallest a fitted text shrinks to
}

-- A point of the layout as the offsetXY of an element centred there.
function SHAPE.at(x, y)
    return string.format('offsetXY="%g %g"', x - PANEL_W / 2, PANEL_H / 2 - y)
end

-- One straight line from point `a` to point `b` ({ x, y } of the layout),
-- `w` thick, in `color`: the edge art (ART.EDGE) stretched along it --
-- an image EDGE_ART times as tall as the line, the line along its middle --
-- and turned to lie along it; without the art a plain panel `w` tall. `e0`
-- and `e1` lengthen it past a and past b (to close a corner with the next
-- line); `id` names it.
function SHAPE.line(a, b, w, color, e0, e1, id)
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-6 then return "" end
    e0, e1 = e0 or 0, e1 or 0
    local x = (a[1] + b[1]) / 2 + dx / len * (e1 - e0) / 2
    local y = (a[2] + b[2]) / 2 + dy / len * (e1 - e0) / 2
    local deg = math.deg((math.atan2 or math.atan)(-dy, dx))       -- the panel's y runs up, the layout's down
    if deg > 90 then deg = deg - 180 elseif deg <= -90 then deg = deg + 180 end
    local art = ART.EDGE ~= ""
    return string.format('<%s%s %s width="%g" height="%g"%s%s color="%s" raycastTarget="false" />',
        art and "Image" or "Panel", id and (' id="' .. id .. '"') or "", SHAPE.at(x, y), len + e0 + e1,
        art and w * ART.EDGE_ART or w, math.abs(deg) > 1e-6 and string.format(' rotation="0 0 %g"', deg) or "",
        art and ' image="mundaneEdge"' or "", color)
end

-- Lines through the points `pts`, `w` thick -- back to the first with
-- `closed` -- each corner closed: the two lines meeting there run on past
-- it as far as half the line's width times the tangent of half the turn,
-- where each just meets the other's outer edge (and a little more, so no
-- seam shows). With `id` the lines are named <id>Line_<k>. Returns the XML
-- and how many lines.
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

-- The outline of `box` with its corners cut by `cut`, as points round
-- from the top left (a corner not cut is one point).
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

-- The fill of `box` with its corners cut by `cut`, in `color`: the
-- rectangles that make it up and, at each cut corner, a square turned half
-- a right angle whose edge is the cut (its middle as far in from the
-- corner both ways as the cut is long, and as far from each of its tips)
-- -- the outline over the cut hides the square's hard edge. The rectangles
-- overlap a little so no seam shows. With `id` each piece is named
-- <id>Fill_<k>. Returns the XML and how many pieces.
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
    rect(x0, y0 + math.max(0, top - 0.5), x1, y1 - math.max(0, bottom - 0.5))   -- the middle, the whole width
    rect(x0 + cut[1], y0, x1 - cut[2], y0 + top)                                   -- the top, between its corners
    rect(x0 + cut[4], y1 - bottom, x1 - cut[3], y1)                                -- the bottom
    for k, c in ipairs(cut) do
        if c > 0 then
            local x = (k == 1 or k == 4) and x0 + c or x1 - c
            local y = k <= 2 and y0 + c or y1 - c
            piece(SHAPE.at(x, y), c * math.sqrt(2), c * math.sqrt(2), true)
        end
    end
    return table.concat(out), #out
end

-- The accent on the cut corners `which` of `box` (as `cut`'s order): a
-- heavier line along the cut and `len` on along the edges either side.
-- A corner is its point, and the two ways along its edges away from it.
SHAPE.CORNERS = {
    function(b) return b[1], b[2], 0, 1, 1, 0 end,      -- top left: down the left edge, along the top
    function(b) return b[3], b[2], -1, 0, 0, 1 end,     -- top right
    function(b) return b[3], b[4], 0, -1, -1, 0 end,    -- bottom right
    function(b) return b[1], b[4], 1, 0, 0, -1 end,     -- bottom left
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

-- A shape: `box`, its corners cut by `cut`, filled and outlined (`look`:
-- { fill, line }; `w` the line's weight -- none: no outline). With `id`
-- its pieces are named and noted in SHAPE.parts.
function SHAPE.shape(box, cut, look, w, id)
    local fill, fills = SHAPE.fill(box, cut, look.fill, id)
    local line, lines = "", 0
    if w then line, lines = SHAPE.lines(SHAPE.path(box, cut), w, look.line, true, id) end
    if id then SHAPE.parts[id] = { fills = fills, lines = lines, fill = look.fill, line = look.line } end
    return fill .. line
end

-- A panel: the shape of `box` in the panel's fill, outlined in gold, the
-- cut corners `which` accented (`len` along the edges).
function SHAPE.panel(box, cut, which, len)
    return SHAPE.shape(box, cut, { fill = LOOK.FILL, line = LOOK.GOLD }, LOOK.LINE) ..
        SHAPE.accents(box, cut, which, len)
end

-- A small solid diamond: `r` from its middle (x, y) to each tip.
function SHAPE.dot(x, y, r, color)
    return string.format('<Panel %s width="%g" height="%g" rotation="0 0 45" color="%s" />',
        SHAPE.at(x, y), r * math.sqrt(2), r * math.sqrt(2), color)
end

-- How wide a character of Arial Bold is, in ems (any other: as wide as an
-- "n") -- to wrap and size the texts (see SHAPE.fit) -- and the few signs
-- the panel shows that aren't plain letters, each counted as a letter
-- about as wide (the selector after the envelope takes no room).
SHAPE.EM = {}
for chars, em in pairs({ [" ijlI.,|'"] = 0.278, ["ft():-!;[]/"] = 0.333, r = 0.389, ['"'] = 0.474, z = 0.5,
                         ["acekpsvxy0123456789J"] = 0.556, ["+"] = 0.584, ["bdghnopquFLTZ?"] = 0.611,
                         ["EPSVXY"] = 0.667, ["ABCDHKNRU&"] = 0.722, ["wGOQ"] = 0.778, M = 0.833, ["m%"] = 0.889,
                         W = 0.944, ["@"] = 0.975 }) do
    for c in chars:gmatch(".") do SHAPE.EM[c] = em end
end
SHAPE.SIGNS = { { "︎", "" }, { "✉", "G" }, { "●", "n" }, { "○", "n" }, { "°", "r" }, { "▲", "W" }, { "▼", "W" } }

-- `s`'s width at font size `size` (none: in ems).
function SHAPE.width(s, size)
    s = tostring(s or "")
    for _, sign in ipairs(SHAPE.SIGNS) do s = s:gsub(sign[1], sign[2]) end
    local n = 0
    for c in s:gmatch(".") do n = n + (SHAPE.EM[c] or 0.611) end
    return n * (size or 1)
end

-- `text` wrapped at its spaces (and its own line breaks) and sized to fit
-- `w` x `h`: the lines (joined by line breaks) and the font size -- `max`,
-- or as much smaller as it needs (never below `min`, SHAPE.MIN).
function SHAPE.fit(text, w, h, max, min)
    min = min or SHAPE.MIN
    local lines
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

-- `text` on one line, as big as fits `w`: `max`, or smaller (never below
-- `min`, SHAPE.MIN) -- a button's label.
function SHAPE.fitLine(text, w, max, min)
    local em = SHAPE.width(text)
    if em <= 0 then return text, max end
    return text, math.max(min or SHAPE.MIN, math.min(max, math.floor(w / em)))
end

-- A text as a Text holds it: "&" as "and", no "<" or ">" -- inch marks and
-- apostrophes as they are (a Text would show an entity as it is written).
function SHAPE.esc(s)
    return (tostring(s or ""):gsub("&", "and"):gsub("[<>]", ""))
end

-- Text that shows at `size`, made at TEXT_DETAIL (or `detail`) times it:
-- the whole font size it is made at, and the scale that brings it back to
-- `size`.
function SHAPE.font(size, detail)
    local fs = math.max(1, math.floor(size * (detail or TEXT_DETAIL) + 0.5))
    return fs, size / fs
end

-- The attributes that make an element's text show at `size` (see
-- SHAPE.font) in a box `w` x `h` as it shows: font size, scale, and the
-- box as it is made (so that scaled it is `w` x `h` again); `detail` as
-- SHAPE.font's.
function SHAPE.sized(size, w, h, detail)
    local fs, sc = SHAPE.font(size, detail)
    return string.format('width="%.6g" height="%.6g" fontSize="%d" scale="%.9g %.9g 1"', w / sc, h / sc, fs, sc, sc)
end

-- Text `id` set to show at `size` in place (its box scales with it: text
-- overflows its box, which only places it).
function SHAPE.size(id, size)
    local fs, sc = SHAPE.font(size)
    self.UI.setAttribute(id, "fontSize", string.format("%d", fs))
    self.UI.setAttribute(id, "scale", string.format("%.9g %.9g 1", sc, sc))
end

-- Bold text centred at x, y in a box `w` x `h`, `size`, in `ink` (`extra`:
-- more attributes; `detail` as SHAPE.font's), free to overflow its box both
-- ways -- unless `bare`: then as TTS lays out a text by default.
function SHAPE.text(x, y, w, h, text, size, ink, id, extra, detail, bare)
    return string.format('<Text%s%s %s %s fontStyle="Bold" alignment="MiddleCenter"%s color="%s" raycastTarget="false">%s</Text>',
        id and (' id="' .. id .. '"') or "", extra or "", SHAPE.at(x, y), SHAPE.sized(size, w, h, detail),
        bare and "" or ' horizontalOverflow="Overflow" verticalOverflow="Overflow"', ink, SHAPE.esc(text))
end

-- A clear button `w` x `h` centred at x, y, calling `fn`: what is under it
-- takes the click, lit a little on hover.
function SHAPE.hit(id, fn, x, y, w, h)
    return string.format('<Button id="%s" %s width="%g" height="%g" colors="%s" onClick="%s" />',
        id, SHAPE.at(x, y), w, h, LOOK.HOVER, fn)
end

-- A button: its shape in `look` (a name of LOOK.BUTTONS, or { fill, line,
-- ink }), outlined EDGE (unless `line` is false), its label over it
-- (fitted on one line, see SHAPE.fitLine, unless `fit` is false) and a
-- clear button over it all that takes the click (none without `fn`). t = {
-- box, cut (none: SHAPE.CUT), look (none: "plain"), line, label, size, fit,
-- fn, btn (the clear button's id), id (the pieces' -- for a button
-- recoloured in place, see SHAPE.paint -- else none), txt (the label's
-- id), detail, bare (the label's, as SHAPE.text's) }.
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

-- Shape `id` (built with its id, see SHAPE.shape) recoloured in place:
-- `look` a name of LOOK.BUTTONS or { fill, line, ink } (what it leaves out
-- stays as it is). Its label is first set to `text`, when given (fitted
-- again): TTS can undo colours set before a label changes. Only the
-- pieces whose colour changes are sent.
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

-- Reset Fighters: every fighter's card back to the fighter as imported
-- (see onResetFighters) -- after a second click, within WAIT seconds,
-- while the button asks (in the ASKING look, see LOOK.BUTTONS).
local RESET = {
    LABEL = "Reset Fighters",
    ASK   = "Click again to reset",
    WAIT  = 4,
    ASKING = "red",
    asking = false, token = 0,
}

-- The game's setup, in the column until the game starts: "GAME SETUP" over
-- a column of buttons (ROWS, top to bottom, all as tall) -- the map size (a
-- click goes on to the next of DEPLOY.SIZES), three that roll a D6 in the
-- dice line for the battle's deployment, objective and crews (said on
-- everyone's screen, and the result is the button's text from then on; a
-- click rolls again -- the deployment also puts its model on the table,
-- see DEPLOY), the roll-off for who chooses Attacker and Defender, three
-- that do nothing yet, and Start Game (round 1: the column shows the round
-- from then on). Each row of ROWS:
--   label    what the button reads until it has rolled
--   start    Start Game
--   key      what a save knows its roll by
--   say      the word the result is said after ("Scenario: Ambush")
--   results  what each face of the D6 means (as said)
--   button   ... and as the button shows it, where it differs: "\n" for
--            a line break of its own
--   rollOff  a D6 for each side, thrown together (DICE.APART apart, the
--            left side's on the left): the higher one chooses -- a tie
--            is thrown again
--   map      the map size
--   deploy   the deployment: its model, and the small buttons right of it
--            (TOOL_W wide each, TOOL_GAP apart) that turn it, and raise
--            and lower it
-- Which side attacks shows on each side panel, under its points (the left
-- one is the Attacker until swapped there). Crews with reinforcements are
-- remembered under the round (SETUP.reminder).
--   Where the rows lie, in the layout's units (see LAYOUT): the heading
-- HEAD down (HEAD_FONT), the rows from TOP down to BOTTOM over the
-- column's bottom, INSET inside its edges, GAP apart, cut CUT; a row's text
-- FONT (Start Game's START_FONT) or as much smaller as it needs.
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
    attacker = 1,           -- the side (1 left, 2 right) that attacks; the other defends (saved)
    map      = 36,          -- the map size, in inches a side (saved)
    rolled   = {},          -- a roll's key -> the face it came up (saved)
    rolling  = {},          -- a row -> true while its die is falling
    HEAD = 48, HEAD_FONT = 30,
    TOP = 76, BOTTOM = 18, INSET = 26, GAP = 7, CUT = 12,
    FONT = 18, START_FONT = 22,
    TOOL_W = 34, TOOL_GAP = 6, TOOL_CUT = 6, TOOL_FONT = 13, ARROW_FONT = 10,
    ATTACKER = "#E0B830", DEFENDER = "#2BB3AD",   -- yellow and turquoise, with dark type
    SAY = { 1, 0.85, 0.4 }, -- what the rolls and swaps say
}

-- Row `k`'s button as a box of the layout (see LAYOUT) -- the rows share
-- the column's height under the heading evenly -- and, for the
-- deployment's row, the boxes of its small buttons right of it: the one
-- that turns the model (turn, as tall as the row) and the ones that raise
-- and lower it (up over down).
function SETUP.place(k)
    local col, n = LAYOUT.MID, #SETUP.ROWS
    local x0, x1 = col[1] + SETUP.INSET, col[3] - SETUP.INSET
    local h = (col[4] - SETUP.BOTTOM - SETUP.TOP - (n - 1) * SETUP.GAP) / n
    local y0 = SETUP.TOP + (k - 1) * (h + SETUP.GAP)
    if not SETUP.ROWS[k].deploy then return { x0, y0, x1, y0 + h } end
    local tw, g = SETUP.TOOL_W, SETUP.TOOL_GAP
    return { x0, y0, x1 - 2 * (tw + g), y0 + h },
        { turn = { x1 - 2 * tw - g, y0, x1 - tw - g, y0 + h },
          up   = { x1 - tw, y0, x1, y0 + h / 2 - 2 },
          down = { x1 - tw, y0 + h / 2 + 2, x1, y0 + h } }
end

-- Side `n`'s name as the setup says it: its gang's, or "Player <n>".
function SETUP.side(n)
    local name = trim(tostring(vpNames[n] or ""))
    return name ~= "" and name or ("Player " .. n)
end

-- The reminder under the round once the game is under way: what each part
-- of the crews rolled that brings reinforcements brings every round, as
-- "Reinforcements - D3" -- "Defender: Reinforcements - D3" when only one
-- side's part of it does. Nil when none does (or no crews were rolled).
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

-- What row `k` reads, fitted to its button: its text and font size.
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

-- The reminder (SETUP.reminder) as it shows under End Round: its text,
-- font size, and whether it shows.
function SETUP.note()
    local R, text = LAYOUT.ROUND, SETUP.reminder()
    local fitted, size = SHAPE.fit(text or "", R.NOTE_W, R.NOTE_H, R.NOTE_FONT)
    return fitted, size, text ~= nil
end

-- The setup in the column (shown before round 1): "GAME SETUP" over its
-- rows (setupBtn_<k> takes a row's click, setupTxt_<k> is its text), Start
-- Game gold; right of the deployment's row its small buttons (deployTurn,
-- deployUp, deployDown).
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

-- Row `k` redrawn in place.
function SETUP.draw(k)
    local text, size = SETUP.view(k)
    SHAPE.size("setupTxt_" .. k, size)
    setLabel("setupTxt_" .. k, text)
end

-- Every row redrawn (a side's name in the roll-off's result may have
-- changed).
function SETUP.drawAll()
    for k in ipairs(SETUP.ROWS) do SETUP.draw(k) end
end

-- Side `n`'s part, as its side panel shows it: the word and the colour
-- behind it.
function SETUP.role(n)
    if n == SETUP.attacker then return "Attacker", SETUP.ATTACKER end
    return "Defender", SETUP.DEFENDER
end

-- Attacker and Defender swapped, both side panels redrawn, and said in
-- chat.
function SETUP.swap()
    SETUP.attacker = 3 - SETUP.attacker
    for n = 1, 2 do
        local word, fill = SETUP.role(n)
        SHAPE.paint("vpRole_" .. n, { fill = fill }, word:upper())
    end
    printToAll(string.format("%sAttacker: %s -- Defender: %s", CHAT_PREFIX, SETUP.side(SETUP.attacker),
        SETUP.side(3 - SETUP.attacker)), SETUP.SAY)
end

-- The deployment's models on the table: those last put down, else every
-- one with DEPLOY.TAG (from before a load). An empty list for none.
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

-- Every deployment model taken off the table. Returns whether there was one.
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

-- Deployment `face`'s model on the map size chosen: its mesh's link, its
-- collider's, how far it is stretched along x (1: made for that size),
-- and how far from the middle its two copies go (nil: one, in the middle).
function DEPLOY.model(face)
    local mesh = DEPLOY.MESH[face] or {}
    if mesh.apart then return DEPLOY.ZONE, DEPLOY.COLLIDER, SETUP.map / DEPLOY.BASE, mesh.apart end
    if mesh[1] == nil then return mesh[SETUP.map] or "", DEPLOY.COLLIDER, 1 end
    return mesh[1], DEPLOY.COLLIDER, 1
end

-- Point `x`, `z` (on the table, from its middle) turned `yaw` degrees
-- about the middle, as an object turned so is.
function DEPLOY.turned(x, z, yaw)
    local a = math.rad(yaw)
    return x * math.cos(a) + z * math.sin(a), -x * math.sin(a) + z * math.cos(a)
end

-- The model of deployment `face` (Roll for Deployment's result) on the
-- map size chosen, in place of any other (see DEPLOY.model): turned
-- DEPLOY.turn about the middle of the table, stretched up DEPLOY.tall,
-- locked, see-through. With no link for it, chat says so and nothing is
-- put down. Returns the models put down.
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

-- The deployment rolled put on the table again (nothing when none was
-- rolled). Returns the models put down.
function DEPLOY.again()
    for _, row in ipairs(SETUP.ROWS) do
        local face = row.deploy and SETUP.rolled[row.key]
        if face then return DEPLOY.spawn(face, row.results[face]) end
    end
    return {}
end

-- Row `k`'s roll-off: a D6 for each side, thrown together, the left
-- side's on the left. The higher one chooses Attacker and Defender (said
-- on everyone's screen, and on the row); a tie is thrown again.
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
            local was = SETUP.rolled[SETUP.ROWS[k].key]   -- NQS fork: for the recorder (below)
            SETUP.rolling[k] = nil
            SETUP.rolled[SETUP.ROWS[k].key] = win
            SETUP.draw(k)
            DICE.announce(string.format("%s%s chooses%s", CHAT_PREFIX, SETUP.side(win), how), SETUP.SAY)
            if was ~= win then SETUP.busAttacker(color) end   -- NQS fork: see SETUP.busAttacker
        end })
end

-- Each player's side panel (sideXml) shows their gang's name -- typed in,
-- or taken from one of the gang's models put on the table in front of its panel (see
-- BOTTLE.tick) -- their victory points, their part (Attacker or Defender:
-- a click swaps them, see SETUP) and their gang's Bottle Check (see the
-- Bottle Check's functions): "BOTTLE CHECK" over the Ld it is taken
-- against (bottleVal: left click one more, right click one fewer, by hand;
-- green while the gang's Iron Will raises it, see BOTTLE.target), with "Ld"
-- left of it, and the die that rolls it (bottleRoll: the card's die,
-- DIE_ICON, upright over it -- ICON of the diamond's side, as on the card's
-- roll buttons -- or a "D"). A dark red plate (bottle_<n>) lies behind the
-- check while it must be taken; a left click on "BOTTLE CHECK"
-- (bottleHead_<n>) switches that by hand. Every diamond is a turned button
-- with a plain Text over it (a turned button's label would turn with it).
local BOTTLE = {
    due   = {},             -- gang (BOTTLE.key) -> "due" (to take: lit) or "done", this turn
    hand  = {},             -- per side: an Ld set by hand (nil: the gang's best)
    seen  = {},             -- per side: the model last found in front of its side panel
    R     = 38,             -- the diamonds: from the middle to each tip (panel units)
    ICON  = 0.78,           -- the die's size, a fraction of a diamond's side (the card's LAY.dieIcon)
    FONT  = 32,             -- the Ld in its diamond
    HAND  = "#F0C060",      -- an Ld set by hand
    UP    = "#6EE07A",      -- an Ld the gang's Iron Will raises (the card's green for a better value)
    HINT  = "[ NO NAME SET ]",                                -- a side's name while it has no gang ...
    HOW   = { "Move a scribed Model", "beneath this panel to", "set the Gangname" },   -- ... and, in place of its points, how to give it one
    ZONE  = 140,            -- how far out on the table in front of a side panel a model sets its name (panel units from its bottom edge)
}

-- One of side `n`'s diamonds, its middle at x, y: the turned button
-- `id`_<n> (calling `fn`) with the card's diamond frame over it (ART.FRAME:
-- turned with it, FRAME_SIZE times its side, in gold -- or, without the
-- art, gold lines round it) and a plain Text over that (`id`Txt_<n>).
function BOTTLE.diamond(id, n, x, y, label, fn, ink)
    local r = BOTTLE.R
    local side = r * math.sqrt(2)
    local frame
    if ART.FRAME ~= "" then
        frame = string.format('<Image %s width="%g" height="%g" rotation="0 0 45" image="mundaneFrame" color="%s"' ..
            ' raycastTarget="false" />', SHAPE.at(x, y), side * ART.FRAME_SIZE, side * ART.FRAME_SIZE, LOOK.GOLD)
    else
        frame = (SHAPE.lines({ { x, y - r }, { x + r, y }, { x, y + r }, { x - r, y } }, LOOK.EDGE, LOOK.GOLD, true))
    end
    return string.format('<Button id="%s_%d" %s width="%g" height="%g" rotation="0 0 45" colors="%s" onClick="%s" />',
        id, n, SHAPE.at(x, y), side, side, LOOK.DIAMOND, fn) ..
        frame .. SHAPE.text(x, y, side, side, label, BOTTLE.FONT, ink or LOOK.TEXT, id .. "Txt_" .. n)
end

-- What side `n`'s name line shows: its gang's name in capitals (BOTTLE.HINT
-- while it has none), and the font size that fits it on the line.
function BOTTLE.nameView(n)
    local S = LAYOUT.SIDE
    local text = BOTTLE.named(n) and trim(tostring(vpNames[n])):upper() or BOTTLE.HINT
    local size = math.floor(math.min(S.NAME_FONT, (S.NAME_W - 24) / math.max(0.01, SHAPE.width(text))))
    return text, math.max(S.NAME_MIN, size)
end

-- A clear panel the size of the whole panel, shown while `on`, round
-- `inner` (laid out on the panel, like everything else).
local function group(id, on, inner)
    return string.format('<Panel id="%s" active="%s" width="%d" height="%d" color="#00000000">\n%s\n</Panel>',
        id, tostring(on), PANEL_W, PANEL_H, inner)
end

-- Side `n`'s panel (see BOTTLE above): the gang's name over a thin rule --
-- an input field without a frame (vpName_<n>), so a name can be typed in;
-- while the side has no gang it reads BOTTLE.HINT, which counts as no name
-- (see onVpName) -- then "VICTORY POINTS" over the points (vpShow_<n>:
-- vpText_<n>, vpBtn_<n> takes the clicks) or, while the side has no gang,
-- how to give it one (vpHint_<n>); a thin rule; the side's part (vpRole_<n>);
-- and the Bottle Check.
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
        group("bottle_" .. n, BOTTLE.lit(n), SHAPE.shape(across(S.PLATE), { pc, pc, pc, pc }, LOOK.BUTTONS.red, LOOK.EDGE)),
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
        SHAPE.text(cx, top + S.BOTTLE, S.HEAD_W, S.HEAD_FONT * 1.4, "BOTTLE CHECK", S.HEAD_FONT, LOOK.TEXT),
        SHAPE.hit("bottleHead_" .. n, "onBottleHead", cx, top + S.BOTTLE, S.HEAD_W, S.HEAD_FONT * 1.4),
        SHAPE.text(cx + S.LD_X, dy, 60, S.LD_FONT * 1.3, "Ld", S.LD_FONT, LOOK.TEXT),
        BOTTLE.diamond("bottleVal", n, cx + S.VAL_X, dy, v and tostring(v) or "-", "onBottleValue", BOTTLE.ink(n, will)),
        roll,
    }, "\n")
end

-- The round's number as the gear shows it, and its size: ROUND.FONT, or
-- smaller so it stays inside the gear's inner ring (the box of its digits
-- -- as wide as they are, 0.72 em tall -- a little clear of the ring).
local function roundView()
    local R, text = LAYOUT.ROUND, tostring(turn)
    local half = math.sqrt((SHAPE.width(text) / 2) ^ 2 + 0.36 ^ 2)
    return text, math.floor(math.min(R.FONT, R.RING * 0.92 / half))
end

-- The column between the side panels. From round 1 (turnView): "ROUND"
-- (turnCaption) between two thin rules, over the gear on its glow with the
-- round's number in it (turnText; turnBack takes a right click on it, which
-- steps the round back), End Round under it (turnBtn: a left click starts
-- the next round, every fighter readied; a right click steps it back -- below
-- round 1 to the setup) and under that the reminder of reinforcements
-- (roundNote, see SETUP.note); over "ROUND" Supported Mechanics (infoBtn:
-- the instructions page on the feedback form's tablet, see onInfo -- dim,
-- plain while the tablet shows the page). Before round 1 the game's setup
-- (SETUP.xml).
local function columnXml()
    local R, col = LAYOUT.ROUND, LAYOUT.MID
    local cx, gy = (col[1] + col[3]) / 2, R.GEAR
    local number, size = roundView()
    local note, noteSize, noteOn = SETUP.note()
    -- the button's cut edges run along the column's, INFO_GAP inside them
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

-- The links between the column and each side panel: a line with a small
-- gold diamond in its middle.
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

-- A row of buttons under a panel, filling x0 to x1 (RAIL_GAP apart): each
-- of `list` a SHAPE.button's t without its box (w: a width of its own, the
-- others sharing the rest) -- cut like the panel's lower corners: the first
-- at its bottom left, the last at its bottom right, the rest square.
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

-- The buttons under the panels: under each side panel Roll Dice, Roll
-- Firepower and Roll Injuries (both rows the same: a die in the line under
-- the panel per click, quick clicks gathered into one roll -- see
-- DICE.click); under the column Reset Fighters (red while it asks for its
-- second click, see RESET), Feedback (the envelope alone: the feedback
-- form on a tablet past the panel, gold while it is up -- feedbackText,
-- the word the importer's button has, stays empty) and Settings.
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

-- The main page: both side panels, the column, the links between them and
-- the buttons under them (playSection: hidden while the Settings page
-- shows).
local function playXml()
    return group("playSection", not HOMEBREW.page,
        table.concat({ sideXml(1), sideXml(2), columnXml(), linksXml(), railsXml() }, "\n"))
end

-- A homebrew set's name or description as a Text shows it (see HOMEBREW).
local function hbText(s)
    return (tostring(s or ""):gsub("&", "and"):gsub("[<>]", ""))
end

-- Radio button `k` of a set (1: the rules as written, 2: the set's) as it
-- looks on the page: gold, "● ...", while it is the page's choice (see
-- HOMEBREW.pick), else plain, "○ ..." -- its look and label -- and the
-- description under the set: what the chosen one does.
local function hbLook(set, k)
    local on = HOMEBREW.pick[set.id] == true
    local chosen = on == (k == 2)
    return chosen and "gold" or "plain", (chosen and "● " or "○ ") .. hbText(k == 2 and set.name or set.off),
           hbText(on and set.desc or set.offDesc)
end

-- The Settings page's bounds: the main page's -- the left side
-- panel's left edge to the right one's right edge, the column's top to the
-- buttons' bottom.
function HOMEBREW.box()
    local L = LAYOUT
    return { L.SIDES[1][1], L.MID[2], L.SIDES[2][3], L.RAIL[2] }
end

-- The page's outline, points round from the top left: the side panels'
-- top with their outer corners cut (SIDE_CUT), the column's top rising
-- between them -- its cuts (MID_CUT) run on down to the side panels' top --
-- and the bottom corners cut as the buttons' row's are (RAIL_CUT). The
-- frame round the panel has this outline too. Also the corners' cuts and
-- where the column's cuts meet the side panels' top (sx0, sx1).
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

-- The page's two columns, each the places in SETS of its sets, in order:
-- Gameplay (the sets marked `gameplay`) and Homebrew Rules (the rest).
function HOMEBREW.columns()
    local cols = { {}, {} }
    for i, set in ipairs(HOMEBREW.SETS) do
        local col = cols[set.gameplay and 1 or 2]
        col[#col + 1] = i
    end
    return cols
end

-- How far down the page each set comes after the one above it: what is
-- left between HEAD (under the side panels' top) and FOOT, shared out among
-- the sets of the fuller column (the other's sets line up with them).
function HOMEBREW.step()
    local H, box, cols = HOMEBREW, HOMEBREW.box(), HOMEBREW.columns()
    return (box[4] - H.FOOT - LAYOUT.SIDES[1][2] - H.HEAD) / math.max(1, #cols[1], #cols[2])
end

-- The page's shape: filled -- the body (under the side panels' top) and
-- the column's top over it, each pieced as SHAPE.fill does -- outlined in
-- gold, every cut accented: the body's four corners ACCENT along the edges,
-- the column's two cuts MID_ACCENT on along the side panels' top and the
-- column's top.
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

-- Set `i`'s description as the page shows it: the chosen choice's,
-- fitted (its text and size).
function HOMEBREW.desc(i)
    local H = HOMEBREW
    local _, _, desc = hbLook(H.SETS[i], 1)
    return SHAPE.fit(desc, H.DESC_W, H.DESC_H, H.DESC_FONT)
end

-- The Settings page in place of the main page (hidden until its button
-- opens it): a panel with the title and Back (homebrewBack), split into
-- two columns (see HOMEBREW.columns) under their headers, and for each set
-- its two radio buttons (hbOpt_<i>_1: as written, hbOpt_<i>_2: the set's)
-- over its description (hbDesc_<i>), thin rules between the sets of a
-- column, and at the bottom Apply Settings (homebrewApply).
local function homebrewXml()
    local H, box = HOMEBREW, HOMEBREW.box()
    local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
    local cx, step, top = (x0 + x1) / 2, HOMEBREW.step(), LAYOUT.SIDES[1][2]
    -- the title's room: the column's top as wide as it is where the
    -- capitals' tops are, less its outline
    local _, _, _, sx0, sx1 = HOMEBREW.outline()
    local room = sx1 - sx0 - 2 * (top - y0 - H.TITLE + H.TITLE_FONT * 0.4) - 4 * LOOK.LINE
    local title = "SETTINGS"
    local _, size = SHAPE.fitLine(title, room, H.TITLE_FONT)
    local out = {
        HOMEBREW.shapeXml(),
        SHAPE.text(cx, y0 + H.TITLE, room, H.TITLE_FONT * 1.4, title, size, LOOK.HEAD),
        SHAPE.button({ box = { x1 + H.BACK[1], top + H.BACK[2], x1 + H.BACK[3], top + H.BACK[4] }, label = "BACK",
            size = H.BACK_FONT, fn = "onHomebrewBack", btn = "homebrewBack" }),
        SHAPE.lines({ { cx, top + H.DIV_UP }, { cx, y1 - H.FOOT } }, LOOK.THIN, LOOK.SEP),
    }
    for c, col in ipairs(HOMEBREW.columns()) do
        -- the column's middle: the middle of its half of the page
        local mx = x0 + (c - 0.5) * (x1 - x0) / 2
        out[#out + 1] = SHAPE.text(mx, top + H.SUB, H.DESC_W, H.SUB_FONT * 1.4, c == 1 and "GAMEPLAY" or "HOMEBREW RULES",
            H.SUB_FONT, LOOK.HEAD)
        for n, i in ipairs(col) do
            local set, y = H.SETS[i], top + H.HEAD + (n - 1) * step
            for k = 1, 2 do
                local look, label = hbLook(set, k)
                local bx = k == 1 and mx - H.RADIO_GAP / 2 - H.RADIO_W or mx + H.RADIO_GAP / 2
                local id = string.format("hbOpt_%d_%d", i, k)
                out[#out + 1] = SHAPE.button({ box = { bx, y, bx + H.RADIO_W, y + H.RADIO_H }, look = look, label = label,
                    size = H.RADIO_FONT, fn = "onHomebrewOption", btn = id, id = id, txt = id .. "Txt" })
            end
            local desc, dsize = HOMEBREW.desc(i)
            out[#out + 1] = SHAPE.text(mx, y + H.DESC, H.DESC_W, H.DESC_H, desc, dsize, LOOK.DIM, "hbDesc_" .. i)
            if n < #col then
                out[#out + 1] = (SHAPE.lines({ { mx - H.SEP_W / 2, y + step - H.SEP_UP },
                    { mx + H.SEP_W / 2, y + step - H.SEP_UP } }, LOOK.THIN, LOOK.SEP))
            end
        end
    end
    out[#out + 1] = SHAPE.button({ box = { cx - H.APPLY_W / 2, y1 - H.APPLY_UP - H.APPLY_H, cx + H.APPLY_W / 2,
        y1 - H.APPLY_UP }, look = HOMEBREW.applyLook(), label = "APPLY SETTINGS", size = H.APPLY_FONT,
        fn = "onHomebrewApply", btn = "homebrewApply", id = "homebrewApply", txt = "homebrewApplyTxt" })
    return group("homebrewPage", H.page, table.concat(out, "\n"))
end

-- The whole panel: the main page, or in its place the Settings page
-- -- built afresh, so what is noted of its shapes is too.
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

-- The panel's pictures as its own UI assets (those with a link).
local function panelAssets()
    local out = {}
    for _, a in ipairs({ { "mundaneEdge", ART.EDGE }, { "mundaneFrame", ART.FRAME }, { "mundaneGear", ART.GEAR },
                         { "mundaneGlow", ART.GLOW }, { "mundaneDie", DIE_ICON } }) do
        if a[2] ~= "" then out[#out + 1] = { name = a[1], url = a[2] } end
    end
    return out
end

-- A player's victory points, clicking them: left click one up, right click
-- one down (never below 0) -- not while the side has no gang (they don't
-- show then).
function onVp(player, value, id)
    local n = tonumber(tostring(id or ""):match("^vpBtn_(%d)$"))
    if not (n and vp[n]) or not BOTTLE.named(n) then return end
    local was = vp[n]                                                   -- NQS fork: for the recorder (below)
    vp[n] = math.max(0, vp[n] + (tostring(value) == "-2" and -1 or 1))
    setLabel("vpText_" .. n, tostring(vp[n]))
    if vp[n] ~= was then SETUP.busVp(n, was, player and player.color or nil) end   -- NQS fork: see SETUP.busVp
end

-- A player's name typed in -- the gang whose Bottle Check that side shows
-- (a model put in front of the side panel types it in, see BOTTLE.tick). The hint
-- an unnamed side shows changes nothing, nor does the name as shown (in
-- capitals).
function onVpName(player, value, id)
    local n = tonumber(tostring(id or ""):match("^vpName_(%d)$"))
    if not (n and vpNames[n]) then return end
    local name = trim(tostring(value or ""))
    if name ~= BOTTLE.HINT and name:lower() ~= trim(tostring(vpNames[n])):lower() then
        vpNames[n] = name
        BOTTLE.hand[n] = nil
        SETUP.busGang(n, player and player.color or nil)                -- NQS fork: see SETUP.busGang
    end
    BOTTLE.drawSide(n)
    SETUP.drawAll()
end

-- ── The Bottle Check ─────────────────────────────────────────────
-- A gang with a fighter taken Out of Action this turn must take one: the
-- fighter's card tells this object (onFighterOut), and that gang's side
-- panel -- the side whose name is the gang's -- shows a dark red plate
-- behind its check until the check is rolled or the turn changes; once a
-- turn. It is taken on 2D6 against the best Ld of the gang's fighters still
-- on the table (not Out of Action), Loners left out unless every one is a
-- Loner -- one higher for each of them with the Iron Will skill, the number
-- then green. A player puts one of their gang's models on their side panel
-- to name their side after the gang.

-- A gang's name as the check compares it: trimmed, any case.
function BOTTLE.key(name) return trim(tostring(name or "")):lower() end

-- A model's gang name: its gang tag without the tag's prefix (nil: none).
function BOTTLE.gangName(obj)
    local tag = gangOf(obj)
    if not tag then return nil end
    for _, pre in ipairs({ GANG_TAG, OLD_TAGS[1], OLD_TAGS[2] }) do
        if tag:sub(1, #pre) == pre then return tag:sub(#pre + 1) end
    end
    return tag
end

-- The fighters of gang `name` on the table, each { name, ld, loner, will }
-- as its card tells it (engageInfo; an older card's Ld read from
-- getFighter) -- those Out of Action left out. `will`: what its Iron Will
-- adds to the number the check is taken against.
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

-- The Ld a Bottle Check is taken against for fighters `list`: the highest
-- of those that aren't Loners -- of the Loners only when all are -- and
-- whose it is (nil: no Ld at all). And what Iron Will does for them: 1 is
-- taken off the check's roll for every fighter of theirs with the skill
-- (what each card says its Iron Will is worth, added up) -- the third
-- value back.
function BOTTLE.best(list)
    local all, will = true, 0
    for _, f in ipairs(list) do
        if not f.loner then all = false end
        will = will + (f.will or 0)
    end
    local best, who
    for _, f in ipairs(list) do
        if f.ld and (all or not f.loner) and (not best or f.ld > best) then best, who = f.ld, f.name end
    end
    return best, who, will
end

-- What gang `name`'s Bottle Check is taken against, as things stand: its
-- best Ld and, since taking Iron Will's off the roll comes to the same,
-- that much added to it (12 at most: 2D6 never roll more). Returns the
-- number (nil: no Ld at all), how much of it is Iron Will's, and whose Ld
-- it is, for chat ("Boss's Ld", "Boss's Ld 8 +1 Iron Will").
function BOTTLE.target(name)
    local best, who, will = BOTTLE.best(BOTTLE.fighters(name))
    if not best then return nil, 0, nil end
    local target = math.min(12, best + will)
    will = target - best
    who = who and (who .. "'s Ld") or "Ld"
    if will > 0 then who = string.format("%s %d +%d Iron Will", who, best, will) end
    return target, will, who
end

-- The number side `n` shows: set by hand, else its gang's (BOTTLE.target)
-- -- and how much of it is Iron Will's (none of one set by hand).
function BOTTLE.value(n)
    if BOTTLE.hand[n] then return BOTTLE.hand[n], 0 end
    local target, will = BOTTLE.target(vpNames[n])
    return target, will
end

-- The colour side `n`'s number shows in: one set by hand in its own, one
-- Iron Will raises (by `will`) green, else plain.
function BOTTLE.ink(n, will)
    return BOTTLE.hand[n] and BOTTLE.HAND or (will or 0) > 0 and BOTTLE.UP or LOOK.TEXT
end

-- Whether side `n`'s check must be taken (its plate shows).
function BOTTLE.lit(n)
    local key = BOTTLE.key(vpNames[n])
    return key ~= "" and BOTTLE.due[key] == "due"
end

-- Whether side `n` has a name of its own (not the "Player <n>" it starts
-- with, nor empty).
function BOTTLE.named(n)
    local key = BOTTLE.key(vpNames[n])
    return key ~= "" and key ~= ("player " .. n)
end

-- Side `n`'s Bottle Check redrawn: its plate and its Ld.
function BOTTLE.draw(n)
    self.UI.setAttribute("bottle_" .. n, "active", tostring(BOTTLE.lit(n)))
    local v, will = BOTTLE.value(n)
    setLabel("bottleValTxt_" .. n, v and tostring(v) or "-")
    self.UI.setAttribute("bottleValTxt_" .. n, "color", BOTTLE.ink(n, will))
end

-- Side `n`'s panel redrawn for its name: the name (or the hint), its
-- points or how to name the side, and its Bottle Check.
function BOTTLE.drawSide(n)
    local text, size = BOTTLE.nameView(n)
    self.UI.setAttribute("vpName_" .. n, "text", text)
    local S = LAYOUT.SIDE
    for a, v in SHAPE.sized(size, S.NAME_W, S.NAME_H):gmatch('(%w+)="([^"]*)"') do
        self.UI.setAttribute("vpName_" .. n, a, v)
    end
    self.UI.setAttribute("vpShow_" .. n, "active", tostring(BOTTLE.named(n)))
    self.UI.setAttribute("vpHint_" .. n, "active", tostring(not BOTTLE.named(n)))
    BOTTLE.draw(n)
end

-- A new turn (either way): no check to take any more, nothing set by hand.
function BOTTLE.newTurn()
    BOTTLE.due, BOTTLE.hand = {}, {}
    for n = 1, 2 do BOTTLE.draw(n) end
end

-- Where a model sets side `n`'s name, worked out from the layout (LAYOUT)
-- and STAND: the strip of table in front of the panel, under the side panel
-- and BOTTLE.ZONE panel units deep from the panel's bottom edge (short of
-- the dice's line). Its middle (local x, z -- the table is local y 0) and its
-- width and depth (local units).
function BOTTLE.spot(n)
    local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
    local b = LAYOUT.SIDES[n] or LAYOUT.SIDES[1]
    local x, _, z = STAND.point((b[1] + b[3]) / 2 - PANEL_W / 2, -PANEL_H / 2)
    local d = BOTTLE.ZONE * k
    return x, z + d / 2, (b[3] - b[1]) * k, d
end

-- The first model with a gang tag standing in side `n`'s strip of table
-- (nil: none): one box looked through over it, from the table up.
function BOTTLE.modelOn(n)
    if not (Physics and Physics.cast and self.positionToWorld) then return nil end
    local x, z, w, d = BOTTLE.spot(n)
    local p = self.positionToWorld({ x, 0, z })
    local okS, sc = pcall(function() return self.getScale() end)
    sc = okS and type(sc) == "table" and sc or {}
    local okR, rot = pcall(function() return self.getRotation() end)
    local hits = Physics.cast({ origin = { p.x, p.y + 1.5, p.z }, direction = { 0, 1, 0 }, type = 3,
        size = { w * (sc.x or 1), 3, d * (sc.z or 1) }, orientation = okR and rot or nil, max_distance = 0 }) or {}
    for _, hit in ipairs(hits) do
        local o = hit.hit_object
        if o and o ~= self and BOTTLE.gangName(o) then return o end
    end
end

-- Half a second after anything on the table is picked up, put down or
-- removed (BOTTLE.soon), and every BOTTLE.POLL seconds besides: a model
-- newly put on the table in front of a side panel names that side after its gang (said in chat,
-- the model flashed) -- not while the Settings page hides the side
-- panels. Looking only when something moved spares a slow machine the
-- panels' physics casts twice a second all game.
function BOTTLE.tick()
    if HOMEBREW.page then return end      -- the side panels are hidden behind the Settings page
    for n = 1, 2 do
        local o = BOTTLE.modelOn(n)
        if o ~= BOTTLE.seen[n] then
            BOTTLE.seen[n] = o
            local g = o and BOTTLE.gangName(o)
            if g then
                local renamed = trim(tostring(vpNames[n])):lower() ~= trim(tostring(g)):lower()   -- NQS fork
                vpNames[n] = g
                BOTTLE.hand[n] = nil
                if renamed then SETUP.busGang(n) end                    -- NQS fork: see SETUP.busGang
                BOTTLE.drawSide(n)
                SETUP.drawAll()
                pcall(function() o.highlightOn({ 0.9, 0.8, 0.4 }, 1) end)
                printToAll(string.format("%s%s play on the %s.", CHAT_PREFIX, g, n == 1 and "left" or "right"),
                    { 0.9, 0.8, 0.4 })
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
function onObjectDrop() BOTTLE.soon() end
function onObjectPickUp() BOTTLE.soon() end
function onObjectDestroy() BOTTLE.soon() end

-- The Bottle Check's two D6, thrown in the dice's line under the panel
-- (see DICE), then done(faces, digital) -- in the order thrown.
function BOTTLE.throw(n, color, done)
    DICE.request({ kinds = { "d6", "d6" }, color = color, done = done })
end

-- ── The dice ─────────────────────────────────────────────────────
-- Every roll falls in a line under the panel (see DICE): a card's (see
-- throwDice), a Bottle Check's -- under the column -- and the Roll Dice /
-- Firepower / Injuries buttons' under the side panel they were clicked on,
-- so both sides can roll at once (a roll-off).
-- A roll: { kinds = { "d6", "firepower", ... }, color = the roller's, and
-- who hears of it: done(faces, digital, dice) and / or a card (from = its
-- GUID, token), or -- own, the buttons' -- said on everyone's screen;
-- apart = its dice fall in a row in the order thrown, that far apart, and
-- lie so (none: they fall from the middle out, and lie STEP apart);
-- inOrder = never lined up by SORT; lane = which line: 1 / 2 under that
-- side panel, nil under the column }.
-- Each line (DICE.lanes, see DICE.lane) goes on its own: its busy = the
-- roll falling now, queue = the rolls waiting for it, shown = the last
-- roll's dice, lined up, open = the buttons' roll still gathering clicks.
-- The tokens let a newer wait win over an older one.
DICE.lanes = {}
DICE.ORDER = { d6 = 1, firepower = 2, injury = 3 }   -- mixed kinds line up in this order

-- Line `key`'s state (1 / 2: under that side panel; nil: under the column).
function DICE.lane(key)
    key = LAYOUT.SIDES[key] and key or "main"
    local l = DICE.lanes[key]
    if not l then
        l = { key = key, queue = {}, shown = {}, joinToken = 0 }
        DICE.lanes[key] = l
    end
    return l
end

-- Throws roll `req` now, or once the one falling in its line has been
-- lined up.
function DICE.request(req)
    local l = DICE.lane(req.lane)
    if l.busy or #l.queue > 0 then l.queue[#l.queue + 1] = req else DICE.start(req) end
end

-- The line the dice of line `lane` fall in: its middle in the world -- on
-- the table in front of the panel, DICE.BELOW panel units out from its
-- bottom edge, under the column's middle or side panel `lane`'s -- and the
-- way it runs (the panel's x, flat, one world unit long) -- nil outside
-- TTS.
function DICE.line(lane)
    if not self.positionToWorld then return nil end
    local k = (tonumber(tostring(PANEL.scale):match("[%d.]+")) or 1) / 100
    local b = LAYOUT.SIDES[lane]
    local x, _, z = STAND.point(b and (b[1] + b[3]) / 2 - PANEL_W / 2 or 0, -PANEL_H / 2)
    z = z + DICE.BELOW * k
    local ox = STAND.point(0, 0)
    local rx = STAND.point(100, 0)                        -- the panel's x, one local unit
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

-- A roll begins: the last roll's dice go, and its dice fall (one each of
-- req.kinds) -- or, outside TTS, its faces are rolled digitally at once.
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

-- One die of `kind` for roll `req`: dropped from DICE.DROP over the line --
-- the first in its middle, the others either side in turn (0, +1, -1, +2
-- ... steps, a little off), so dice a click adds don't drift one way --
-- turned any way and spinning: the custom dice's art when its URL is set,
-- else TTS's own D6 in a light shade of the roller's colour.
function DICE.spawn(req, kind)
    local i = #req.dice + 1
    local k = i - 1
    local off = (k % 2 == 1 and 1 or -1) * math.ceil(k / 2) * DICE.STEP + (math.random() - 0.5) * 0.3
    if req.apart then off = (k - (#req.kinds - 1) / 2) * req.apart end   -- in a row, in order, that far apart
    local m, d, url, s = req.mid, req.dir, DICE.URL[kind] or "", DICE.SCALE
    -- the roll's entry: where it spawned and, once spawned, its kick (see
    -- DICE.settled)
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
                -- NQS fork: dedup tag for the game-recorder's Type 2 observer,
                -- which sees die spawns via onObjectSpawn and skips any
                -- carrying this tag -- the bus-publish event already carries
                -- the roll with its full game context (fighter, weapon,
                -- action, faces), so the physical die is redundant. Shared
                -- tag name with gang-roster's spawns on purpose: the observer
                -- only needs to know WHETHER a sibling claimed the roll, not
                -- WHO. See MR !27.
                obj.addTag("gang-roster-roll")
                if url == "" and req.color and stringColorToRGB then
                    local c = stringColorToRGB(req.color)
                    obj.setColorTint({ 0.45 + 0.55 * c.r, 0.45 + 0.55 * c.g, 0.45 + 0.55 * c.b })
                end
                -- tumbling about every axis (at least half of SPIN each
                -- way, so none just drops flat) ...
                local function turn() return (math.random() * 0.5 + 0.5) * DICE.SPIN * (math.random() < 0.5 and -1 or 1) end
                local av = { turn(), turn(), turn() }
                -- ... and pushed up to PUSH sideways, any way (the row is
                -- lined up afterwards anyway), so it rolls on when it lands.
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
                -- set now and again two frames on: TTS may still be finishing
                -- the spawn, and a velocity set then can be lost (the die just
                -- drops, showing the face it spawned with) -- and kept, to
                -- give again (DICE.settled)
                entry.kick = go
                go()
                if Wait and Wait.frames then Wait.frames(go, 2) end
            end)
        end,
    })
    if ok and o and url ~= "" then pcall(function() o.setCustomObject({ image = url, type = 1 }) end) end
    entry.obj = ok and o or nil
end

-- Whether roll `req` can be read: every die fallen and at rest again (one
-- taken off the table meanwhile doesn't count). Called every frame until
-- then. TTS can hold a fresh die still in mid-air for a moment, calling it
-- resting all the while -- read then, the roll would come back at once
-- with the faces the dice spawned with. So a die is down only once it has
-- moved FALL from its spawn point and rests; until it falls it is kicked
-- again every KICK frames, and once more as it starts to fall, so it
-- tumbles on the way down.
function DICE.settled(req)
    local all = true                               -- every die looked at: each is kicked as needed
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

-- Roll `req` has settled (or waited long enough): each die read as it lies
-- (rolled digitally if it can't be), lined up (by SORT), handed to whoever
-- asked in the order thrown -- the roll's order is kept on the card and in
-- chat -- then the next roll waiting, if any.
function DICE.finish(req)
    if req.finished then return end
    req.finished = true
    local list = {}
    for i, d in ipairs(req.dice) do
        local face
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

-- The dice of `list` moved into a row along the line, in its order, STEP
-- apart and at the height the lowest came to rest at, each with its face
-- up and all turned alike (DICE.faceUp) -- then locked.
function DICE.lineUp(req, list)
    if not req.mid then return end
    local low
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

-- The rotation that shows face `face` of die `o` up (its rotation values),
-- turned `yaw` degrees -- or nil when TTS doesn't say.
function DICE.faceUp(o, face, yaw)
    local ok, rv = pcall(function() return o.getRotationValues() end)
    for _, r in ipairs(ok and type(rv) == "table" and rv or {}) do
        local rot = r.rotation
        if rot and tostring(r.value) == tostring(face) then
            return { rot.x or rot[1] or 0, ((rot.y or rot[2] or 0) + yaw) % 360, rot.z or rot[3] or 0 }
        end
    end
end

-- The faces, in the order they lie, to whoever asked for roll `req`: its
-- done function, the card that asked (onDiceThrown), or -- the buttons'
-- -- everyone, in chat.
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
    if req.own then DICE.say(req, list, digital) end
end

-- This object's own rolls said on everyone's screen (and in chat).
function DICE.announce(msg, rgb)
    if broadcastToAll then broadcastToAll(msg, rgb) else printToAll(msg, rgb) end
end

-- The Injury dice's results as the chat names them (RULES.injury's short
-- names: Inj, S. Inj, OOA; the result that counts written out,
-- DICE.LABEL: Injury, Serious Injury, Out of Action), and their ranks (1
-- the worst).
RULES.follow(function()
    DICE.INJURY, DICE.LABEL, DICE.RANK = {}, {}, {}
    for k, r in pairs(RULES.injury) do
        DICE.INJURY[k], DICE.LABEL[k], DICE.RANK[k] = r.short or r.label, r.label or r.short, r.rank or 0
    end
end)

-- The buttons' roll said on everyone's screen, in the roller's colour, as
-- the gang of the side panel it was rolled under ("[Alpha] rolls ...";
-- a side with no gang: "[Player 1] rolls ..."): the D6 and their total,
-- the Firepower dice (CHART) and their hits -- and whether an Ammo check
-- is due -- and the Injury dice's results, every one and the best after
-- them written out ("Inj, OOA = Injury"; one die: its result written out;
-- no count of dice, no faces).
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

-- Line `l`'s last roll's dice taken off the table as its next roll begins
-- -- with any left lying from before a save (they carry DICE.TAG; the
-- other lines' dice, falling or shown, stay).
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

-- Line `l`'s next roll waiting, if any: thrown DICE.NEXT seconds after the
-- last was lined up, so that one can be seen (at once when nothing was
-- thrown).
function DICE.next(l)
    if #l.queue == 0 then return end
    local function go()
        if l.busy or #l.queue == 0 then return end
        DICE.start(table.remove(l.queue, 1))
    end
    if l.shown[1] and l.shown[1].obj then Wait.time(go, DICE.NEXT) else go() end
end

-- A click on Roll Dice / Roll Firepower / Roll Injuries under side panel
-- `lane`: one more die of `kind` for the clicking player's roll there
-- while it is still gathering, else a roll of its own (another player's
-- gathering one there is thrown first). It is thrown -- all its dice at
-- once, under that side panel -- when no click has come for DICE.JOIN
-- seconds.
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

-- A fighter's card wants dice thrown (see its ACTIVATION.viaController): t
-- = { n, kind ("d6", "firepower", "injury"), color, label, from = the
-- card's GUID, token } -- or, for dice of several kinds (a weapon's
-- attack: its hit die, Firepower dice, the Ammo trait's die), `kinds`, one
-- die of each in the order thrown. They fall in the line like any roll;
-- the faces go back to the card's onDiceThrown, in the order thrown, once
-- they have settled. Returns true (taken).
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

-- The side panel a rail button sits under (its id ends in _1 / _2).
function DICE.side(id) return tonumber(tostring(id or ""):match("_(%d+)$")) end
function onRollDiceBtn(player, value, id) DICE.click("d6", player, DICE.side(id)) end
function onRollFirepowerBtn(player, value, id) DICE.click("firepower", player, DICE.side(id)) end
function onRollInjuriesBtn(player, value, id) DICE.click("injury", player, DICE.side(id)) end

-- A fighter's card: the fighter has gone Out of Action (t = { gang, name }),
-- or is back (t.back: revived). Its gang's Ld is looked at again either
-- way (one Out of Action doesn't count); going out, the gang must take a
-- Bottle Check this turn -- once, however many go.
function onFighterOut(t)
    t = type(t) == "table" and t or {}
    local gang = trim(tostring(t.gang or ""))
    local key = BOTTLE.key(gang)
    if key == "" then return end
    local due = not t.back and not BOTTLE.due[key]
    if due then BOTTLE.due[key] = "due" end
    local shown = false
    for n = 1, 2 do
        if BOTTLE.key(vpNames[n]) == key then shown = true; BOTTLE.draw(n) end
    end
    if not due then return end
    printToAll(string.format("[%s] %s is Out of Action: %s must take a Bottle Check this round.%s", gang,
        tostring(t.name or "A fighter"), gang,
        shown and "" or " Put one of its models on the table in front of a side panel of the Mundane Controller."), { 1, 0.55, 0.2 })
end

-- "Bottle Check" over a side's diamonds, left click: the reminder that its
-- gang must take the check switched by hand -- on, or off when it was lit
-- by mistake (then a fighter going Out of Action later this turn lights it
-- again). Said in chat. A side without a gang yet asks for one, as the die
-- does.
function onBottleHead(player, value, id)
    local n = tonumber(tostring(id or ""):match("_(%d)$"))
    if not n or tostring(value) == "-2" or tostring(value) == "-3" then return end
    if not BOTTLE.named(n) then
        broadcastToAll(string.format("%sBottle Check: no gang on the %s yet -- put one of your gang's models on your " ..
            "side panel of the Mundane Controller.", CHAT_PREFIX, n == 1 and "left" or "right"), { 1, 0.55, 0.2 })
        return
    end
    local key = BOTTLE.key(vpNames[n])
    local on = BOTTLE.due[key] ~= "due"
    BOTTLE.due[key] = on and "due" or nil
    for m = 1, 2 do
        if BOTTLE.key(vpNames[m]) == key then BOTTLE.draw(m) end
    end
    printToAll(string.format("%sBottle Check for %s %s (set by hand)", CHAT_PREFIX, vpNames[n],
        on and "to take this round" or "no longer to take"), { 1, 0.55, 0.2 })
    return on
end

-- The Ld diamond: left click one more, right click one fewer (by hand).
function onBottleValue(player, value, id)
    local n = tonumber(tostring(id or ""):match("_(%d)$"))
    if not n then return end
    local v = BOTTLE.value(n) or 7
    BOTTLE.hand[n] = math.max(2, math.min(12, v + (tostring(value) == "-2" and -1 or 1)))
    BOTTLE.draw(n)
end

-- The die: the Bottle Check rolled, 2D6 at or under the Ld shown -- a
-- fail means one model of the gang must leave the battlefield, two on a
-- natural 12. Taken once the dice have settled; said in chat. A side still
-- without a name of its own ("Player <n>") only asks, on everyone's
-- screen, for one of the gang's models on its plate; a named one with no
-- Ld to go by (none of its fighters on the table, none set by hand) still
-- rolls, the total said without a verdict.
function onBottleRoll(player, value, id)
    local n = tonumber(tostring(id or ""):match("_(%d)$"))
    if not n then return end
    if not BOTTLE.named(n) then
        broadcastToAll(string.format("%sBottle Check: no gang on the %s yet -- put one of your gang's models on your " ..
            "side panel of the Mundane Controller.", CHAT_PREFIX, n == 1 and "left" or "right"), { 1, 0.55, 0.2 })
        return
    end
    local gang = vpNames[n]
    local target, who = BOTTLE.hand[n], "set by hand"
    if not target then
        local _
        target, _, who = BOTTLE.target(gang)
    end
    local key = BOTTLE.key(gang)
    if BOTTLE.due[key] == "due" then BOTTLE.due[key] = "done" end
    BOTTLE.draw(n)
    local color = player and player.color or nil
    BOTTLE.throw(n, color, function(faces, digital)
        local total = faces[1] + faces[2]
        local verdict
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
        -- MI4b-8 bottle-check bus publish. Gang-level 2D6 lte against the
        -- gang's Ld (set by hand on BOTTLE.hand[n] or derived from the
        -- highest-Ld fighter still on the table via BOTTLE.target). Published
        -- from the Controller because the Bottle Check is a gang-level event,
        -- not a per-fighter one -- the Controller holds the gang's Ld state
        -- and names both sides. Natural 12 is the Necromunda "worst-case"
        -- edge: two models leave rather than one.
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

-- Calls `fn` on every fighter's card on the table (every model an import
-- tagged) that has it. Cards older than the Mundane Importer's are brought
-- up to date by it first (its upgradeCards) and left out -- they can take
-- the call once they have reloaded; with no importer on the table every
-- card that has `fn` takes it as it is. Returns how many took it, and how
-- many were brought up to date.
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

-- The column redrawn in place for `turn` (the round): the setup's buttons
-- before round 1, the round from then on, with the reinforcements reminder
-- (font sizes as SHAPE.font makes them).
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

-- A click on End Round (or on the setup's Start Game): the counter on one
-- (Start Game -> round 1) and every fighter readied -- at Start Game every
-- weapon's Reliable trait ready again too (the card's resetReliable). A
-- right click -- there or on the round's number (turnBack, which takes
-- nothing else) -- only steps the counter back, for a round advanced by
-- mistake -- below round 1 to the setup.
function onAdvanceTurn(player, value, id)
    if tostring(id) == "turnBack" and tostring(value) ~= "-2" then return end
    if tostring(value) == "-2" then
        local was = turn
        if turn > 0 then BOTTLE.newTurn() end
        turn = math.max(0, turn - 1)
        drawTurn()
        if was == 1 then DEPLOY.again() end               -- back to the setup: the deployment's model too
        if turn ~= was then SETUP.busRound(was, player and player.color or nil) end   -- NQS fork: see SETUP.busRound
        return
    end
    turn = turn + 1
    drawTurn()
    BOTTLE.newTurn()
    local n, up = everyFighter("setReady", true)
    if turn == 1 then                                     -- Start Game: every Reliable ready, the deployment's model gone
        everyFighter("resetReliable")
        DEPLOY.remove()
    end
    printToAll(string.format("%sRound %d: %d fighter(s) readied%s.", CHAT_PREFIX, turn, n, updatedNote(up)),
        { 0.3, 1, 0.4 })
    -- NQS fork: the round boundary on the game-recorder bus (agreed on
    -- game-recorder !16, decision 3). The recorder takes `field ==
    -- "ready_all"` as its primary round signal, so an N26 table marks its
    -- rounds itself instead of falling back to Mark round. Forward only:
    -- the right-click step back above returns before this, and is a
    -- correction, not a round. Emitted after every card is readied, so the
    -- cards' own actions_left events land first. Start Game (round 0 -> 1)
    -- also says the game has started, first (game-recorder !19).
    if turn == 1 then SETUP.busStart(player and player.color or nil) end
    __nqs_mundane_bus.emit({
        kind = "state_change", action = "ready_all", field = "ready_all",
        round = turn, n = n,
        player = player and player.color or nil,
    })
end

-- A click on a setup row (setupBtn_<k>, see SETUP) -- Map Size: either
-- mouse button, the next size; Roll for Deployment: a right click takes
-- its model away, or puts it back; otherwise a left click: a roll's D6
-- thrown in the dice line ("Rolling..." on the row until it lands), its
-- result said on everyone's screen and shown on the row; Determine
-- Attacker | Defender: the roll-off (SETUP.rollOff). The rest do nothing
-- yet.
function onSetup(player, value, id)
    local k = tonumber(tostring(id or ""):match("^setupBtn_(%d+)$"))
    local row = k and SETUP.ROWS[k]
    if row and row.deploy and tostring(value) == "-2" then
        if not DEPLOY.remove() then DEPLOY.again() end
        return
    end
    if row and row.map then                                             -- either mouse button
        SETUP.nextMap(k)
        return SETUP.busMap(player and player.color or nil)               -- NQS fork: see SETUP.busMap
    end
    if not row or tostring(value) ~= "-1" or SETUP.rolling[k] then return end
    if row.rollOff then return SETUP.rollOff(k, player and player.color or nil) end
    if not row.results then return end
    SETUP.rolling[k] = true
    SETUP.draw(k)
    DICE.request({ kinds = { "d6" }, color = player and player.color or nil, done = function(faces, digital)
        local was = SETUP.rolled[row.key]                               -- NQS fork: for the recorder (below)
        SETUP.rolling[k] = nil
        SETUP.rolled[row.key] = faces[1]
        SETUP.draw(k)
        DICE.announce(string.format("%s%s: %s%s", CHAT_PREFIX, row.say, row.results[faces[1]],
            digital and " (rolled digitally)" or ""), SETUP.SAY)
        if row.deploy then DEPLOY.spawn(faces[1], row.results[faces[1]]) end
        if was ~= faces[1] then SETUP.busRow(k, player and player.color or nil) end   -- NQS fork: see SETUP.busRow
    end })
end

-- The map size on to the next of DEPLOY.SIZES (row `k` redrawn); a
-- deployment model on the table is swapped for that size's.
function SETUP.nextMap(k)
    local i = 1
    for n, size in ipairs(DEPLOY.SIZES) do if size == SETUP.map then i = n end end
    SETUP.map = DEPLOY.SIZES[i % #DEPLOY.SIZES + 1]
    SETUP.draw(k)
    if #DEPLOY.find() > 0 then DEPLOY.again() end
end

-- A click on one of the deployment's small buttons (any mouse button):
-- the models turned DEPLOY.TURN degrees about the middle of the table, or
-- stretched up / down by DEPLOY.STEP of their height -- remembered for the
-- next one.
function onDeployTool(player, value, id)
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

-- A left click on a side panel's Attacker / Defender: swapped.
function onSwapRoles(player, value, id)
    if tostring(value) == "-1" then
        SETUP.swap()
        SETUP.busAttacker(player and player.color or nil)               -- NQS fork: see SETUP.busAttacker
    end
end

-- ── NQS fork: the setup, the round and the points on the recorder's bus ──
-- Agreed on game-recorder !19 (2026-10-26), its SPEC's "The Mundane
-- Controller drives the record": this panel holds the game's setup, its
-- round and both sides' points, so it publishes them, flat, through the
-- __nqs_mundane_bus copy above. Each helper emits one event for the state
-- the Controller holds NOW; the handlers call one only after a real change,
-- with the clicking colour as `player` (nil for a scripted change), and
-- publishState() calls every one of them with `replay = true`. One producer
-- per shape, so a live change and a catch-up cannot drift apart. They are
-- fields of SETUP rather than locals: no new chunk-level local.

-- A rolled setup row (Deployment, Objective, Crews): its result as said
-- ("Ambush") and the D6 it came up. Nothing for a row not rolled.
function SETUP.busRow(k, color, replay)
    local row = SETUP.ROWS[k]
    local face = row and row.results and SETUP.rolled[row.key]
    if not face then return end
    __nqs_mundane_bus.emit({ kind = "setup", field = row.key, to = row.results[face], face = face,
        player = color, replay = replay })
end

-- The map size, in inches a side.
function SETUP.busMap(color, replay)
    __nqs_mundane_bus.emit({ kind = "setup", field = "map", to = SETUP.map, player = color, replay = replay })
end

-- The side that attacks (1 left, 2 right), as the side panels show it, and
-- its gang. The roll-off decides who CHOOSES, not who attacks, and changes
-- no side's part; so after a roll-off this is the Attacker as it stands,
-- and a swap that follows the winner's choice publishes the correction.
function SETUP.busAttacker(color, replay)
    __nqs_mundane_bus.emit({ kind = "setup", field = "attacker", to = SETUP.attacker,
        gang = SETUP.side(SETUP.attacker), player = color, replay = replay })
end

-- Side `n`'s gang name.
function SETUP.busGang(n, color, replay)
    __nqs_mundane_bus.emit({ kind = "setup", field = "gang", side = n, to = trim(tostring(vpNames[n] or "")),
        player = color, replay = replay })
end

-- Side `n`'s victory points, from `was` (nil in a replay: no change is told).
function SETUP.busVp(n, was, color, replay)
    __nqs_mundane_bus.emit({ kind = "state_change", field = "vp", side = n, from = was, to = vp[n],
        player = color, replay = replay })
end

-- Start Game: round 1.
function SETUP.busStart(color, replay)
    __nqs_mundane_bus.emit({ kind = "setup", field = "start", round = 1, player = color, replay = replay })
end

-- The round stepped back (a right click), from `was` to the round now.
function SETUP.busRound(was, color)
    __nqs_mundane_bus.emit({ kind = "state_change", field = "round", from = was, to = turn, player = color })
end

-- The recorder's catch-up (game-recorder !19): everything above for the
-- state this panel holds now, each with `replay = true`, so a recorder
-- switched on mid-setup or mid-game gets the shapes it would have had live.
-- It changes nothing. Called as obj.call("publishState") and DEFERRED A
-- FRAME, so that call returns before the first event reaches the caller's
-- bus_publish: no script-to-script re-entry. In a stable order: the rolled
-- rows in the panel's order, then the map, the Attacker (once decided: the
-- roll-off made, or the parts swapped from the default), the named sides'
-- gangs, both sides' points, and the round -- `start` and then a
-- `ready_all` carrying round = turn, without the `n` of a readying that did
-- not happen, once the game has started. At round 0 the round says nothing.
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

-- The Reset Fighters button as it stands: plain, red while it asks for the
-- second click.
function RESET.draw()
    SHAPE.paint("resetFighters", RESET.asking and RESET.ASKING or "plain", RESET.asking and RESET.ASK or RESET.LABEL)
end

-- A left click on Reset Fighters: the first asks for a second (for
-- RESET.WAIT seconds), the second puts every fighter back as imported (the
-- card's resetFighter; older cards brought up to date first, as for every
-- call to all fighters).
function onResetFighters(player, value, id)
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

-- Every condition taken off every fighter (the card's clearConditions) --
-- for a script to call: no button on the panel does.
function onClearConditions(player, value, id)
    local n, up = everyFighter("clearConditions")
    printToAll(string.format("%sConditions cleared on %d fighter(s)%s.", CHAT_PREFIX, n, updatedNote(up)),
        { 1, 0.7, 0.2 })
end

-- ── The table's own rules ─────────────────────────────────────
-- The overrides come from two places (see RULES): RULES.custom, what a
-- script gave setRules ({} = none), and the homebrew sets that are on
-- (HOMEBREW). RULES.active is them all laid over each other, in that order:
-- the overrides in force (nothing: the rules as written). The cards ask for
-- it (getRules) when they load and when told to (their loadRules); this
-- Controller reads its own dice through it too.
RULES.custom, RULES.active = {}, {}

-- The overrides `b` makes laid over the overrides `a`, as one override
-- table (a fresh one) that does what the two do one after the other --
-- which is not `b` merged over the defaults: a keyed table (a status's
-- actions, a stat's limits) in both has its fields laid over each other, a
-- list of entries (actions, skills ...) gets the later entries after the
-- earlier ones, and a list or a value of `b` replaces `a`'s.
function RULES.stack(a, b)
    local out = RULES.copy(type(a) == "table" and a or {})
    if type(b) ~= "table" then return out end
    for part, kind in pairs(RULES.PARTS) do
        local o, t = b[part], out[part]
        if type(o) ~= "table" then
            -- nothing of `b`'s here
        elseif type(t) ~= "table" or kind == "list" then
            out[part] = RULES.copy(o)
        elseif kind == "map" or kind == "values" then
            local d = RULES.DEFAULT[part]
            for k, v in pairs(o) do
                local was = t[k]
                if type(v) == "table" and type(was) == "table" and not RULES.isList(v) and not RULES.isList(was) then
                    for f, x in pairs(v) do t[k][f] = RULES.copy(x) end   -- a false stays: it still takes the field out
                else
                    t[k] = RULES.copy(v)
                    -- `b` starts the key afresh (`a` took it out, or set a
                    -- list): the defaults' other fields must not show through
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

-- The overrides in force now: the custom ones, then each homebrew set that
-- is on, in the order of SETS.
function HOMEBREW.overrides()
    local out = RULES.copy(RULES.custom)
    for _, set in ipairs(HOMEBREW.SETS) do
        if HOMEBREW.on[set.id] then out = RULES.stack(out, set.rules) end
    end
    return out
end

-- Every fighter's card that can take them told to fetch the rules again
-- (its loadRules: it rebuilds only if they have changed for it). Returns
-- how many were told.
function RULES.push()
    local n = 0
    for _, obj in ipairs(getAllObjects()) do
        if IMPORT_TAG ~= "" and obj.hasTag(IMPORT_TAG) and callIfHas(obj, "loadRules") then n = n + 1 end
    end
    return n
end

-- The overrides in force worked out again (RULES.custom and the sets that
-- are on): when they differ from those in force, this Controller's dice
-- follow them and every card is told. Returns whether they changed, and how
-- many cards were told.
function RULES.refresh()
    local now = HOMEBREW.overrides()
    if RULES.same(now, RULES.active) then return false, 0 end
    RULES.active = now
    RULES.use(now)
    return true, RULES.push()
end

-- The overrides in force, for a fighter's card (its loadRules): a copy.
function getRules()
    return RULES.copy(RULES.active)
end

-- Puts the table's own rules in force: `t` the overrides (see RULES; nil
-- or {} = none), which count along with the homebrew sets that are on.
-- When they change the rules in force they are kept (saved with the
-- Controller), this Controller's dice follow and every card is told,
-- which is said in chat. Returns whether the rules in force changed.
function setRules(t)
    RULES.custom = RULES.copy(type(t) == "table" and t or {})
    local changed, n = RULES.refresh()
    if changed then
        printToAll(string.format("%sRules changed: %s -- %d fighter(s) told.", CHAT_PREFIX,
            next(RULES.active) and "the table's own" or "the rules as written", n), { 1, 0.7, 0.2 })
    end
    return changed
end

-- ── Homebrew ─────────────────────────────────────────────────────
-- The sets (HOMEBREW.SETS) that are on are rules of the table: laid over
-- the rules as written (RULES.stack) and handed to the cards like any
-- override (RULES.refresh). They are chosen on the Settings page --
-- every choice there only marks the page (HOMEBREW.pick) until "Apply
-- Settings" puts them all in force at once.

-- A set's place in SETS, and the set, by its id (nil: no such set).
function HOMEBREW.find(id)
    for i, set in ipairs(HOMEBREW.SETS) do
        if set.id == id then return i, set end
    end
end

-- The main page's button: "Settings", and how many sets (either column)
-- are on.
function HOMEBREW.button()
    local n = #HOMEBREW.list()
    return n > 0 and string.format("Settings (%d on)", n) or "Settings"
end

-- Whether the page's choices differ from the sets in force.
function HOMEBREW.changed()
    for _, set in ipairs(HOMEBREW.SETS) do
        if (HOMEBREW.pick[set.id] == true) ~= (HOMEBREW.on[set.id] == true) then return true end
    end
    return false
end

-- Apply Settings as it looks: gold while there is something to
-- apply, plain while the page's choices are those in force.
function HOMEBREW.applyLook()
    return HOMEBREW.changed() and "gold" or "plain"
end

-- Set `i`'s radio buttons redrawn, as the page has it chosen, with the
-- description of the chosen one -- and Apply.
function HOMEBREW.draw(i)
    local set = HOMEBREW.SETS[i]
    for k = 1, 2 do
        local look, label = hbLook(set, k)
        SHAPE.paint(string.format("hbOpt_%d_%d", i, k), look, label)
    end
    local desc, size = HOMEBREW.desc(i)
    setLabel("hbDesc_" .. i, desc)
    SHAPE.size("hbDesc_" .. i, size)
    SHAPE.paint("homebrewApply", HOMEBREW.applyLook())
end

-- The Settings page shown in the main page's place (`on`), its
-- choices those in force -- or the main page back, whatever the page had
-- chosen and not applied gone with it.
function HOMEBREW.show(on)
    HOMEBREW.page = on == true
    HOMEBREW.pick = {}
    for id in pairs(HOMEBREW.on) do HOMEBREW.pick[id] = true end
    for i in ipairs(HOMEBREW.SETS) do HOMEBREW.draw(i) end
    self.UI.setAttribute("playSection", "active", tostring(not HOMEBREW.page))
    self.UI.setAttribute("homebrewPage", "active", tostring(HOMEBREW.page))
    SHAPE.paint("homebrewBtn", "plain", HOMEBREW.button())
end

-- What chat says once the sets in force have changed: `what`, and how many
-- cards heard of it (none did when the rules in force stayed the same).
function HOMEBREW.say(what, changed, told)
    printToAll(string.format("%sHomebrew: %s -- %s.", CHAT_PREFIX, what,
        changed and string.format("%d fighter(s) told", told) or "no change to the rules"), { 1, 0.7, 0.2 })
end

-- Every choice the page has made put in force at once (the cards told
-- once), said in chat by the names of the choices that changed; then the
-- play section again. Returns whether any changed.
function HOMEBREW.apply()
    local what = {}
    for _, set in ipairs(HOMEBREW.SETS) do
        local want = HOMEBREW.pick[set.id] == true
        if want ~= (HOMEBREW.on[set.id] == true) then
            HOMEBREW.on[set.id] = want or nil
            what[#what + 1] = hbText(want and set.name or set.off)
        end
    end
    HOMEBREW.show(false)
    if #what == 0 then return false end
    local changed, told = RULES.refresh()
    HOMEBREW.say(table.concat(what, ", "), changed, told)
    return true
end

-- The set with id `id` switched on or off (`on` nil: the other way) at
-- once -- for a script (setHomebrew). Returns whether it changed.
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

-- The ids of the sets that are on, in the order of SETS (what is saved).
function HOMEBREW.list()
    local out = {}
    for _, set in ipairs(HOMEBREW.SETS) do
        if HOMEBREW.on[set.id] then out[#out + 1] = set.id end
    end
    return out
end

-- The main page's Settings: the page opens. Back: it closes, nothing
-- changed.
function onHomebrewOpen(player, value, id) HOMEBREW.show(true) end
function onHomebrewBack(player, value, id) HOMEBREW.show(false) end

-- A click on a radio button (hbOpt_<set>_<1 | 2>, whichever mouse
-- button): that choice for the set, on the page only.
function onHomebrewOption(player, value, id)
    local i, k = tostring(id or ""):match("^hbOpt_(%d+)_([12])$")
    i = tonumber(i)
    local set = i and HOMEBREW.SETS[i]
    if not set then return end
    HOMEBREW.pick[set.id] = k == "2" or nil
    HOMEBREW.draw(i)
end

-- Apply Settings: see HOMEBREW.apply.
function onHomebrewApply(player, value, id) HOMEBREW.apply() end

-- The Feedback button (under the column): the feedback form on a tablet
-- past the panel -- or, when it is up, taken away (see FEEDBACK.open).
function onFeedback(player, value, id)
    FEEDBACK.open(PANEL, PANEL_H)
end

-- Supported Mechanics (over "ROUND"): the instructions page on the same
-- tablet as the feedback form (see FEEDBACK.open) -- chat says so while
-- there is no page yet.
function onInfo(player, value, id)
    if FEEDBACK.INFO_URL == "" then
        return printToAll(CHAT_PREFIX .. "No instructions page yet.", { 0.8, 0.8, 0.8 })
    end
    FEEDBACK.open(PANEL, PANEL_H, "info")
end

-- Where the feedback tablet goes for this panel (in place of the shared
-- FEEDBACK.spot, which reckons from a panel lying flat): BEYOND world units
-- past the panel's top edge, over the table along the panel's up,
-- FEEDBACK.LIFT over this object's origin (the table), leaned back
-- FEEDBACK.TILT, facing the players -- its centre and rotation in the
-- world, nil outside TTS.
FEEDBACK.BEYOND = 6.5
function FEEDBACK.spot()
    local x, _, z = STAND.point(0, PANEL_H / 2)                 -- the top edge's middle
    local dx0, _, dz0 = STAND.point(0, PANEL_H / 2 - 100)       -- and back down the panel
    local ok, a, b = pcall(function()
        return self.positionToWorld({ x, 0, z }), self.positionToWorld({ dx0, 0, dz0 })
    end)
    if not (ok and a and b) then return nil end
    local ax, ay, az = a.x or a[1], a.y or a[2], a.z or a[3]
    local dx, dz = (b.x or b[1]) - ax, (b.z or b[3]) - az     -- the panel's down, over the table
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 1e-6 then dx, dz, len = 0, 1, 1 end
    dx, dz = dx / len, dz / len
    return { ax - dx * FEEDBACK.BEYOND, ay + FEEDBACK.LIFT, az - dz * FEEDBACK.BEYOND },
           { FEEDBACK.TILT, math.deg((math.atan2 or math.atan)(dx, dz)) + FEEDBACK.TURN, 0 }
end

-- The Feedback button lit (the tablet shows the form) or not, in place --
-- in this panel's own look, gold while lit like a choice made -- and
-- Supported Mechanics plain while the tablet shows the instructions, else
-- dim. `on`: as FEEDBACK.showing says, or true / false from an older
-- script (the shared FEEDBACK.draw's colours are for the importer's
-- parchment, so this one takes its place here; the other script's
-- relight, feedbackLit, comes here too).
function FEEDBACK.draw(on)
    local look = (on == true or on == "feedback") and "gold" or "plain"
    pcall(function()
        SHAPE.paint("feedback", look)
        self.UI.setAttribute("feedbackText", "color", LOOK.BUTTONS[look].ink)
        SHAPE.paint("info", on == "info" and "plain" or "dim")
    end)
end

-- The sets, for a script: a list of { id, name (the set's choice), off
-- (the rules as written), on }.
function getHomebrew()
    local out = {}
    for _, set in ipairs(HOMEBREW.SETS) do
        out[#out + 1] = { id = set.id, name = set.name, off = set.off, on = HOMEBREW.on[set.id] == true }
    end
    return out
end

-- Switches a set at once: t = { id = "pre_measure", value = true | false }
-- (no value: the other way). Returns whether it changed.
function setHomebrew(t)
    t = type(t) == "table" and t or {}
    local on = t.value
    if on ~= nil then on = on == true end
    return HOMEBREW.switch(t.id, on)
end

function onSave()
    return JSON.encode({ version = VERSION, turn = turn, vp = vp, vpNames = vpNames, bottle = BOTTLE.due, rules = RULES.custom,
        homebrew = HOMEBREW.list(), setup = { attacker = SETUP.attacker, rolled = SETUP.rolled, map = SETUP.map,
                                              deployTurn = DEPLOY.turn, deployTall = DEPLOY.tall } })
end

-- The version comes from the updater block at the end of the published
-- script (none: "?").
function onLoad(saved)
    if Updater_stateVersion then
        local _
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
    end
    RULES.active = HOMEBREW.overrides()
    RULES.use(RULES.active)
    -- the panel built on its main page, the Homebrew page's choices those in force
    HOMEBREW.page, HOMEBREW.pick = false, {}
    for id in pairs(HOMEBREW.on) do HOMEBREW.pick[id] = true end
    pcall(function() if not self.hasTag(CONTROLLER_TAG) then self.addTag(CONTROLLER_TAG) end end)
    self.UI.setXml(panelXml(), panelAssets())
    Wait.time(BOTTLE.tick, BOTTLE.POLL, -1)
    -- the cards that loaded before this did asked no one: tell them now
    -- (the table's own rules only -- as written, they already have them)
    if next(RULES.active) then Wait.frames(RULES.push, 2) end
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
local SELF_UPDATE    = true                    -- false pins this copy for good
local REPO_BASE      = "https://raw.githubusercontent.com/Antaresx101/TTS_tools/main"
local TOOL_ID        = "mundane-controller"
local TOOL_VERSION   = "3.0.0"                 -- bumped with manifest.json
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
