vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "fuzzy.vim" as Fuzzy


com! FuzzyMRU Fuzzy.MRU.Instance.Search() 
com! -nargs=* FuzzyLine Fuzzy.Line.Instance.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyFind Fuzzy.Find.Instance.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyShell Fuzzy.ShellFuzzy.Instance.Search(<q-args>) 
com! FuzzyCmdHistory Fuzzy.CmdHistory.Instance.Search() 
com! FuzzyCmd Fuzzy.Cmd.Instance.Search() 
com! FuzzyBuffer Fuzzy.Buffer.Instance.Search() 
com! FuzzyGitFile Fuzzy.GitFile.Instance.Search() 
com! FuzzyExplorer Fuzzy.Explorer.Instance.Search() 
com! FuzzyKeyMap Fuzzy.VimKeyMap.Instance.Search() 
com! FuzzyHelp Fuzzy.Help.Instance.Search() 
com! FuzzyTag Fuzzy.Tag.Instance.Search() 
com! -nargs=* -complete=dir FuzzyGrep Fuzzy.Grep.Instance.Search(<q-args>) 

nn os :FuzzyShell
nn om <cmd>FuzzyMRU<cr>
nn ol <cmd>FuzzyLine<cr>
nn of <cmd>FuzzyFind<cr>
nn ob <cmd>FuzzyCmdHistory<cr>
nn ox <cmd>FuzzyCmd<cr>
nn oz <cmd>FuzzyBuffer<cr>
nn og <cmd>FuzzyGitFile<cr>
nn oe <cmd>FuzzyExplorer<cr>
nn on <cmd>FuzzyKeyMap<cr>
nn oh <cmd>FuzzyHelp<cr>
nn ok <cmd>FuzzyTag<cr>
nn oi <cmd>FuzzyGrep<cr>

if !hlexists('PopupSelected')
  hi def link PopupSelected  CursorLine
endif
if !hlexists('FuzzyMatchCharacter')
  hi FuzzyMatchCharacter ctermfg=136 cterm=underline 
endif
if !hlexists('FuzzyBorderNormal')
  hi FuzzyBorderNormal ctermfg=4 cterm=none
endif
if !hlexists('FuzzyBorderRunning')
  hi FuzzyBorderRunning ctermfg=136 cterm=none
endif

if empty(prop_type_get('PopupSelected'))
  prop_type_add('PopupSelected', {highlight: "PopupSelected", override: true, priority: 999, combine: true})
endif
if empty(prop_type_get('FuzzyMatchCharacter'))
  prop_type_add('FuzzyMatchCharacter', {highlight: "FuzzyMatchCharacter", override: true, priority: 1000, combine: true})
endif
if empty(prop_type_get('FuzzyBorderRunning'))
  prop_type_add('FuzzyBorderRunning', {highlight: "FuzzyBorderRunning", override: true, priority: 1000, combine: true})
endif

