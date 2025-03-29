vim9script

if exists("b:current_syntax")
    finish
endif

syn match Explorer_Permission '[-djl][-rwx]\{9}' transparent contains=Explorer_Type
syn match Explorer_OwnerGroup '\(^[-djl][-rwx]\{9}\s\)\@<=\a[[:alpha:]-_]*\s\+\a[[:alpha:]-_]*\ze\s' transparent contains=Explorer_Owner,Explorer_Group

syn match Explorer_Type "^[-djl]" contained nextgroup=Explorer_PermissionUser
hi def link Explorer_Type Statement

syn match Explorer_PermissionUser '[-r][-w][-x]' contained nextgroup=Explorer_PermissionGroup
hi def link Explorer_PermissionUser Type

syn match Explorer_PermissionGroup '[-r][-w][-x]' contained nextgroup=Explorer_PermissionOther
hi def link Explorer_PermissionGroup String

syn match Explorer_PermissionOther '[-r][-w][-x]' contained
hi def link Explorer_PermissionOther Special

syn match Explorer_Owner '\a[[:alpha:]-_]*' contained skipwhite
hi def link Explorer_Owner Comment
syn match Explorer_Group '\a[[:alpha:]-_]*' contained
hi def link Explorer_Group Comment

syn match Explorer_Size '-\?\d\+\(\.\d\+\)\?[KMG]\? \ze\d\{4}-\d\{2}-\d\{2}\s\d\d:\d\d' contains=Explorer_SizeMod skipwhite nextgroup=Explorer_Time
hi def link Explorer_Size Constant

syn match Explorer_SizeMod '[KMG]' contained
hi def link Explorer_SizeMod Statement

syn match Explorer_Time '\d\{4}-\d\{2}-\d\{2}\s\d\d:\d\d'
hi def link Explorer_Time Comment

syn match Explorer_Directory '\(^\|\s\)[\/].\{-}\ze\($\| ->\)'
hi def link Explorer_Directory Directory

syn match Explorer_Link '-> .*'
hi def link Explorer_Link Type

b:current_syntax = "fuzzydir"
