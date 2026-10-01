-- toolName = Chirp Setup Wizard
-- Dynamically configures Wood2026's repeating log-sine chirp setpoint.
-- Non-destructive: scans, appends, and links LS, Curves, and Mixes.

local menuItems = {
    { label = "Chirp Switch", isDetect = true, swId = nil, swName = nil },
    { label = "Safety Switch", isDetect = true, swId = nil, swName = nil },
    { label = "Chirp Weight", val = 23, min = 5, max = 40, step = 1, display = function(v) return v .. "%" end },
    { label = "WRITE CHIRP", isButton = true }
}

local selected = 1
local editing = false
local showSuccess = false
local errorMessage = nil

-- Switch detection state
local detectItem = nil
local detectPrev = {}
local detectedId = nil

local function init()
end

local function findFreeLogicalSwitches(count)
    local free_indices = {}
    for i = 0, 63 do
        local ls = model.getLogicalSwitch(i)
        if not ls or ls.func == 0 or ls.func == LS_FUNC_NONE then
            free_indices[#free_indices + 1] = i
            if #free_indices == count then return free_indices end
        end
    end
    return nil
end

-- A curve slot is free only if it is unnamed and still flat (all y == 0)
local function isCurveFree(curve)
    if not curve then return true end
    if curve.name and curve.name ~= "" then return false end
    for _, y in ipairs(curve.y or {}) do
        if y ~= 0 then return false end
    end
    return true
end

local function findFreeCurves(count)
    local free_indices = {}
    for i = 0, 31 do
        if isCurveFree(model.getCurve(i)) then
            free_indices[#free_indices + 1] = i
            if #free_indices == count then return free_indices end
        end
    end
    return nil
end

-- Physical switch positions only (SA.., SW1..), skipping inverted, logical, trims, etc.
local function isPhysicalSwitch(idx, name)
    return idx > 0 and name ~= nil and string.match(name, "^S%u") ~= nil
end

local function startDetect(item)
    detectPrev = {}
    for idx, name in switches() do
        if isPhysicalSwitch(idx, name) then
            detectPrev[idx] = getSwitchValue(idx)
        end
    end
    detectedId = nil
    detectItem = item
end

-- Track the most recent position that turned on; clear it if it turns back off
local function pollDetect()
    for idx, was in pairs(detectPrev) do
        local now = getSwitchValue(idx)
        if now and not was then detectedId = idx end
        detectPrev[idx] = now
    end
    if detectedId and not detectPrev[detectedId] then detectedId = nil end
end

-- Mix sources use source indices, which differ from switch indices
local function logicalSwitchSource(ls_idx)
    local info = getFieldInfo("ls" .. (ls_idx + 1))
    if info then return info.id end
    return getSourceIndex(string.format("L%02d", ls_idx + 1))
end

local function writeChirp()
    local free_lss = findFreeLogicalSwitches(4)
    local free_curves = findFreeCurves(4)

    if not free_lss or not free_curves then
        errorMessage = "Error: Need 4 free LS & 4 free Curves!"
        return false
    end

    -- Trigger and safety switch positions, chosen via detection
    local trigger_sw_id = menuItems[1].swId
    local safety_sw_id = menuItems[2].swId
    local weight = menuItems[3].val

    if not trigger_sw_id or not safety_sw_id then
        errorMessage = "Error: Detect Chirp & Safety switches!"
        return false
    end

    -- 1. Setup the 4 custom 17-point smoothed curves (Sc1 - Sc4) [8]
    local sc1_y = {0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0}
    local sc1_x = {-100, -74, -53, -34, -17, -3, 10, 23, 34, 44, 53, 62, 71, 79, 86, 93, 100}

    local sc2_y = {0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0}
    local sc2_x = {-100, -84, -68, -53, -38, -25, -11, 2, 14, 26, 38, 49, 60, 70, 80, 90, 100}

    local sc3_y = {0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0}
    local sc3_x = {-100, -85, -71, -57, -43, -29, -16, -4, 9, 21, 33, 45, 56, 68, 79, 89, 100}

    local sc4_y = {0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0, 100, 0, -100, 0}
    local sc4_x = {-100, -86, -72, -58, -45, -32, -19, -6, 7, 19, 31, 43, 55, 66, 78, 89, 100}

    local curves = {
        { "Sc1", sc1_x, sc1_y }, { "Sc2", sc2_x, sc2_y },
        { "Sc3", sc3_x, sc3_y }, { "Sc4", sc4_x, sc4_y },
    }
    for i, c in ipairs(curves) do
        local rc = model.setCurve(free_curves[i], { name = c[1], type = 1, smooth = true, x = c[2], y = c[3] })
        if rc and rc ~= 0 then
            errorMessage = "Error: Curve " .. c[1] .. " write failed (code " .. rc .. ")"
            return false
        end
    end

    -- 2. Setup Logical Switches (L01 - L04) [7, 16]
    local ls1_idx, ls2_idx, ls3_idx, ls4_idx = free_lss[1], free_lss[2], free_lss[3], free_lss[4]
    local l1_name = string.format("L%02d", ls1_idx + 1)
    local l3_name = string.format("L%02d", ls3_idx + 1)

    local not_l01_id = getSwitchIndex("!" .. l1_name) or getSwitchIndex("!" .. string.format("L%d", ls1_idx + 1))
    local l03_id = getSwitchIndex(l3_name) or getSwitchIndex(string.format("L%d", ls3_idx + 1))

    -- Resolve LS sources for Mix page mapping [17]
    local ls2_src_id = logicalSwitchSource(ls2_idx)
    local ls4_src_id = logicalSwitchSource(ls4_idx)

    if not (not_l01_id and l03_id and ls2_src_id and ls4_src_id) then
        errorMessage = "Error constructing Logical triggers!"
        return false
    end

    -- L01: Repeat Latch
    model.setLogicalSwitch(ls1_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, delay = 25 })
    -- L02: Roll Enable (Triggers WP1-4 mixes) [9]
    model.setLogicalSwitch(ls2_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, ["and"] = safety_sw_id })
    -- L03: Phase Shift Delay
    model.setLogicalSwitch(ls3_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, delay = 13, duration = 1 })
    -- L04: Pitch Enable (Triggers HP1-4 mixes) [9, 10]
    model.setLogicalSwitch(ls4_idx, { func = LS_FUNC_AND, v1 = 0, v2 = l03_id, ["and"] = safety_sw_id, duration = 24 })

    -- 3. Write Mixer lines (Roll CH1 & Pitch CH2) in ADD mode [9, 10]
    local mix_plans = {
        { curve = free_curves[1], name = "WR1", delay = 0, slow = 13 },
        { curve = free_curves[2], name = "WR2", delay = 13, slow = 5 },
        { curve = free_curves[3], name = "WR3", delay = 18, slow = 3 },
        { curve = free_curves[4], name = "WR4", delay = 21, slow = 2 }
    }

    for _, mix in ipairs(mix_plans) do
        -- Roll Mixes (CH1) [9]
        local ch1_cnt = model.getMixesCount(0)
        model.insertMix(0, ch1_cnt, {
            name = mix.name,
            source = ls2_src_id,
            weight = math.floor(weight * 10.24),
            curveType = 3, -- Custom curve (0=diff, 1=expo, 2=func, 3=custom)
            curveValue = mix.curve + 1, -- custom curve refs are 1-based
            multiplex = 0, -- ADD
            delayUp = mix.delay,
            speedUp = mix.slow
        })
        -- Pitch Mixes (CH2) [9, 10]
        local ch2_cnt = model.getMixesCount(1)
        model.insertMix(1, ch2_cnt, {
            name = "WP" .. string.sub(mix.name, 3),
            source = ls4_src_id,
            weight = math.floor(weight * 10.24),
            curveType = 3, -- Custom curve (0=diff, 1=expo, 2=func, 3=custom)
            curveValue = mix.curve + 1, -- custom curve refs are 1-based
            multiplex = 0, -- ADD
            delayUp = mix.delay,
            speedUp = mix.slow
        })
    end
    return true
