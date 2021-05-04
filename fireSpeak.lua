-- TODO
--   - Document the shit out of your code
--   - Beta test by guild and friends

----------------------------------------------------------------  
------------------ ADDON SETUP CODE ----------------------------
----------------------------------------------------------------
FireSpeak = LibStub("AceAddon-3.0"):NewAddon("FireSpeak", "AceConsole-3.0", "AceHook-3.0")

-- This is not the most elegant solution but clearly the easiest
-- Those globals will shortly hold the rules while they're not saved in the user's profile
local g_ReplaceRules = {}
local g_Stutter = nil
local g_InsertRules = {}
local g_ReplaceChoiceRules = {}

-- Called whenever the character enters the world, before OnEnable
function FireSpeak:OnInitialize()
    -- This is the default layout of the user's profile.
    -- Each new profile will have this layout and each reset will take this default layout
    local dbDefaults = {
        profile = {
            replaceRules = {},
            insertRules = {},
            replaceChoiceRules = {},
            stutter = nil
        }
    }
    -- Create some importants members for later use:
    -- db is an abstraction layer around SavedVariables
    self.db = LibStub("AceDB-3.0"):New("FireSpeakDB", dbDefaults)
    -- gui alow us to create frames
    self.gui = LibStub("AceGUI-3.0")
end

-- Called after OnInitialize
function FireSpeak:OnEnable()
    self:Print("FireSpeak loaded, have fun !")
    -- Register slash commands to load the import menu
    -- We associate the same method as handler
    self:RegisterChatCommand("FireSpeakConfig", "Config")
    self:RegisterChatCommand("fsc", "Config")
    -- Register a secure hook in order to intercept messages from the user
    -- We use a secure hook because the ChatEdit_ParseText event is protected by the game client...
    -- We associate the ParseText method of FireSpeak as the handler of the secure hook.
    self.SecureHook(FireSpeak, "ChatEdit_ParseText", "ParseText")
end

-- Called whenever the addon in Disabled
function FireSpeak:OnDisable()
    -- Unregister what wi registered, just to be clean
    self.UnregisterChatCommand("FireSpeakConfig")
    self.UnregisterChatCommand("fsc")
    self.Unhook(FireSpeak, "ChatEdit_ParseText")
end

-- Called whenever the user types in /fsc or /FireSpeakConfig
-- This method is responsible for the config frame
function FireSpeak:Config()
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
    -- We register a callback for the OnClick Event
    -- This callback is responsible for the parsing of the configuration.
    -- The callback is inlined in order to have access to FireSpeak's self member
    importButton:SetCallback("OnClick", 
        function()
            -- Reset profile here so that each time we import a rule set, it cleans the old one
            -- This is done in order to avoid spamming the profile with duplicate rules
            self.db:ResetProfile()
            -- We make a deep copy because LUA passes references to variable instead of copies
            local saveReplaceRules = table:deepcopy(g_ReplaceRules)
            local saveInsertRules = table:deepcopy(g_InsertRules)
            local saveReplaceChoiceRules = table:deepcopy(g_ReplaceChoiceRules)
            local saveStutter = g_stutter
            -- As the data is wiped here, so is the reference
            table:clear(g_ReplaceRules)
            table:clear(g_InsertRules)
            table:clear(g_ReplaceChoiceRules)
            g_Stutter = nil
            -- Now that all the data is saved and the profile squeaky clean we can actually parse the user's configuration
            local status = Firespeak_ParseConfig(editBox:GetText())
            if status then
                -- Oups, there was an error
                -- Highlight the value that caused the error
                editBox:HighlightText(status.sel.startChar, status.sel.endChar)
                -- Set the status text in the frame
                configFrame:SetStatusText(status.msg)
                -- Restore the rules
                g_ReplaceRules = saveReplaceRules
                g_InsertRules = saveInsertRules
                g_Stutter = saveStutter
                g_ReplaceChoiceRules = saveReplaceChoiceRules
                self.db.profile.replaceRules = g_ReplaceRules
                self.db.profile.insertRules = g_InsertRules
                self.db.profile.stutter = g_Stutter
                self.db.profile.replaceChoiceRules = g_ReplaceChoiceRules
                return
            end
            -- Everything went fine, update the rule set in the user's profile
            self.db.profile.replaceRules = g_ReplaceRules
            self.db.profile.insertRules = g_InsertRules
            self.db.profile.stutter = g_Stutter
            self.db.profile.replaceChoiceRules = g_ReplaceChoiceRules
            configFrame:SetStatusText("Configuration succesfully imported!")
        end
    )
    configFrame:AddChild(importButton)
