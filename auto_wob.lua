-- toolName = Auto Wobble Setup
-- Dynamically configures the PID Toolbox infinite wobble controller.
-- Non-destructive: appends free logical switches, curves, and mixes.

local menuItems = {
    { label = "Wobble Switch", val = 1, min = 1, max = 3, step = 1, display = function(v) return v == 1 and "sh↓" or (v == 2 and "sf↓" or "sg↓") end },
    { label = "Wobble Weight", val = 50, min = 10, max = 100, step = 5, display = function(v) return v .. "%" end },
    { label = "WRITE WOBBLE", isButton = true }
}

local selected = 1
local editing = false
local showSuccess = false
local errorMessage = nil

local function init()
end

-- Find free Logical Switch slots
local function findFreeLogicalSwitches(count)
    local free_indices = {}
    for i = 0, 63 do
        local ls = model.getLogicalSwitch(i)
        if not ls or ls.func == 0 or ls.func == LS_FUNC_NONE then
            table.insert(free_indices, i)
            if #free_indices == count then return free_indices end
        end
    end
    return nil
end

-- Find free Curve slots
local function findFreeCurves(count)
    local free_indices = {}
    for i = 0, 31 do
        local curve = model.getCurve(i)
        if not curve or curve.name == "" or #curve.y == 0 then
            table.insert(free_indices, i)
            if #free_indices == count then return free_indices end
        end
    end
    return nil
end

local function writeWobble()
    -- Scan for safe slots
    local free_lss = findFreeLogicalSwitches(2)
    local free_curves = findFreeCurves(4)

    if not free_lss or not free_curves then
        errorMessage = "Error: Need 2 free LS & 4 free Curves!"
        return false
    end

    -- Determine physical toggle trigger switch
    local sw_opts = { "sh↓", "sf↓", "sg↓" }
    local trigger_sw_name = sw_opts[menuItems[1].val]
    local sw_trigger_id = getSwitchIndex(trigger_sw_name)

    if not sw_trigger_id then
        errorMessage = "Error: Physical switch " .. trigger_sw_name .. " not found!"
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

    model.setCurve(r1_idx, { name = "R1", type = 0, smooth = true, y = r1_y })
    model.setCurve(r2_idx, { name = "R2", type = 0, smooth = true, y = r2_y })
    model.setCurve(p1_idx, { name = "P1", type = 0, smooth = true, y = p1_y })
    model.setCurve(p2_idx, { name = "P2", type = 0, smooth = true, y = p2_y })

    -- 2. Setup Logical Switches
    local ls1_idx, ls2_idx = free_lss[1], free_lss[2]
    local ls1_name = string.format("L%02d", ls1_idx + 1)
    local ls2_name = string.format("L%02d", ls2_idx + 1)

    -- Resolve negative trigger targets
    local not_ls1_sw_id = getSwitchIndex("!" .. ls1_name) or getSwitchIndex("!" .. string.format("L%d", ls1_idx + 1))
    local ls2_sw_id = getSwitchIndex(ls2_name) or getSwitchIndex(string.format("L%d", ls2_idx + 1))

    if not (not_ls1_sw_id and ls2_sw_id) then
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
        source = ls2_sw_id,
        weight = 1024,
        curveType = 2, -- Custom curve
        curveValue = r1_idx,
        multiplex = 0, -- ADD
        speedUp = 15 -- 1.5s slow up
    })
    model.insertMix(0, ch1_count + 1, {
        name = "WobR2",
        source = ls2_sw_id,
        weight = 1024,
        curveType = 2,
        curveValue = r2_idx,
        multiplex = 0, -- ADD
        speedUp = 15, -- 1.5s slow up
        delayUp = 15 -- 1.5s delay up
    })

    -- CH2: Pitch (Elevator) mixes
    local ch2_count = model.getMixesCount(1)
    model.insertMix(1, ch2_count, {
        name = "WobP1",
        source = ls2_sw_id,
        weight = 1024,
        curveType = 2,
        curveValue = p1_idx,
        multiplex = 0, -- ADD
        speedUp = 15 -- 1.5s slow up
    })
    model.insertMix(1, ch2_count + 1, {
        name = "WobP2",
        source = ls2_sw_id,
        weight = 1024,
        curveType = 2,
        curveValue = p2_idx,
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
            lcd.drawText(rightAlign, y, item.display(item.val), valFlag)
        end
    end

    return 0
end

return { run = run, init = init }
