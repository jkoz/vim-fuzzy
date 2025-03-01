vim9script 

import autoload "./KeyHandler.vim" as kh


interface Fuzzy
  def Initialize(): void
  def DoFuzzy(searchstr: string)
  def Search(): void
  def GetDisplayList(): list<string> 
  def GetSelectedItem(): string 
  def SelectedItem_Down(): void
  def SelectedItem_Up(): void
endinterface

abstract class AbstractFuzzy implements Fuzzy
  var _handlers: kh.KeyHandlerManager =  kh.KeyHandlerManagerImpl.new()
  var _selected_id: number = 0  # current selected index
  var _input_list: list<any>    # input list 
  var _results: list<list<any>> # return by matchfuzzypos()

  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ">> "
  var _searchstr: string

  def __Initialize()
    echo "Missing internal initialization for input list"
  enddef

  def Initialize()
    if !hlexists('FuzzyMatch')
      hi def link FuzzyMatch PmenuSel
    endif
    if empty(prop_type_get('FuzzyMatch'))
      prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 1000, combine: true})
    endif
    ch_logfile('/tmp/vim-fuzz.log', 'w')

    this.__Initialize() # subclass init
  enddef

  def FormatSelectedItem()
    if (!this._results[0]->empty())
      setbufvar(this._bufnr, '&filetype', '')
      prop_add(this._selected_id + 2, 1, { length: 120, type: 'FuzzyMatch', bufnr: this._bufnr })
    endif
  enddef

  # if up/down call update, there is no update on searchstr
  def Update(ss: string)

    # update latest search string from RegularKeyHandler
    this._searchstr = ss

    if (this._searchstr->empty()) # searchstr is now empty, restore _input_list
      this._results = [this._input_list]
    else # got a new _searhstr, lets match
      this.DoFuzzy(this._searchstr)
    endif

    # Clear old matched lines in the buffer, skip the first line 
    deletebufline(this._bufnr, 1, "$")

    # TODO: HACK to disable delete empty buffer messg "--No Lines in BUffers--"
    echo ""

    # update current filter items to buffer including the prompt
    setbufline(this._bufnr, '$', this._prompt .. this._searchstr)
    this.GetDisplayList()->appendbufline(this._bufnr, '$')
  enddef

  def Search(): void
    this.Initialize() # populate search list

    if (empty(this._input_list)) # got an empty list, do nothing
      echo "Provided list are empty"
      return
    endif

    # initially, results[0] will be set to input_list
    this._results = [this._input_list]

    this._popup_id = popup_create( 
      extend([this._prompt], this.GetDisplayList()), {
        filter: this._OnKeyDown,
        mapping: 0, 
        filtermode: 'a',
        minwidth: float2nr(&columns * 0.6),
        maxwidth: float2nr(&columns * 0.6),
        maxheight: float2nr(&lines * 0.6),
        minheight: float2nr(&lines * 0.6),
        highlight: '',
        padding: [0, 1, 0, 1],
        border: [1, 1, 1, 1],
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
      })

    this._bufnr = winbufnr(this._popup_id)
    this.FormatSelectedItem()  # we have initial _input_list, high light first item right away
  enddef

  def _OnKeyDown(winid: number, key: string): bool
    ch_log("Fuzzy.vim: _OnkeyDown(): key = '" .. key .. "' ")
    return this._handlers.OnKeyDown({
      'key': key,
      'winid': winid, 
      'searchstr': this._searchstr,
      'on_enter_cb': this.OnEnter,
      'on_item_up_cb': this.SelectedItem_Up,
      'on_item_down_cb': this.SelectedItem_Down,
      'update_cb': this.Update,
      'format_cb': this.FormatSelectedItem
    })
  enddef

  def OnEnter()
    echo "missing OnEnter() implement for fuzzy command"
  enddef

  def DoFuzzy(searchstr: string): void
    this._results = this._input_list->matchfuzzypos(searchstr)
  enddef

  def GetDisplayList(): list<string> 
    ch_log("Fuzzy.vim: Update(): GetDisplayList()= '" .. this._results[0]->string() .. "' ")
    return this._results[0]
  enddef

  def GetSelectedItem(): string
    return this._results[0]->empty() ? "" : this.GetDisplayList()[this._selected_id]
  enddef

  def SelectedItem_Down(): void
    this._selected_id = min([this._selected_id + 1, this.GetDisplayList()->len() - 1])
    ch_log("Fuzzy.vim: SelectedItem_Down  " .. this._selected_id)
  enddef

  def SelectedItem_Up(): void
    this._selected_id = max([this._selected_id - 1, 0])
    ch_log("Fuzzy.vim: SelectedItem_Up  " .. this._selected_id)
  enddef
