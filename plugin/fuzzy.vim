vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "Fuzzy.vim"


com! FuzzyMRU Fuzzy.MRU.Instance.Search() 
com! FuzzyLine Fuzzy.Line.Instance.Search() 
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
com! FuzzyPrompt Fuzzy.Prompt.Instance.Search() 

nn ,s :FuzzyShell
nn ,m <cmd>FuzzyMRU<cr>
nn ,l <cmd>FuzzyLine<cr>
nn ,f <cmd>FuzzyFind<cr>
nn ,j <cmd>FuzzyCmdHistory<cr>
nn ,x <cmd>FuzzyCmd<cr>
nn ,z <cmd>FuzzyBuffer<cr>
nn ,g <cmd>FuzzyGitFile<cr>
nn ,e <cmd>FuzzyExplorer<cr>
nn ,k <cmd>FuzzyKeyMap<cr>
nn ,h <cmd>FuzzyHelp<cr>
nn ,n <cmd>FuzzyTag<cr>
nn ,p <cmd>FuzzyPrompt<cr>

if !hlexists('FuzzyMatch')
  hi FuzzyMatch term=inverse cterm=inverse ctermfg=64 ctermbg=0
endif
if !hlexists('FuzzyMatchCharacter')
  hi FuzzyMatchCharacter ctermfg=136 cterm=underline 
endif
if !hlexists('FuzzyBorderNormal')
  hi FuzzyBorderNormal ctermfg=64 cterm=none
endif
if !hlexists('FuzzyBorderRunning')
  hi FuzzyBorderRunning ctermfg=136 cterm=none
endif

if empty(prop_type_get('FuzzyMatch'))
  prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 999, combine: true})
endif
if empty(prop_type_get('FuzzyMatchCharacter'))
  prop_type_add('FuzzyMatchCharacter', {highlight: "FuzzyMatchCharacter", override: true, priority: 1000, combine: true})
endif
if empty(prop_type_get('FuzzyBorderRunning'))
  prop_type_add('FuzzyBorderRunning', {highlight: "FuzzyBorderRunning", override: true, priority: 1000, combine: true})
endif

fu CompleteMonths(findstart, base)
  if a:findstart
    " locate the start of the word
    let line = getline('.')
    let start = col('.') - 1
    while start > 0 && line[start - 1] =~ '\a'
      let start -= 1
    endwhile
    return start
  else
    " find months matching with "a:base"
    let res = []
    for m in split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec")
      if m =~ '.*' .. a:base
        call add(res, m)
      endif
    endfor
    return res
  endif
endf

# use C-X C-I to trigger
set completefunc=CompleteMonths

fu Thesaur(findstart, base)
  if a:findstart
    return searchpos('\<', 'bnW', line('.'))[1] - 1
  endif
  let res = []
  let h = ''
  for l in systemlist('aiksaurus ' .. shellescape(a:base))
    if l[:3] == '=== '
      let h = '(' .. substitute(l[4:], ' =*$', ')', '')
    elseif l ==# 'Alphabetically similar known words are: '
      let h = "\U0001f52e"
    elseif l[0] =~ '\a' || (h ==# "\U0001f52e" && l[0] ==# "\t")
      call extend(res, map(split(substitute(l, '^\t', '', ''), ', '), {_, val -> {'word': val, 'menu': h}}))
    endif
  endfor
  return res
endf

if exists('+thesaurusfunc')
  set thesaurusfunc=Thesaur
endif
