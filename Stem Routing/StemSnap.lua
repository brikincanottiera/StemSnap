-- @description StemSnap - Drop your stems into the right folder buses automatically — no clicks, no drag.
-- @author Brik in canottiera
-- @version 1.3
-- @changelog
--   1.3 - Added track counter, window position memory
--   1.2 - Added stale rules detection, reset config
--   1.1 - Added welcome screen, settings info panel
--   1.0 - Added direct track pointers, single-word keyword matching
--   0.9 - Added placeholder dropdown for unrecognized tracks
--   0.8 - Added Settings window with custom rules
--   0.7 - Added partial routing confirmation popup
--   0.6 - Added version header, ReaImGui dependency check
-- @provides
--   [main] StemSnap.lua
-- @link
--   GitHub https://github.com/brikincanottiera/StemSnap
-- @about
--   # StemSnap
--   Drop your stems into the right folder buses automatically — no clicks, no drag.
--
--   ## How it works
--   Select your tracks, run the script, confirm the assignments and done.
--   Simple bus names like "Kick Bus" or "Snare Bus" are matched automatically.
--   For compound bus names like "Hi End Perc Bus", add a custom rule in Settings.
--   Custom rules are saved and reused every time you run the script.
--
--   ## Requirements
--   - REAPER 6+
--   - ReaImGui (install via ReaPack)

if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox(
        "This script requires ReaImGui.\nPlease install it via ReaPack:\nExtensions > ReaPack > Browse packages > ReaImGui",
        "Missing dependency", 0)
    return
end

reaper.ClearConsole()

local SCRIPT_VERSION = "v1.3"

local script_path   = reaper.GetResourcePath() .. "/Scripts/AutoFolderRouting_config.json"
local firstrun_path = reaper.GetResourcePath() .. "/Scripts/AutoFolderRouting_firstrun.flag"
local winstate_path = reaper.GetResourcePath() .. "/Scripts/AutoFolderRouting_winstate.json"

local L = {
    select_tracks        = "Please select tracks first.",
    confirm              = "Confirm ✓",
    cancel               = "Cancel",
    new_bus              = "New Bus",
    new_bus_prompt       = "New bus name:",
    create               = "Create",
    track_col            = "Track",
    bus_col              = "Bus",
    lock_tooltip         = "Lock assignment",
    unlock_tooltip       = "Unlock assignment",
    new_bus_tooltip      = "Create new bus",
    confirm_tooltip      = "Some tracks are unassigned - click to review",
    window_title         = "StemSnap",
    keywords_label       = "Bus Keywords:",
    add_keyword          = "Add",
    keyword_hint         = "Custom keyword...",
    locked_col           = "Locked",
    success              = "tracks routed successfully!",
    remove_keyword       = "Remove keyword",
    unassigned_warning   = "The following tracks have no bus assigned:\n\n",
    unassigned_question  = "\nProceed anyway?",
    proceed              = "Proceed",
    settings             = "Settings",
    settings_title       = "Settings - Custom Rules",
    rules_keyword_col    = "Keyword",
    rules_bus_col        = "Bus",
    rules_hint           = "e.g. rimshot",
    close                = "Close",
    add_rule             = "Add Rule",
    remove_rule          = "Remove rule",
    no_rules             = "No custom rules yet. Add one below.",
    select_bus           = "-- Select a bus --",
    welcome_title        = "Welcome to StemSnap",
    got_it               = "Got it!",
    reset_config         = "Reset Config",
    reset_confirm        = "Reset all settings and custom rules?",
    reset_confirm_title  = "Reset Config",
    stale_rules_warning  = "The following custom rules point to buses that no longer exist in the project and have been disabled:\n\n",
    stale_rules_info     = "\nYou can re-add them in Settings once the buses are available again.",
    ok                   = "OK",
}

