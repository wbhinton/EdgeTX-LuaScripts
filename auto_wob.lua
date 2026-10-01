-- toolName = Auto Wobble Setup
-- Dynamically configures the PID Toolbox infinite wobble controller.
-- Non-destructive: appends free logical switches, curves, and mixes.

local menuItems = {
    { label = "Wobble Switch", isDetect = true, swId = nil, swName = nil },
    { label = "Wobble Weight", val = 50, min = 10, max = 100, step = 5, display = function(v) return v .. "%" end },
    { label = "WRITE WOBBLE", isButton = true }
}

local selected = 1
local editing = false
local showSuccess = false
local errorMessage = nil

-- Switch detection state
local detecting = false
local detectPrev = {}
local detectedId = nil

local function init()
end

-- Find free Logical Switch slots
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

-- Find free Curve slots
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

local function startDetect()
    detectPrev = {}
    for idx, name in switches() do
        if isPhysicalSwitch(idx, name) then
            detectPrev[idx] = getSwitchValue(idx)
        end
    end
    detectedId = nil
    detecting = true
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

local function writeWobble()
    -- Scan for safe slots
    local free_lss = findFreeLogicalSwitches(2)
    local free_curves = findFreeCurves(4)

    if not free_lss or not free_curves then
        errorMessage = "Error: Need 2 free LS & 4 free Curves!"
        return false
    end

    -- Physical toggle trigger switch, chosen via detection
    local sw_trigger_id = menuItems[1].swId

    if not sw_trigger_id then
        errorMessage = "Error: Detect a Wobble Switch first!"
        return false
    end

    local weight = menuItems[2].val

    -- 1. Setup the 4 custom 17-point Standard curves (R1, R2, P1, P2)
    local r1_idx, r2_idx, p1_idx, p2_idx = free_curves[1], free_curves[2], free_curves[3], free_curves[4]

    -- Curve arrays (Standard spaced in time, smoothing on)
    local r1_y = {0, 0, 0, 0, 0, weight, 0, -weight, 0, weight, 0, -weight, 0, weight, 0, -weight, 0}
    local r2_y = {0, 0, 0, 0, 0, -weight, 0, weight, 0, -weight, 0, weight, 0, -weight, 0, weight, 0}
    local p1_y = {0, weight, 0, -weight, 0, weight, 0, -weight, 0, 0, 0, 0, 0, -weight, 0, weight, 0}
    local p2_y = {0, -weight, 0, weight, 0, -weight, 0, weight, 0, 0, 0, 0, 0, weight, 0, -weight, 0}

    local curves = {
        { r1_idx, "R1", r1_y }, { r2_idx, "R2", r2_y },
        { p1_idx, "P1", p1_y }, { p2_idx, "P2", p2_y },
    }
    for _, c in ipairs(curves) do
        local rc = model.setCurve(c[1], { name = c[2], type = 0, smooth = true, y = c[3] })
        if rc and rc ~= 0 then
            errorMessage = "Error: Curve " .. c[2] .. " write failed (code " .. rc .. ")"
            return false
        end
    end

    -- 2. Setup Logical Switches
    local ls1_idx, ls2_idx = free_lss[1], free_lss[2]
    local ls1_name = string.format("L%02d", ls1_idx + 1)

    -- Resolve negative trigger targets
    local not_ls1_sw_id = getSwitchIndex("!" .. ls1_name) or getSwitchIndex("!" .. string.format("L%d", ls1_idx + 1))

    local ls2_src_id = logicalSwitchSource(ls2_idx)

    if not (not_ls1_sw_id and ls2_src_id) then
        errorMessage = "Error constructing Logical triggers!"
        return false
    end

    -- LS1: AND (Switch down, !LS1), Delay 3s (keeps loop running)
    model.setLogicalSwitch(ls1_idx, {
        func = LS_FUNC_AND,
        v1 = sw_trigger_id,
        v2 = not_ls1_sw_id,
        delay = 30 -- 3.0 seconds
    })

    -- LS2: AND (Switch down, !LS1)
    model.setLogicalSwitch(ls2_idx, {
        func = LS_FUNC_AND,
        v1 = sw_trigger_id,
        v2 = not_ls1_sw_id,
        delay = 0
    })

    -- 3. Write Mixer lines (ADD mode to preserve user control)
    -- CH1: Roll (Aileron) mixes
    local ch1_count = model.getMixesCount(0)
    model.insertMix(0, ch1_count, {
        name = "WobR1",
        source = ls2_src_id,
        weight = 1024,
        curveType = 3, -- Custom curve (0=diff, 1=expo, 2=func, 3=custom)
        curveValue = r1_idx + 1, -- custom curve refs are 1-based
        multiplex = 0, -- ADD
        speedUp = 15 -- 1.5s slow up
    })
    model.insertMix(0, ch1_count + 1, {
        name = "WobR2",
        source = ls2_src_id,
        weight = 1024,
        curveType = 3,
        curveValue = r2_idx + 1, -- custom curve refs are 1-based
        multiplex = 0, -- ADD
        speedUp = 15, -- 1.5s slow up
        delayUp = 15 -- 1.5s delay up
    })

    -- CH2: Pitch (Elevator) mixes
    local ch2_count = model.getMixesCount(1)
    model.insertMix(1, ch2_count, {
        name = "WobP1",
        source = ls2_src_id,
        weight = 1024,
        curveType = 3,
        curveValue = p1_idx + 1, -- custom curve refs are 1-based
        multiplex = 0, -- ADD
        speedUp = 15 -- 1.5s slow up
    })
    model.insertMix(1, ch2_count + 1, {
        name = "WobP2",
        source = ls2_src_id,
        weight = 1024,
        curveType = 3,
        curveValue = p2_idx + 1, -- custom curve refs are 1-based
        multiplex = 0, -- ADD
        speedUp = 15, -- 1.5s slow up
        delayUp = 15 -- 1.5s delay up
    })

    return true
