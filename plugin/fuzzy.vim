vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "Fuzzy.vim"

com! FuzzyMRU Fuzzy.MRU.Instance.Search() 
com! FuzzyLine Fuzzy.Line.Instance.Search() 
com! -nargs=* -complete=dir FuzzyFind Fuzzy.Find.Instance.Search(<q-args>) 
com! FuzzyCmdHistory Fuzzy.CmdHistory.Instance.Search() 
com! FuzzyCmd Fuzzy.Cmd.Instance.Search() 
com! FuzzyBuffer Fuzzy.Buffer.Instance.Search() 
com! FuzzyGitFile Fuzzy.GitFile.Instance.Search() 

nn ,m <cmd>FuzzyMRU<cr>
nn ,l <cmd>FuzzyLine<cr>
nn ,f <cmd>FuzzyFind<cr>
nn ,h <cmd>FuzzyCmdHistory<cr>
nn ,x <cmd>FuzzyCmd<cr>
nn ,z <cmd>FuzzyBuffer<cr>
nn ,g <cmd>FuzzyGitFile<cr>


# type ,g & d -> fail
