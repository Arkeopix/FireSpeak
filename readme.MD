# FireSpeak

An addon aiming to automate some aspects of speaking in World Of Warcraft.

## Usage

when in game, type ``/fsc`` to open the import frame. There you can type in or paste your configuration and click the import button. The changes are immediately applied.

## Configuration syntax

### Replace

This is a simple string substitution using LUA patterns.

    -- the basic syntax
    replace: "oldValue"*"newValue"
    
    -- some examples
    replace: "test"*"poil"
    replace: "([0-9])"*"(%1)"

### Stutter

This simulates stuttering. This is **NOT** an accurate representation of stuttering.

    -- the basic syntax
    stutter: value

    -- some example
    stutter: 0.5
    stutter: 0.3

value is a value between 0 and 1 and represents the intensity of the stuttering.

## TODO

- localization
- Improve rule parsing so that it's less pissy about spaces and shits
- insert random strings in sentence
- react to emotes with custom text (callback on event CHAT_MSG_TEXT_EMOTE)