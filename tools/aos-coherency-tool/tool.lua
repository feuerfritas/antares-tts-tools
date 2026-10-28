-- TTS-SELFUPDATE:aos-coherency-tool
--
-- ── AOS COHERENCY TOOL by Antares77 ───────────────────────────
-- A tool for checking AoS coherency and arranging units in legal formations.

-- TTS-SELFUPDATE - Update this script automatically by writing '!update' in chat.

-- The running version, handed over by the updater block below and put on the
-- UI during onLoad. Nothing sets it by hand: it is whatever TOOL_VERSION says,
-- so it stays right through every update on its own. The "?" only shows if the
-- block is not there at all.
local VERSION                = "?"

local MM_TO_INCH             = 0.0393701
local RING_CLEARANCE         = 0.10  -- world units the aura ring floats above the table
local AURA_THICK             = 0.05  -- aura ring line width
local BASE_THICK             = 0.04  -- base outline line width
-- Breach lines (models out of coherency) only read well from above at this width.
local BREACH_THICK           = 0.05  -- coherency breach line width
local MAX_UNIT               = 40    -- models per unit for coherency / shapes
local MAX_BREACH_LINES       = 24    -- breach lines drawn at once
local MOTION_TICK            = 0.1   -- s, motion loop period
local MONITOR_TIMEOUT        = 60    -- s, monitor auto-stop
local UPRIGHT_EPS            = 0.5   -- degrees of lean a shape button will ignore
-- How far a base's two semi-axes have to differ before it counts as an oval and
-- the Ovals Sideways toggle turns it. The closest catalogued oval, 35.5 x 60 mm,
-- has semi-axes 0.48" apart and a round base's are equal, so 0.05" separates the
-- two with room to spare.
local OVAL_EPS               = 0.05

-- Rounds, then ovals in both orientations.
local VALID_BASE_SIZES_IN_MM = {
    {x=25,z=25},{x=28,z=28},{x=30,z=30},{x=32,z=32},{x=40,z=40},{x=50,z=50},
    {x=55,z=55},{x=60,z=60},{x=65,z=65},{x=80,z=80},{x=90,z=90},{x=100,z=100},
    {x=130,z=130},{x=160,z=160},{x=25,z=75},{x=75,z=25},{x=35.5,z=60},
    {x=60,z=35.5},{x=40,z=95},{x=95,z=40},{x=52,z=90},{x=90,z=52},{x=70,z=105},
    {x=105,z=70},{x=92,z=120},{x=120,z=92},{x=95,z=150},{x=150,z=95},
    {x=109,z=170},{x=170,z=109},
}

-- Coherency distance modes, in UI order. Base contact = edge gap <= 0.01".
local MODES = {
    { id = "mode1", label = '0.5"',        dist = 0.5  },
    { id = "mode2", label = '2"',          dist = 2.0  },
    { id = "mode3", label = "Base contact", dist = 0.01 },
}
-- Buddy models that need to be in range for coherency
local BUDDY_IDS = { "buddyAuto", "buddy1", "buddy2" } -- 0 = auto, 1 = force 1, 2 = force 2

-- Resting is a white wash over the parchment, lit inverts it. Background and text
-- colour always move together, or a lit button ends up anthracite on anthracite.
local ANTHRACITE          = "#293133"
local ON_COLOR,  ON_TEXT  = "#293133d9", "#f2f1ec"
local OFF_COLOR, OFF_TEXT = "#ffffff40", ANTHRACITE
-- panelField's fill, which every button's wash sits over. Only used to work out
-- whether a coloured fill wants the pale label or the anthracite one.
local PARCHMENT           = {0.902, 0.898, 0.882}   -- #e6e5e1

-- The colour picker's twelve swatches, in the order colorPopup lists them in the
-- XML. A swatch's id is "auraCol" .. its index here, which is how aosPickColor
-- finds it, and the hex baked into the XML is this same colour, so the popup is
-- right on the first frame. Every aura drawn takes whichever one is picked.
local AURA_PRESETS = {
    {0.902, 0.149, 0.149}, {0.980, 0.522, 0.051}, {0.969, 0.851, 0.149},
    {0.549, 0.878, 0.200}, {0.102, 0.722, 0.278}, {0.000, 0.780, 0.749},
    {0.251, 0.651, 1.000}, {0.149, 0.298, 0.902}, {0.620, 0.251, 0.922},
    {1.000, 0.349, 0.702}, {0.549, 0.361, 0.200}, {1.000, 1.000, 1.000},
}
local AURA_DEFAULT    = 7     -- the sky blue: clear of the monitor's own colours
local AURA_BTN_ALPHA  = 0.38  -- how solid the five radius buttons wear that colour
local COLOR_BTN_ALPHA = 0.62  -- and Aura Color, which is the swatch itself

-- The XML names the picture (image="aosPanelBg") and that name resolves against the
-- object's Custom UI Assets list, filled in on load.
local UI_ASSETS = {
    { name = "aosPanelBg",
      url  = "https://steamusercontent-a.akamaihd.net/ugc/12352082712112839381/58ABA6CE8570F5CB9E72C7E53BE4BE3A2CD8C9F7/" },
} -- Must be hosted, e.g. directly on the Steam Cloud

-- ---------------------------------------------------------------- state -----
local uiMode        = 1              -- index into MODES
local buddyOverride = 0              -- 0 auto | 1 force 1 | 2 force 2
local lastCustom    = "4"
local auraIdx       = AURA_DEFAULT   -- index into AURA_PRESETS
local ovalSideways  = false          -- oval bases turned across the formation
local colorOpen     = false          -- the picker panel is up
local actingColor   = nil            -- whoever pressed the last button, for broadcasts

local monActive, monTimer, monTimeout = false, nil, nil
local monGuids, monIdx, monDesc, monBase, monDrop = {}, {}, {}, {}, {}
local monGap, monCp, monPrevMoving = {}, {}, {}
local monGlowed, monGlowState = {}, {}

local undoStack = {}

-- ======================================================= GEOMETRY CORE ======
-- No TTS API calls anywhere below until the "base + descriptors" header.
local sqrt, cos, sin, rad, deg = math.sqrt, math.cos, math.sin, math.rad, math.deg
local floor, ceil, abs, max, min = math.floor, math.ceil, math.abs, math.max, math.min
local atan2 = math.atan2 or math.atan   -- 5.2 has atan2; 5.3+ folds it into atan
local SQRT3_2 = sqrt(3) / 2             -- also cos(30 deg): the triangle cap offset
local EPS = 1e-6

-- A descriptor is { pos, a, b, right, forward }: a and b are the base's
-- semi-radii along the model's local x/z, right and forward its local axes as
-- world unit vectors. Rotation-correct for ovals, with no handedness guess.
local function makeDesc(x, z, a, b, yawDeg)
    local t = rad(yawDeg or 0)
    return {
        pos     = { x = x, y = 0, z = z },
        a       = max(a, 0.01), b = max(b, 0.01),
        right   = { x = cos(t), y = 0, z = -sin(t) },
        forward = { x = sin(t), y = 0, z =  cos(t) },
    }
end

-- Ellipse polar equation: the base's radius along world unit direction (dx,dz).
local function baseRadiusInDir(d, dx, dz)
    local lx = dx * d.right.x   + dz * d.right.z
    local lz = dx * d.forward.x + dz * d.forward.z
    return 1 / sqrt((lx * lx) / (d.a * d.a) + (lz * lz) / (d.b * d.b))
end

-- Horizontal edge-to-edge gap, plus the base-edge point on each (for drawing).
local function baseGap(d1, d2)
    local dx, dz = d2.pos.x - d1.pos.x, d2.pos.z - d1.pos.z
    local centre = sqrt(dx * dx + dz * dz)
    if centre < EPS then return 0, d1.pos, d2.pos end
    local ux, uz = dx / centre, dz / centre
    local r1 = baseRadiusInDir(d1,  ux,  uz)
    local r2 = baseRadiusInDir(d2, -ux, -uz)
    local gap = centre - r1 - r2
    if gap < 0 then gap = 0 end
    return gap,
        { x = d1.pos.x + ux * r1, z = d1.pos.z + uz * r1 },
        { x = d2.pos.x - ux * r2, z = d2.pos.z - uz * r2 }
end

-- AoS Ruling: 1 buddy, 2 once the unit is 7+. Capped at n-1, so a lone model is legal.
local function requiredBuddies(n, override)
    local req
    if override == 1 or override == 2 then req = override
    elseif n >= 7 then req = 2
    else req = 1 end
    if req > n - 1 then req = n - 1 end
    if req < 0 then req = 0 end
    return req
end

