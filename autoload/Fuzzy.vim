vim9script 

import autoload "./KeyHandler.vim" as kh


interface Fuzzy

  def DoFuzzy(searchstr: string)

  # main call from mapping commands
  def Search(): void

  # ret list of matched string for display
  def GetDisplayList(): list<string> 

  def GetSelectedItem(): string 

  def SelectedItem_Down(): void

  def SelectedItem_Up(): void

  def IsEmptyResults(): bool

  def GetSelectedItem_Index(): number

  def Initialize_Result_List()

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


	# initialized static options
	var _popup_opts = {
		mapping: 0, 
		filtermode: 'a',
		minwidth: &columns / 2,
		maxheight: &lines - 8,
    border: [],
		borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
	}

  def FormatSelectedItem()
    if (!this.IsEmptyResults())
      setbufvar(this._bufnr, '&filetype', '')

      # Add highlight line text prop, need a bufnr
      if empty(prop_type_get('FuzzyMatch'))
        hi def link FuzzyMatch PmenuSel
        prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 1000, combine: true})
      endif

      # initally, _index will point to 0
      # TODO: uncomment me for current high light
      
        prop_add(this.GetSelectedItem_Index() + 2, 1, { length: 70, type: 'FuzzyMatch', bufnr: this._bufnr })
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

  def Initialize_Result_List()
    # initially, results[0] will be set to input_list
    this._results = [this._input_list]
  enddef 

  def Search(): void
    if (empty(this._input_list))
      echo "Provided list are empty"
      return
    endif

    this.Initialize_Result_List()

    this._popup_id = popup_create( extend([this._prompt], this._input_list), extend({filter: this._OnKeyDown}, this._popup_opts))
    this._bufnr = winbufnr(this._popup_id)

    this.FormatSelectedItem()

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
    return this.IsEmptyResults() ? "" : this.GetDisplayList()[this._selected_id]
  enddef

  def IsEmptyResults(): bool
    return this.GetDisplayList()->empty()
  enddef

  def GetSelectedItem_Index(): number
    return this._selected_id
  enddef

  def SelectedItem_Down(): void
    this._selected_id = min([this.GetSelectedItem_Index() + 1, this.GetDisplayList()->len() - 1])
    ch_log("Fuzzy.vim: SelectedItem_Down  " .. this._selected_id)
  enddef

  def SelectedItem_Up(): void
    this._selected_id = max([this.GetSelectedItem_Index() - 1, 0])
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
    # [ {'id': 1, 'text': 'line 1'}, {'id': 1, 'text': 'line 1'} ]
    # [{lnum: 14, text: "line"]
    # winbufnr(0) return the current buff
    # TODO: need to remove blanks space      
    this._input_list = matchbufline(winbufnr(0), $'^.*$', 1, '$') 
    ch_logfile('/tmp/fuzzy.log', 'w')
  enddef

  def DoFuzzy(searchstr: string)
    # matchfuzzypos([{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}], 'cy', {'key': 'text'})
    # > [[{'id': 2, 'hj': 55, 'text': 'lacylicyc'}, {'id': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
    #
    #  _input_list: [{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}]
    #      > matchfuzzypos(_input_list, 'cy', {'key': 'text'})
    #  _results: [[{'lnum': 2, 'hj': 55, 'text': 'lacylicyc'}, {'lnum': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
    this._results = this._input_list->matchfuzzypos(searchstr, {'key': 'text'})
  enddef

  def Initialize_Result_List()
    # initially, results[0] will be set to input_list
    this._results = [this._input_list]
  enddef 

  def GetDisplayList(): list<string> 
    # ch_log("Fuzzy.vim: Line.GetDisplayList:  " .. this._results->string())
    var ret: list<string> = []
    this._results[0]->foreach((_, v) => {
        ret->extend([v.text])
      })
    # ch_log("Fuzzy.vim: GetDisplayList.ret" .. ret->string())
    return ret
  enddef

  def IsEmptyResults(): bool
    ch_log("Fuzzy.vim: IsEmptyResults(): this._searchstr = '" .. this._results[0]->string() .. "'")
    return this._results[0]->empty()
  enddef

  def OnEnter()
    if (!this.IsEmptyResults())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef

  def FormatSelectedItem()
    if (!this.IsEmptyResults())
      setbufvar(this._bufnr, '&filetype', '')

      # Add highlight line text prop, need a bufnr
      if empty(prop_type_get('FuzzyMatch'))
        hi def link FuzzyMatch PmenuSel
        prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 1000, combine: true})
      endif

      # initally, _index will point to 0
      # TODO: uncomment me for current high light
      # lines does not show up at first times,
      if (this.GetSelectedItem_Index() != 0)
        prop_add(this.GetSelectedItem_Index() + 2, 1, { length: 70, type: 'FuzzyMatch', bufnr: this._bufnr })
      endif
    endif
  enddef

endclass
