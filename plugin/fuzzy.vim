vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "Fuzzy.vim"


nn ,m <scriptcmd>Fuzzy.MRU.new().Search()<cr>
nn ,l <scriptcmd>Fuzzy.Line.new().Search()<cr>
nn ,a <scriptcmd>Fuzzy.File.new().Search()<cr>
nn ,h <scriptcmd>Fuzzy.CmdHistory.new().Search()<cr>
nn ,x <scriptcmd>Fuzzy.Cmd.new().Search()<cr>
nn ,z <scriptcmd>Fuzzy.Buffer.new().Search()<cr>
nn ,g <scriptcmd>Fuzzy.GitFile.new().Search()<cr>