local WELCOME_TEXT = [[
StemSnap automatically moves your selected tracks
into the correct folder buses based on their names.

HOW AUTOMATIC MATCHING WORKS
─────────────────────────────
Buses whose names contain "bus" or "group" are detected
automatically. The script extracts the first word of the
bus name and uses it as a keyword to match tracks:

  ✓  Kick Bus      →  matches tracks containing "kick"
  ✓  Snare Bus     →  matches tracks containing "snare"
  ✓  808 Bus       →  matches tracks containing "808"
  ✓  Bass Group    →  matches tracks containing "bass"

WHEN DO YOU NEED A CUSTOM RULE?
─────────────────────────────────
Buses with compound names cannot be matched automatically
because the first word alone is too generic:

  ✗  Hi End Perc Bus   →  "hi" matches too many things
  ✗  Riser & Fx Bus    →  "&" breaks the pattern

For these buses, go to ⚙ Settings and add a custom rule:

  "hihat"   →  Hi End Perc Bus
  "open"    →  Hi End Perc Bus
  "riser"   →  Riser & Fx Bus
  "fx"      →  Riser & Fx Bus

Custom rules are saved and reused every time you
run the script, so you only need to set them up once.
]]

local default_keyword_words = {bus=true, group=true}
local default_keywords = {
    {word="bus",   active=true, is_default=true},
    {word="group", active=true, is_default=true},
}

function IsFirstRun()
    local f = io.open(firstrun_path, "r")
    if f then f:close() return false end
    return true
end

function MarkFirstRunDone()
    local f = io.open(firstrun_path, "w")
    if f then f:write("done") f:close() end
end

