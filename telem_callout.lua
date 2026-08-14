-- toolName = Telemetry Callout Setup
-- Unified telemetry setup script that appends settings dynamically.

local menuItems = {
    { label = "Battery Cells", val = 4, min = 0, max = 8, step = 1, display = function(v) return v == 0 and "Avg Cell" or (v .. "S") end },
    { label = "Low Cell Lvl", val = 350, min = 300, max = 420, step = 5, display = function(v) return string.format("%.2fV", v/100) end },
    { label = "Link Quality", val = 50, min = 10, max = 100, step = 5, display = function(v) return v .. "%" end },
    { label = "RSSI (1RSS)",  val = -92, min = -115, max = -40, step = 1, display = function(v) return v .. "dBm" end },
    { label = "RSNR Limit",   val = -5, min = -20, max = 15, step = 1, display = function(v) return v .. "dB" end },
    { label = "Repeat Alarm", val = 20, min = 2, max = 60, step = 2, display = function(v) return v .. "s" end },
    { label = "WRITE SETTINGS", isButton = true }
}

local selected = 1
local editing = false
local showSuccess = false
local errorMessage = nil

local function init()
end

-- Scan model config for 'count' number of unused Logical Switches
local function findFreeLogicalSwitches(count)
    local free_indices = {}
    for i = 0, 63 do
        local ls = model.getLogicalSwitch(i)
        if not ls or ls.func == 0 or ls.func == LS_FUNC_NONE then
            table.insert(free_indices, i)
            if #free_indices == count then
                return free_indices
            end
        end
    end
    return nil
end

-- Scan model config for 'count' number of unused Special Functions
local function findFreeSpecialFunctions(count)
    local free_indices = {}
    for i = 0, 63 do
        local sf = model.getCustomFunction(i)
        if not sf or sf.func == 0 then
            table.insert(free_indices, i)
            if #free_indices == count then
                return free_indices
            end
        end
    end
    return nil
end

local function writeSettings()
    -- Find empty slots dynamically
    local free_lss = findFreeLogicalSwitches(5)
    local free_sfs = findFreeSpecialFunctions(5)

    if not free_lss or not free_sfs then
        errorMessage = "Error: Not enough empty LS/SF slots!"
        return false
    end

    local rxbt_id = getSourceIndex("RxBt")
    local rqly_id = getSourceIndex("Rqly") or getSourceIndex("RQly")
    local rssi_id = getSourceIndex("1RSS") or getSourceIndex("RSSI")
    local rsnr_id = getSourceIndex("RSNR")
    local tpwr_id = getSourceIndex("TPWR")

    local cells_val = menuItems[9].val
    local low_cell_val = menuItems[10].val
    local rqly_val = menuItems[11].val
    local rssi_val = menuItems[12].val
    local rsnr_val = menuItems[13].val
    local repeat_val = menuItems[14].val

    local total_voltage_scaled
    if cells_val == 0 then
        total_voltage_scaled = math.floor(low_cell_val / 10)
    else
        total_voltage_scaled = math.floor((low_cell_val * cells_val) / 10)
    end

    -- Helper to program LS and linked SF dynamically
    local function setupAlert(ls_idx, sf_idx, sensor_id, func_type, threshold, delay, rep_time)
        if not sensor_id then return end

        -- 1. Write logical switch to safe slot
        model.setLogicalSwitch(ls_idx, {
            func = func_type,
            v1 = sensor_id,
            v2 = threshold,
            delay = delay
        })

        -- 2. Resolve remapped switch name to resolve its system switch trigger ID
        local switch_name = string.format("L%02d", ls_idx + 1)
        local trigger = getSwitchIndex(switch_name) or getSwitchIndex(string.format("L%d", ls_idx + 1))
        
        if trigger then
            -- 3. Write Special Function to safe slot
            model.setCustomFunction(sf_idx, {
                switch = trigger,
                func = FUNC_PLAY_VALUE,
                value = sensor_id,
                param = rep_time,
                active = 1
            })
        end
    end

    -- Setup each alert sequentially on the resolved empty slots
    setupAlert(free_lss[9], free_sfs[9], rssi_id, LS_FUNC_VNEG, rssi_val, 10, repeat_val)
    setupAlert(free_lss[10], free_sfs[10], rsnr_id, LS_FUNC_VNEG, rsnr_val, 30, repeat_val)
    setupAlert(free_lss[11], free_sfs[11], rqly_id, LS_FUNC_VNEG, rqly_val, 5, repeat_val)
    setupAlert(free_lss[12], free_sfs[12], rxbt_id, LS_FUNC_VNEG, total_voltage_scaled, 30, repeat_val)
    
    -- Setup Dynamic Power (play once on change)
    if tpwr_id then
        model.setLogicalSwitch(free_lss[13], {
            func = LS_FUNC_DIFFEGREATER,
            v1 = tpwr_id,
            v2 = 1,
            delay = 0
        })
        local switch_name = string.format("L%02d", free_lss[13] + 1)
        local trigger = getSwitchIndex(switch_name) or getSwitchIndex(string.format("L%d", free_lss[13] + 1))
        if trigger then
            model.setCustomFunction(free_sfs[13], {
                switch = trigger,
                func = FUNC_PLAY_VALUE,
                value = tpwr_id,
                param = 0, -- once
                active = 1
            })
        end
    end
    return true
end

local function run(event)
    local w = LCD_W
    local h = LCD_H
    local isColor = (w > 220)

    lcd.clear()

    if showSuccess then
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, h, BLUE)
            lcd.drawText(w/2 - 160, h/2 - 30, "UAVTech Setup Wizard", DBLSIZE + WHITE)
            lcd.drawText(w/2 - 120, h/2 + 10, "SUCCESSFULLY APPENDED!", MIDSIZE + YELLOW)
            lcd.drawText(w/2 - 100, h/2 + 40, "Press any key to exit.", SMLSIZE + WHITE)
        else
            lcd.drawText(w/2 - 40, 10, "SUCCESS!", DBLSIZE)
            lcd.drawText(w/2 - 50, 30, "Alerts cleanly appended", SMLSIZE)
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

    -- Key Event Handling
    if not editing then
        if event == EVT_VIRTUAL_NEXT then
            selected = selected + 1
            if selected > #menuItems then selected = 1 end
        elseif event == EVT_VIRTUAL_PREV then
            selected = selected - 1
            if selected < 1 then selected = #menuItems end
        elseif event == EVT_VIRTUAL_ENTER then
            if menuItems[selected].isButton then
                if writeSettings() then
                    showSuccess = true
                end
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

    -- UI Rendering Layout
    local leftAlign = isColor and 40 or 5
    local rightAlign = isColor and 280 or 85
    local startY = isColor and 60 or 10
    local stepY = isColor and 32 or 8

    if isColor then
        lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
        lcd.drawText(20, 10, "UAVTech Dynamic Setup", DBLSIZE + WHITE)
    else
        lcd.drawText(5, 0, "UAVTech Append Setup", SMLSIZE)
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
