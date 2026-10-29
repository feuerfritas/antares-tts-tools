-- TTS-SELFUPDATE:test-tool
--
-- A life / score counter that lives on one object: -5 -1 [total] +1 +5, with
-- reset on the right-click menu. It touches nothing but itself and keeps its
-- total across a reload.
--
-- It is also the worked example for the whole repo, which is why it has a UI
-- as well as a script: tool.xml beside it gives the same counter as an
-- on-screen panel. Either one drives the total and both show it. That file is
-- authored on its own and spliced in below as TOOL_XML by validate.py, so
-- what ships - and what an update replaces - is this one file.
--
-- Everything above the spliced layout is the tool. Everything below the
-- divider is updater/updater.lua pasted in unchanged, with three config
-- values set.

local START   = 20
local total   = START
local VERSION = "?"   -- the running version, handed over by the block below

-- Both faces of the same number. The XML ids are the ones in tool.xml, and
-- setValue on an id that is not there is harmless, so a copy whose UI never
-- arrived still works as an object with buttons on it.
local function refresh()
  self.editButton({index = 0, label = tostring(total)})
  self.UI.setValue("ttTotal", tostring(total))
  self.UI.setValue("ttHeader", "test-tool v" .. VERSION)
end

local function adjust(delta)
  total = total + delta
  refresh()
end

local function reset()
  total = START
  refresh()
end

-- TTS resolves click_function by name, so each button needs a global.
function lcPlusOne()   adjust(1)  end
function lcPlusFive()  adjust(5)  end
function lcMinusOne()  adjust(-1) end
function lcMinusFive() adjust(-5) end
function lcNoop()      end        -- the total in the middle is a label

-- The panel's buttons, which arrive with the click value from the XML rather
-- than one global per button.
function ttAdjust(player, value) adjust(tonumber(value) or 0) end
function ttReset()               reset() end

local LAYOUT = {
  {fn = "lcMinusFive", label = "-5", x = -1.2},
  {fn = "lcMinusOne",  label = "-1", x = -0.6},
  {fn = "lcPlusOne",   label = "+1", x =  0.6},
  {fn = "lcPlusFive",  label = "+5", x =  1.2},
}

function onLoad(state)
  local from
  from, VERSION = Updater_stateVersion(state)   -- optional migration hook
  if from and from ~= VERSION then
    print("[test-tool] state written by v" .. from .. ", now running v" .. VERSION)
  end

  local ok, saved = pcall(JSON.decode, state or "")
  if ok and type(saved) == "table" then total = tonumber(saved.total) or START end

  -- Index 0 is the total, so refresh() can address it.
  self.createButton({
    click_function = "lcNoop", function_owner = self,
    label = tostring(total), position = {0, 0.15, 0},
    width = 0, height = 0, font_size = 400
  })
  for _, b in ipairs(LAYOUT) do
    self.createButton({
      click_function = b.fn, function_owner = self,
      label = b.label, position = {b.x, 0.15, 0},
      width = 320, height = 320, font_size = 200
    })
  end

  self.addContextMenuItem("Reset to " .. START, reset)
end

-- The panel is not addressable in the frame it loads in, so the first fill is
-- left to the update block, which calls this once the layout is live.
-- Everything in onLoad works whether or not the UI ever arrives.
function onUIReady()
  refresh()
end

function onSave()
  return JSON.encode({version = VERSION, total = total})
end

-- ===========================================================================
-- The tool's UI, spliced in from tool.xml. Edits in that file, not this copy.
-- ===========================================================================

local TOOL_XML = [[
<!-- TTS-SELFUPDATE:test-tool -->
<!--
  The XML UI half of test-tool: a tool with a UI keeps it beside tool.lua
  as tool.xml, and its manifest carries "xml": true.
  Without that flag no client ever asks for this file, so the
  script would update on its own and the UI would stay on the old version.

  The signature comment on the first line is what a client checks a downloaded
  UI against, the same way TOOL_SIGNATURE is checked in the script. It is
  stamped in by scripts/validate.py - -fix; nothing else is touched.

  Everything with an id is filled in from tool.lua at load.-->
<Panel position="0 0 -80" width="460" height="210" color="#101418E6"
       outlineSize="2 2" outline="#000000FF">
  <VerticalLayout padding="16 16 12 16" spacing="10">

    <Text id="ttHeader" fontSize="24" color="#8FB8FF"
          alignment="MiddleCenter">test-tool</Text>

    <Text id="ttTotal" fontSize="64" color="#FFFFFF"
          alignment="MiddleCenter">20</Text>

    <HorizontalLayout spacing="8" preferredHeight="60">
      <Button id="ttMinusFive" fontSize="30" onClick="ttAdjust(-5)">-5</Button>
      <Button id="ttMinusOne"  fontSize="30" onClick="ttAdjust(-1)">-1</Button>
      <Button id="ttPlusOne"   fontSize="30" onClick="ttAdjust(1)">+1</Button>
      <Button id="ttPlusFive"  fontSize="30" onClick="ttAdjust(5)">+5</Button>
      <Button id="ttReset"     fontSize="24" onClick="ttReset">Reset</Button>
    </HorizontalLayout>

  </VerticalLayout>
</Panel>
]]

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
local REPO_BASE      = "https://raw.githubusercontent.com/feuerfritas/antares-tts-tools/main"
local TOOL_ID        = "test-tool"
local TOOL_VERSION   = "1.4.0"                 -- bumped with manifest.json
local TOOL_SIGNATURE = "TTS-SELFUPDATE:test-tool"

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