function LoadWinState()
    local f = io.open(winstate_path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    local x = content:match('"x":([%-?%d]+)')
    local y = content:match('"y":([%-?%d]+)')
    if x and y then return tonumber(x), tonumber(y) end
    return nil
end

function SaveWinState(x, y)
    local f = io.open(winstate_path, "w")
    if not f then return end
    f:write('{"x":' .. math.floor(x) .. ',"y":' .. math.floor(y) .. '}')
    f:close()
end

function LoadConfig()
    local file = io.open(script_path, "r")
    if not file then return default_keywords, {} end
    local content = file:read("*a")
    file:close()

    local kw_result = {}
    for word, active in content:gmatch('"word":"([^"]+)","active":(%a+)') do
        table.insert(kw_result, {
            word       = word,
            active     = (active == "true"),
            is_default = default_keyword_words[word] or false
        })
    end
    if #kw_result == 0 then kw_result = default_keywords end

    local rules_result = {}
    for kw, bus in content:gmatch('"rule_kw":"([^"]+)","rule_bus":"([^"]+)"') do
        table.insert(rules_result, {keyword=kw, bus=bus})
    end

    return kw_result, rules_result
end

function SaveConfig(kws, rules)
    local file = io.open(script_path, "w")
    if not file then return end
    file:write('{"keywords":[')
    for i, kw in ipairs(kws) do
        file:write('{"word":"' .. kw.word .. '","active":' .. tostring(kw.active) .. '}')
        if i < #kws then file:write(',') end
    end
    file:write('],"rules":[')
    for i, rule in ipairs(rules) do
        file:write('{"rule_kw":"' .. rule.keyword .. '","rule_bus":"' .. rule.bus .. '"}')
        if i < #rules then file:write(',') end
    end
    file:write(']}')
    file:close()
end

function ResetConfig()
    local f = io.open(script_path, "w")
    if f then f:write('{"keywords":[],"rules":[]}') f:close() end
end

function ValidateCustomRules(rules)
    local valid = {}
    local stale = {}
    for _, rule in ipairs(rules) do
        local found = false
        for i = 0, reaper.CountTracks(0) - 1 do
            local tr = reaper.GetTrack(0, i)
            local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
            if name == rule.bus then found = true break end
        end
        if found then table.insert(valid, rule)
        else table.insert(stale, rule) end
    end
    return valid, stale
end

local keywords, custom_rules = LoadConfig()
local stale_rules = {}
custom_rules, stale_rules = ValidateCustomRules(custom_rules)

local new_keyword_input  = ""
local new_rule_keyword   = ""
local new_rule_bus_idx   = 0
local show_welcome       = IsFirstRun()
local show_stale_warning = #stale_rules > 0
local show_reset_confirm = false

local saved_win_x, saved_win_y = LoadWinState()
local win_pos_set = false

function GetTrackByName(name)
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, tr_name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if tr_name == name then return tr end
    end
    return nil
end

function BuildBusList()
    local list = {}
    local active_kws = {}
    for _, kw in ipairs(keywords) do
        if kw.active then table.insert(active_kws, kw.word) end
    end
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local _, name = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        local lower = string.lower(name)
        for _, kw in ipairs(active_kws) do
            if string.find(lower, kw, 1, true) then
                table.insert(list, name)
                break
            end
        end
    end
    return list
end

function ExtractSingleWordKeyword(bus_name)
    local lower = string.lower(bus_name)
    local stripped = lower
    for _, kw in ipairs(keywords) do
        stripped = stripped:gsub("%s*" .. kw.word .. "%s*", " ")
    end
    stripped = stripped:gsub("[%&%-%_%+]", " ")
    stripped = stripped:match("^%s*(.-)%s*$")
    if stripped ~= "" and not stripped:match("%s") then
        return stripped
    end
    return nil
end

function BuildRoutingMap(bus_list)
    local map = {}
    for _, rule in ipairs(custom_rules) do
        table.insert(map, {keyword=string.lower(rule.keyword), bus=rule.bus})
    end
    for _, bus_name in ipairs(bus_list) do
        local keyword = ExtractSingleWordKeyword(bus_name)
        if keyword then
            local already_custom = false
            for _, rule in ipairs(custom_rules) do
                if string.lower(rule.keyword) == keyword then
                    already_custom = true break
                end
            end
            if not already_custom then
                table.insert(map, {keyword=keyword, bus=bus_name})
            end
        end
    end
    return map
end

function BuildTrackList(bus_list, routing_map, track_pointers)
    local list = {}
    for _, ptr in ipairs(track_pointers) do
        local _, name = reaper.GetSetMediaTrackInfo_String(ptr, "P_NAME", "", false)
        local lower = string.lower(name)
        local matched_bus = nil
        for _, rule in ipairs(routing_map) do
            if string.find(lower, rule.keyword, 1, true) then
                matched_bus = rule.bus
                break
            end
        end
        local selected_idx = -1
        if matched_bus then
            for i, b in ipairs(bus_list) do
                if b == matched_bus then selected_idx = i - 1 break end
            end
        end
        table.insert(list, {
            name             = name,
            ptr              = ptr,
            assigned_bus     = matched_bus,
            selected_bus_idx = selected_idx,
            locked           = matched_bus ~= nil,
            recognized       = matched_bus ~= nil
        })
    end
    return list
end

function CountAssigned(track_list)
    local count = 0
    for _, item in ipairs(track_list) do
        if item.assigned_bus and item.assigned_bus ~= "" then
            count = count + 1
        end
    end
    return count
end

function MoveUnderBus(track_ptr, bus_ptr)
    local bus_idx = math.floor(reaper.GetMediaTrackInfo_Value(bus_ptr, "IP_TRACKNUMBER")) - 1
    local total   = reaper.CountTracks(0)
    local bus_fd  = reaper.GetMediaTrackInfo_Value(bus_ptr, "I_FOLDERDEPTH")
    local children = {}

    if bus_fd >= 1 then
        local depth = 0
        for i = bus_idx, total - 1 do
            local tr = reaper.GetTrack(0, i)
            local fd = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
            depth = depth + fd
            if i ~= bus_idx then table.insert(children, tr) end
            if depth < 0 then break end
        end
    end

    reaper.Main_OnCommand(40297, 0)
    reaper.SetTrackSelected(track_ptr, true)
    reaper.ReorderSelectedTracks(bus_idx + 1, 0)

    bus_idx = math.floor(reaper.GetMediaTrackInfo_Value(bus_ptr, "IP_TRACKNUMBER")) - 1
    local moved_track = reaper.GetTrack(0, bus_idx + 1)

    if #children == 0 then
        local old_bus_fd = reaper.GetMediaTrackInfo_Value(bus_ptr, "I_FOLDERDEPTH")
        reaper.SetMediaTrackInfo_Value(bus_ptr, "I_FOLDERDEPTH", 1)
        reaper.SetMediaTrackInfo_Value(moved_track, "I_FOLDERDEPTH", old_bus_fd - 1)
    else
        reaper.SetMediaTrackInfo_Value(moved_track, "I_FOLDERDEPTH", 0)
    end

    bus_idx = math.floor(reaper.GetMediaTrackInfo_Value(bus_ptr, "IP_TRACKNUMBER")) - 1
    local depth = 1
    local last_child = nil
    for i = bus_idx + 1, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        local fd = reaper.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH")
        last_child = tr
        depth = depth + fd
        if depth <= 0 then break end
    end
    if last_child then
        local current_fd = reaper.GetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH")
        if current_fd >= 0 then
            reaper.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH", -1)
        end
    end
end

function CreateNewBus(bus_name)
    reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
    local bus = reaper.GetTrack(0, reaper.CountTracks(0) - 1)
    reaper.GetSetMediaTrackInfo_String(bus, "P_NAME", bus_name, true)
    reaper.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 1)
    return bus
