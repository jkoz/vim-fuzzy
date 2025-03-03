vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "Fuzzy.vim"

com! FuzzyMRU Fuzzy.Types.MRU.Search() 
com! FuzzyLine Fuzzy.Types.Line.Search() 
com! -nargs=* -complete=dir FuzzyFind Fuzzy.Types.Find.Search(<q-args>) 
com! FuzzyCmdHistory Fuzzy.Types.CmdHistory.Search() 
com! FuzzyCmd Fuzzy.Types.Cmd.Search() 
com! FuzzyBuffer Fuzzy.Types.Buffer.Search() 
com! FuzzyGitFile Fuzzy.Types.GitFile.Search() 

nn ,m <cmd>FuzzyMRU<cr>
nn ,l <cmd>FuzzyLine<cr>
nn ,f <cmd>FuzzyFind<cr>
nn ,h <cmd>FuzzyCmdHistory<cr>
nn ,x <cmd>FuzzyCmd<cr>
nn ,z <cmd>FuzzyBuffer<cr>
nn ,g <cmd>FuzzyGitFile<cr>