end

----------------------------------------------------------------  
------------------ ADDON LOGIC CODE ----------------------------
----------------------------------------------------------------

-- Parses the input string s and split it on spaces to get an array
-- then for each word, check wether the word is part of flavor text (*like this*)
-- Also safeguard text inbetween parenthesis
-- Return a table containings words and their status regarding their belonging to flavor text
-- Arguments:
--   - s: the input string
-- Return:
--   - a pair in the form (integer, list of tokens)
--     - the integer is the number of tokens that do not belong in a flavor text
--     - Each entry in list of tokens looks like the following:
--       - {s = string, flavor = bool}
function FireSpeak_GetTokensSaveFlavor(s)
    local tokens = {}
    local actualTokens = 0
    local flavorStatus = false
    -- We make sure that the string is splitable
    if s ~= nil and string.match(s, " ") then
        for _, word in pairs(string:split(s, " ")) do
            -- if the word is self contained flavor text
            if string.match(word, "^[%*%(].*[%*%)]$") then
                flavorStatus = true
                table.insert(tokens, {s = word, flavor = flavorStatus})
                flavorStatus = false
            -- if the word is the begining of a flavor text
            elseif string.match(word, "^[%*%(]") then
                flavorStatus = true
                table.insert(tokens, {s = word, flavor = flavorStatus})
            -- if the word is the ending of a flavor text
            elseif string.match(word, "[%*%)]$") then
                table.insert(tokens, {s = word, flavor = flavorStatus})
                flavorStatus = false
            -- any other case
            else
                table.insert(tokens, {s = word, flavor = flavorStatus})
                if flavorStatus == false then
                    actualTokens = actualTokens + 1
                end
            end
        end
    end
    return actualTokens, tokens
end

