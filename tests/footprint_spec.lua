-- Offline checks for S3 (base footprints): the pure functions of the card's
-- MODEL block are loaded straight out of tools/mundane-importer/tool.lua.
--   lua tests/footprint_spec.lua            (from the repo root)
local PATH = "tools/mundane-importer/tool.lua"
local f = assert(io.open(PATH, "rb")); local src = f:read("a"); f:close()

-- both copies of the MODEL block (importer, card) must stay identical
local blocks = {}
for b in src:gmatch("%-%-@@MODEL_BEGIN.-%-%-@@MODEL_END") do blocks[#blocks + 1] = b end
assert(#blocks == 2, "expected two MODEL blocks, found " .. #blocks)
assert(blocks[1] == blocks[2], "the two MODEL blocks differ")

local MODEL = assert(load(blocks[1] .. "\nreturn MODEL", "MODEL"))()

local fails, n = 0, 0
local function check(cond, what)
    n = n + 1
    if not cond then fails = fails + 1; print("FAIL: " .. what) end
end
local function near(a, b, tol, what)
    check(a ~= nil and b ~= nil and math.abs(a - b) <= tol, string.format("%s (%s vs %s)", what, tostring(a), tostring(b)))
end
local MM = MODEL.MM_PER_INCH

-- ── the Base: line ───────────────────────────────────────────
local function line(s) local w, l, len = MODEL.baseLine(s); return w, len, l end
local cases = {
    { "Base: 32mm", 32, nil }, { "Base: 32", 32, nil }, { "base:40 MM", 40, nil },
    { "[b]Base: 28.5mm[/b]", 28.5, nil }, { "x\nBase: 50mm\ny", 50, nil },
    { "Base: 90x52mm", 52, 90 }, { "Base: 90x52mm oval", 52, 90 }, { "Base: 90 x 52", 52, 90 },
    { "Base: 52x90mm", 52, 90 }, { "Base: 90\195\15152mm", 52, 90 }, { "Base: 90X52 Oval", 52, 90 },
    { "Base: 50x50mm", 50, nil },
}
for _, c in ipairs(cases) do
    local w, len = line(c[1])
    check(w == c[2] and len == c[3], string.format("baseLine %q -> %s,%s", c[1], tostring(w), tostring(len)))
end
for _, bad in ipairs({ "Base:", "Base: abc", "Base: 90x", "Base: 0", "Ba se: 32", "Base: 32mm round extra", "" }) do
    check(MODEL.baseLine(bad) == nil, "baseLine rejects " .. bad)
end
local _, kept = MODEL.baseLine("a\nBase: 90x52mm oval\nb")
check(kept == "Base: 90x52mm oval", "baseLine returns the line as written")

-- ── the record ───────────────────────────────────────────────
local r = MODEL.baseRecord(32, "description")
check(r.shape == "round" and r.axis == "z", "round record")
near(r.diameter, 32 / MM, 1e-9, "round diameter"); near(r.length, r.width, 1e-9, "round length==width")
r = MODEL.baseRecord(52, "description", nil, nil, nil, 90, "x")
check(r.shape == "oval" and r.axis == "x", "oval record")
near(r.diameter, 52 / MM, 1e-9, "oval diameter is the width"); near(r.mm, 52, 1e-9, "oval mm is the width")
near(r.length, 90 / MM, 1e-9, "oval length")
check(MODEL.baseLabel(r) == "90x52mm oval" and MODEL.baseLabel(MODEL.baseRecord(32)) == "32mm", "baseLabel")

-- ── snapping ─────────────────────────────────────────────────
local L, W, guess = MODEL.snapOval(91.2, 50.9)
check(L == 90 and W == 52 and guess == false, "snapOval 91.2x50.9 -> 90x52")
L, W, guess = MODEL.snapOval(100, 60)
check(guess == true, "snapOval 100x60 is a guess")

-- ── local sizes from a world-aligned rectangle ───────────────
-- an ellipse 90x52 mm turned by `yaw`: the world rectangle it fills
local function worldRect(lx, lz, yaw)
    local c, s = math.cos(math.rad(yaw)), math.sin(math.rad(yaw))
    return 2 * math.sqrt((lx / 2) ^ 2 * c * c + (lz / 2) ^ 2 * s * s),
           2 * math.sqrt((lx / 2) ^ 2 * s * s + (lz / 2) ^ 2 * c * c)
end
for _, yaw in ipairs({ 0, 90, 180, 270, 30, 60, 120, -20, 75 }) do
    for _, dims in ipairs({ { 90, 52 }, { 52, 90 } }) do
        local X, Z = worldRect(dims[1], dims[2], yaw)
        local x, z = MODEL.localSizes(X, Z, yaw)
        near(x, dims[1], 1e-6, "localSizes x at yaw " .. yaw); near(z, dims[2], 1e-6, "localSizes z at yaw " .. yaw)
    end
end
do local x, z = MODEL.localSizes(60, 60, 33); near(x, 60, 1e-9, "round stays round"); near(z, 60, 1e-9, "round z") end
do local x, z = MODEL.localSizes(70, 60, 45); near(x, 60, 1e-9, "near 45 degrees falls back to the smaller side"); near(z, 60, 1e-9, "45 z") end

-- ── measuring through a fake object ─────────────────────────
local function fakeObj(xmm, zmm, yaw, how)
    local X, Z = worldRect(xmm / MM, zmm / MM, yaw or 0)
    local bounds = { size = { x = X, y = 1, z = Z } }
    local o = { getRotation = function() return { x = 0, y = yaw or 0, z = 0 } end,
                getGUID = function() return "g" .. tostring(os.clock()) .. math.random() end }
    if how == "renderer" then o.getComponent = function() return { get = function() return bounds end } end
    else o.getComponent = function() error("none") end end
    o.getComponents = function() return {} end
    o.getBoundsNormalized = function() return { size = { x = xmm / MM, y = 1, z = zmm / MM } } end
    o.getBounds = function() return bounds end
    return o
end
local function measure(...) return MODEL.measureBase(fakeObj(...)) end
r = measure(90, 52, 0, "renderer")
check(r.shape == "oval" and r.axis == "x" and not r.guess, "Orrom-like 90x52 along x")
near(r.mm, 52, 1e-9, "width 52"); near(r.length * MM, 90, 1e-9, "length 90")
r = measure(52, 90, 0, "renderer"); check(r.shape == "oval" and r.axis == "z" and r.mm == 52, "90x52 along z")
r = measure(90, 52, 90, "renderer"); check(r.shape == "oval" and r.axis == "x", "turned 90 degrees, still local x")
r = measure(90.8, 51.1, 37, "renderer"); check(r.shape == "oval" and r.axis == "x" and r.mm == 52 and not r.guess, "turned 37 degrees")
r = measure(25, 25, 0, "renderer"); check(r.shape == "round" and r.mm == 25 and not r.guess, "25 mm round")
r = measure(32.9, 31.4, 13, "renderer"); check(r.shape == "round" and r.mm == 32 and not r.guess, "round within snap")
r = measure(100, 60, 0, "renderer"); check(r.shape == "oval" and r.guess == true and r.how == "renderer", "unknown oval is a flagged guess")
r = measure(100, 60, 0, "bounds"); check(r.shape == "round" and r.mm == 60, "unknown oval from bounds: round, as before")
r = measure(90, 52, 0, "bounds"); check(r.shape == "oval" and r.mm == 52, "known oval from bounds")
check(MODEL.measureBase({ getRotation = function() return {y=0} end }) == nil, "nothing measurable -> nil")
-- round bases measure exactly as they did: min side snapped
for _, mmv in ipairs({ 25, 28.5, 32, 40, 50, 60 }) do
    r = measure(mmv + 0.7, mmv - 0.6, 0, "renderer"); check(r.shape == "round" and r.mm == mmv, "round " .. mmv)
end

-- ── the base from a description line ────────────────────────
r = MODEL.baseFromLine(fakeObj(90, 52, 0, "renderer"), "Base: 90x52mm")
check(r.shape == "oval" and r.axis == "x" and r.source == "description", "line + measured axis x")
r = MODEL.baseFromLine(fakeObj(52, 90, 0, "renderer"), "Base: 90x52mm")
check(r.axis == "z", "line + measured axis z")
r = MODEL.baseFromLine(fakeObj(60, 60, 0, "renderer"), "Base: 90x52mm oval")
check(r.axis == "z", "no longer side: local z")
r = MODEL.baseFromLine({}, "Base: 90x52mm")
check(r.axis == "z", "unmeasurable: local z")
r = MODEL.baseFromLine({}, "Base: 32mm"); check(r.shape == "round" and r.mm == 32, "round line")
check(MODEL.baseFromLine({}, "nothing") == nil, "no line")

-- ── baseGap: round against round is exactly what it was ────
local gapSrc = assert(src:match("(local function baseGap%(a, b%).-\nend)\n"), "baseGap not found")
local baseGap = assert(load("local MODEL = ...\n" .. gapSrc .. "\nreturn baseGap", "baseGap"))(MODEL)
math.randomseed(20261102)
for i = 1, 5000 do
    local a = { x = math.random() * 60 - 30, z = math.random() * 60 - 30, r = (25 + math.random() * 35) / MM / 2 }
    local b = { x = math.random() * 60 - 30, z = math.random() * 60 - 30, r = (25 + math.random() * 35) / MM / 2 }
    local old = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) - a.r - b.r
    if math.abs(baseGap(a, b) - old) > 1e-9 then check(false, "round-vs-round baseGap changed") break end
    if i == 5000 then check(true, "round-vs-round") end
end
-- close ones, overlapping included (the engagement range)
for i = 1, 2000 do
    local r1, r2 = (25 + math.random() * 35) / MM / 2, (25 + math.random() * 35) / MM / 2
    local d = r1 + r2 + (math.random() * 3 - 1)
    local a, b = { x = 0, z = 0, r = r1 }, { x = d, z = 0, r = r2 }
    near(baseGap(a, b), d - r1 - r2, 0.001, "close round gap")
end

-- ── ovals ──────────────────────────────────────────────────
local OVAL = MODEL.baseRecord(52, "description", nil, nil, nil, 90, "x")
local A, B = 90 / MM / 2, 52 / MM / 2
local function ent(x, z, base, yaw)
    local e = { x = x, z = z, r = base.diameter / 2 }
    e.fp = MODEL.footprintOf(base, yaw)
    return e
end
local R25 = MODEL.baseRecord(25, "description")
local r25 = 25 / MM / 2
for _, d in ipairs({ 0.5, 1.5, 3, 5 }) do
    local o = ent(0, 0, OVAL, 0)   -- local x along world: yaw 0 -> (cos, -sin) = (1, 0)
    -- end-on: round base along the length axis
    near(baseGap(o, ent(d + A + r25, 0, R25, 0)), d, 0.001, "end-on gap " .. d)
    near(baseGap(ent(d + A + r25, 0, R25, 0), o), d, 0.001, "end-on gap, swapped " .. d)
    -- side-on: round base across the width
    near(baseGap(o, ent(0, d + B + r25, R25, 0)), d, 0.001, "side-on gap " .. d)
    -- turned a quarter: the length now runs along world z
    local t = ent(0, 0, OVAL, 90)
    near(baseGap(t, ent(0, d + A + r25, R25, 0)), d, 0.001, "turned, end-on " .. d)
    near(baseGap(t, ent(d + B + r25, 0, R25, 0)), d, 0.001, "turned, side-on " .. d)
end
-- the same centre distance reads a larger gap side-on than end-on
do
    local o, dist = ent(0, 0, OVAL, 0), 3
    check(baseGap(o, ent(dist, 0, R25, 0)) < baseGap(o, ent(0, dist, R25, 0)), "side-on gap is larger at the same distance")
end
-- touching reads 0; overlapping reads negative by the depth on the line of centres
near(baseGap(ent(0, 0, OVAL, 0), ent(A + r25, 0, R25, 0)), 0, 0.001, "touching reads 0")
near(baseGap(ent(0, 0, OVAL, 0), ent(A + r25 - 0.3, 0, R25, 0)), -0.3, 0.001, "overlap reads -depth")
check(baseGap(ent(0, 0, OVAL, 0), ent(0, 0, R25, 0)) < 0, "same centre overlaps")
-- oval against oval: end to end, and crossed
near(baseGap(ent(0, 0, OVAL, 0), ent(2 * A + 1, 0, OVAL, 0)), 1, 0.001, "oval end to end")
near(baseGap(ent(0, 0, OVAL, 0), ent(0, 2 * B + 1, OVAL, 0)), 1, 0.001, "oval side by side")
check(baseGap(ent(0, 0, OVAL, 0), ent(0, 0, OVAL, 90)) < 0, "crossed ovals overlap")
check(baseGap(ent(0, 0, OVAL, 0), ent(0.3, 0.3, OVAL, 90)) < 0, "crossed ovals, offset, overlap")
-- the polygon is within 0.01" of the true ellipse: round base against an oval at 35 degrees
for _, ang in ipairs({ 20, 35, 50, 70 }) do
    local d = 4
    local cx, cz = d * math.cos(math.rad(ang)), d * math.sin(math.rad(ang))
    local best = math.huge                       -- nearest point of the true ellipse to the round base's centre
    for k = 0, 7199 do
        local t = k * math.pi / 3600
        local px, pz = A * math.cos(t), B * math.sin(t)
        best = math.min(best, math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2))
    end
    near(baseGap(ent(0, 0, OVAL, 0), ent(cx, cz, R25, 0)), best - r25, 0.011, "polygon vs true ellipse at " .. ang)
