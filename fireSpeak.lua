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

function FireSpeak:OnInitialize()
    local dbDefaults = {
        profile = {
            replaceRules = {},
            stutter = nil,
        }
    }
    self.db = LibStub("AceDB-3.0"):New("FireSpeakDB", dbDefaults)
    self.gui = LibStub("AceGUI-3.0")
end

function FireSpeak:OnEnable()
    self:Print("FireSpeak loaded, have fun !")
    self:RegisterChatCommand("FireSpeakConfig", "Config")
    self:RegisterChatCommand("fsc", "Config")
    self:RegisterChatCommand("fsl", "ListRules")
    self:RegisterChatCommand("fsd", "DeleteRule")
    self:RegisterChatCommand("fsh", "Help")
    self.SecureHook(FireSpeak, "ChatEdit_ParseText", "ParseText")
end

function FireSpeak:Help()
    self:Print("Welcome to firespeak !")
    self:Print("Here is a list of commands and the way to use them")
    self:Print("  - /fsc -> Open the configuration pannel allowing to import rules")
    self:Print("  - /fsl <rule type> -> List all registered rules of type <rule type>")
    self:Print("  - /fsd <rule type>:<rule index> -> Delete a registered rule by type and index")
end

function FireSpeak:OnDisable()
    self.Unhook(FireSpeak, "ChatEdit_ParseText")
end

function FireSpeak:DeleteRule(input)
    local arg = self:GetArgs(input)
    if arg ~= nil then
        local toDelete = string.lower(arg)
        if toDelete:match(".-:%d+") then
            local rule = string:split(toDelete, ":")
            self.Print("Deleting rule: " .. rule[1] .. ":" .. rule[2])
            if rule[1] == "replace" then
                table.remove(self.db.profile.replaceRules, rule[2])
            end
        elseif toDelete == "stutter" then
            self.Print("Disabling stutter")
            self.db.profile.stutter = nil
        else
            self:Print("Argument does not match exepected syntax")
        end
    else
        self:Print("You need to specify rule type and a rule index")
    end
end

function FireSpeak:ListRules(input)
    local arg = self:GetArgs(input)
    if arg ~= nil then
        local toList = string.lower(arg)
        if "replace" == toList then
            self:Print("Listing Replace rules")
            for index, rule in pairs(self.db.profile.replaceRules) do
                self:Print("rule " .. index .. ": replace \"" .. rule.oldValue .. "\" with \"" .. rule.newValue .. "\"")
            end
        else
            self:Print("Incorrect rule type specified")
        end
    else
        self:Print("Dumping all rules")
        self:Print("Listing Replace rules")
        for index, rule in pairs(self.db.profile.replaceRules) do
            self:Print("rule " .. index .. ": replace \"" .. rule.oldValue .. "\" with \"" .. rule.newValue .. "\"")
        end
        if self.db.profile.stutter ~= nil then
            self:Print("Stutter: " .. self.db.profile.stutter .. "\n")
        end
    end
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
            local save = table:deepcopy(g_ReplaceRules)
            -- so as the data is wiped here, so is the reference
            table:clear(g_ReplaceRules)
            local status = Firespeak_ParseConfig(editBox:GetText())
            if status then
                editBox:HighlightText(status.sel.startChar, status.sel.endChar)
                configFrame:SetStatusText(status.msg)
                g_ReplaceRules = save
                self.db.profile.replaceRules = g_ReplaceRules
                --self.db.profile.stutter = g_Stutter
                return
            end
            -- Check status and clear only if true
            -- in case of error, display message in frame
            self.db.profile.replaceRules = g_ReplaceRules
            self.db.profile.stutter = g_Stutter
            configFrame:SetStatusText("Configuration succesfully imported!")
        end
    )
    configFrame:AddChild(importButton)
end

----------------------------------------------------------------  
------------------ ADDON LOGIC CODE ----------------------------
----------------------------------------------------------------

function FireSpeak_Stuttering(s, intensity)
    tokens = string:split(s, ' ')
    tokenNumbers = #tokens

    repeatOccurences = math.floor(((intensity * tokenNumbers) / 100) * 100)
    if repeatOccurences == 0 then
        repeatOccurences = 1
    end

    --math.randomseed(time())
    local oldIdx = {}
    while (repeatOccurences ~= 0) do
        local idx = math.random(tokenNumbers)
        if oldIdx[idx] == nil then
            tokens[idx] = tokens[idx]:gsub("^%a", '%1-%1-%1-%0')
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

function FireSpeak:ParseText(chatEntry, send)
    if (1 == send) then
        local text = chatEntry:GetText()
        if text:match("^[^/].*") then
            for _, strReplace in pairs(self.db.profile.replaceRules) do
                text = text:gsub(strReplace.oldValue, strReplace.newValue)
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
    return rules
end


function FireSpeak_ConfigParseReplace(rule)
    local msg = nil
    -- So we check that the rule matches the expected syntax
    if string.lower(rule):match("%s+\".-\"%*\".-\"") then
        local trimmedRule = string:trim(rule)
        local replacePair = string:split(trimmedRule, "*")
        table.insert(g_ReplaceRules, {
            oldValue = string:extract(string:trim(replacePair[1]), "\""),
            newValue = string:extract(replacePair[2], "\"")
        })
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

function FireSpeak_ConfigParseStutter(rule)
    local msg = nil
    if string.lower(rule):match("%s+%d%.%d$") then
        local trimmedRule = string:trim(rule)
        g_Stutter = tonumber(trimmedRule)
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

-- FireSpeak configuration input consists of a blob of text respecting the following grammar
-- <rule>         ::= <rule-type> ":" <rule-content>
-- <rule-type>    ::= "ReplaceStrlit" | "ReplaceRgxp"
-- <rule-content> ::= [A-Za-z0-9\.\*\-\\(\)\:\s"]
-- Some examples:
--    - Replace: "test"*"remplacé"
--    - Replace: "([0-9])"*"(%1)"
--    - Stutter: 0.5
function Firespeak_ParseConfig(config)
    local parseFuncTable = {
        replace = FireSpeak_ConfigParseReplace,
        stutter = FireSpeak_ConfigParseStutter,
    }

    local conf = string:split(config, "\n")
    local currChar = 0
    for _, line in pairs(conf) do
        print(line, currChar)
        local confRule = string:split(line, ":")
        local ruleType = string.lower(confRule[1])
        if parseFuncTable[ruleType] ~= nil then
            local msg = parseFuncTable[ruleType](confRule[2])
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