end

function ApplyRouting(track_list)
    reaper.ClearConsole()
    reaper.ShowConsoleMsg("=== StemSnap routing ===\n")
    for _, item in ipairs(track_list) do
        reaper.ShowConsoleMsg("Track: " .. item.name .. " → Bus: " .. (item.assigned_bus or "SKIPPED") .. "\n")
    end

    reaper.Undo_BeginBlock()
    local count = 0
    local by_bus = {}
    for _, item in ipairs(track_list) do
        if item.assigned_bus and item.assigned_bus ~= "" then
            by_bus[item.assigned_bus] = by_bus[item.assigned_bus] or {}
            table.insert(by_bus[item.assigned_bus], item)
        end
    end
    for bus_name, items in pairs(by_bus) do
        local bus_ptr = GetTrackByName(bus_name)
        if not bus_ptr then bus_ptr = CreateNewBus(bus_name) end
        if bus_ptr then
            for _, item in ipairs(items) do
                MoveUnderBus(item.ptr, bus_ptr)
                count = count + 1
            end
        end
    end
    reaper.Undo_EndBlock("StemSnap", -1)
    reaper.UpdateArrange()
    reaper.ShowMessageBox(count .. " " .. L.success, "StemSnap", 0)
end

function GetUnassigned(track_list)
    local list = {}
    for _, item in ipairs(track_list) do
        if not item.assigned_bus or item.assigned_bus == "" then
            table.insert(list, item.name)
        end
    end
    return list
end

function BuildComboStr(list)
    if #list == 0 then return "\0\0" end
    return table.concat(list, "\0") .. "\0\0"
end

function BuildComboStrWithPlaceholder(bus_list)
    if #bus_list == 0 then return L.select_bus .. "\0\0" end
    return L.select_bus .. "\0" .. table.concat(bus_list, "\0") .. "\0\0"
end

local sel_count = reaper.CountSelectedTracks(0)
if sel_count == 0 then
    reaper.ShowMessageBox(L.select_tracks, "Error", 0)
    return
end

local selected_track_pointers = {}
for i = 0, sel_count - 1 do
    table.insert(selected_track_pointers, reaper.GetSelectedTrack(0, i))
end

local bus_list         = BuildBusList()
local routing_map      = BuildRoutingMap(bus_list)
local track_list       = BuildTrackList(bus_list, routing_map, selected_track_pointers)
local bus_combo_str    = BuildComboStr(bus_list)
local bus_combo_ph_str = BuildComboStrWithPlaceholder(bus_list)
local keywords_dirty   = false

local show_new_bus_popup = false
local show_partial_popup = false
local show_settings      = false
local new_bus_name       = ""
local new_bus_target_idx = nil

local ctx  = reaper.ImGui_CreateContext("StemSnap")
local font = reaper.ImGui_CreateFont('sans-serif', 14)
reaper.ImGui_Attach(ctx, font)

local COLOR_GREEN  = 0x00CC00FF
local COLOR_RED    = 0xFF3333FF
local COLOR_GREY   = 0x888888FF
local COLOR_YELLOW = 0xFFCC00FF
local COLOR_ORANGE = 0xFF8800FF

