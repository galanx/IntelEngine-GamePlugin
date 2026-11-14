Scriptname IntelEngine_Locale Hidden
; Resolve canonical capital names through stable forms, in the running language.
; Unknown names are preserved. No global record or SkyrimNet prompt is changed.

String Function LocationName(String canonical) Global
    Int id = 0
    If canonical == "Whiterun"
        id = 0x018A56
    ElseIf canonical == "Windhelm"
        id = 0x018A57
    ElseIf canonical == "Solitude"
        id = 0x018A5A
    ElseIf canonical == "Riften"
        id = 0x018A58
    ElseIf canonical == "Markarth"
        id = 0x018A59
    ElseIf canonical == "Falkreath"
        id = 0x018A49
    ElseIf canonical == "Dawnstar"
        id = 0x018A50
    ElseIf canonical == "Morthal"
        id = 0x018A53
    ElseIf canonical == "Winterhold"
        id = 0x018A51
    EndIf
    If id == 0
        return canonical
    EndIf
    Form place = Game.GetFormFromFile(id, "Skyrim.esm")
    If place == None
        return canonical
    EndIf
    String translated = place.GetName()
    If translated == ""
        return canonical
    EndIf
    return translated
EndFunction

Int Function SkipWhitespace(String text, Int offset) Global
    Int size = StringUtil.GetLength(text)
    While offset < size
        Int code = StringUtil.AsOrd(StringUtil.GetNthChar(text, offset))
        If code != 32 && code != 9 && code != 13 && code != 10
            return offset
        EndIf
        offset += 1
    EndWhile
    return offset
EndFunction

String Function ReplaceLocationToken(String response, String original, String translated) Global
    ; JContainers represents JSON booleans as integers. Never reserialize the
    ; envelope: preserve every other byte/type, including should_act:true.
    String fieldToken = "\"battle_location\""
    Int found = StringUtil.Find(response, fieldToken)
    If found < 0
        return response
    EndIf
    Int afterKey = found + StringUtil.GetLength(fieldToken)
    If StringUtil.Find(response, fieldToken, afterKey) >= 0
        ; Ambiguous keys: leave author validation in control.
        return response
    EndIf
    Int pos = SkipWhitespace(response, afterKey)
    If StringUtil.GetNthChar(response, pos) != ":"
        return response
    EndIf
    pos = SkipWhitespace(response, pos + 1)
    If StringUtil.GetNthChar(response, pos) != "\""
        return response
    EndIf
    pos += 1
    Int end = pos + StringUtil.GetLength(original)
    If StringUtil.Substring(response, pos, StringUtil.GetLength(original)) != original
        return response
    EndIf
    If StringUtil.GetNthChar(response, end) != "\""
        return response
    EndIf
    If StringUtil.Find(translated, "\"") >= 0 || StringUtil.Find(translated, "\\") >= 0
        return response
    EndIf
    return StringUtil.Substring(response, 0, pos) + translated + StringUtil.Substring(response, end)
EndFunction

String Function NormalizePoliticalResponse(String response) Global
    Int parsed = JValue.objectFromPrototype(response)
    If parsed == 0
        ; Preserve the author's invalid-input handling.
        return response
    EndIf
    JValue.retain(parsed)
    String original = JMap.getStr(parsed, "battle_location", "")
    String translated = LocationName(original)
    String result = response
    If translated != original
        result = ReplaceLocationToken(response, original, translated)
    EndIf
    JValue.release(parsed)
    return result
EndFunction
