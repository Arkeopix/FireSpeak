-- TODO
--   - Document the shit out of your code
--   - Beta test by guild and friends
-- Done
--   - List saved rules
--   - Delete saved rule by index
--   - Load saved rules in MultiLineEditBox when user launches /fsc
--   - Check syntax error in rules and report them to users
--   - Validate every user input and return usefull error messages
--   - Write usage for slash commands

----------------------------------------------------------------  
------------------ ADDON SETUP CODE ----------------------------
----------------------------------------------------------------
FireSpeak = LibStub("AceAddon-3.0"):NewAddon("FireSpeak", "AceConsole-3.0", "AceHook-3.0")

-- This is not the most elegant solution but clearly the easiest
-- This global will shortly hold the replace rules while they're not saved in the user's profile
local g_ReplaceRules = {}
local g_Stutter = nil
local g_InsertRules = {}

function FireSpeak:OnInitialize()
    local dbDefaults = {
        profile = {
            replaceRules = {},
            insertRules = {},
            stutter = nil
        }
    }
    self.db = LibStub("AceDB-3.0"):New("FireSpeakDB", dbDefaults)
    self.gui = LibStub("AceGUI-3.0")
end

function FireSpeak:OnEnable()
    self:Print("FireSpeak loaded, have fun !")
    self:RegisterChatCommand("FireSpeakConfig", "Config")
    self:RegisterChatCommand("fsc", "Config")
    self.SecureHook(FireSpeak, "ChatEdit_ParseText", "ParseText")
end

function FireSpeak:OnDisable()
    self.Unhook(FireSpeak, "ChatEdit_ParseText")
end


function FireSpeak:Config(input)
    local configFrame = self.gui:Create("Frame")
    configFrame:SetTitle("FireSpeak Config")
    configFrame:SetCallback("OnClose", 
        function(widget)
            self.gui:Release(widget) 
        end
    )
    configFrame:SetLayout("Flow")
    
    local editBox = self.gui:Create("MultiLineEditBox")
    editBox:SetLabel("Import your configuration here")
    editBox:SetText(FireSpeak_ConfigLoad(self.db.profile))
    editBox:SetRelativeWidth(1.0)
    editBox:DisableButton(true)
    configFrame:AddChild(editBox)

    local importButton = self.gui:Create("Button")
    importButton:SetText("Import")
    importButton:SetCallback("OnClick", 
        function()
            -- Reset profile here so that each time we import a rule set, it cleans the old one
            -- This is done in order to avoid spamming the profile with duplicate rules
            self.db:ResetProfile()
            -- We make a deep copy because LUA passes references to variable instead of copies
            local saveReplaceRules = table:deepcopy(g_ReplaceRules)
            local saveInsertRules = table:deepcopy(g_InsertRules)
            local saveStutter = g_stutter
            -- so as the data is wiped here, so is the reference
            table:clear(g_ReplaceRules)
            table:clear(g_InsertRules)
            g_Stutter = nil
            local status = Firespeak_ParseConfig(editBox:GetText())
            if status then
                editBox:HighlightText(status.sel.startChar, status.sel.endChar)
                configFrame:SetStatusText(status.msg)
                g_ReplaceRules = saveReplaceRules
                g_InsertRules = saveInsertRules
                g_Stutter = saveStutter
                self.db.profile.replaceRules = g_ReplaceRules
                self.db.profile.insertRules = g_InsertRules
                self.db.profile.stutter = g_Stutter
                return
            end
            -- Check status and clear only if true
            -- in case of error, display message in frame
            self.db.profile.replaceRules = g_ReplaceRules
            self.db.profile.insertRules = g_InsertRules
            self.db.profile.stutter = g_Stutter
            configFrame:SetStatusText("Configuration succesfully imported!")
        end
    )
    configFrame:AddChild(importButton)
end

----------------------------------------------------------------  
------------------ ADDON LOGIC CODE ----------------------------
----------------------------------------------------------------