endclass 

abstract class EditFuzzy extends AbstractFuzzy
  def OnEnter()
    execute($"edit {this.GetSelectedItem()}")
  enddef
endclass

export class MRU extends EditFuzzy
  def __Initialize()
    this._input_list = v:oldfiles->copy()->filter((_, v) => filereadable(fnamemodify(v, ":p")))
  enddef
endclass

export class File extends EditFuzzy
  def __Initialize()
    this._input_list = getcompletion('', 'file')
  enddef
endclass

export class JumpFuzzy extends AbstractFuzzy
  def OnEnter()
    if (!this._results[0]->empty())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef
endclass

export class Line extends JumpFuzzy
  def __Initialize()
    # TODO: - Crash at java files Animal.java
    this._input_list = matchbufline(winbufnr(0), '\S.*', 1, '$') 
  enddef

  def DoFuzzy(searchstr: string)
    #  _input_list: [{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}]
    #      > matchfuzzypos(_input_list, 'cy', {'key': 'text'})
    #  _results: [[{'lnum': 2, 'hj': 55, 'text': 'lacylicyc'}, {'lnum': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
    this._results = this._input_list->matchfuzzypos(searchstr, {'key': 'text'})
  enddef

  def GetDisplayList(): list<string> 
    return this._results[0]->mapnew((_, v) => v.text) # convert from list<dict> to list<string>
  enddef
endclass

abstract class ExecuteFuzzy extends AbstractFuzzy
  def OnEnter()
    feedkeys(":" .. this.GetSelectedItem(), "n") # feed keys to command only, don't execute it 
  enddef
endclass

export class CmdHistory extends ExecuteFuzzy
  def __Initialize()
    this._input_list = [ histget('cmd') ]
    this._input_list += range(1, histnr('cmd'))->mapnew((_, v) =>  histget('cmd', v) )  
  enddef
endclass

export class Cmd extends ExecuteFuzzy
  def __Initialize()
    this._input_list = getcompletion('', 'command')
  enddef
endclass

export class Buffer extends EditFuzzy
  def __Initialize()
    this._input_list = getcompletion('', 'buffer')->filter((_, v) => bufnr(v) != bufnr())
  enddef
endclass

export class GitFile extends EditFuzzy
  var _file_pwd: string

  def __Initialize()
    # get directory path of current open file, can check error here 
    this._file_pwd = expand('%:p:h')
    # find top level of current open files & list all git files in the projects
    # TODO: call with async timer start
    # show popup with out data, then timer_start fill the popup screen
    this._input_list = systemlist('git -C ' .. this._file_pwd .. ' ls-files `git -C ' .. this._file_pwd .. ' rev-parse --show-toplevel`')
  enddef

  def OnEnter()
    execute($"edit {this._file_pwd .. "/" .. this.GetSelectedItem()}")
  enddef

  def GetDisplayList(): list<string> 
    # echo "../../../../fff/jjj/autoload/fuzzy.vim"->substitute('.*\/\(/*`\)$', '\1', '')
    return this._results[0]->mapnew((_, v) => v->substitute('.*\/\(.*\)$', '\1', ''))
  enddef

  # TODO: eed to figure out whey turn this on failed.
  # def GetSelectedItem(): string
  #   return this._results[0]->empty() ? "" : this._results[0].[this._selected_id]
  # enddef

endclass
