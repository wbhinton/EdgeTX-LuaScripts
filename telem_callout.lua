-- toolName = Telemetry Callout Setup
-- A clean, unified telemetry callout setup script for EdgeTX 2.11+
-- Fully compatible with TX16S, Boxer, Zorro, and Pocket.

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

local function init()
end

-- Write settings directly into model configuration
local function writeSettings()
    -- Resolve dynamic telemetry source indexes for the connected receiver
    local rxbt_id = getSourceIndex("RxBt")
    local rqly_id = getSourceIndex("Rqly") or getSourceIndex("RQly")
    local rssi_id = getSourceIndex("1RSS") or getSourceIndex("RSSI")
    local rsnr_id = getSourceIndex("RSNR")
    local tpwr_id = getSourceIndex("TPWR")

    local cells_val = menuItems[8].val
    local low_cell_val = menuItems[9].val
    local rqly_val = menuItems[10].val
    local rssi_val = menuItems[11].val
    local rsnr_val = menuItems[12].val
    local repeat_val = menuItems[13].val

    -- Calculate total voltage threshold or use single cell threshold
    local total_voltage_scaled
    if cells_val == 0 then
        total_voltage_scaled = math.floor(low_cell_val / 10) -- e.g., 3.5V -> 35
    else
        total_voltage_scaled = math.floor((low_cell_val * cells_val) / 10) -- e.g., 4S * 3.5V = 14.0V -> 140
    end

    -- Program Logical Switch triggers (UAVTech standard: L05-L09)
    -- L05: RSSI (1RSS) Alarm
    if rssi_id then
        model.setLogicalSwitch(4, {
            func = LS_FUNC_VNEG,
            v1 = rssi_id,
            v2 = rssi_val,
            delay = 10 -- 1.0s delay
        })
    end

    -- L06: RSNR Alarm
    if rsnr_id then
        model.setLogicalSwitch(5, {
            func = LS_FUNC_VNEG,
            v1 = rsnr_id,
            v2 = rsnr_val,
            delay = 30 -- 3.0s delay
        })
    end

    -- L07: Rqly Link Quality Alarm
    if rqly_id then
        model.setLogicalSwitch(6, {
            func = LS_FUNC_VNEG,
            v1 = rqly_id,
            v2 = rqly_val,
            delay = 5 -- 0.5s delay
        })
    end

    -- L08: Battery (RxBt) Alarm
    if rxbt_id then
        model.setLogicalSwitch(7, {
            func = LS_FUNC_VNEG,
            v1 = rxbt_id,
            v2 = total_voltage_scaled,
            delay = 30 -- 3.0s delay
        })
    end

    -- L09: Dynamic Power Step Change Alarm
    if tpwr_id then
        model.setLogicalSwitch(8, {
            func = LS_FUNC_DIFFEGREATER,
            v1 = tpwr_id,
            v2 = 1, -- trigger on changes > 1mW
            delay = 0,
            duration = 0
        })
    end

    -- Helper to link Logical Switch trigger to Custom/Special function
    local function setCalloutSF(sf_idx, sw_num, sensor_id, rep_seconds)
        -- Support both Boxer (L05) and Zorro (L5) naming variants
        local name1 = string.format("L%02d", sw_num)
        local name2 = string.format("L%d", sw_num)
        local trigger = getSwitchIndex(name1) or getSwitchIndex(name2)
        if trigger and sensor_id then
            model.setCustomFunction(sf_idx, {
                switch = trigger,
                func = FUNC_PLAY_VALUE,
                value = sensor_id,
                param = rep_seconds,
                active = 1
            })
        end
    end

    -- Apply Special Functions (SF5-SF9)
    if rssi_id then setCalloutSF(4, 5, rssi_id, repeat_val) end
    if rsnr_id then setCalloutSF(5, 6, rsnr_id, repeat_val) end
    if rqly_id then setCalloutSF(6, 7, rqly_id, repeat_val) end
    if rxbt_id then setCalloutSF(7, 8, rxbt_id, repeat_val) end
    if tpwr_id then setCalloutSF(8, 9, tpwr_id, 0) end -- 0 means play once
end

local function run(event)
    local w = LCD_W
    local h = LCD_H
    local isColor = (w > 220) -- Identify screen type color vs. B&W

    lcd.clear()

    -- Process success screen exit
    if showSuccess then
        if isColor then
            lcd.drawFilledRectangle(0, 0, w, h, BLUE)
            lcd.drawText(w/2 - 160, h/2 - 30, "UAVTech Setup Wizard", DBLSIZE + WHITE)
            lcd.drawText(w/2 - 120, h/2 + 10, "SUCCESSFULLY PROGRAMMED!", MIDSIZE + YELLOW)
            lcd.drawText(w/2 - 100, h/2 + 40, "Press any key to exit.", SMLSIZE + WHITE)
        else
            lcd.drawText(w/2 - 40, 10, "SUCCESS!", DBLSIZE)
            lcd.drawText(w/2 - 50, 30, "LS05-09 & SF05-09 Set", SMLSIZE)
            lcd.drawText(w/2 - 40, 48, "Press key to exit.", INVERS + SMLSIZE)
        end
        if event ~= 0 then
            return 1 -- Terminate script cleanly
        end
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
                writeSettings()
                showSuccess = true
            else
                editing = true
            end
        elseif event == EVT_VIRTUAL_EXIT then
            return 1 -- Exit script
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

    -- Draw UI Layout (Responsive based on screen metrics)
    local titleOffset = isColor and 15 or 0
    local leftAlign = isColor and 40 or 5
    local rightAlign = isColor and 280 or 85
    local startY = isColor and 60 or 10
    local stepY = isColor and 32 or 8

    -- Header Title
    if isColor then
        lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
        lcd.drawText(20, 10, "UAVTech Telemetry Setup", DBLSIZE + WHITE)
    else
        lcd.drawText(5, 0, "UAVTech Telem Setup", SMLSIZE)
        lcd.drawLine(0, 7, w, 7, SOLID, 0)
    end

    -- Draw Menu Items
    for i = 1, #menuItems do
        local y = startY + (i - 1) * stepY
        local item = menuItems[i]

        -- Construct selection styles
        local textFlag = isColor and (MIDSIZE + WHITE) or SMLSIZE
        local valFlag = isColor and (MIDSIZE + YELLOW) or SMLSIZE

        if i == selected then
            if isColor then
                lcd.drawFilledRectangle(leftAlign - 10, y - 4, w - (leftAlign * 2) + 20, stepY - 2, BLUE)
                textFlag = MIDSIZE + WHITE
                valFlag = MIDSIZE + YELLOW
                if editing then valFlag = MIDSIZE + RED end
            else
                textFlag = SMLSIZE + INVERS
                valFlag = SMLSIZE + INVERS
                if editing then valFlag = SMLSIZE + INVERS + BLINK end
            end
        end

        -- Render Line content
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