function FireSpeak_IterChooseRandom(action, s, intensity, data)
    tokens = string:split(s, ' ')
    tokenNumbers = #tokens

    repeatOccurences = math.floor(((intensity * tokenNumbers) / 100) * 100)
    if repeatOccurences == 0 then
        repeatOccurences = 1
    end

    local oldIdx = {}
    while (repeatOccurences ~= 0) do
        local idx = math.random(tokenNumbers)
        if oldIdx[idx] == nil then
            -- action 0 is stutter
            if action == 0 then
                tokens[idx] = tokens[idx]:gsub("^%a", '%1-%1-%1-%0')
            -- action 1 is insert
            elseif action == 1 then
                local insertIdx = math.random(#data)
                tokens[idx] = tokens[idx] .. data[insertIdx]
            end
            oldIdx[idx] = true
            repeatOccurences = repeatOccurences - 1
        end
    end
    local final = ""
    for i=1,tokenNumbers,1 do
        final = final .. (i == 1 and "" or  " ") .. tokens[i]
    end
    return final
end

function FireSpeak_Stuttering(s, intensity)
    return FireSpeak_IterChooseRandom(0, s, intensity, nil)
end

function FireSpeak_Insert(s, insert)
    return FireSpeak_IterChooseRandom(1, s, insert.intensity, insert.insertTable)
end

function FireSpeak:ParseText(chatEntry, send)
    if (1 == send) then
        local text = chatEntry:GetText()
        if text:match("^[^/].*") then
            for _, strReplace in pairs(self.db.profile.replaceRules) do
                text = text:gsub(strReplace.oldValue, strReplace.newValue)
            end
            for _, insertRules in pairs(self.db.profile.insertRules) do
                text = FireSpeak_Insert(text, insertRules)
            end
            if self.db.profile.stutter ~= nil then
                text = FireSpeak_Stuttering(text, self.db.profile.stutter)
            end
            chatEntry:SetText(text)
        end
    end
end

----------------------------------------------------------------  
------------------ CONFIGURATION PARSING CODE ------------------
----------------------------------------------------------------

function FireSpeak_ConfigLoad(userProfile) 
    local rules = ""
    for index, rule in pairs(userProfile.replaceRules) do
        rules = rules .. "Replace: " .. "\"" .. rule.oldValue .. "\"*\"" .. rule.newValue .. "\"\n" 
    end
    if userProfile.stutter ~= nil then
        rules = rules .. "Stutter: " .. userProfile.stutter .. "\n"
    end

    for index, rule in pairs(userProfile.insertRules) do
        rules = rules .. "insert: ["
        for _, v in pairs(rule.insertTable) do
            rules = rules .. "\"" .. v .. "\","
        end
        rules = rules .. "]*" .. rule.intensity .. "\n"
    end
    return rules
end

function FireSpeak_ConfigParseReplace(rule)
    local msg = nil
    -- So we check that the rule matches the expected syntax
    if string.lower(rule):match("%s*\".-\":\".-\"") then
        local trimmedRule = string:trim(rule)
        --local replacePair = string:split(trimmedRule, "*")
        local oldValue = string:extract(get_conf_string_part1(trimmedRule), "\"")
        local newValue = string:extract(get_conf_string_part2(trimmedRule), "\"")
        print(oldValue, newValue)
        table.insert(g_ReplaceRules, {
            oldValue = oldValue,--string:extract(string:trim(replacePair[1]), "\""),
            newValue = newValue--string:extract(replacePair[2], "\"")
        })
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

function FireSpeak_ConfigParseStutter(rule)
    local msg = nil
    if string:match_conf_percent_value(rule) then
        local trimmedRule = string:trim(rule)
        g_Stutter = tonumber(trimmedRule)
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

function FireSpeak_ConfigParseInsert(rule)
    local msg = nil
    if rule:match("^%s*%[.*%]%:[%d.]*$") then
        local insertTable = {}
        local intensity = nil
        for _, v in pairs(string:split(string:get_conf_array_content(rule), ",")) do
            v = string:extract(string:trim(v), "\"")
            table.insert(insertTable, v)
        end
        if string:match_conf_percent_value(rule) then
            intensity = tonumber(string:get_after(rule, ":"))
        end
        table.insert(g_InsertRules, {
            insertTable = insertTable,
            intensity = intensity
        })
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

-- Some examples:
--    - Replace: "test":"remplacé"
--    - Replace: "([0-9])"*"(%1)"
--    - Stutter: 0.5
--    - insert: ["...", "...bougie!", "...Gnya!"]*0.5
function Firespeak_ParseConfig(config)
    local parseFuncTable = {
        replace = FireSpeak_ConfigParseReplace,
        stutter = FireSpeak_ConfigParseStutter,
        insert  = FireSpeak_ConfigParseInsert,
    }

    local conf = string:split(config, "\n")
    local currChar = 0
    for _, line in pairs(conf) do
        local ruleType = string.lower(string:get_until(line, ":"))
        local ruleValue = string:get_after(line, ":")
        if parseFuncTable[ruleType] ~= nil then
            local msg = parseFuncTable[ruleType](ruleValue)
            if msg then
                return {msg = msg .. ". Please double check highligted line", sel = {startChar = currChar, endChar = currChar + string.len(line)}}
            end
        else
            return {msg = "Rule type does not exists. Please double check highligted line", sel = {startChar = currChar, endChar = currChar + string.len(line)}}
        end
        currChar = currChar + string.len(line) + 1
    end
    return nil
end

----------------------------------------------------------------  
------------------ UTIL FUNCTIONS ------------------------------
----------------------------------------------------------------

function get_conf_string_part1(s)
    start, stop = s:find("^%s*\".*\":")
    return s:sub(start, stop-1)
end

function get_conf_string_part2(s)
    start, stop = s:find("\":\".-$")
    return s:sub(start+2, stop)
end

function string:match_conf_percent_value(s)
    return s:match("%s*%d%.%d$") or s:match("%s*%d$")
end

function string:split(inputstr, sep)
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
            table.insert(t, str)
    end
    return t
end

function string:trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function string:extract(s, sep)
    start, stop = s:find(sep .. "(.*)" .. sep)
    return s:sub(start+1, stop-1)
end

function string:get_until(s, needle)
    start, stop = s:find(".-" .. needle)
    return s:sub(start, stop-1)
end

function string:get_after(s, needle)
    start, stop = s:find(".-" .. needle)
    return s:sub(stop+1, string.len(s))
end

function string:get_conf_array_content(s)
    start, stop = s:find("%[(.*)%]")
    return s:sub(start+1, stop-1)
end

-- http://lua-users.org/wiki/CopyTable
function table:deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[table:deepcopy(orig_key)] = table:deepcopy(orig_value)
        end
        setmetatable(copy, table:deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function table:clear(t) 
    for k in pairs(t) do
        t[k] = nil
    end
end