end
-- footprintOf: a round base has none; the axis follows the model's turn
check(MODEL.footprintOf(R25, 40) == nil, "round has no fp")
do
    local fp = MODEL.footprintOf(MODEL.baseRecord(52, "x", nil, nil, nil, 90, "z"), 90)
    near(fp.ux, 1, 1e-9, "local z at yaw 90 points along world +x"); near(fp.uz, 0, 1e-9, "uz")
    fp = MODEL.footprintOf(OVAL, 90)
    near(fp.ux, 0, 1e-9, "local x at yaw 90 points along world -z"); near(fp.uz, -1, 1e-9, "uz -1")
end

-- ── the base on the bus ───────────────────────────────────
do
    local fnSrc = assert(src:match("(function __nqs_mundane_bus%.baseChanged%(base%).-\nend)\n"), "baseChanged not found")
    local events = {}
    local env = { __nqs_mundane_bus = { card = {}, emit = function(e) events[#events + 1] = e end },
                  MODEL = MODEL, fighter = { name = "Orrom" }, string = string, tostring = tostring,
                  tonumber = tonumber, type = type }
    assert(load(fnSrc, "baseChanged", "t", env))()
    local bc = env.__nqs_mundane_bus.baseChanged
    bc(MODEL.baseRecord(50, "measured"))
    check(#events == 0, "the first base is only remembered")
    bc(MODEL.baseRecord(50, "measured")); check(#events == 0, "an unchanged base publishes nothing")
    bc(MODEL.baseRecord(52, "description", nil, nil, nil, 90, "x"))
    check(#events == 1 and events[1].field == "base" and events[1].action == "base" and events[1].kind == "state_change", "a change is a state_change")
    check(events[1].from == "50mm" and events[1].to == "90x52mm oval" and events[1].shape == "oval" and events[1].axis == "x", "from, to, shape, axis")
    bc(MODEL.baseRecord(52, "manual", nil, nil, nil, 90, "x")); check(#events == 1, "same footprint, other source: nothing")
    bc(MODEL.baseRecord(52, "manual", nil, nil, nil, 90, "z")); check(#events == 2, "a turned axis is a change")
    env.__nqs_mundane_bus.card.baseSig = nil
    bc(MODEL.baseRecord(32)); check(#events == 2, "a new fighter reseeds")
end

if fails > 0 then print(fails .. " of " .. n .. " checks FAILED"); os.exit(1) end
print("footprint_spec: " .. n .. " checks passed")
