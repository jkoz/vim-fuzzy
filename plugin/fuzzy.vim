vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "fuzzy.vim" as Fuzzy

g:fuzzy_commands = {
  'MRU': Fuzzy.MRU.new(),
  'CmdHistory': Fuzzy.CmdHistory.new(),
  'Cmd': Fuzzy.Cmd.new(),
  'Buffer': Fuzzy.Buffer.new(),
  'GitFile': Fuzzy.GitFile.new(),
  'Explorer': Fuzzy.Explorer.new(),
  'KeyMap': Fuzzy.VimKeyMap.new(),
  'Help': Fuzzy.Help.new(),
  'Tag': Fuzzy.Tag.new(),
  'Highlight': Fuzzy.Highlight.new(),
  'Line': Fuzzy.Line.new(),
  'Grep': Fuzzy.Grep.new(),
  'LGrep': Fuzzy.LGrep.new(),
  'Find': Fuzzy.Find.new(),
  'Shell': Fuzzy.ShellFuzzy.new(),
  'Quickfix': Fuzzy.QuickFix.new(),
}

g:fuzzy_logger = Fuzzy.Logger.new()

com! FuzzyMRU g:fuzzy_commands.MRU.Search() 
com! FuzzyCmdHistory g:fuzzy_commands.CmdHistory.Search() 
com! FuzzyCmd g:fuzzy_commands.Cmd.Search() 
com! FuzzyBuffer g:fuzzy_commands.Buffer.Search() 
com! FuzzyGitFile g:fuzzy_commands.GitFile.Search() 
com! FuzzyExplorer g:fuzzy_commands.Explorer.Search() 
com! FuzzyKeyMap g:fuzzy_commands.KeyMap.Search() 
com! FuzzyHelp g:fuzzy_commands.Help.Search() 
com! FuzzyTag g:fuzzy_commands.Tag.Search() 
com! FuzzyHighlight g:fuzzy_commands.Highlight.Search() 
com! FuzzyQuickFix g:fuzzy_commands.Quickfix.Search() 
com! -nargs=* FuzzyLine g:fuzzy_commands.Line.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyGrep g:fuzzy_commands.Grep.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyFind g:fuzzy_commands.Find.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyShell g:fuzzy_commands.Shell.Search(<q-args>) 
com! -nargs=* -complete=dir FuzzyGrepL g:fuzzy_commands.LGrep.Search(<q-args>) 

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
nn oa <cmd>FuzzyHighlight<cr>
nn oq <cmd>FuzzyQuickFix<cr>
nn od <cmd>FuzzyGrepL<cr>


if !hlexists('PopupSelected') | hi def link PopupSelected  CursorLine | endif
if !hlexists('FuzzyMatchCharacter') | hi FuzzyMatchCharacter ctermfg=136 cterm=underline | endif
if !hlexists('FuzzyBorderNormal') | hi FuzzyBorderNormal ctermfg=4 cterm=none | endif
if !hlexists('FuzzyBorderRunning') | hi FuzzyBorderRunning ctermfg=136 cterm=none | endif
if !hlexists('FuzzyBorderRunning') | hi FuzzyBorderRunning ctermfg=136 cterm=none | endif
if !hlexists('FuzzyPostText') | hi FuzzyPostText ctermfg=11 cterm=none | endif
if !hlexists('FuzzyGrepMatch') | | hi FuzzyGrepMatch term=bold,underline cterm=bold,underline ctermfg=8 ctermbg=136 | endif

if empty(prop_type_get('PopupSelected'))
  prop_type_add('PopupSelected', {highlight: "PopupSelected", override: true, priority: 999, combine: true})
endif
if empty(prop_type_get('FuzzyMatchCharacter'))
  prop_type_add('FuzzyMatchCharacter', {highlight: "FuzzyMatchCharacter", override: true, priority: 1000, combine: true})
endif
if empty(prop_type_get('FuzzyBorderRunning'))
  prop_type_add('FuzzyBorderRunning', {highlight: "FuzzyBorderRunning", override: true, priority: 1000, combine: true})
endif
if empty(prop_type_get('FuzzyPostText'))
  prop_type_add('FuzzyPostText', {highlight: "FuzzyPostText", override: true, priority: 1000, combine: true})
endif
if empty(prop_type_get('FuzzyGrepMatch'))
  prop_type_add('FuzzyGrepMatch', {highlight: "FuzzyGrepMatch", override: true, priority: 1000, combine: true})
endif

