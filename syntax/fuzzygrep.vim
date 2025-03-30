vim9script

if exists("b:current_syntax")
    finish
endif

# [._a-zA-Z0-9]+\ze:\d+:.+

syn match Grep_Entry '^[-._a-zA-Z0-9]\+\ze:\d\+:.\+' transparent contains=Grep_File nextgroup=Grep_LineNumber
syn match Grep_File '^[-._a-zA-Z0-9]\+' contained
syn match Grep_LineNumber ':\d\+:' contained


hi def link Grep_File Statement
hi def link Grep_LineNumber ErrorMsg
b:current_syntax = "fuzzygrep"
