vim9script 

import autoload "./KeyHandler.vim" as kh


interface Fuzzy
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

  def FormatSelectedItem()
    if (!this._results[0]->empty())
      setbufvar(this._bufnr, '&filetype', '')

      # Add highlight line text prop, need a bufnr
      if empty(prop_type_get('FuzzyMatch'))
        hi def link FuzzyMatch PmenuSel
        prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 1000, combine: true})
      endif

      # initally, _index will point to 0
      # TODO: uncomment me for current high light
      
        prop_add(this._selected_id + 2, 1, { length: 70, type: 'FuzzyMatch', bufnr: this._bufnr })
    endif
  enddef

  # if up/down call update, there is no update on searchstr
  def Update(ss: string)
    ch_log("Fuzzy.vim: Update(): this._searchstr = '" .. this._searchstr .. "'")

    # update latest search string from RegularKeyHandler
    this._searchstr = ss

    if (!empty(this._searchstr))

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
    if (empty(this._input_list))
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
        padding: [0, 1, 0, 1],
        border: [1, 1, 1, 1],
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
      })

    this._bufnr = winbufnr(this._popup_id)
    this.FormatSelectedItem()  # we have initial _input_list, high light first item right away
  enddef

  def _OnKeyDown(winid: number, key: string): bool
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
  def new()
    this._input_list = v:oldfiles->copy()->filter((_, v) => filereadable(fnamemodify(v, ":p")))
    # DEBUG
    ch_logfile('/tmp/fuzzy.log', 'w')
  enddef
endclass

export class File extends EditFuzzy
  def new()
    this._input_list = getcompletion('', 'file')
  enddef
endclass

export class JumpFuzzy extends AbstractFuzzy

endclass

export class Line extends JumpFuzzy
  def new()
    # TODO:
    #  - Remove blanks space      
    #  - Crash at java files Animal.java
    this._input_list = matchbufline(winbufnr(0), $'\S.*', 1, '$') 
    ch_logfile('/tmp/fuzzy.log', 'w')
  enddef

  def DoFuzzy(searchstr: string)
    #  _input_list: [{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}]
    #      > matchfuzzypos(_input_list, 'cy', {'key': 'text'})
    #  _results: [[{'lnum': 2, 'hj': 55, 'text': 'lacylicyc'}, {'lnum': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
    this._results = this._input_list->matchfuzzypos(searchstr, {'key': 'text'})
  enddef

  def GetDisplayList(): list<string> 
    # ch_log("Fuzzy.vim: Line.GetDisplayList:  " .. this._results->string())
    var ret: list<string> = []
    this._results[0]->foreach((_, v) => {
        ret->extend([v.text])
        # ret->extend([v.lnum .. "\t" ..  v.text])
      })
    # ch_log("Fuzzy.vim: GetDisplayList.ret" .. ret->string())
    return ret
  enddef

  def OnEnter()
    if (!this._results[0]->empty())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef

endclass
