vim9script

if exists("b:current_syntax")
    finish
endif

syn match Explorer_Permission '[-djl][-rwx]\{9}' transparent contains=Explorer_Type
syn match Explorer_Type "^[-djl]" contained nextgroup=Explorer_PermissionUser
hi def link Explorer_Type Statement
syn match Explorer_PermissionUser '[-r][-w][-x]' contained nextgroup=Explorer_PermissionGroup
hi def link Explorer_PermissionUser Type
syn match Explorer_PermissionGroup '[-r][-w][-x]' contained nextgroup=Explorer_PermissionOther
hi def link Explorer_PermissionGroup String
syn match Explorer_PermissionOther '[-r][-w][-x]' contained
hi def link Explorer_PermissionOther Special

syn match Explorer_OwnerGroup '\(^[-djl][-rwx]\{9}\)\@<=\s\a\+\s\a\+\s' transparent contains=Explorer_Owner
syn match Explorer_Owner '\s\a\+' contained skipwhite nextgroup=Explorer_Group
hi def link Explorer_Owner SpellCap
syn match Explorer_Group '\s\a\+' contained
hi def link Explorer_Group Comment

syn match Explorer_Size '\d\+\(\.\d\+\)\?[KMG]\?\s\ze\a\+\s\d\{2}\s\d\{2}:\d\{2}' contains=Explorer_SizeMod skipwhite nextgroup=Explorer_Time
hi def link Explorer_Size Constant
syn match Explorer_SizeMod '[KMG]' contained
hi def link Explorer_SizeMod vimCommentString

syn match Explorer_Time '\a\+\s\d\{2}\s\d\{2}:\d\{2}'
hi def link Explorer_Time Underlined
syn match Explorer_Directory '\(^\|\s\)[\/].\{-}\ze\($\| ->\)'
hi def link Explorer_Directory Directory
syn match Explorer_Link '-> .*'
hi def link Explorer_Link Type

b:current_syntax = "fuzzydir"