local TABLE_FLAGS = reaper.ImGui_TableFlags_BordersInnerV() |
                   reaper.ImGui_TableFlags_BordersOuter()   |
                   reaper.ImGui_TableFlags_RowBg()          |
                   reaper.ImGui_TableFlags_SizingFixedFit() |
                   reaper.ImGui_TableFlags_ScrollY()

local SETTINGS_TABLE_FLAGS = reaper.ImGui_TableFlags_BordersInnerV() |
                             reaper.ImGui_TableFlags_BordersOuter()   |
                             reaper.ImGui_TableFlags_RowBg()          |
                             reaper.ImGui_TableFlags_SizingFixedFit()

local function DrawWelcome()
    local w_visible, w_open = reaper.ImGui_Begin(ctx, L.welcome_title, true,
        reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoDocking())

    if w_visible then
        reaper.ImGui_SetWindowSize(ctx, 520, 480)
        reaper.ImGui_TextColored(ctx, COLOR_YELLOW, "★  " .. L.welcome_title)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, WELCOME_TEXT)
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, L.got_it, 120, 30) then
            MarkFirstRunDone()
            w_open = false
        end
        reaper.ImGui_End(ctx)
    end

    return w_open
end

local function DrawSettings()
    local s_visible, s_open = reaper.ImGui_Begin(ctx, L.settings_title, true,
        reaper.ImGui_WindowFlags_NoResize() | reaper.ImGui_WindowFlags_NoDocking())

    if s_visible then
        reaper.ImGui_SetWindowSize(ctx, 540, 560)

        reaper.ImGui_TextColored(ctx, COLOR_YELLOW, "ℹ  How automatic matching works")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, COLOR_GREEN,
            "  ✓  Simple bus names (\"Kick Bus\", \"Snare Bus\", \"Bass Group\")")
        reaper.ImGui_Text(ctx, "     are matched automatically from the first word.")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, COLOR_RED,
            "  ✗  Compound bus names (\"Hi End Perc Bus\", \"Riser & Fx Bus\")")
        reaper.ImGui_Text(ctx, "     cannot be matched automatically.")
        reaper.ImGui_Text(ctx, "     Add a custom rule below for each one.")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        local no_auto = {}
        for _, bus_name in ipairs(bus_list) do
            local kw = ExtractSingleWordKeyword(bus_name)
            if not kw then
                local covered = false
                for _, rule in ipairs(custom_rules) do
                    if rule.bus == bus_name then covered = true break end
                end
                if not covered then table.insert(no_auto, bus_name) end
            end
        end

        if #no_auto > 0 then
            reaper.ImGui_TextColored(ctx, COLOR_RED, "⚠  Buses without automatic matching (need custom rule):")
            for _, name in ipairs(no_auto) do
                reaper.ImGui_TextColored(ctx, COLOR_RED, "     • " .. name)
            end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
        end

        reaper.ImGui_TextColored(ctx, COLOR_GREY, "Custom keyword → bus rules")
        reaper.ImGui_Spacing(ctx)

        if #custom_rules == 0 then
            reaper.ImGui_TextColored(ctx, COLOR_GREY, L.no_rules)
        else
            if reaper.ImGui_BeginTable(ctx, "rules_table", 3, SETTINGS_TABLE_FLAGS) then
                reaper.ImGui_TableSetupColumn(ctx, L.rules_keyword_col, reaper.ImGui_TableColumnFlags_WidthFixed(), 170)
                reaper.ImGui_TableSetupColumn(ctx, L.rules_bus_col,     reaper.ImGui_TableColumnFlags_WidthFixed(), 280)
                reaper.ImGui_TableSetupColumn(ctx, "",                  reaper.ImGui_TableColumnFlags_WidthFixed(), 40)
                reaper.ImGui_TableHeadersRow(ctx)

                local rule_to_remove = nil
                for i, rule in ipairs(custom_rules) do
                    reaper.ImGui_TableNextRow(ctx)
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                    reaper.ImGui_Text(ctx, rule.keyword)
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)
                    reaper.ImGui_Text(ctx, rule.bus)
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    if reaper.ImGui_SmallButton(ctx, "x##rl_" .. i) then
                        rule_to_remove = i
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, L.remove_rule)
                    end
                end

                if rule_to_remove then
                    table.remove(custom_rules, rule_to_remove)
                    SaveConfig(keywords, custom_rules)
                    keywords_dirty = true
                end

                reaper.ImGui_EndTable(ctx)
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Add new rule:")
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_SetNextItemWidth(ctx, 150)
        local rk_changed, rk_val = reaper.ImGui_InputTextWithHint(ctx, "##rule_kw", L.rules_hint, new_rule_keyword)
        if rk_changed then new_rule_keyword = rk_val end

        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, "→")
        reaper.ImGui_SameLine(ctx)

        reaper.ImGui_SetNextItemWidth(ctx, 200)
        local rb_changed, rb_val = reaper.ImGui_Combo(ctx, "##rule_bus", new_rule_bus_idx, bus_combo_str)
        if rb_changed then new_rule_bus_idx = rb_val end

        reaper.ImGui_SameLine(ctx)
        local can_add = new_rule_keyword ~= "" and #bus_list > 0
        if not can_add then reaper.ImGui_BeginDisabled(ctx) end
        if reaper.ImGui_Button(ctx, L.add_rule) then
            local exists = false
            for _, rule in ipairs(custom_rules) do
                if string.lower(rule.keyword) == string.lower(new_rule_keyword) then
                    exists = true break
                end
            end
            if not exists then
                table.insert(custom_rules, {
                    keyword = string.lower(new_rule_keyword),
                    bus     = bus_list[new_rule_bus_idx + 1]
                })
                SaveConfig(keywords, custom_rules)
                keywords_dirty = true
                new_rule_keyword = ""
                new_rule_bus_idx = 0
            end
        end
        if not can_add then reaper.ImGui_EndDisabled(ctx) end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        if reaper.ImGui_Button(ctx, L.close, 100, 28) then
            s_open = false
        end
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_SetCursorPosX(ctx, 420)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xAA2222FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCC3333FF)
        if reaper.ImGui_Button(ctx, L.reset_config, 110, 28) then
            show_reset_confirm = true
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        if show_reset_confirm then
            reaper.ImGui_OpenPopup(ctx, L.reset_confirm_title)
            show_reset_confirm = false
        end

        if reaper.ImGui_BeginPopupModal(ctx, L.reset_confirm_title, nil,
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, L.reset_confirm)
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xAA2222FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xCC3333FF)
            if reaper.ImGui_Button(ctx, L.reset_config, 110, 28) then
                ResetConfig()
                keywords       = default_keywords
                custom_rules   = {}
                keywords_dirty = true
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx, 2)
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, L.cancel, 100, 28) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_End(ctx)
    end

    return s_open
