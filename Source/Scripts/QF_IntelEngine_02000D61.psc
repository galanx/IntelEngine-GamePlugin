;BEGIN FRAGMENT CODE - Do not edit anything between this and the end comment
;NEXT FRAGMENT INDEX 4
Scriptname QF_IntelEngine_02000D61 Extends Quest Hidden

;BEGIN ALIAS PROPERTY AgentAlias04
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_AgentAlias04 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY PlayerAlias
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_PlayerAlias Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY TargetAlias00
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_TargetAlias00 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY TargetAlias01
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_TargetAlias01 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY AgentAlias01
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_AgentAlias01 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY TargetAlias02
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_TargetAlias02 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY AgentAlias02
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_AgentAlias02 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY AgentAlias00
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_AgentAlias00 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY TargetAlias04
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_TargetAlias04 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY AgentAlias03
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_AgentAlias03 Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY QuestTarget
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_QuestTarget Auto
;END ALIAS PROPERTY

;BEGIN ALIAS PROPERTY TargetAlias03
;ALIAS PROPERTY TYPE ReferenceAlias
ReferenceAlias Property Alias_TargetAlias03 Auto
;END ALIAS PROPERTY

;BEGIN FRAGMENT Fragment_2
Function Fragment_2()
;BEGIN AUTOCAST TYPE IntelEngine_StoryEngine
Quest __temp = self as Quest
IntelEngine_StoryEngine kmyQuest = __temp as IntelEngine_StoryEngine
;END AUTOCAST
;BEGIN CODE
SetObjectiveDisplayed(0, true)
;END CODE
EndFunction
;END FRAGMENT

;END FRAGMENT CODE - Do not edit anything between this and the begin comment
