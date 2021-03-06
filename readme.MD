# FireSpeak

An addon aiming to automate some aspects of speaking in World Of Warcraft.

## Usage

when in game, type ``/fsc`` to open the import frame. There you can type in or paste your configuration and click the import button. The changes are immediately applied.

## Configuration syntax

### Replace

This is a simple string substitution using LUA patterns.

    -- the basic syntax
    replace: "oldValue":"newValue"
    
    -- some examples
    replace: "test":"poil"
    replace: "([0-9])":"(%1)"

### ReplaceChoice

Just like Replace but inserts a random value among a list

    -- the basic syntax
    replaceChoice: "oldValue":["newValue1","newValue2"]
    
    -- some examples
    replacechoice: "mdr":["Haha je rigole vraiment beaucoup", "*Se tape le cul parterre*"]
    ReplaceChoice: "([0-9])":["(%1)","%1%1"]

### Stutter

This simulates stuttering. This is **NOT** an accurate representation of stuttering.

    -- the basic syntax
    stutter: value

    -- some examples
    stutter: 0.5
    stutter: 0.3

value is a value between 0 and 1 and represents the intensity of the stuttering.

### Insert

Allow the user to insert random strings at random intervals in sentences.

    -- the basic syntax
    insert: ["string1", "string2"]:value

    -- some examples
    insert: ["...", "...bougie!", "...Gnya!"]:0.5

value is a value between 0 and 1 and represents the intensity of the occurences of the strings stored in the array.

## Instalation

For the moment, just unzip the directory in your addon folder.

## TODO

- localization
- react to emotes with custom text (callback on event CHAT_MSG_TEXT_EMOTE)