end

local function run(event)
    local w, h = LCD_W, LCD_H
    local isColor = (w > 220)
    lcd.clear()

    if showSuccess then
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, h, BLUE)
            lcd.drawText(w/2 - 160, h/2 - 30, "Wood2026 Chirp Wizard", DBLSIZE + WHITE)
            lcd.drawText(w/2 - 120, h/2 + 10, "SUCCESSFULLY APPENDED!", MIDSIZE + YELLOW)
            lcd.drawText(w/2 - 100, h/2 + 40, "Press any key to exit.", SMLSIZE + WHITE)
        else
            lcd.drawText(w/2 - 40, 10, "SUCCESS!", DBLSIZE)
            lcd.drawText(w/2 - 50, 30, "Chirp cleanly appended", SMLSIZE)
            lcd.drawText(w/2 - 40, 48, "Press key to exit.", INVERS + SMLSIZE)
        end
        if event ~= 0 then return 1 end
        return 0
    end

    if errorMessage then
        lcd.drawText(20, 50, errorMessage, isColor and (MIDSIZE + RED) or INVERS)
        if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
        return 0
    end

    if detectItem then
        pollDetect()
        if event == EVT_VIRTUAL_ENTER and detectedId then
            detectItem.swId = detectedId
            detectItem.swName = getSwitchName(detectedId)
            detectItem = nil
            return 0
        elseif event == EVT_VIRTUAL_EXIT then
            detectItem = nil
            return 0
        end

        local found = detectedId and getSwitchName(detectedId) or "waiting..."
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
            lcd.drawText(20, 10, "Detect " .. detectItem.label, DBLSIZE + WHITE)
            lcd.drawText(20, 70, "Flip the switch to the position", MIDSIZE + WHITE)
            lcd.drawText(20, 100, "that should ACTIVATE it.", MIDSIZE + WHITE)
            lcd.drawText(20, 145, "Detected: " .. found, DBLSIZE + YELLOW)
            lcd.drawText(20, 210, "ENTER = confirm   EXIT = cancel", SMLSIZE + WHITE)
        else
            lcd.drawText(5, 0, "Detect " .. detectItem.label, SMLSIZE)
            lcd.drawLine(0, 7, w, 7, SOLID, 0)
            lcd.drawText(5, 12, "Flip switch to the", SMLSIZE)
            lcd.drawText(5, 20, "ACTIVATE position.", SMLSIZE)
            lcd.drawText(5, 32, "Got: " .. found, MIDSIZE)
            lcd.drawText(5, 54, "ENT=ok  EXIT=cancel", SMLSIZE)
        end
        return 0
    end

    -- Handle Navigation
    if not editing then
        if event == EVT_VIRTUAL_NEXT then
            selected = selected + 1
            if selected > #menuItems then selected = 1 end
        elseif event == EVT_VIRTUAL_PREV then
            selected = selected - 1
            if selected < 1 then selected = #menuItems end
        elseif event == EVT_VIRTUAL_ENTER then
            if menuItems[selected].isButton then
                if writeChirp() then showSuccess = true end
            elseif menuItems[selected].isDetect then
                startDetect(menuItems[selected])
            else
                editing = true
            end
        elseif event == EVT_VIRTUAL_EXIT then
            return 1
        end
    else
        local item = menuItems[selected]
        if event == EVT_VIRTUAL_NEXT then
            item.val = item.val + item.step
            if item.val > item.max then item.val = item.max end
        elseif event == EVT_VIRTUAL_PREV then
            item.val = item.val - item.step
            if item.val < item.min then item.val = item.min end
        elseif event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then
            editing = false
        end
    end

    -- Draw Responsive Layout
    local leftAlign = isColor and 40 or 5
    local rightAlign = isColor and 280 or 85
    local startY = isColor and 60 or 10
    local stepY = isColor and 32 or 8

    if isColor then
        lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
        lcd.drawText(20, 10, "UAV Chirp Setup Wizard", DBLSIZE + WHITE)
    else
        lcd.drawText(5, 0, "Chirp Setup Wizard", SMLSIZE)
        lcd.drawLine(0, 7, w, 7, SOLID, 0)
    end

    for i = 1, #menuItems do
        local y = startY + (i - 1) * stepY
        local item = menuItems[i]
        local textFlag = isColor and (MIDSIZE + WHITE) or SMLSIZE
        local valFlag = isColor and (MIDSIZE + YELLOW) or SMLSIZE

        if i == selected then
            if isColor then
                lcd.drawFilledRectangle(leftAlign - 10, y - 4, w - (leftAlign * 2) + 20, stepY - 2, BLUE)
                if editing then valFlag = MIDSIZE + RED end
            else
                textFlag = SMLSIZE + INVERS
                valFlag = SMLSIZE + INVERS
                if editing then valFlag = SMLSIZE + INVERS + BLINK end
            end
        end

        if item.isButton then
            if isColor then
                lcd.drawFilledRectangle(leftAlign + 40, y, 200, stepY - 4, RED)
                lcd.drawText(leftAlign + 90, y + 4, item.label, MIDSIZE + WHITE)
            else
                lcd.drawText(w/2 - 35, y, " [ " .. item.label .. " ]", textFlag)
            end
        else
            lcd.drawText(leftAlign, y, item.label, textFlag)
            local valText = item.isDetect and (item.swName or "[ENTER]") or item.display(item.val)
            lcd.drawText(rightAlign, y, valText, valFlag)
        end
    end

    return 0
end

return { run = run, init = init }
