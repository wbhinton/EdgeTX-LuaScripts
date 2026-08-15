-- toolName = Chirp Setup Wizard
-- Dynamically configures Wood2026's repeating log-sine chirp setpoint.
-- Non-destructive: scans, appends, and links LS, Curves, and Mixes.

local menuItems = {
    { label = "Chirp Switch", val = 1, min = 1, max = 3, step = 1, display = function(v) return v == 1 and "sc↑" or (v == 2 and "sd↓" or "sf↓") end },
    { label = "Safety Switch", val = 1, min = 1, max = 3, step = 1, display = function(v) return v == 1 and "sb-" or (v == 2 and "sc-" or "sa-") end },
    { label = "Chirp Weight", val = 23, min = 5, max = 40, step = 1, display = function(v) return v .. "%" end },
    { label = "WRITE CHIRP", isButton = true }
}

local selected = 1
local editing = false
local showSuccess = false
local errorMessage = nil

local function init()
end

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

local function writeChirp()
    local free_lss = findFreeLogicalSwitches(4)
    local free_curves = findFreeCurves(4)

    if not free_lss or not free_curves then
        errorMessage = "Error: Need 4 free LS & 4 free Curves!"
        return false
    end

    local sw_opts = { "sc↑", "sd↓", "sf↓" }
    local safe_opts = { "sb-", "sc-", "sa-" }
    
    local trigger_sw_id = getSwitchIndex(sw_opts[menuItems[1].val])
    local safety_sw_id = getSwitchIndex(safe_opts[menuItems[2].val])
    local weight = menuItems[3].val

    if not trigger_sw_id or not safety_sw_id then
        errorMessage = "Error: Selected switches not found!"
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

    model.setCurve(free_curves[1], { name = "Sc1", type = 1, smooth = true, x = sc1_x, y = sc1_y })
    model.setCurve(free_curves[2], { name = "Sc2", type = 1, smooth = true, x = sc2_x, y = sc2_y })
    model.setCurve(free_curves[3], { name = "Sc3", type = 1, smooth = true, x = sc3_x, y = sc3_y })
    model.setCurve(free_curves[4], { name = "Sc4", type = 1, smooth = true, x = sc4_x, y = sc4_y })

    -- 2. Setup Logical Switches (L01 - L04) [7, 16]
    local ls1_idx, ls2_idx, ls3_idx, ls4_idx = free_lss[1], free_lss[2], free_lss[3], free_lss[4]
    local l1_name = string.format("L%02d", ls1_idx + 1)
    local l3_name = string.format("L%02d", ls3_idx + 1)

    local not_l01_id = getSwitchIndex("!" .. l1_name) or getSwitchIndex("!" .. string.format("L%d", ls1_idx + 1))
    local l03_id = getSwitchIndex(l3_name) or getSwitchIndex(string.format("L%d", ls3_idx + 1))

    -- L01: Repeat Latch
    model.setLogicalSwitch(ls1_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, delay = 25 })
    -- L02: Roll Enable (Triggers WP1-4 mixes) [9]
    model.setLogicalSwitch(ls2_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, ["and"] = safety_sw_id })
    -- L03: Phase Shift Delay
    model.setLogicalSwitch(ls3_idx, { func = LS_FUNC_AND, v1 = trigger_sw_id, v2 = not_l01_id, delay = 13, duration = 1 })
    -- L04: Pitch Enable (Triggers HP1-4 mixes) [9, 10]
    model.setLogicalSwitch(ls4_idx, { func = LS_FUNC_AND, v1 = 0, v2 = l03_id, ["and"] = safety_sw_id, duration = 24 })

    -- Resolve LS triggers for Mix page mapping [17]
    local ls2_sw_id = getSwitchIndex(string.format("L%02d", ls2_idx + 1)) or getSwitchIndex(string.format("L%d", ls2_idx + 1))
    local ls4_sw_id = getSwitchIndex(string.format("L%02d", ls4_idx + 1)) or getSwitchIndex(string.format("L%d", ls4_idx + 1))

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
            source = ls2_sw_id,
            weight = math.floor(weight * 10.24),
            curveType = 2,
            curveValue = mix.curve,
            multiplex = 0, -- ADD
            delayUp = mix.delay,
            speedUp = mix.slow
        })
        -- Pitch Mixes (CH2) [9, 10]
        local ch2_cnt = model.getMixesCount(1)
        model.insertMix(1, ch2_cnt, {
            name = "WP" .. string.sub(mix.name, 3),
            source = ls4_sw_id,
            weight = math.floor(weight * 10.24),
            curveType = 2,
            curveValue = mix.curve,
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
            lcd.drawText(rightAlign, y, item.display(item.val), valFlag)
        end
    end

    return 0
end

return { run = run, init = init }