-- Read a filled gap matrix: buddy counts, pass/fail, each model's nearest
-- neighbour (for breach lines) and the connected-group count (informational --
-- a split unit is just a warning, but not a failure). Split out from evaluate() so the
-- live monitor can re-read its cached matrix without redoing the distance work.
local function summarize(gap, n, dist, req)
    local adj, buddies, near = {}, {}, {}
    for i = 1, n do adj[i], buddies[i], near[i] = {}, 0, 0 end
    local thr = dist + EPS
    for i = 1, n - 1 do
        for j = i + 1, n do
            local g = gap[i][j]
            if g ~= nil then
                if g <= thr then
                    buddies[i] = buddies[i] + 1; buddies[j] = buddies[j] + 1
                    adj[i][#adj[i] + 1] = j;     adj[j][#adj[j] + 1] = i
                end
                if near[i] == 0 or g < gap[i][near[i]] then near[i] = j end
                if near[j] == 0 or g < gap[j][near[j]] then near[j] = i end
            end
        end
    end
    local ok, fails = {}, 0
    for i = 1, n do
        ok[i] = buddies[i] >= req
        if not ok[i] then fails = fails + 1 end
    end
    local seen, groups = {}, 0                      -- flood fill for the groups
    for i = 1, n do
        if not seen[i] then
            groups, seen[i] = groups + 1, true
            local stack = { i }
            while #stack > 0 do
                local v = stack[#stack]; stack[#stack] = nil
                for _, w in ipairs(adj[v]) do
                    if not seen[w] then seen[w] = true; stack[#stack + 1] = w end
                end
            end
        end
    end
    return { n = n, req = req, gap = gap, buddies = buddies, near = near,
             ok = ok, fails = fails, groups = groups }
end

-- Full O(n^2) evaluation from scratch: measure every pair, then summarize.
local function evaluate(descs, dist, req)
    local n = #descs
    local gap, cp = {}, {}
    for i = 1, n do gap[i], cp[i] = {}, {} end
    for i = 1, n - 1 do
        for j = i + 1, n do
            local g, p1, p2 = baseGap(descs[i], descs[j])
            gap[i][j], gap[j][i] = g, g
            cp[i][j],  cp[j][i]  = p1, p2
        end
    end
    local r = summarize(gap, n, dist, req)
    r.cp = cp
    return r
end

-- Long axis of the formation: principal eigenvector of the 2D covariance of the
-- models' x/z positions. n <= 3 uses the most-separated pair; a degenerate
-- spread falls back to world +x. Buttons always hand buildLayout the tool's own
-- axis; this is what it uses when it is given none, as in the geometry tests.
local function principalAxis(descs)
    local n, X = #descs, { x = 1, z = 0 }
    if n < 2 then return X end
    if n <= 3 then
        local best, bx, bz = -1, 1, 0
        for i = 1, n - 1 do for j = i + 1, n do
            local dx = descs[j].pos.x - descs[i].pos.x
            local dz = descs[j].pos.z - descs[i].pos.z
            local d2 = dx * dx + dz * dz
            if d2 > best then best, bx, bz = d2, dx, dz end
        end end
        if best < EPS then return X end
        return { x = bx / sqrt(best), z = bz / sqrt(best) }
    end
    local mx, mz = 0, 0
    for i = 1, n do mx = mx + descs[i].pos.x; mz = mz + descs[i].pos.z end
    mx, mz = mx / n, mz / n
    local sxx, szz, sxz = 0, 0, 0
    for i = 1, n do
        local dx, dz = descs[i].pos.x - mx, descs[i].pos.z - mz
        sxx = sxx + dx * dx; szz = szz + dz * dz; sxz = sxz + dx * dz
    end
    if sxx + szz < EPS then return X end
    local tr  = sxx + szz
    local lam = tr / 2 + sqrt(max(0, tr * tr / 4 - (sxx * szz - sxz * sxz)))
    local vx, vz = sxz, lam - sxx
    if abs(vx) + abs(vz) < EPS then vx, vz = lam - szz, sxz end
    if abs(vx) + abs(vz) < EPS then return X end
    local m = sqrt(vx * vx + vz * vz)
    return { x = vx / m, z = vz / m }
end

-- The circles of radius dP about P and dQ about Q meet in two points, mirrored
-- across the P->Q line; both are returned and the caller picks a side. A solution
-- always exists: the two target distances always sum to more than |PQ|.
local function triangulate(Px, Pz, dP, Qx, Qz, dQ)
    local dx, dz = Qx - Px, Qz - Pz
    local D = sqrt(dx * dx + dz * dz)
    if D < EPS then dx, dz, D = 1, 0, EPS end
    local t  = (D * D + dP * dP - dQ * dQ) / (2 * D)
    local h2 = dP * dP - t * t
    local h  = h2 > 0 and sqrt(h2) or 0
    local ex, ez = dx / D, dz / D
    local ax, az = Px + ex * t, Pz + ez * t          -- foot on the P->Q line
    local nx, nz = -ez * h, ex * h                   -- perpendicular offset
    return ax + nx, az + nz, ax - nx, az - nz
end

local function dist2(ax, az, bx, bz)
    local dx, dz = bx - ax, bz - az
    return dx * dx + dz * dz
end

-- ---- slot generators -------------------------------------------------------
-- Each returns { {along, perp}, ... } in sorted-model order about an arbitrary
-- origin; buildLayout re-anchors on the centroid. rin(k, dx, dz) is model k's
-- semi-radius along layout-frame direction (dx,dz): an oval presents a different
-- radius to every neighbour, so spacing is asked for per direction.
--
-- Every one of them places its models PAIR BY PAIR, at an exact edge gap from
-- named neighbours, rather than on one spacing shared by the whole unit. That is
-- what lets a unit that mixes base sizes still hold the coherency distance: one
-- uniform step cannot keep the small bases coherent and the large ones apart at
-- the same time, and when those two pull against each other it is the coherency
-- that has to win.

-- Centre-to-centre distance putting i and j at edge gap g, given where they sit.
-- The direction depends on the answer, so callers iterate; the half-step damping
-- (prev) is what stops a 3:1 oval oscillating.
local function pairDist(rin, i, j, xi, zi, xj, zj, g, prev)
    local dx, dz = xj - xi, zj - zi
    local m = sqrt(dx * dx + dz * dz)
    if m < EPS then dx, dz, m = 1, 0, 1 end
    dx, dz = dx / m, dz / m
    local d = rin(i, dx, dz) + g + rin(j, -dx, -dz)
    if prev == nil then return d end
    return 0.5 * (prev + d)
end

-- Edge gap between two models already placed in the layout frame. rin answers in
-- that frame, so this needs no round trip through world coordinates.
local function slotGap(rin, slots, i, j)
    local dx, dz = slots[j][1] - slots[i][1], slots[j][2] - slots[i][2]
    local m = sqrt(dx * dx + dz * dz)
    if m < EPS then return -1 end
    return m - rin(i, dx / m, dz / m) - rin(j, -dx / m, -dz / m)
end

-- Per-pair steps: every consecutive edge gap is exactly g. Neighbours lie along
-- the axis, so no iteration is needed.
local function slotsSingleLine(n, rin, g)
    local out = { {0, 0} }
    for k = 2, n do
        out[k] = { out[k - 1][1] + rin(k - 1, 1, 0) + g + rin(k, -1, 0), 0 }
    end
    return out
end

-- Settle model k at edge gap g from two already-placed anchors, i at (Px,Pz) and
-- j at (Qx,Qz). Both target distances depend on where k ends up, so this
-- iterates: `pick` chooses between the two mirrored solutions on the first pass,
-- and every later pass stays on whichever side that first choice landed.
-- It runs until the distances stop moving. The half-step damping keeps an oval
-- from oscillating but converges slowly, and a formation has only SHAPE_MARGIN of
-- room under the coherency limit, so a pass short of settled can leave a model
-- out of range. The pass cap is only a guard; this runs on a button press.
local function settle(rin, g, i, Px, Pz, j, Qx, Qz, k, pick)
    local dP = rin(i, 1, 0) + g + rin(k, -1, 0)
    local dQ = rin(j, 1, 0) + g + rin(k, -1, 0)
    local x, z = pick(triangulate(Px, Pz, dP, Qx, Qz, dQ))
    for _ = 1, 80 do
        local nP = pairDist(rin, i, k, Px, Pz, x, z, g, dP)
        local nQ = pairDist(rin, j, k, Qx, Qz, x, z, g, dQ)
        local moved = abs(nP - dP) + abs(nQ - dQ)
        dP, dQ = nP, nQ
        local a, b, c, d = triangulate(Px, Pz, dP, Qx, Qz, dQ)
        if dist2(x, z, a, b) <= dist2(x, z, c, d) then x, z = a, b else x, z = c, d end
        if moved < 1e-10 then break end
    end
    return x, z
end

-- Of the two mirrored solutions, the one further along the perpendicular: the
-- rank being built always stands in front of the rank it is settling against.
local function pickFar(x1, z1, x2, z2)
    if z1 >= z2 then return x1, z1 end
    return x2, z2
end

-- Hex-staggered two-rank block, built as a chain of triangles: model k sits at
-- edge gap exactly g from BOTH k-1 and k-2, which is what makes it legal for any
-- n >= 3 (model 1 has 2 and 3, model 2 has 1 and 3).
local function slotsChain(n, rin, g)
    local out = { {0, 0} }
    if n >= 2 then
        -- 60 degrees off the axis. The direction does not depend on how far along
        -- it model 2 ends up, so the distance is exact in one step and is not
        -- iterated: damping it would leave part of the correction unapplied.
        local dx, dz = 0.5, SQRT3_2
        local d = rin(1, dx, dz) + g + rin(2, -dx, -dz)
        out[2] = { d * dx, d * dz }
    end
    -- Pick the solution farther from k-3, the model the chain would otherwise
    -- fold back onto. "Farther along the axis" looks equivalent but degenerates
    -- when k-2 and k-1 line up with the axis, and a fold stacks two bases.
    for k = 3, n do
        local rx, rz = -1e6, 0                            -- k=3: just go forward
        if k >= 4 then rx, rz = out[k - 3][1], out[k - 3][2] end
        out[k] = { settle(rin, g, k - 2, out[k - 2][1], out[k - 2][2],
                                 k - 1, out[k - 1][1], out[k - 1][2], k,
            function(x1, z1, x2, z2)
                if dist2(rx, rz, x1, z1) >= dist2(rx, rz, x2, z2) then return x1, z1 end
                return x2, z2
            end) }
    end
    return out
end

-- The Dogbone: a straight line of n-4 with a 2-model cap at each end. Each cap
-- model sits at edge gap g from the end model and from its partner, so it has 2
-- buddies and the apex gains 2. This is usually for maximum spread while still
-- respecting coherency.
local function slotsTriangles(n, rin, g)
    local out, prev = {}, 0
    for k = 1, n - 4 do
        if k > 1 then prev = prev + rin(k + 1, 1, 0) + g + rin(k + 2, -1, 0) end
        out[k + 2] = { prev, 0 }
    end
    local function cap(iA, i1, i2, sign)          -- sign: -1 front cap, +1 rear
        local ax, az = out[iA][1], out[iA][2]
        local dx, dz = sign * SQRT3_2, 0.5        -- 30 deg off the axis
        local d1 = rin(iA, dx, dz) + g + rin(i1, -dx, -dz)
        out[i1] = { ax + dx * d1, az + dz * d1 }
        -- The partner mirrors i1 across the axis: take the negative-perp side.
        out[i2] = { settle(rin, g, iA, ax, az, i1, out[i1][1], out[i1][2], i2,
            function(x1, z1, x2, z2)
                if z1 <= z2 then return x1, z1 end
                return x2, z2
            end) }
    end
    cap(3, 1, 2, -1)
    cap(n - 2, n - 1, n, 1)
    return out
end

-- Columns across the block, picked so the footprint comes out roughly square:
-- a row is one step wide per model and the rows are only sqrt(3)/2 of a step
-- apart, which is where the 0.866 comes from.
local function honeyCols(n)
    return max(2, floor(sqrt(0.866 * n) + 0.5))
end

-- Honeycomb, built pair by pair like the rest rather than on one lattice step.
-- Rows run left to right and alternate their offset by half a step, so the block
-- comes out square-edged, and every model is settled at exactly edge gap g from
-- the model before it in its row and from the model it nests against in the row
-- behind. Equal bases reproduce the textbook hex grid to the last decimal; mixed
-- bases give a grid that goes a little irregular and holds the coherency
-- distance, which is the way round that matters.
--
-- EVERY PAIR OF ANCHORS IS ITSELF A NEIGHBOURING PAIR, and that is the whole
-- trick. Two circles of radius (anchor + g + model) about anchors that are only
-- (anchor + g + anchor) apart always cross, so a model can always be put at the
-- exact gap from both; anchors any further apart than that -- the two ends of a
-- row, say -- have no such guarantee, and once a unit mixes a 25mm base with a
-- 75mm one they stop crossing and the model lands short of one of them.
--
-- Rows are filled to a WIDTH, not to a model count, and each model nests against
-- whichever model of the row behind actually ends up under it. Both of those are
-- for mixed bases: a row of 40mm bases holding the same COUNT as the row of 25mm
-- bases beneath it is half again as long, so it runs off the end of that row and
-- its last models have nothing left to nest against. Filling by width keeps the
-- rows stacked over each other however the sizes are mixed, and looking up the
-- neighbour by position rather than by index lets one big base span two small
-- ones. With equal bases every row comes out the same count and the lookup finds
-- the model a fixed index rule would have named, so the block is the plain
-- lattice again.
--
-- A row starts either OFFSET -- between the first two models of the row behind --
-- or FLUSH, half a step back from that row's first model, where there is only one
-- neighbour to have and the next model along gives it its second. Alternating the
-- two is what squares the block off; nesting every row would shear it.
local function slotsHoneycomb(n, rin, g)
    -- Row widths first: the full single-line length, split into the number of rows
    -- that makes the block roughly square. A row is one model-width plus a gap per
    -- model and the rows are only sqrt(3)/2 of that apart, which is the 0.866.
    local w, total = {}, (n - 1) * g
    for k = 1, n do
        w[k] = rin(k, 1, 0) + rin(k, -1, 0)
        total = total + w[k]
    end
    local rows = max(1, floor(sqrt(n / 0.866) + 0.5))
    local wide = total / rows
    local first, last, rowOf = { 1 }, {}, {}
    local r, used = 1, 0
    for k = 1, n do
        local grown = (k == first[r]) and w[k] or (used + g + w[k])
        if k > first[r] and grown > wide then
            last[r] = k - 1
            r = r + 1
            first[r], used = k, w[k]
        else
            used = grown
        end
        rowOf[k] = r
    end
    last[r] = n

    local out = { {0, 0} }
    for k = 2, n do
        local rr = rowOf[k]
        if rr == 1 then                                  -- the first row is a line
            out[k] = { out[k - 1][1] + rin(k - 1, 1, 0) + g + rin(k, -1, 0), 0 }
        else
            local b0, b1 = first[rr - 1], last[rr - 1]   -- the row behind
            -- A final row with fewer models than the one behind nests whatever its
            -- parity, and starts far enough in to sit centred: left flush, a lone
            -- trailing model hangs off the corner of the block with one buddy.
            local mine = last[rr] - first[rr]
            local nest = (rr % 2 == 0) or (mine < b1 - b0)
            if k ~= first[rr] then
                -- Where continuing this row puts k, then the model of the row
                -- behind nearest that spot. The <= keeps the earlier of two equal
                -- candidates, which is the one the lattice wants.
                local ax = out[k - 1][1] + rin(k - 1, 1, 0) + g + rin(k, -1, 0)
                local b, near = b0, abs(out[b0][1] - ax)
                for t = b0 + 1, b1 do
                    local d = abs(out[t][1] - ax)
                    if d < near then near, b = d, t end
                end
                local function put(t)
                    out[k] = { settle(rin, g, k - 1, out[k - 1][1], out[k - 1][2],
                                             t,     out[t][1],     out[t][2],
                                             k, pickFar) }
                end
                -- The model that ENDS a row takes the model that ENDS the row
                -- behind, wherever the two still settle cleanly. It is the only
                -- pairing that gives that one a second buddy of its own, and in the
                -- first row -- where a model has nothing but its two neighbours in
                -- the line -- there is no other way for the far corner to get one.
                -- Whether they settle depends on how far apart they are, so it is
                -- tried and then measured rather than reasoned about.
                if k == last[rr] and b ~= b1 then
                    put(b1)
                    if abs(slotGap(rin, out, k, k - 1) - g) < 1e-6
                       and abs(slotGap(rin, out, k, b1) - g) < 1e-6 then b = nil end
                end
                if b ~= nil then put(b) end
            elseif nest and b1 > b0 then
                local c = floor(((b1 - b0) - mine) / 2)
                if c < 0 then c = 0 elseif b0 + c + 1 > b1 then c = b1 - b0 - 1 end
                local p, q = b0 + c, b0 + c + 1
                out[k] = { settle(rin, g, p, out[p][1], out[p][2],
                                         q, out[q][1], out[q][2], k, pickFar) }
            else
                local dx, dz = -0.5, SQRT3_2             -- half a step back, one row up
                local d = rin(b0, dx, dz) + g + rin(k, -dx, -dz)
                out[k] = { out[b0][1] + dx * d, out[b0][2] + dz * d }
            end
        end
    end
    return out
end

-- The last-resort honeycomb: one lattice step for every pair, and the only layout
-- here that is not built per pair, used when every per-pair attempt still puts
-- two bases on top of each other. The step is wide enough that the widest pair
-- cannot touch and, where the bases allow it, narrow enough that the narrowest
-- pair stays coherent; when both cannot be had it takes the tightest step the
-- widest base allows, and buildLayout notes that the distance was given up.
local function slotsHoneyGrid(n, rmaxK, rminK, g)
    local rmin, rmax = rminK[1], rmaxK[1]
    for k = 2, n do
        if rminK[k] < rmin then rmin = rminK[k] end
        if rmaxK[k] > rmax then rmax = rmaxK[k] end
    end
    local s = max(2 * rmax + 0.01, 2 * rmin + g)
    local cols = honeyCols(n)
    local rows = ceil(n / cols)
    -- A short final row is centred on whole columns so its models keep landing in
    -- the previous row's valleys -- without that, a lone trailing model (n=13)
    -- would have only 1 buddy.
    local c0   = floor((cols - (n - (rows - 1) * cols)) / 2)
    local h, out = s * SQRT3_2, {}
    for k = 1, n do
        local idx = k - 1
        local r   = floor(idx / cols)
        local c   = idx - r * cols
        if r == rows - 1 then c = c + c0 end
        local along = c * s
        if r % 2 == 1 then along = along + s * 0.5 end
        out[k] = { along, r * h }
    end
    return out
end

-- Formations aim just INSIDE the coherency limit rather than at it: SHAPE_MARGIN
-- under the mode distance, which is room enough for float error and the physics
-- settle and small enough that a 2" formation measures 1.99". Base contact cannot
-- give up a whole hundredth, so it keeps a proportional margin instead and lands
-- on 0.008" -- still base contact on any table.
local SHAPE_MARGIN = 0.01
local function shapeGap(modeIdx)
    local d = MODES[modeIdx].dist
    return max(d - SHAPE_MARGIN, 0.8 * d)
end

-- Build a formation. shape is "line" | "double" | "triangles" (Dogbone) | "honey".
-- Returns newPos[i] = {x,z} aligned with the INPUT order, plus a note when the
-- shape had to be substituted. Callers keep each model's current y and rotation.
-- `axis` pins the direction the formation runs in; omit it and the unit is laid
-- out along principalAxis instead, which is what the geometry tests exercise.
local function buildLayout(shape, descs, g, axis)
    local n = #descs
    if n < 1 then return {}, "no models" end
    local note = nil
    local u = axis or principalAxis(descs)
    local p = { x = -u.z, z = u.x }
    local pa, pb, order = {}, {}, {}
    for i = 1, n do
        pa[i] = descs[i].pos.x * u.x + descs[i].pos.z * u.z
        pb[i] = descs[i].pos.x * p.x + descs[i].pos.z * p.z
        order[i] = i
    end
    table.sort(order, function(i, j)
        if pa[i] ~= pa[j] then return pa[i] < pa[j] end
        return pb[i] < pb[j]
    end)

    -- Layout frame -> world. u and p are orthonormal, so unit stays unit. It
    -- reads `order` live, so re-sorting below re-aims every generator with it.
    local function rin(k, dx, dz)
        return baseRadiusInDir(descs[order[k]], u.x * dx + p.x * dz,
                                                u.z * dx + p.z * dz)
    end
    if shape == "triangles" and n < 6 then
        shape, note = "line", "n<6, used Single Line"
    end
    local function generate()
        if shape == "line"        then return slotsSingleLine(n, rin, g) end
        if shape == "double"      then return slotsChain(n, rin, g) end
        if shape == "triangles"   then return slotsTriangles(n, rin, g) end
        return slotsHoneycomb(n, rin, g)
    end
    -- Placing each model at an exact gap from named neighbours says nothing about
    -- the pairs it never named, so a unit that mixes a 25mm base with a 130mm one
    -- can still fold one of those onto another or leave one hanging by a single
    -- buddy. What comes out is therefore MEASURED rather than assumed, and the
    -- shape gets up to three further attempts.
    --
    -- Overlaps are counted a thousand times heavier than models short of a buddy:
    -- a model standing inside another is broken outright, where a model out of
    -- coherency is only wrong. Below that, coherency is the thing being bought,
    -- which is the whole point of the fallbacks -- a formation is allowed to come
    -- out irregular, or not to be the shape that was asked for, before it is
    -- allowed to break the distance the player set.
    -- A single line cannot give its two end models a second buddy at any spacing,
    -- so it is scored against one.
    local want = (shape == "line") and 1 or min(2, n - 1)
    local function score(slots)
        local within, bad = {}, 0
        for i = 1, n do within[i] = 0 end
        for i = 1, n - 1 do
            for j = i + 1, n do
                local s = slotGap(rin, slots, i, j)
                if s < 0 then bad = bad + 1 end
                if s <= g + EPS then
                    within[i] = within[i] + 1; within[j] = within[j] + 1
                end
            end
        end
        local lonely = 0
        for i = 1, n do if within[i] < want then lonely = lonely + 1 end end
        return bad * 1000 + lonely
    end
    local slots = generate()
    local best = score(slots)
    local function tryIt(candidate, why)
        if best == 0 then return end
        local s = score(candidate)
        if s < best then slots, best, note = candidate, s, why end
    end
    if best > 0 then
        -- Fill the slots smallest base first instead of in the order the models
        -- happen to be standing. Neighbouring slots then hold neighbouring sizes,
        -- which is all the regularity these shapes need, and the models inside a
        -- unit are interchangeable -- the whole button is about moving them.
        local byPos = {}
        for i = 1, n do byPos[i] = order[i] end
        table.sort(order, function(i, j)
            local a, b = descs[i], descs[j]
            local am, bm = max(a.a, a.b), max(b.a, b.b)
            if am ~= bm then return am < bm end
            return min(a.a, a.b) < min(b.a, b.b)
        end)
        local sized = generate()
        local s = score(sized)
        if s < best then
            slots, best, note = sized, s, "bases mixed, filled by base size"
        else
            order = byPos                        -- rin reads it, so put it back
        end
    end
    -- The staggered chain is the most forgiving shape here -- every model at an
    -- exact gap from the two before it, and no row to keep in step with -- so it
    -- is what a block that cannot be packed falls back to. It is a real change of
    -- shape and the note says so.
    if best > 0 and shape ~= "double" and shape ~= "line" then
        tryIt(slotsChain(n, rin, g), "bases too mixed for that shape, used Double Line")
    end
    -- Last resort, and the only layout here that gives up the distance rather than
    -- keeping it: one lattice step, which cannot overlap however the bases are
    -- mixed. It only ever wins when everything above it still overlaps.
    if best >= 1000 and shape == "honey" then
        local rmaxK, rminK = {}, {}
        for k = 1, n do
            local d = descs[order[k]]
            rmaxK[k] = max(d.a, d.b); rminK[k] = min(d.a, d.b)
        end
        tryIt(slotsHoneyGrid(n, rmaxK, rminK, g),
              "bases too mixed to pack, spaced on one grid step")
    end
    local sa, sb, cx, cz = 0, 0, 0, 0
    for k = 1, n do sa = sa + slots[k][1]; sb = sb + slots[k][2] end
    for i = 1, n do cx = cx + descs[i].pos.x; cz = cz + descs[i].pos.z end
    sa, sb, cx, cz = sa / n, sb / n, cx / n, cz / n
    local out = {}
    for k = 1, n do
        local a, b = slots[k][1] - sa, slots[k][2] - sb
        out[order[k]] = { x = cx + u.x * a + p.x * b, z = cz + u.z * a + p.z * b }
    end
    return out, note
end

-- Exported for tests/geometry_test.lua only; nothing in TTS reads this.
AOS_GEO = {
    makeDesc = makeDesc, baseRadiusInDir = baseRadiusInDir, baseGap = baseGap,
    requiredBuddies = requiredBuddies, evaluate = evaluate, summarize = summarize,
    principalAxis = principalAxis, buildLayout = buildLayout,
    shapeGap = shapeGap, MODES = MODES,
}

-- ================================================== BASE + DESCRIPTORS ======
-- Everything below talks to TTS. Nothing above this line does.

local GLOW_OK     = {0.15, 0.90, 0.25}
local GLOW_BAD    = {0.95, 0.15, 0.15}
local BREACH_COL  = {1.00, 0.55, 0.10, 0.9}

local function alive(o) return o ~= nil and not o.isDestroyed() end

-- Smallest catalogued base the model's footprint still covers, cached on the
-- model itself so it is measured once per model per table, not once per tick.
local function determineBaseInInches(model)
    local saved = model.getTable("aos_base")
    if saved ~= nil and saved.base ~= nil then return saved.base end
    local size, chosen, best = model.getBoundsNormalized().size, nil, 1e10
    for _, b in ipairs(VALID_BASE_SIZES_IN_MM) do
        local bx, bz = (MM_TO_INCH - 0.001) * b.x, (MM_TO_INCH - 0.001) * b.z
        if size.x > bx and size.z > bz then
            local d = (size.x - bx) + (size.z - bz)
            if d < best then best, chosen = d, b end
        end
    end
    local out
    if chosen == nil then out = { x = size.x / 2, z = size.z / 2 }
    else out = { x = chosen.x * MM_TO_INCH / 2, z = chosen.z * MM_TO_INCH / 2 } end
    if out.x < 0.01 then out.x = 0.01 end
    if out.z < 0.01 then out.z = 0.01 end
    model.setTable("aos_base", { base = out })
    return out
end

-- A base wide enough one way and narrow the other: the ones Ovals Sideways turns.
local function isOvalBase(b) return abs(b.x - b.z) > OVAL_EPS end

-- yaw (degrees) overrides the model's real heading, so a layout can be computed
-- against the rotation the models are turning to: setRotationSmooth is animated,
-- so reading the rotation back would give the old pose and size ovals wrongly.
local function descOf(o, base, yaw)
    local d = { pos = o.getPosition(), a = base.x, b = base.z }
    if yaw == nil then
        d.right, d.forward = o.getTransformRight(), o.getTransformForward()
    else
        local t = rad(yaw)
        d.right   = { x = cos(t), y = 0, z = -sin(t) }
        d.forward = { x = sin(t), y = 0, z =  cos(t) }
    end
    return d
end

-- ================================================================ STATUS ====
-- No status panel: messages go to whoever pressed the button, as a TTS broadcast.
-- Only buttons speak; the live monitor is silent.
local function setStatus(msg)
    if actingColor ~= nil then broadcastToColor(msg, actingColor, {0.85, 0.9, 1})
    else broadcastToAll(msg, {0.85, 0.9, 1}) end
end

local function selectionOf(playerColor)
    local pl, out = Player[playerColor], {}
    if pl == nil then return out end
    local sel = pl.getSelectedObjects()
    if sel == nil then return out end
    for _, o in ipairs(sel) do if alive(o) then out[#out + 1] = o end end
    return out
end

-- The models a button acts on: whatever the player has selected is the unit.
local function resolveUnit(playerColor)
    local sel = selectionOf(playerColor)
    if #sel == 0 then return nil, "Select models first" end
    return sel, nil
end

-- ================================================================= AURAS ====
-- The colour every aura is drawn in: whichever swatch the picker is on.
local function auraColor() return AURA_PRESETS[auraIdx] or AURA_PRESETS[1] end

local function sameRGB(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    return abs((a[1] or 0) - (b[1] or 0)) < 0.004
       and abs((a[2] or 0) - (b[2] or 0)) < 0.004
       and abs((a[3] or 0) - (b[3] or 0)) < 0.004
end

-- One stored ring, normalised to radius + colour. A bare number is the older
-- stored form, a radius without a colour, and draws in the colour picked now.
local function auraEntry(e)
    if type(e) == "number" then return e, auraColor() end
    if type(e) == "table" and type(e.r) == "number" then
        return e.r, (type(e.c) == "table" and e.c or auraColor())
    end
    return nil
end

-- Ring points are object-local (they scale with the object, hence the 1/scale) and
-- shared between identical models, so 20 Liberators generate one table, not twenty.
local ringCache = {}
-- `inset` pulls the centreline in by half the line width, so the OUTER edge of the
-- drawn ring lands on the measured range instead of overshooting it. Points and
-- inset are scaled together, so it holds on a scaled model too.
local function ringPoints(radius, a, b, sf, h, inset)
    local key = string.format("%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", radius, a, b, sf, h, inset)
    local pts = ringCache[key]
    if pts ~= nil then return pts end
    pts = {}
    local ra, rb = radius + a - inset, radius + b - inset
    if ra < 0.01 then ra = 0.01 end
    if rb < 0.01 then rb = 0.01 end
    local steps = 64
    -- Built straight into the model's horizontal x/z plane at height h: a ring in
    -- the x/y plane stands upright, and a line entry's `rotation` cannot lay it down.
    for i = 0, steps do
        local t = rad(360 / steps * i)
        pts[i + 1] = { x = cos(t) * ra * sf, y = h, z = sin(t) * rb * sf }
    end
    ringCache[key] = pts
    return pts
end

-- Ring height in the model's local space, from the model's own bounds so it clears
-- a tall base instead of sinking into it.
local function ringHeight(o)
    local b, sc = o.getBoundsNormalized(), o.getScale()
    local sy = (sc.y ~= 0) and sc.y or 1
    return (b.center.y - b.size.y * 0.5 - o.getPosition().y + RING_CLEARANCE) / sy
end

-- The same height in world space, as an offset from the model's own position so it
-- holds as the model is lifted and dropped. Used by the breach lines, which are
-- drawn on the tool object and cannot borrow the model's local frame.
local function floorOffset(o)
    local b = o.getBoundsNormalized()
    return (b.center.y - b.size.y * 0.5) - o.getPosition().y + RING_CLEARANCE
end

local function mixRGB(a, b, t)
    return { a[1] + (b[1] - a[1]) * t,
             a[2] + (b[2] - a[2]) * t,
             a[3] + (b[3] - a[3]) * t }
end

local function hexRGB(c, alpha)
    local function ch(v)
        v = floor(v * 255 + 0.5)
        if v < 0 then v = 0 elseif v > 255 then v = 255 end
        return v
    end
    if alpha == nil then
        return string.format("#%02x%02x%02x", ch(c[1]), ch(c[2]), ch(c[3]))
    end
    return string.format("#%02x%02x%02x%02x", ch(c[1]), ch(c[2]), ch(c[3]), ch(alpha))
end

-- Which label a coloured button wants: Rec. 709 luma of the fill as it actually
-- appears once the wash has been laid over the parchment, so a dark swatch takes
-- the pale label and a bright one keeps the anthracite.
local function labelOver(c, alpha)
    local m = mixRGB(PARCHMENT, c, alpha)
    local y = 0.2126 * m[1] + 0.7152 * m[2] + 0.0722 * m[3]
    return (y < 0.5) and ON_TEXT or OFF_TEXT
end

-- Every ring this model carries, plus a thin outline of the base itself, in ONE
-- setVectorLines call.
local function drawAuras(o)
    local list, lines = o.getTable("aos_auras"), {}
    if list ~= nil and #list > 0 then
        local b, sf, h = determineBaseInInches(o), 1 / o.getScale().x, ringHeight(o)
        lines[1] = { points = ringPoints(0, b.x, b.z, sf, h, BASE_THICK * 0.5),
                     color = {1, 1, 1, 0.85}, thickness = BASE_THICK }
        for _, e in ipairs(list) do
            local r, c = auraEntry(e)
            if r ~= nil then
                lines[#lines + 1] = { points = ringPoints(r, b.x, b.z, sf, h,
                                                          AURA_THICK * 0.5),
                                      color = c, thickness = AURA_THICK }
            end
        end
    end
    o.setVectorLines(lines)
end

-- One ring at a time: a new radius replaces whatever the model was carrying.
-- Pressing the radius it already has, in the colour it already has, clears it;
-- pressing it after picking a different colour recolours instead, which is how a
-- ring is changed without having to take it off and put it back. Returns true
-- when a ring is now showing. Stored on the model, so it survives save/load.
local function setAura(o, r)
    local list = o.getTable("aos_auras")
    local cur, curC = nil, nil
    if list ~= nil then cur, curC = auraEntry(list[1]) end
    local c = auraColor()
    local same = cur ~= nil and abs(cur - r) < 0.001 and sameRGB(curC, c)
    o.setTable("aos_auras", same and {} or { { r = r, c = c } })
    drawAuras(o)
    return not same
end

-- Sets rather than toggles, because onEndEdit also fires on clicking away: firing
-- twice on the same radius has to leave the ring up. The presets keep the toggle.
local function forceAura(o, r)
    o.setTable("aos_auras", { { r = r, c = auraColor() } })
    drawAuras(o)
end

local function clearAuras(o)
    o.setTable("aos_auras", {})
    o.setVectorLines({})
end

-- ===================================================== COHERENCY MONITOR ====
local refreshUI            -- forward declaration; defined with the UI glue

local function clearMonitorVisuals()
    for guid in pairs(monGlowed) do                 -- only ever our own glows
        local o = getObjectFromGUID(guid)
        if alive(o) then o.highlightOff() end
    end
    monGlowed, monGlowState = {}, {}
    self.setVectorLines({})
end

local function stopMonitor(msg)
    monActive = false
    if monTimer   ~= nil then Wait.stop(monTimer);   monTimer   = nil end
    if monTimeout ~= nil then Wait.stop(monTimeout); monTimeout = nil end
    clearMonitorVisuals()
    monGuids, monIdx, monDesc, monBase, monDrop = {}, {}, {}, {}, {}
    monGap, monCp, monPrevMoving = {}, {}, {}
    if msg ~= nil then setStatus(msg) end
end

-- One model moved: re-measure only its row/column of the cached matrices. O(n).
local function recomputeRow(i)
    local di = monDesc[i]
    if di == nil then return end
    for j = 1, #monDesc do
        if j ~= i and monDesc[j] ~= nil then
            local g, pi, pj = baseGap(di, monDesc[j])
            monGap[i][j], monGap[j][i] = g, g
            monCp[i][j],  monCp[j][i]  = pi, pj
        end
    end
end

-- Resolve the monitored guids to live objects, dropping any that were deleted so
-- indices stay dense, then measure every pair once. Start and deletions only --
-- never per tick. Returns the live model count.
local function fullRecompute()
    local guids, desc, base, drop = {}, {}, {}, {}
    for _, guid in ipairs(monGuids) do
        local o = getObjectFromGUID(guid)
        if alive(o) then
            guids[#guids + 1] = guid
            base[#base + 1]   = determineBaseInInches(o)
            desc[#desc + 1]   = descOf(o, base[#base])
            drop[#drop + 1]   = floorOffset(o)      -- shape, not pose: cache once
        end
    end
    monGuids, monDesc, monBase, monDrop = guids, desc, base, drop
    monIdx, monGap, monCp = {}, {}, {}
    for i = 1, #guids do
        monIdx[guids[i]] = i
        monGap[i], monCp[i] = {}, {}
    end
    for i = 1, #desc do recomputeRow(i) end
    return #desc
end

-- Glow every model and draw a breach line from each failing model to its nearest
-- neighbour. Silent; returns the summary for the button that started the check.
-- Breach lines live on the tool object, in its own local space.
local function drawMonitor()
    local n = #monDesc
    if n == 0 then return end
    local dist = MODES[uiMode].dist
    local r = summarize(monGap, n, dist, requiredBuddies(n, buddyOverride))
    local want = {}
    for i = 1, n do
        local guid = monGuids[i]
        local o = getObjectFromGUID(guid)
        if alive(o) then
            -- Only re-issue the glow when this model's verdict actually flipped.
            if monGlowState[guid] ~= r.ok[i] then
                o.highlightOn(r.ok[i] and GLOW_OK or GLOW_BAD)
                monGlowState[guid] = r.ok[i]
            end
            want[guid] = true
        end
    end
    for guid in pairs(monGlowed) do
        if want[guid] == nil then
            local o = getObjectFromGUID(guid)
            if alive(o) then o.highlightOff() end
            monGlowState[guid] = nil
        end
    end
    monGlowed = want
    -- A plain segment between the two base edges at one shared height, mapped
    -- through positionToLocal so it lands where the models are whatever the tool
    -- object's transform is.
    local lines, drawn = {}, 0
    for i = 1, n do
        if not r.ok[i] and r.near[i] > 0 then
            if drawn >= MAX_BREACH_LINES then break end
            local j = r.near[i]
            local a, b = monCp[i][j], monCp[j][i]
            -- Just above the tabletop, so it reads as drawn ON it.
            local y = monDesc[i].pos.y + (monDrop[i] or RING_CLEARANCE)
            lines[#lines + 1] = {
                points = { self.positionToLocal({ x = a.x, y = y, z = a.z }),
                           self.positionToLocal({ x = b.x, y = y, z = b.z }) },
                color = BREACH_COL, thickness = BREACH_THICK,
            }
            drawn = drawn + 1
        end
    end
    self.setVectorLines(lines)
    return r
end

local motionTick                -- forward declaration; defined just below
local function startMotionLoop()
    if not monActive or monTimer ~= nil then return end
    monTimer = Wait.time(motionTick, MOTION_TICK, -1)
end

-- Refresh only the models actually in motion, then redraw. The loop stops its own
-- timer the moment nothing is moving; onObjectPickUp / onObjectDrop, or a shape
-- move, start it again.
motionTick = function()
    if not monActive then return end
    local moving, obj, rebuild = {}, {}, false
    for i = 1, #monGuids do
        local o = getObjectFromGUID(monGuids[i])
        if not alive(o) then rebuild = true
        elseif o.held_by_color ~= nil or o.resting == false then
            moving[i], obj[i] = true, o
        end
    end
    if rebuild then
        monPrevMoving = {}
        if fullRecompute() < 2 then
            -- Every path that stops the monitor by itself has to unlight the
            -- button as well, or Check Coherency reads as running when it is not.
            stopMonitor("Coherency stopped: unit too small")
            refreshUI()
        else drawMonitor() end
        return
    end
    -- Union of moving-now and moving-last-tick, so the tick a model comes to
    -- rest its final position is still captured before the loop stops.
    local refresh = {}
    for i in pairs(moving) do refresh[i] = true end
    for i in pairs(monPrevMoving) do
        if moving[i] == nil then
            local o = getObjectFromGUID(monGuids[i])
            if alive(o) then obj[i] = o; refresh[i] = true end
        end
    end
    for i in pairs(refresh) do monDesc[i] = descOf(obj[i], monBase[i]) end
    for i in pairs(refresh) do recomputeRow(i) end
    monPrevMoving = moving
    drawMonitor()
    if next(moving) == nil then
        monPrevMoving = {}
        if monTimer ~= nil then Wait.stop(monTimer); monTimer = nil end
    end
end

-- Object events fire for every object on the table, so bail cheaply first.
function onObjectPickUp(playerColor, obj)
    if not monActive then return end
    if monIdx[obj.getGUID()] == nil then return end
    startMotionLoop()
end

function onObjectDrop(playerColor, obj)
    if not monActive then return end
    local i = monIdx[obj.getGUID()]
    if i == nil then return end
    monDesc[i] = descOf(obj, monBase[i])            -- snap to the new spot at once
    recomputeRow(i)
    drawMonitor()
    startMotionLoop()                               -- then track the physics settle
end

function onObjectDestroy(obj)
    if not monActive then return end
    if monIdx[obj.getGUID()] == nil then return end
    Wait.frames(function()                          -- the object still exists now
        if not monActive then return end
        if fullRecompute() < 2 then
            stopMonitor("Coherency stopped: unit too small")
            refreshUI()
        else drawMonitor() end
    end, 1)
end

local function resyncMonitor()
    if not monActive then return end
    fullRecompute()
    drawMonitor()
    startMotionLoop()
end

-- ================================================================ SHAPES ====
local SHAPE_LABEL = { line = "Single Line", double = "Double Line",
                      triangles = "Dogbone", honey = "Honeycomb" }

-- How far off level an angle is, folded to +/-180 so 359 reads as 1, not 359.
local function offLevel(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return abs(a)
end

-- The frame EVERY formation is built in, so a unit always lands parallel to the
-- panel and facing out across the table, whatever way it was standing before:
-- the tool's own long edge is the axis the shape runs along, and every model
-- ends turned away from the tool: half a turn from the tool's own heading, which
-- is the way a model faces when it is given the tool's yaw. Both come off one
-- vector, so they cannot drift apart.
--
-- It is read off the object's TRANSFORM rather than its Euler angles. A yaw of t
-- puts local +X at (cos t, -sin t) and +Z at (sin t, cos t) -- the frame descOf
-- builds for that yaw -- but getRotation().y stops being that heading the moment
-- the tool is tilted or flipped, and the formation then comes out square to the
-- panel instead of along it. The transform stays right through both.
local function toolFrame()
    local r = self.getTransformRight()
    local ax, az = r.x, r.z
    local m = sqrt(ax * ax + az * az)
    if m < EPS then                                 -- stood on end: no long edge
        local f = self.getTransformForward()        -- on the table, so take the
        ax, az = f.z, -f.x                          -- forward turned back a quarter
        m = sqrt(ax * ax + az * az)
        if m < EPS then ax, az, m = 1, 0, 1 end     -- and world +x if that fails too
    end
    ax, az = ax / m, az / m
    return { x = ax, z = az }, (deg(atan2(-az, ax)) + 180) % 360
end

-- Shapes always stand their models up: a leaning model reports its silhouette from
-- getBoundsNormalized rather than its base, so it would be spaced wrongly. Only
-- leaning models are touched. yaws[i] is the heading each model is to end on, which
-- is also the heading its descriptor is built against.
local function standUp(objs, yaws)
    for i = 1, #objs do
        local o = objs[i]
        if alive(o) then
            local r = o.getRotation()
            if offLevel(r.x) > UPRIGHT_EPS or offLevel(r.z) > UPRIGHT_EPS
               or offLevel(r.y - yaws[i]) > UPRIGHT_EPS then
                o.setRotationSmooth({ 0, yaws[i], 0 }, false, true)
            end
        end
    end
end

local function doShape(shape, playerColor)
    local objs, err = resolveUnit(playerColor)
    if err ~= nil then return setStatus(err) end
    local n = #objs
    if n < 2 then return setStatus("Need 2+ models") end
    if n > MAX_UNIT then
        return setStatus("Unit too big: " .. n .. "/" .. MAX_UNIT)
    end
    -- Settle on the end pose first, so the descriptors below are built against the
    -- pose the models are about to have rather than the one they are leaving.
    -- Ovals Sideways turns the oval bases a quarter turn out of that heading and
    -- leaves the round ones alone -- a round base presents the same footprint
    -- either way, and turning it would only leave the model looking off to one
    -- side while the rest of the unit faces front.
    local axis, yaw = toolFrame()
    local bases, yaws, snap = {}, {}, {}
    for i = 1, n do
        bases[i] = determineBaseInInches(objs[i])
        if ovalSideways and isOvalBase(bases[i]) then yaws[i] = (yaw + 90) % 360
        else yaws[i] = yaw end
        -- Snapshot for Undo before anything moves: setRotationSmooth is animated,
        -- so a rotation read back after standUp can already be the new heading.
        snap[i] = { guid = objs[i].getGUID(), pos = objs[i].getPosition(),
                    rot = objs[i].getRotation() }
    end
    undoStack = snap                                -- one level of undo is enough
    standUp(objs, yaws)

    local descs = {}
    for i = 1, n do descs[i] = descOf(objs[i], bases[i], yaws[i]) end
    local dist = MODES[uiMode].dist
    local pos, note = buildLayout(shape, descs, shapeGap(uiMode), axis)
    for i = 1, n do
        local p = { x = pos[i].x, y = descs[i].pos.y, z = pos[i].z }
        objs[i].setPositionSmooth(p, false, true)   -- no collision, fast
        descs[i].pos = p
    end

    -- Validate the layout we just committed to, against our own checker.
    local req = requiredBuddies(n, buddyOverride)
    local r = evaluate(descs, dist, req)
    local head = SHAPE_LABEL[shape]
    if note ~= nil then head = head .. " (" .. note .. ")" end
    if r.fails > 0 then head = head .. ": " .. r.fails .. " failing" end
    setStatus(head)
    resyncMonitor()
end

-- ============================================================= UI GLUE ======
-- XML callbacks are globals taking (player, value, id). Never assume a colour --
-- always resolve the acting player from player.color.

-- Always write background AND label colour together, so an active button can
-- never end up with a dark label on a dark background.
local function paint(id, on)
    self.UI.setAttribute(id, "color",     on and ON_COLOR or OFF_COLOR)
    self.UI.setAttribute(id, "textColor", on and ON_TEXT  or OFF_TEXT)
end

local AURA_BTN = { "aura3", "aura6", "aura9", "aura12", "aura18" }

-- The five radius buttons and Aura Color all wear the picked colour, so the
-- column says what the next ring will look like before it is drawn, and the
-- swatch that is picked is ringed in the popup.
local function paintAuraButtons()
    local c = auraColor()
    local fill, text = hexRGB(c, AURA_BTN_ALPHA), labelOver(c, AURA_BTN_ALPHA)
    for _, id in ipairs(AURA_BTN) do
        self.UI.setAttribute(id, "color",     fill)
        self.UI.setAttribute(id, "textColor", text)
    end
    self.UI.setAttribute("colorBtn", "color",     hexRGB(c, COLOR_BTN_ALPHA))
    self.UI.setAttribute("colorBtn", "textColor", labelOver(c, COLOR_BTN_ALPHA))
    for i = 1, #AURA_PRESETS do
        local on = (i == auraIdx)
        self.UI.setAttribute("auraCol" .. i, "outline",
                             on and "#f2f1ec" or "#29313366")
        self.UI.setAttribute("auraCol" .. i, "outlineSize", on and "4 4" or "2 2")
    end
end

local function showColors(on)
    colorOpen = on
    self.UI.setAttribute("colorPopup", "active", on and "true" or "false")
end

refreshUI = function()
    for i = 1, #MODES do paint(MODES[i].id, i == uiMode) end
    for i = 1, #BUDDY_IDS do paint(BUDDY_IDS[i], (i - 1) == buddyOverride) end
    paint("checkBtn", monActive)
    paint("ovalBtn",  ovalSideways)
    self.UI.setAttribute("customAura", "text", lastCustom)
end

function aosMode(player, value, id)
    actingColor = player.color
    for i = 1, #MODES do if MODES[i].id == id then uiMode = i end end
    refreshUI()
    if monActive then drawMonitor() end             -- same gaps, new threshold
end

function aosBuddy(player, value, id)
    actingColor = player.color
    for i = 1, #BUDDY_IDS do if BUDDY_IDS[i] == id then buddyOverride = i - 1 end end
    refreshUI()
    if monActive then drawMonitor() end
end

function aosOval(player)
    actingColor = player.color
    ovalSideways = not ovalSideways
    refreshUI()
    setStatus(ovalSideways and "Oval bases turn sideways in formations"
                            or "Oval bases face forward in formations")
end

function aosCheck(player)
    actingColor = player.color
    if monActive then
        stopMonitor("Coherency off")
        return refreshUI()
    end
    local objs, err = resolveUnit(player.color)
    if err ~= nil then return setStatus(err) end
    if #objs < 2 then return setStatus("Need 2+ models") end
    if #objs > MAX_UNIT then
        return setStatus("Unit too big: " .. #objs .. "/" .. MAX_UNIT)
    end
    stopMonitor()                                   -- only one monitor per tool
    monActive, monGuids = true, {}
    for _, o in ipairs(objs) do monGuids[#monGuids + 1] = o.getGUID() end
    fullRecompute()
    local r = drawMonitor()
    -- A split unit passes the rule as written but is treated as illegal at most
    -- events, so it is the one thing worth saying. The glows say the rest.
    local msg = "Measuring coherency"
    if r ~= nil and r.groups > 1 then msg = msg .. ": unit is in " .. r.groups .. " groups" end
    setStatus(msg)
    monTimeout = Wait.time(function()
        stopMonitor("Coherency timed out")
        refreshUI()
    end, MONITOR_TIMEOUT)
    -- Only start polling if something is actually in motion right now.
    for _, o in ipairs(objs) do
        if o.held_by_color ~= nil or o.resting == false then startMotionLoop(); break end
    end
    refreshUI()
end

-- ---- the colour picker -----------------------------------------------------
function aosColors(player)
    actingColor = player.color
    showColors(not colorOpen)
end

function aosColorsClose(player)
    if player ~= nil then actingColor = player.color end
    showColors(false)
end

-- The swatch ids are auraCol1..auraCol12, in AURA_PRESETS order, so the index is
-- whatever follows the prefix.
function aosPickColor(player, value, id)
    actingColor = player.color
    local i = tonumber(string.sub(id, 8))
    if i == nil or AURA_PRESETS[i] == nil then return end
    auraIdx = i
    paintAuraButtons()
    showColors(false)
end

-- ---- auras -----------------------------------------------------------------
local function auraOnSelection(playerColor, r)
    local sel = selectionOf(playerColor)
    if #sel == 0 then return setStatus("Select models first") end
    local on = 0
    for _, o in ipairs(sel) do
        if setAura(o, r) then on = on + 1 end
    end
    -- setAura toggles, so say which way it went.
    if on > 0 then setStatus("Aura " .. r .. [["]])
    else setStatus("Aura " .. r .. [[" cleared]]) end
end

function aosAura(player, value, id)
    actingColor = player.color
    auraOnSelection(player.color, tonumber(string.sub(id, 5)))
end

-- Fires per keystroke, so it stays silent; applying does the validating.
function aosCustomChanged(player, value)
    lastCustom = value
end

-- The field's Decimal validation accepts a comma as the decimal separator, which
-- half the table types. tonumber only knows the period, so swap before parsing.
local function customRadius()
    if type(lastCustom) ~= "string" then return tonumber(lastCustom) end
    return tonumber((string.gsub(lastCustom, ",", ".")))
end

-- Enter and Apply Custom are one action that can arrive as two events in the same
-- frame: pressing Apply Custom while the field has focus fires onEndEdit as the
-- field lets go,
-- then the button's own click. Doing the work twice is harmless -- this path SETS
-- the ring -- but saying so twice is noise, hence the one-frame guard. An empty
-- selection is silent, so clicking off the field never nags.
local applyBusy = false
local function applyCustom(playerColor)
    if applyBusy then return end
    applyBusy = true
    Wait.frames(function() applyBusy = false end, 1)
    local r = customRadius()
    if r == nil or r < 0.5 or r > 60 then
        return setStatus("Radius must be 0.5-60")
    end
    local sel = selectionOf(playerColor)
    if #sel == 0 then return end
    for _, o in ipairs(sel) do forceAura(o, r) end
    setStatus("Aura " .. r .. [["]])
end

-- Bound to onEndEdit, which fires on Enter AND on clicking away.
function aosApplyCustom(player, value)
    actingColor = player.color
    if value ~= nil and value ~= "" then lastCustom = value end
    applyCustom(player.color)
end

-- A Button's second argument is its own value, never the field's text, so this goes
-- on what the keystrokes left in lastCustom -- the string the field is showing.
function aosApply(player)
    actingColor = player.color
    applyCustom(player.color)
end

function aosClearSel(player)
    actingColor = player.color
    local sel = selectionOf(player.color)
    if #sel == 0 then return setStatus("Select models first") end
    for _, o in ipairs(sel) do clearAuras(o) end
    setStatus("Auras cleared")
end

function aosClearAll(player)
    if player ~= nil then actingColor = player.color end
    local n = 0
    for _, o in ipairs(getAllObjects()) do          -- button press only, never a timer
        local t = o.getTable("aos_auras")
        if t ~= nil and #t > 0 then clearAuras(o); n = n + 1 end
    end
    setStatus(n == 0 and "No auras on the table"
                     or ("Cleared " .. n .. " auras"))
end

-- ---- formation -------------------------------------------------------------
function aosShape(player, value, id)
    actingColor = player.color
    local map = { shapeLine = "line", shapeDouble = "double",
                  shapeTri = "triangles", shapeHoney = "honey" }
    doShape(map[id], player.color)
end

function aosUndo(player)
    if player ~= nil then actingColor = player.color end
    if #undoStack == 0 then return setStatus("Nothing to undo") end
    local n = 0
    for _, s in ipairs(undoStack) do
        local o = getObjectFromGUID(s.guid)
        if alive(o) then
            o.setPositionSmooth(s.pos, false, true)
            o.setRotationSmooth(s.rot, false, true)
            n = n + 1
        end
    end
    undoStack = {}
    -- n < #undoStack means models were destroyed between the move and the undo.
    setStatus(n > 0 and "Move undone" or "Nothing left to put back")
    resyncMonitor()
end

-- setCustomAssets replaces the whole list rather than adding to it, so read what is
-- there and put it all back with ours alongside. Writing rebuilds the UI, so the
-- ordinary case -- everything already registered against the right URL -- writes
-- nothing and the panel does not flicker on load.
--   getCustomAssets() hands back TTS's own LIVE list, the same object
--   setCustomAssets() compares against to decide whether anything changed. Editing
--   an entry in place mutates the "before" as well, the compare sees no change and
--   the new URL silently fails to take. So every entry here is built fresh: never
--   write into the table this function was handed.
local function ensureUIAssets()
    local ok, current = pcall(function() return self.UI.getCustomAssets() end)
    if not ok or type(current) ~= "table" then current = {} end
    local assets, dirty = {}, false
    for i = 1, #current do
        local a = current[i]
        if type(a) == "table" and a.name ~= nil and a.url ~= nil then
            assets[#assets + 1] = { name = a.name, url = a.url }
        end
    end
    for _, want in ipairs(UI_ASSETS) do
        local found = false
        for i = 1, #assets do
            if assets[i].name == want.name then
                found = true
                if assets[i].url ~= want.url then
                    assets[i] = { name = want.name, url = want.url }
                    dirty = true
                end
                break
            end
        end
        if not found then
            assets[#assets + 1] = { name = want.name, url = want.url }
            dirty = true
        end
    end
    if dirty then pcall(function() self.UI.setCustomAssets(assets) end) end
end

-- ======================================================= SAVE / LOAD ========
-- uiMode is deliberately NOT saved: the coherency distance always comes back at
-- 0.5", the value nearly every unit uses. The rest persist -- they are
-- preferences, not readings.
function onSave()
    return JSON.encode({ buddy = buddyOverride, custom = lastCustom,
                         color = auraIdx, oval = ovalSideways })
end

function onLoad(saved)
    local _
    _, VERSION = Updater_stateVersion(saved)   -- the version this copy is on
    ensureUIAssets()
    if saved ~= nil and saved ~= "" then
        local ok, d = pcall(JSON.decode, saved)
        if ok and type(d) == "table" then
            -- d.mode, written by versions before this one, is ignored on purpose.
            if type(d.buddy)  == "number" then buddyOverride = d.buddy end
            if type(d.custom) == "string" then lastCustom = d.custom end
            if type(d.color)  == "number" and AURA_PRESETS[d.color] ~= nil then
                auraIdx = d.color
            end
            if type(d.oval)   == "boolean" then ovalSideways = d.oval end
        end
    end
end

-- Everything that paints the panel, run once the panel is actually there. The
-- update block calls this after it applies the layout; setAttribute before
-- that point does nothing and reports nothing.
function onUIReady()
    refreshUI()
    paintAuraButtons()
    showColors(false)
    self.UI.setAttribute("versionText", "text", "v" .. VERSION)
end

function onDestroy()
    stopMonitor()
end

-- ===========================================================================
-- The tool's UI, spliced in from tool.xml. Edits in that file, not this copy.
-- ===========================================================================

local TOOL_XML = [[
<!-- TTS-SELFUPDATE:aos-coherency-tool -->
<!-- ── AOS COHERENCY TOOL by Antares77 ───────────────────────────
     AoS Coherency Tool - object UI.

     Laid out WIDE and SHORT, should sit along the edge of a game table:
     three columns - Auras, Coherency, Formation - and a narrow credit strip.
     Nothing in the Lua depends on the order - the script addresses the buttons
     by id, so the columns can be shuffled here.

     BORDER. Drawn as geometry, not with an `outline` attribute: root carries the
     border colour and 3 px of padding, and panelField sits inside it with the pale
     stone, so the border is the 3 px of root that panelField does not cover.
     The buttons keep their `outline`, where at their size it reads as a bevel.
     Geometry to reduce flickering.

     BACKGROUND. bgImage is the source picture at the full width of panelField,
     docked to the top edge and running off the bottom; the Mask trims it at the
     field edge.

     ASSETS. `image="aosPanelBg"` is a NAME, and it resolves against the object's
     Custom UI Assets list, which the Lua fills in on load.
     The picture can be changed in UI_ASSETS at the top of the script.

     COLOURS. The values baked into mode1 and buddyAuto are the script's own
     defaults (0.5", Auto), so the panel is right on the first frame, before onLoad
     re-applies them; both carry a textColor of their own, because the anthracite
     one from Defaults would be invisible on a dark fill. No `colors` attribute in
     Defaults for the same reason - it would override the background the script
     sets. The five aura buttons and colorBtn carry no colour here: the script
     fills them with the chosen aura colour on load, and they wear the ordinary
     wash until then.

     COLOUR PICKER. colorPopup is the last child of panelField, so it draws over
     everything else, and starts inactive. Its twelve swatches carry their preset
     fill here - that list is the one in AURA_PRESETS at the top of the Lua, in
     the same order, and the script reads a swatch's index out of its id.

     Both three-way rows (distance, buddy rule) set childForceExpandWidth="false"
     and size their buttons by hand, so the long labels ("Base Contact", the two
     "in Range") get the room an equal three-way split would give the short ones.

     VERSION in the Lua, which onUIReady writes into versionText here once the
     panel is live. Nothing sets a version by hand in either file. -->

<Defaults>
  <Text color="#293133" fontSize="20" alignment="MiddleCenter"/>
  <!-- fontStyle Bold across every button: the stock face is thin enough at this
       size to go soft as soon as the camera leaves the panel. -->
  <Button color="#ffffff40" textColor="#293133" fontSize="20" fontStyle="Bold"
          outline="#29313366" outlineSize="2 2"/>
  <HorizontalLayout spacing="6" childForceExpandWidth="true" preferredHeight="46"/>
  <VerticalLayout spacing="6" childForceExpandHeight="false"/>
  <!-- Same wash, edge and weight as the buttons, so the field reads as one of
       them. The four colours are normal|highlighted|pressed|disabled. -->
  <InputField fontSize="20" fontStyle="Bold" textColor="#293133"
              textAlignment="MiddleCenter"
              colors="#ffffff40|#ffffff73|#ffffff26|#ffffff26"
              outline="#29313366" outlineSize="2 2"/>
</Defaults>

<Panel id="root" position="665 -95 -500" rotation="0 0 0"
       scale="1 1 1" width="1330" height="220"
       color="#293133" padding="3 3 3 3">

  <!-- The panel proper. root is the border it sits in; see BORDER above. -->
  <Panel id="panelField" color="#e6e5e1">

    <!-- Background first, so everything below draws on top of it. -->
    <Mask id="bgMask">
      <Image id="bgImage" image="aosPanelBg" raycastTarget="false"
             rectAlignment="UpperCenter" width="1324" height="1829"/>
    </Mask>

    <HorizontalLayout padding="9 9 9 9" spacing="14" childForceExpandWidth="false">

      <!-- AURAS. Placed by coordinates rather than by a layout group, so every rect
           is exactly the size written here and the right edges of all three rows
           coincide by construction, whatever the layout groups around them decide.
           The grid is five 72 px cells with 6 px gaps, (384 - 4 x 6) / 5 = 72, so
           the cells start at 0, 78, 156, 234 and 312: a radius button and the
           field take one cell, Apply Custom and Aura Color two (150), Clear
           (Selected) three (228) and Clear (All) two. Rows are 46 px tall and 6 px
           apart under the 38 px heading, at 44, 96 and 148 px down, which ends at
           194 like the other columns: 38 + 6 + 3 x 46 + 2 x 6. rectAlignment sets
           both the anchor and the pivot to the upper-left corner, so offsetXY is
           that corner's position and y runs negative going down. -->
      <Panel preferredWidth="384" color="#00000000">
        <Text rectAlignment="UpperLeft" offsetXY="0 0" width="384" height="38"
              fontSize="24" fontStyle="Bold"
              alignment="UpperCenter">AURAS (Selected Models)</Text>

        <Button id="aura3"  onClick="aosAura" text="3&quot;"
                rectAlignment="UpperLeft" offsetXY="0 -44"   width="72" height="46"/>
        <Button id="aura6"  onClick="aosAura" text="6&quot;"
                rectAlignment="UpperLeft" offsetXY="78 -44"  width="72" height="46"/>
        <Button id="aura9"  onClick="aosAura" text="9&quot;"
                rectAlignment="UpperLeft" offsetXY="156 -44" width="72" height="46"/>
        <Button id="aura12" onClick="aosAura" text="12&quot;"
                rectAlignment="UpperLeft" offsetXY="234 -44" width="72" height="46"/>
        <Button id="aura18" onClick="aosAura" text="18&quot;"
                rectAlignment="UpperLeft" offsetXY="312 -44" width="72" height="46"/>

        <InputField id="customAura" text="4"
                    rectAlignment="UpperLeft" offsetXY="0 -96" width="72" height="46"
                    onValueChanged="aosCustomChanged" onEndEdit="aosApplyCustom"
                    placeholder="0.5-60" characterLimit="5"
                    characterValidation="Decimal"/>
        <Button id="applyBtn" onClick="aosApply" text="Apply Custom" fontSize="18"
                rectAlignment="UpperLeft" offsetXY="78 -96"  width="150" height="46"/>
        <Button id="colorBtn" onClick="aosColors" text="Aura Color"
                rectAlignment="UpperLeft" offsetXY="234 -96" width="150" height="46"/>

        <Button id="auraClearSel" onClick="aosClearSel" text="Clear (Selected)"
                rectAlignment="UpperLeft" offsetXY="0 -148"   width="228" height="46"/>
        <Button id="auraClearAll" onClick="aosClearAll" text="Clear (All)"
                rectAlignment="UpperLeft" offsetXY="234 -148" width="150" height="46"/>
      </Panel>

      <VerticalLayout preferredWidth="417">
        <Text preferredHeight="38" fontSize="24" fontStyle="Bold"
              alignment="UpperCenter">COHERENCY (Selection)</Text>
        <!-- 100 + 100 + 205 + two 6 px gaps = 417. -->
        <HorizontalLayout childForceExpandWidth="false" spacing="6">
          <Button id="mode1" onClick="aosMode" text="0.5&quot;" preferredWidth="100"
                  color="#293133cc" textColor="#f2f1ec"/>
          <Button id="mode2" onClick="aosMode" text="2&quot;" preferredWidth="100"/>
          <Button id="mode3" onClick="aosMode" text="Base Contact" preferredWidth="205"/>
        </HorizontalLayout>
        <!-- 95 + 155 + 155 + two 6 px gaps = 417. -->
        <HorizontalLayout childForceExpandWidth="false" spacing="6">
          <Button id="buddyAuto" onClick="aosBuddy" text="Auto" preferredWidth="95"
                  color="#293133cc" textColor="#f2f1ec"/>
          <Button id="buddy1"    onClick="aosBuddy" text="1 in Range" preferredWidth="155"/>
          <Button id="buddy2"    onClick="aosBuddy" text="2 in Range" preferredWidth="155"/>
        </HorizontalLayout>
        <HorizontalLayout>
          <Button id="checkBtn" onClick="aosCheck" text="Check Coherency"/>
        </HorizontalLayout>
      </VerticalLayout>

      <VerticalLayout preferredWidth="417">
        <Text preferredHeight="38" fontSize="24" fontStyle="Bold"
              alignment="UpperCenter">FORMATION (Selection)</Text>
        <HorizontalLayout>
          <Button id="shapeLine"   onClick="aosShape" text="Single Line"/>
          <Button id="shapeDouble" onClick="aosShape" text="Double Line"/>
        </HorizontalLayout>
        <HorizontalLayout>
          <Button id="shapeTri"   onClick="aosShape" text="Dogbone"/>
          <Button id="shapeHoney" onClick="aosShape" text="Honeycomb"/>
        </HorizontalLayout>
        <!-- Two buttons share this row, so both labels drop a size to fit half
             the column. -->
        <HorizontalLayout>
          <Button id="undoBtn" onClick="aosUndo" text="Undo Formation" fontSize="18"/>
          <Button id="ovalBtn" onClick="aosOval" text="Ovals Sideways" fontSize="18"/>
        </HorizontalLayout>
      </VerticalLayout>

      <!-- Credit then version, reading bottom-to-top: a HorizontalLayout turned a
           quarter-turn counter-clockwise, so its width becomes its height on
           screen. 140 + 6 + 50 = 196, the height the strip has to give - the
           panel's 220 less 3 px of border top and bottom and the 9 + 9 padding.
           50 px holds a version such as "v1.2.0" with room for another digit.
           versionText's own text is only what shows until onUIReady writes the
           real version into it, so it is left blank. -->
      <Panel preferredWidth="34" color="#00000000">
        <HorizontalLayout width="196" height="30" rotation="0 0 90" spacing="6"
                          padding="0 0 0 0" childForceExpandWidth="false"
                          childAlignment="MiddleCenter">
          <Text preferredWidth="140" fontSize="15">Made by Antares77</Text>
          <Text id="versionText" preferredWidth="50" fontSize="14" fontStyle="Bold"></Text>
        </HorizontalLayout>
      </Panel>

    </HorizontalLayout>

    <!-- The colour picker, last so it covers the columns while it is up. Six
         swatches to a row: 6 x 84 + 5 x 6 of spacing + 12 + 12 of padding = 558
         across, and 44 + 44 + 34 of rows + 2 x 6 + 24 = 158 down. -->
    <Panel id="colorPopup" active="false" rectAlignment="MiddleCenter"
           width="558" height="158" color="#1c2224f5" padding="12 12 12 12"
           outline="#e6e5e1" outlineSize="2 2">
      <VerticalLayout spacing="6" childForceExpandHeight="false">
        <HorizontalLayout preferredHeight="44" spacing="6" childForceExpandWidth="false">
          <Button id="auraCol1"  onClick="aosPickColor" preferredWidth="84" color="#e62626"/>
          <Button id="auraCol2"  onClick="aosPickColor" preferredWidth="84" color="#fa850d"/>
          <Button id="auraCol3"  onClick="aosPickColor" preferredWidth="84" color="#f7d926"/>
          <Button id="auraCol4"  onClick="aosPickColor" preferredWidth="84" color="#8ce033"/>
          <Button id="auraCol5"  onClick="aosPickColor" preferredWidth="84" color="#1ab847"/>
          <Button id="auraCol6"  onClick="aosPickColor" preferredWidth="84" color="#00c7bf"/>
        </HorizontalLayout>
        <HorizontalLayout preferredHeight="44" spacing="6" childForceExpandWidth="false">
          <Button id="auraCol7"  onClick="aosPickColor" preferredWidth="84" color="#40a6ff"/>
          <Button id="auraCol8"  onClick="aosPickColor" preferredWidth="84" color="#264ce6"/>
          <Button id="auraCol9"  onClick="aosPickColor" preferredWidth="84" color="#9e40eb"/>
          <Button id="auraCol10" onClick="aosPickColor" preferredWidth="84" color="#ff59b3"/>
          <Button id="auraCol11" onClick="aosPickColor" preferredWidth="84" color="#8c5c33"/>
          <Button id="auraCol12" onClick="aosPickColor" preferredWidth="84" color="#ffffff"/>
        </HorizontalLayout>
        <!-- Its own colours: the anthracite label the Defaults hand out would be
             all but invisible on the popup's dark fill. -->
        <HorizontalLayout preferredHeight="34">
          <Button id="colorClose" onClick="aosColorsClose" text="Close" fontSize="18"
                  color="#ffffff26" textColor="#e6e5e1" outline="#e6e5e14d"/>
        </HorizontalLayout>
      </VerticalLayout>
    </Panel>

  </Panel>
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
local TOOL_ID        = "aos-coherency-tool"
local TOOL_VERSION   = "1.1.0"                 -- bumped with manifest.json
local TOOL_SIGNATURE = "TTS-SELFUPDATE:aos-coherency-tool"

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
