-- toolName = Trainer Auto-Setup
-- Non-destructive Trainer setup script that scans and appends.

local function init()
end

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

local function run(event)
    lcd.clear()
    local w, h = LCD_W, LCD_H
    local isColor = (w > 220)
    
    local titleFlags = isColor and (MIDSIZE + WHITE) or SMLSIZE
    local bodyFlags = isColor and (MIDSIZE + YELLOW) or SMLSIZE

    if isColor then
        lcd.drawFilledRectangle(0, 0, w, 45, DARKBLUE)
        lcd.drawText(20, 10, "Trainer Dynamic Wizard", DBLSIZE + WHITE)
    else
        lcd.drawText(5, 0, "Trainer Dyn Setup", SMLSIZE)
        lcd.drawLine(0, 7, w, 7, SOLID, 0)
    end

    lcd.drawText(15, isColor and 60 or 15, "Press [ENTER] to append trainer config.", bodyFlags)
    lcd.drawText(15, isColor and 90 or 30, "Uses Throttle Trim (Trm3) as toggle.", SMLSIZE)
    lcd.drawText(15, isColor and 110 or 42, "Will NOT overwrite existing switches.", SMLSIZE)

    if event == EVT_VIRTUAL_ENTER then
        lcd.clear()
        
        local free_lss = findFreeLogicalSwitches(4)
        local free_sfs = findFreeSpecialFunctions(2)

        if not free_lss or not free_sfs then
            lcd.drawText(10, 30, "Error: Not enough free LS or SF slots!", bodyFlags)
            return 0
        end

        local ail_stick = getSourceIndex("Ail")
        local ele_stick = getSourceIndex("Ele")
        local toggle_sw_id = getSwitchIndex("trm3+") or getSwitchIndex("trm5+")
        
        if not (ail_stick and ele_stick and toggle_sw_id) then
            lcd.drawText(10, 30, "Error: Standard sticks or trim not found!", bodyFlags)
            return 0
        end

        -- Map out our sequential empty logical switches
        local l1_idx = free_lss[9]
        local l2_idx = free_lss[10]
        local l3_idx = free_lss[11]
        local l4_idx = free_lss[12]

        -- L_A (L1): |a|>x on Aileron
        model.setLogicalSwitch(l1_idx, { func = LS_FUNC_APOS, v1 = ail_stick, v2 = 10, delay = 0 })

        -- L_B (L2): |a|>x on Elevator
        model.setLogicalSwitch(l2_idx, { func = LS_FUNC_APOS, v1 = ele_stick, v2 = 10, delay = 0 })

        -- Resolve L1 and L2 names to system IDs to build the OR switch
        local l1_name = string.format("L%02d", l1_idx + 1)
        local l1_sw_id = getSwitchIndex(l1_name) or getSwitchIndex(string.format("L%d", l1_idx + 1))
        
        local l2_name = string.format("L%02d", l2_idx + 1)
        local l2_sw_id = getSwitchIndex(l2_name) or getSwitchIndex(string.format("L%d", l2_idx + 1))

        -- L_C (L3): L_A OR L_B
        model.setLogicalSwitch(l3_idx, { func = LS_FUNC_OR, v1 = l1_sw_id, v2 = l2_sw_id, delay = 0 })

        -- Resolve L3 name to feed into L_D (L4) Sticky Switch
        local l3_name = string.format("L%02d", l3_idx + 1)
        local l3_sw_id = getSwitchIndex(l3_name) or getSwitchIndex(string.format("L%d", l3_idx + 1))

        -- L_D (L4): Sticky toggled by Trim, cut by Instructor Stick (L3)
        model.setLogicalSwitch(l4_idx, { func = LS_FUNC_STICKY, v1 = toggle_sw_id, v2 = l3_sw_id, delay = 0 })

        -- Resolve L4 (Master Active) and !L4 (Instructor Active)
        local l4_name = string.format("L%02d", l4_idx + 1)
        local l4_sw_id = getSwitchIndex(l4_name) or getSwitchIndex(string.format("L%d", l4_idx + 1))
        
        local not_l4_name = "!" .. l4_name
        local not_l4_sw_id = getSwitchIndex(not_l4_name) or getSwitchIndex("!" .. string.format("L%d", l4_idx + 1))

        if l4_sw_id and not_l4_sw_id then
            -- SF_A: Play "trnon"
            model.setCustomFunction(free_sfs[9], {
                switch = l4_sw_id,
                func = FUNC_PLAY_TRACK,
                name = "trnon",
                active = 1
            })
            -- SF_B: Play "trnoff"
            model.setCustomFunction(free_sfs[10], {
                switch = not_l4_sw_id,
                func = FUNC_PLAY_TRACK,
                name = "trnoff",
                active = 1
            })
        end

        -- Update Mixer Overrides
        local tr_inputs = { 
            { ch = 0, tr_ch = "TR2" }, -- Aileron
            { ch = 1, tr_ch = "TR3" }, -- Elevator
            { ch = 2, tr_ch = "TR1" }, -- Throttle
            { ch = 3, tr_ch = "TR4" }  -- Rudder
        }
        
        for _, mix in ipairs(tr_inputs) do
            local inst_mix = model.getMix(mix.ch, 0)
            if inst_mix then
                inst_mix.switch = not_l4_sw_id
                model.insertMix(mix.ch, 0, inst_mix) -- Restrict instructor to !L4
            end
            
            local student_mix_src = getSourceIndex(mix.tr_ch)
            if student_mix_src then
                model.insertMix(mix.ch, 1, {
                    name = "Studnt",
                    source = student_mix_src,
                    weight = 100,
                    switch = l4_sw_id,
                    multiplex = 2 -- REPLACE mode
                })
            end
        end

        lcd.clear()
        lcd.drawText(15, 30, "Trainer Setup Appended!", MIDSIZE)
        lcd.drawText(15, 45, "Press any key to exit.", SMLSIZE)
        return 1
    end

    if event == EVT_VIRTUAL_EXIT then return 1 end
    return 0
end

return { run = run, init = init }
