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

  def GetSelectedItem_Index(): number

endinterface


abstract class AbstractFuzzy implements Fuzzy

  static var handlers: list<kh.KeyHandler> = [
    kh.EnterHandler.new(), 
    kh.CancelHandler.new(),
    kh.UpHandler.new(),
    kh.DownHandler.new()
  ]
  static var regular_handler = kh.RegularKeyHandler.new()

  var _selected_id: number = 0  # current selected index
  var _input_list: list<any>    # input list 
  var _results: list<list<any>> # return by matchfuzzypos()

  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ">> "
  var _searchstr: string

  # static var _regular_handler = kh.RegularHandler.new() 

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
    if (!this.GetSelectedItem()->empty())
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
      # matchfuzzypos([{'id': 1, 'text': 'clay'}, {'id': 2, 'text': 'lacylicyc', 'hj': 55}], 'cy', {'key': 'text'})
      # > [[{'id': 2, 'hj': 55, 'text': 'lacylicyc'}, {'id': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
      #
      #  _matched_items: [{'id': 1, 'text': 'clay'}, {'id': 2, 'text': 'lacylicyc', 'hj': 55}]
      #  _filter_items: [[{'id': 2, 'hj': 55, 'text': 'lacylicyc'}, {'id': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]

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

    this._popup_id = popup_create( extend([this._prompt], this._input_list), extend({filter: this._OnKeyDown}, this._popup_opts))
    this._bufnr = winbufnr(this._popup_id)

    this.FormatSelectedItem()

  enddef

  def _OnKeyDown(winid: number, key: string): bool
    var props = {
      'winid': winid, 
      'searchstr': this._searchstr,
      'on_enter_cb': this.OnEnter,
      'on_item_up_cb': this.SelectedItem_Up,
      'on_item_down_cb': this.SelectedItem_Down,
      'update_cb': this.Update,
      'format_cb': this.FormatSelectedItem
    }

    # 1. handle all special keys first
    for it in AbstractFuzzy.handlers
      if (it.Accept(key, props)) 
        return true
      endif
    endfor

    # 2. 2. here comes the regular keys: a, b, c..
    AbstractFuzzy.regular_handler.Accept(key, props)

    return true
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
    return this.GetDisplayList()->empty() ? "" : this.GetDisplayList()[this._selected_id]
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
