vim9script

if exists("g:loaded_fuzzy") | finish | endif
g:loaded_fuzzy = 1

import autoload "Fuzzy.vim"

# nn ,x <scriptcmd>fz.Cmd.new().Search()<cr>
# nn ,z <scriptcmd>fz.Buffer.new().Search()<cr>
# nn ,l <scriptcmd>fz.Line.new().Search()<cr>
# nn ,ff <scriptcmd>fz.File.new().Search()<cr>


nn ,m <scriptcmd>Fuzzy.MRU.new().Search()<cr>
nn ,l <scriptcmd>Fuzzy.Line.new().Search()<cr>
nn ,f <scriptcmd>Fuzzy.File.new().Search()<cr>