end

local function run(event)
    local w, h = LCD_W, LCD_H
    local isColor = (w > 220)

    lcd.clear()

    if showSuccess then
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, h, BLUE)
            lcd.drawText(w/2 - 160, h/2 - 30, "Auto Wobble Setup Wizard", DBLSIZE + WHITE)
            lcd.drawText(w/2 - 120, h/2 + 10, "SUCCESSFULLY APPENDED!", MIDSIZE + YELLOW)
            lcd.drawText(w/2 - 100, h/2 + 40, "Press any key to exit.", SMLSIZE + WHITE)
        else
            lcd.drawText(w/2 - 40, 10, "SUCCESS!", DBLSIZE)
            lcd.drawText(w/2 - 50, 30, "Wobble cleanly appended", SMLSIZE)
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

    if detecting then
        pollDetect()
        if event == EVT_VIRTUAL_ENTER and detectedId then
            menuItems[1].swId = detectedId
            menuItems[1].swName = getSwitchName(detectedId)
            detecting = false
        elseif event == EVT_VIRTUAL_EXIT then
            detecting = false
        end

        local found = detectedId and getSwitchName(detectedId) or "waiting..."
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
            lcd.drawText(20, 10, "Detect Wobble Switch", DBLSIZE + WHITE)
            lcd.drawText(20, 70, "Flip the switch to the position", MIDSIZE + WHITE)
            lcd.drawText(20, 100, "that should ACTIVATE wobble.", MIDSIZE + WHITE)
            lcd.drawText(20, 145, "Detected: " .. found, DBLSIZE + YELLOW)
            lcd.drawText(20, 210, "ENTER = confirm   EXIT = cancel", SMLSIZE + WHITE)
        else
            lcd.drawText(5, 0, "Detect Wobble Switch", SMLSIZE)
            lcd.drawLine(0, 7, w, 7, SOLID, 0)
            lcd.drawText(5, 12, "Flip switch to the", SMLSIZE)
            lcd.drawText(5, 20, "ACTIVATE position.", SMLSIZE)
            lcd.drawText(5, 32, "Got: " .. found, MIDSIZE)
            lcd.drawText(5, 54, "ENT=ok  EXIT=cancel", SMLSIZE)
        end
        return 0
    end

    -- Input Handler
    if not editing then
        if event == EVT_VIRTUAL_NEXT then
            selected = selected + 1
            if selected > #menuItems then selected = 1 end
        elseif event == EVT_VIRTUAL_PREV then
            selected = selected - 1
            if selected < 1 then selected = #menuItems end
        elseif event == EVT_VIRTUAL_ENTER then
            if menuItems[selected].isButton then
                if writeWobble() then showSuccess = true end
            elseif menuItems[selected].isDetect then
                startDetect()
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

    -- UI Drawing Layout
    local leftAlign = isColor and 40 or 5
    local rightAlign = isColor and 280 or 85
    local startY = isColor and 60 or 10
    local stepY = isColor and 32 or 8

    if isColor then
        lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
        lcd.drawText(20, 10, "Auto Wobble Setup Tool", DBLSIZE + WHITE)
    else
        lcd.drawText(5, 0, "Wobble Setup Wizard", SMLSIZE)
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