-- Chooses "random" positions in a string to apply a modification.
-- Arguments:
--  - action: An integer that specifies the type of modification to apply
--    - 0: stutter
--    - 1: insert
--  - s: The input string on which the modification is applied
--  - intensity: A float value between 0 and 1 representing a percentage. Used to calculate the number of modifications to apply
--  - data: Some data, depending on Action value
--    - 0: nil
--    - 1: table of inserts
-- Return:
--  - A new string containing the applied modifications
function FireSpeak_IterChooseRandom(action, s, intensity, data)
    local actualWords, tokens = FireSpeak_GetTokensSaveFlavor(s)
    local tokenNumber = #tokens

    -- If there is no modification to apply, ignore logic and return the input string as is
    if actualWords ~= 0 then
        -- We calculate the number of modifications we will need to apply.
        -- We use actualWords instead of tokenNumber because we don't want to modify the flavor text
        local repeatOccurences = math.floor(((intensity * actualWords) / 100) * 100)
        -- In case the result is floured to 0, we want to apply at leat 1 modifications
        if repeatOccurences == 0 then
            repeatOccurences = 1
        end

        -- visitedTokens is used to keep track of the already visited tokens. This is done
        -- in order to avoir modifying the same tokens multiple times
        local visitedTokens = {}
        while (repeatOccurences ~= 0) do
            local idx = math.random(tokenNumber)
            if visitedTokens[idx] == nil then
                -- action 0 is stutter
                if action == 0 then
                    -- We only want to modify NON flavor text
                    if tokens[idx].flavor == false then
                        -- Here we apply the stutter modification
                        -- We take a token, capture its begining letter and repeat it 3 times, followed by the whole token
                        tokens[idx].s = tokens[idx].s:gsub("^%a", '%1-%1-%1-%0')
                        repeatOccurences = repeatOccurences - 1
                        visitedTokens[idx] = true
                    end
                -- action 1 is insert
                elseif action == 1 then
                    -- We only want to modify NON flavor text
                    if tokens[idx].flavor == false then
                        -- Here we apply the insert modification
                        -- We take a random entry from data and append it to a random token
                        local insertIdx = math.random(#data)
                        tokens[idx].s = tokens[idx].s .. " " .. data[insertIdx]
                        repeatOccurences = repeatOccurences - 1
                        visitedTokens[idx] = true
                    else
                        repeatOccurences = repeatOccurences - 1
                    end
                end
            end
        end
        -- Finally we rebuild a string and return it
        local final = ""
        for i=1,tokenNumber,1 do
            final = final .. (i == 1 and "" or  " ") .. tokens[i].s
        end
        return final
    end
    return s
end

-- Just a wrapper function calling FireSpeak_IterChooseRandom with the right arguments
function FireSpeak_Stuttering(s, intensity)
    if string.match(s, " ") then
        s = FireSpeak_IterChooseRandom(0, s, intensity, nil)
    else
        s = s:gsub("^%a", '%1-%1-%1-%0')
    end
    return s
end

-- Just a wrapper function calling FireSpeak_IterChooseRandom with the right arguments
function FireSpeak_Insert(s, insert)
    if string.match(s, " ") then
        s = FireSpeak_IterChooseRandom(1, s, insert.intensity, insert.insertTable)
    end
    return s
end

-- This method is the core of the addon's text parsing abilities
-- This is where the rules are applied to the user's input text
-- Arguments:
--  - chatEntry: The text the user typed so far
--  - send: a boolean indicating that the user pressed enter
function FireSpeak:ParseText(chatEntry, send)
    -- As of now, we only want to modify the text once the user user pressed enter
    -- but maybe when we add fuzzy matching and autocomplete...
    if (1 == send) then
        local text = chatEntry:GetText()
        -- Check that the user's input is not a command
        if text:match("^[^/].*") then
            -- Applying replaces
            for _, strReplace in pairs(self.db.profile.replaceRules) do
                text = text:gsub(strReplace.oldValue, strReplace.newValue)
            end
            for _, strReplace in pairs(self.db.profile.replaceChoiceRules) do
                local replaceIdx = math.random(#strReplace.newValue)
                text = text:gsub(strReplace.oldValue, strReplace.newValue[replaceIdx])
            end
            -- Applying inserts
            for _, insertRules in pairs(self.db.profile.insertRules) do
                text = FireSpeak_Insert(text, insertRules)
            end
            -- Applying stutter
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

-- Responsible for loading the configuration whenever the FireSpeak:Config is called
-- Arguments:
--  - userProfile: the user's profile holding the configuration rules
-- Return:
--  - a string representing the user's configuration
function FireSpeak_ConfigLoad(userProfile) 
    local rules = ""
    for _, rule in pairs(userProfile.replaceRules) do
        rules = rules .. "Replace: " .. "\"" .. rule.oldValue .. "\":\"" .. rule.newValue .. "\"\n" 
    end
    if userProfile.stutter ~= nil then
        rules = rules .. "Stutter: " .. userProfile.stutter .. "\n"
    end

    for _, rule in pairs(userProfile.insertRules) do
        rules = rules .. "Insert: ["
        for _, v in pairs(rule.insertTable) do
            rules = rules .. "\"" .. v .. "\","
        end
        rules = rules .. "]:" .. rule.intensity .. "\n"
    end

    for _, rule in pairs(userProfile.replaceChoiceRules) do
        rules = rules .. "ReplaceChoice: \"".. rule.oldValue .. "\"\:["
        for _, v in pairs(rule.newValue) do
            rules = rules .. "\"" .. v .. "\","
        end
        rules = rules .. "]\n"
    end
    return rules
end

-- Parses the replace rules, uses g_ReplaceRules as storage for the rules
-- Arguments:
--  - rule: the value part of the rule. 
-- Return:
--  - nil if no was encoutered
--  - An error message
function FireSpeak_ConfigParseReplace(rule)
    local msg = nil
    -- We check that the rule matches the expected syntax
    -- Must match a patter that looks like this:
    --  - "blabla":"blabla"
    if string.lower(rule):match("%s*\".-\":\".-\"") then
        local trimmedRule = string:trim(rule)
        local oldValue = string:extract(get_conf_string_part1(trimmedRule), "\"")
        local newValue = string:extract(get_conf_string_part2(trimmedRule), "\"")
        table.insert(g_ReplaceRules, {
            oldValue = oldValue,
            newValue = newValue
        })
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

-- Parses the stutter rule, use g_Stutter as storage
-- Arguments:
--  - rule: the value part of the rule. 
-- Return:
--  - nil if no was encoutered
--  - An error message
function FireSpeak_ConfigParseStutter(rule)
    local msg = nil
    -- We check that the rule matches the expected syntax
    -- We're looking for either digit.digit or a digit
    if string:match_conf_percent_value(rule) then
        local trimmedRule = string:trim(rule)
        g_Stutter = tonumber(trimmedRule)
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

-- Parses the insert rule, uses g_InsertRules as storage
-- Arguments:
--  - rule: the value part of the rule. 
-- Return:
--  - nil if no was encoutered
--  - An error message
function FireSpeak_ConfigParseInsert(rule)
    local msg = nil
    -- We check that the rule matches the expected syntax
    -- Must match a patter that looks like this:
    --  - ["bla", "bleh"]:(digit.digit or digit)
    -- This pattern is not ideal but lua patterns do not seem to be able to match non ascii characters
    if rule:match("^%s*%[.*%]%:[%d.]*$") then
        local insertTable = {}
        local intensity = nil
        -- This loop gets the strings in the conf array
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

-- Parses the Replacechoice rules, uses g_ReplaceChoiceRules as storage
-- Arguments:
--  - rules: the value part of the rule
-- Return:
--  - nil if no was encoutered
--  - An error message
function FireSPeak_ConfigParseReplaceChoice(rule)
    local msg = nil
    -- We check that the rule matches the expected syntax
    -- Must match a patter that looks like this:
    --  - "blal":["bla", "bleh"]
    -- This pattern is not ideal but lua patterns do not seem to be able to match non ascii characters
    if rule:match("^%s*%\".-\"%:%[.*%]$") then
        local trimmedRule = string:trim(rule)
        local oldValue = string:extract(get_conf_string_part1(trimmedRule), "\"")
        local insertTable = {}
        for _, v in pairs(string:split(string:get_conf_array_content(rule), ",")) do
            v = string:extract(string:trim(v), "\"")
            table.insert(insertTable, v)
        end
        table.insert(g_ReplaceChoiceRules, {
            oldValue = oldValue,
            newValue = insertTable
        })
    else
        msg = "Rule does not match expected syntax"
    end
    return msg
end

-- The core of the configuration parsing
-- Some examples of rules:
--    - Replace: "test":"remplacé"
--    - Replace: "([0-9])"*"(%1)"
--    - Stutter: 0.5
--    - insert: ["...", "...bougie!", "...Gnya!"]*0.5
--    - replaceChoice: "test":["...", "...bougie!", "...Gnya!"]
-- Arguments:
--  - config: A string representing the full user's configurations
-- Return:
--  - nil if everything wen well
--  - a table indicating the error and information about the position of the error
--    - { msg = string, sel = { startChar = integer, endChar = integer}}
function Firespeak_ParseConfig(config)
    local parseFuncTable = {
        replace       = FireSpeak_ConfigParseReplace,
        stutter       = FireSpeak_ConfigParseStutter,
        insert        = FireSpeak_ConfigParseInsert,
        replacechoice = FireSPeak_ConfigParseReplaceChoice
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

-- In replace like rules, used to get the first part of the value
function get_conf_string_part1(s)
    -- plain stupid: get everything from start to last ':' preceded by an '"'
    -- ie "coucoucoucoucou":
    --    |                |
    --    +----------------+---> this is the match
    start, stop = s:find("^%s*\".*\":")
    return s:sub(start, stop-1)
end

-- In replace like rules, used to get the second part of the value
function get_conf_string_part2(s)
    -- matches: ":"coucoucoucou"
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