vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "fuzzy.vim" as fz

nn ,m <scriptcmd>fz.MRU.new().Search()<cr>
nn ,x <scriptcmd>fz.Cmd.new().Search()<cr>
nn ,z <scriptcmd>fz.Buffer.new().Search()<cr>
nn ,l <scriptcmd>fz.Line.new().Search()<cr>
nn ,ff <scriptcmd>fz.File.new().Search()<cr>