end

local function loop()
    reaper.ImGui_PushFont(ctx, font, 0)

    if not win_pos_set then
        if saved_win_x and saved_win_y then
            reaper.ImGui_SetNextWindowPos(ctx, saved_win_x, saved_win_y)
        end
        win_pos_set = true
    end

    local visible, open = reaper.ImGui_Begin(ctx, L.window_title, true,
        reaper.ImGui_WindowFlags_NoResize())

    if visible then
        reaper.ImGui_SetWindowSize(ctx, 640, 580)

        local wx, wy = reaper.ImGui_GetWindowPos(ctx)
        SaveWinState(wx, wy)

        reaper.ImGui_TextColored(ctx, COLOR_GREY, "StemSnap  " .. SCRIPT_VERSION)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, L.keywords_label)
        reaper.ImGui_SameLine(ctx)

        local keyword_to_remove = nil
        for i, kw in ipairs(keywords) do
            local changed, val = reaper.ImGui_Checkbox(ctx, kw.word .. "##kw_" .. i, kw.active)
            if changed then
                kw.active = val
                keywords_dirty = true
            end
            reaper.ImGui_SameLine(ctx)
            if not kw.is_default then
                if reaper.ImGui_SmallButton(ctx, "x##rm_" .. i) then
                    keyword_to_remove = i
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, L.remove_keyword)
                end
                reaper.ImGui_SameLine(ctx)
            end
        end

        if keyword_to_remove then
            table.remove(keywords, keyword_to_remove)
            SaveConfig(keywords, custom_rules)
            keywords_dirty = true
        end

        reaper.ImGui_SetNextItemWidth(ctx, 140)
        local kw_changed, kw_val = reaper.ImGui_InputTextWithHint(ctx, "##newkw", L.keyword_hint, new_keyword_input)
        if kw_changed then new_keyword_input = kw_val end
        reaper.ImGui_SameLine(ctx)

        if reaper.ImGui_Button(ctx, L.add_keyword) and new_keyword_input ~= "" then
            local exists = false
            for _, kw in ipairs(keywords) do
                if kw.word == string.lower(new_keyword_input) then exists = true break end
            end
            if not exists then
                table.insert(keywords, {
                    word       = string.lower(new_keyword_input),
                    active     = true,
                    is_default = false
                })
                SaveConfig(keywords, custom_rules)
                keywords_dirty = true
            end
            new_keyword_input = ""
        end

        if keywords_dirty then
            SaveConfig(keywords, custom_rules)
            bus_list         = BuildBusList()
            routing_map      = BuildRoutingMap(bus_list)
            track_list       = BuildTrackList(bus_list, routing_map, selected_track_pointers)
            bus_combo_str    = BuildComboStr(bus_list)
            bus_combo_ph_str = BuildComboStrWithPlaceholder(bus_list)
            keywords_dirty   = false
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        local table_height = 340
        if reaper.ImGui_BeginTable(ctx, "tracks_table", 3, TABLE_FLAGS, 0, table_height) then
            reaper.ImGui_TableSetupScrollFreeze(ctx, 0, 1)
            reaper.ImGui_TableSetupColumn(ctx, L.track_col,  reaper.ImGui_TableColumnFlags_WidthFixed(), 200)
            reaper.ImGui_TableSetupColumn(ctx, L.bus_col,    reaper.ImGui_TableColumnFlags_WidthFixed(), 300)
            reaper.ImGui_TableSetupColumn(ctx, L.locked_col, reaper.ImGui_TableColumnFlags_WidthFixed(), 60)
            reaper.ImGui_TableHeadersRow(ctx)

            for idx, item in ipairs(track_list) do
                reaper.ImGui_TableNextRow(ctx)

                reaper.ImGui_TableSetColumnIndex(ctx, 0)
                if item.recognized then
                    reaper.ImGui_TextColored(ctx, COLOR_GREEN, "● " .. item.name)
                else
                    reaper.ImGui_TextColored(ctx, COLOR_RED, "● " .. item.name)
                end

                reaper.ImGui_TableSetColumnIndex(ctx, 1)
                if item.locked then reaper.ImGui_BeginDisabled(ctx) end
                reaper.ImGui_SetNextItemWidth(ctx, 240)

                if item.recognized then
                    local changed, new_idx = reaper.ImGui_Combo(ctx, "##bus_" .. idx, item.selected_bus_idx, bus_combo_str)
                    if changed then
                        item.selected_bus_idx = new_idx
                        item.assigned_bus     = bus_list[new_idx + 1]
                    end
                else
                    local combo_idx = item.selected_bus_idx >= 0 and (item.selected_bus_idx + 1) or 0
                    local changed, new_idx = reaper.ImGui_Combo(ctx, "##bus_" .. idx, combo_idx, bus_combo_ph_str)
                    if changed then
                        if new_idx == 0 then
                            item.selected_bus_idx = -1
                            item.assigned_bus     = nil
                            item.recognized       = false
                        else
                            item.selected_bus_idx = new_idx - 1
                            item.assigned_bus     = bus_list[new_idx]
                            item.recognized       = true
                        end
                    end
                end

                if item.locked then reaper.ImGui_EndDisabled(ctx) end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_SmallButton(ctx, "+##new_" .. idx) then
                    show_new_bus_popup = true
                    new_bus_target_idx = idx
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, L.new_bus_tooltip)
                end

                reaper.ImGui_TableSetColumnIndex(ctx, 2)
                if item.recognized then
                    local lock_changed, lock_val = reaper.ImGui_Checkbox(ctx, "##lock_" .. idx, item.locked)
                    if lock_changed then item.locked = lock_val end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, item.locked and L.unlock_tooltip or L.lock_tooltip)
                    end
                end
            end

            reaper.ImGui_EndTable(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        local assigned     = CountAssigned(track_list)
        local total        = #track_list
        local counter_color = assigned == total and COLOR_GREEN or COLOR_ORANGE
        reaper.ImGui_TextColored(ctx, counter_color,
            assigned .. " / " .. total .. " tracks assigned")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)

        if show_new_bus_popup then
            reaper.ImGui_OpenPopup(ctx, L.new_bus)
            show_new_bus_popup = false
        end

        if reaper.ImGui_BeginPopupModal(ctx, L.new_bus, nil,
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_Text(ctx, L.new_bus_prompt)
            reaper.ImGui_SetNextItemWidth(ctx, 260)
            local nb_changed, nb_val = reaper.ImGui_InputText(ctx, "##newbusname", new_bus_name)
            if nb_changed then new_bus_name = nb_val end
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx, L.create) and new_bus_name ~= "" then
                table.insert(bus_list, new_bus_name)
                bus_combo_str    = BuildComboStr(bus_list)
                bus_combo_ph_str = BuildComboStrWithPlaceholder(bus_list)
                if new_bus_target_idx then
                    local item = track_list[new_bus_target_idx]
                    item.assigned_bus     = new_bus_name
                    item.selected_bus_idx = #bus_list - 1
                    item.recognized       = true
                end
                new_bus_name = ""
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, L.cancel) then
                new_bus_name = ""
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        if show_partial_popup then
            reaper.ImGui_OpenPopup(ctx, "Unassigned Tracks")
            show_partial_popup = false
        end

        if reaper.ImGui_BeginPopupModal(ctx, "Unassigned Tracks", nil,
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            local unassigned = GetUnassigned(track_list)
            local msg = L.unassigned_warning
            for _, name in ipairs(unassigned) do
                msg = msg .. "  • " .. name .. "\n"
            end
            msg = msg .. L.unassigned_question
            reaper.ImGui_Text(ctx, msg)
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx, L.proceed, 100, 30) then
                reaper.ImGui_CloseCurrentPopup(ctx)
                ApplyRouting(track_list)
                open = false
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, L.cancel, 100, 30) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        if show_stale_warning then
            reaper.ImGui_OpenPopup(ctx, "Missing Buses")
            show_stale_warning = false
        end

        if reaper.ImGui_BeginPopupModal(ctx, "Missing Buses", nil,
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_TextColored(ctx, COLOR_ORANGE, "⚠  Some custom rules have been disabled")
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, L.stale_rules_warning)
            for _, rule in ipairs(stale_rules) do
                reaper.ImGui_TextColored(ctx, COLOR_ORANGE,
                    "   • \"" .. rule.keyword .. "\"  →  " .. rule.bus)
            end
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, L.stale_rules_info)
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx, L.ok, 100, 28) then
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, L.cancel, 100, 30) then
            open = false
        end
        reaper.ImGui_SameLine(ctx)

        local unassigned = GetUnassigned(track_list)
        if reaper.ImGui_Button(ctx, L.confirm, 100, 30) then
            if #unassigned > 0 then
                show_partial_popup = true
            else
                ApplyRouting(track_list)
                open = false
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) and #unassigned > 0 then
            reaper.ImGui_SetTooltip(ctx, L.confirm_tooltip)
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "⚙ " .. L.settings, 100, 30) then
            show_settings = not show_settings
        end

        reaper.ImGui_End(ctx)
    end

    if show_settings then show_settings = DrawSettings() end
    if show_welcome  then show_welcome  = DrawWelcome()  end

    reaper.ImGui_PopFont(ctx)

    if open then reaper.defer(loop) end
end

reaper.defer(loop)
