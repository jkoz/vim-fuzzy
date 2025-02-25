vim9script

interface IKeyContext
  def GetWinId(): number
  def GetBufNr(): number
  def GetKey(): string
endinterface

interface IGenericDisplay
  def Show(display_lines: list<any>)
endinterface

interface IFuzzy
  def OnEnter(selected: string): void
  def DoFuzzy(searchstr: string)
  def Search(): void # main call from mapping commands
  def GetDisplayList(): list<string> # ret list of matched string for display
  def GetSelectedItem(): string # return current choice, 1 choice for simpility
  def GetSelectedItemIndex(): number
  def SelectedItem_Down(): void
  def SelectedItem_Up(): void
endinterface

interface Formater
  def Format(bufnr: number, index: number)
endinterface

interface IDisplay extends IGenericDisplay
  def Update(event: IKeyContext) # this may not in here, just for vim termianl update
  def GetBufNr(): number # get current bufnr in the display
  def SetSearchStr(search_str: string) # call by handler
  def GetSearchStr(): string
  def GetLineFormatter(): Formater # return formatter for using in Keyhandler
  def GetFuzzySpecific(): IFuzzy
  def FormatSelectedItem()
endinterface

class KeyContext implements IKeyContext
  var _win_id: number
  var _key: string
  var _bufnr: number

  def new(winid: number, key: string)
    this._win_id = winid
    this._key = key
    this._bufnr = winbufnr(winid)
  enddef

  def GetWinId(): number
    return this._win_id
  enddef

  def GetKey(): string
    return this._key
  enddef

  def GetBufNr(): number
    return this._bufnr
  enddef
endclass

class SelectedFormatter implements Formater
  def Format(bufnr: number, index: number)


    setbufvar(bufnr, '&filetype', '')

    # Add highlight line text prop, need a bufnr
    if empty(prop_type_get('FuzzyMatch'))
        # prop_type_add('match', { bufnr: bufnr, highlight: 'PmenuSel'})
        hi def link FuzzyMatch PmenuSel
        prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 1000, combine: true})
    endif

    # initally, _index will point to 0
    # TODO: uncomment me for current high light
    ch_log('Fuzzy.vim: SelectedFormatter.Format: bufnr: ' .. bufnr .. " id: " .. index)
    prop_add(index + 2, 1, { length: 70, type: 'FuzzyMatch', bufnr: bufnr })

  enddef
endclass

# IKeyHandler is specific for vim script display
interface IKeyHandler
	def Perform(dis: IDisplay, event: IKeyContext): bool
  def Accept(key: string): bool
endinterface

abstract class AbstractKeyHandler implements IKeyHandler
  # list of key subless handler will take care of
	# initialized static options
	var _popup_opts = {
		mapping: 0, 
		filtermode: 'a',
		minwidth: &columns / 2,
		maxheight: &lines - 8,
    border: [],
		borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
	}

  def new(fuzzy: IFuzzy)
    this._fuzzy = fuzzy
    ch_logfile('/tmp/fuzzy.log', 'w')
  enddef

  def GetLineFormatter(): Formater
    return this._line_formater
  enddef

  def GetFuzzySpecific(): IFuzzy
    return this._fuzzy
  enddef

  def FormatSelectedItem()
    if (!this._fuzzy.GetSelectedItem()->empty())
      # if we got an selected items, we high light it up
      this._line_formater.Format(this.GetBufNr(), this._fuzzy.GetSelectedItemIndex())
    endif
  enddef

  def SetSearchStr(search_str: string) 
    this._searchstr = search_str
  enddef

  def GetSearchStr(): string
    return this._searchstr
  enddef

  def GetBufNr(): number
    return winbufnr(this._popup_id)
  enddef

  def Update(event: IKeyContext)
    if (!empty(this._searchstr))
      # matchfuzzypos([{'id': 1, 'text': 'clay'}, {'id': 2, 'text': 'lacylicyc', 'hj': 55}], 'cy', {'key': 'text'})
      # > [[{'id': 2, 'hj': 55, 'text': 'lacylicyc'}, {'id': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
      #
      #  _matched_items: [{'id': 1, 'text': 'clay'}, {'id': 2, 'text': 'lacylicyc', 'hj': 55}]
      #  _filter_items: [[{'id': 2, 'hj': 55, 'text': 'lacylicyc'}, {'id': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]

      this.GetFuzzySpecific().DoFuzzy(this._searchstr)

    endif

    # Clear old matched lines in the buffer, skip the first line 
    deletebufline(event.GetBufNr(), 1, "$")

    # TODO: HACK to disable delete empty buffer messg "--No Lines in BUffers--"
    echo ""

    # update current filter items to buffer including the prompt
    setbufline(event.GetBufNr(), '$', this._prompt .. this._searchstr)
    this.GetFuzzySpecific().GetDisplayList()->appendbufline(event.GetBufNr(), '$')
  enddef

  def _OnKeyDown(winid: number, key: string): bool
    var context: IKeyContext = KeyContext.new(winid, key)
    # 1. handle all special keys first
    for it in PopupDisplay.handlers
      if (it.Accept(key)) 
        if it.Perform(this, context) |  return true | endif 
      endif
    endfor

    # 2. 2. here comes the regular keys: a, b, c..
    PopupDisplay.regular_handler.Perform(this, context)

    return true
  enddef

  def Show(display_lines: list<any>)
    this._popup_id = popup_create(
      extend([this._prompt], display_lines), 
      extend({filter: this._OnKeyDown}, this._popup_opts))
    this.FormatSelectedItem()
  enddef
endclass

abstract class AbstractFuzzy implements IFuzzy
  var _display: IDisplay = PopupDisplay.new(this) 

  var _selected_id: number = 0 # current choice in the list, point to the top item which is 0 (_promp is not part of the list)
  var _input_list: list<any> # input list 
  var _results: list<list<any>> # return by matchfuzzypos()

  def Search(): void
    if (empty(this._input_list))
      echo "Provided list are empty"
      return
    endif

    # initially, results[0] will be set to input_list
    this._results = [this._input_list]

    ch_log("Fuzzy.vim: Search._input_list  " .. this._input_list->string())
    this._display.Show(this._input_list)
  enddef

  def OnEnter(selected: string)
    echo "missing OnEnter() implement for fuzzy command"
  enddef

  def DoFuzzy(searchstr: string): void
    this._results = this._input_list->matchfuzzypos(searchstr)
  enddef

  def GetDisplayList(): list<string> 
    return this._results[0]
  enddef

  def GetSelectedItem(): string
    ch_log("Fuzzy.vim: GetSelectedItem id: " .. this._selected_id)
    ch_log("Fuzzy.vim: GetSelectedItem id: " .. this.GetDisplayList())
    return this.GetDisplayList()->empty() ? "" : this.GetDisplayList()[this._selected_id]
  enddef

  def GetSelectedItemIndex(): number
    return this._selected_id
  enddef

  def SelectedItem_Down(): void
    # ch_log('Fuzzy.vim: SelectedItem_Down before: ' .. this.GetSelectedItemIndex())
    this._selected_id = min([this.GetSelectedItemIndex() + 1, this.GetDisplayList()->len() - 1])
    ch_log('Fuzzy.vim: SelectedItem_Down after: ' .. this.GetSelectedItemIndex())
  enddef

  def SelectedItem_Up(): void
    # ch_log('Fuzzy.vim: SelectedItem_Up before: ' .. this.GetSelectedItemIndex())
    this._selected_id = max([this.GetSelectedItemIndex() - 1, 0])
    ch_log('Fuzzy.vim: SelectedItem_Up after: ' .. this.GetSelectedItemIndex())
  enddef
endclass 

abstract class EditFuzzy extends AbstractFuzzy
  def OnEnter(selected: string)
    execute($"edit {selected}")
  enddef
endclass

export class MRU extends EditFuzzy
  def new()
    this._input_list = v:oldfiles->copy()->filter((_, v) => filereadable(fnamemodify(v, ":p")))
  enddef
endclass

export class File extends EditFuzzy
  var _path: string = ''
  def new()
    var opath = expand(this._path ?? "%:p:h")
    if !isdirectory(opath) | opath = getcwd() | endif
    this._input_list = readdir(opath)->mapnew((_, v) => opath .. "/" .. v)
  enddef
endclass

export class Buffer extends EditFuzzy
  def new()
	  this._input_list = getcompletion('', 'buffer')->filter((_, val) => bufnr(val) != bufnr())
  enddef
  def OnEnter(selected: string)
    execute($"buffer {selected}")
  enddef
endclass

export class Cmd extends AbstractFuzzy
  def new()
    this._input_list = getcompletion('', 'command')->copy()
  enddef
  def OnEnter(selected: string)
    feedkeys($":{selected}\<CR>", "nt")
  enddef
endclass

abstract class JumpFuzzy extends AbstractFuzzy
endclass

export class Line extends JumpFuzzy
  def new()

    # [ {'id': 1, 'text': 'line 1'}, {'id': 1, 'text': 'line 1'} ]
    # this._input_list = range(1, line('$'))->map((_, v) => string(v))
    # var lines = matchbufline(bufnr(), $'^.*\<{word}\>.*$', 1, '$')
    this._input_list = matchbufline(this._display.GetBufNr(), $'^.*.*$', 1, '$') 

    # {lnum: 14, text: "line"

  enddef

  def DoFuzzy(searchstr: string)
    this._results = this._input_list->matchfuzzypos(searchstr, {'key': 'text'})
  enddef

  def GetDisplayList(): list<string> 
    # ch_log("Fuzzy.vim: Line.GetDisplayList:  " .. this._results->string())
    var ret: list<string> = []
    this._results[0]->foreach((_, v) => {
        ret->extend([v.text])
      })
    ch_log("Fuzzy.vim: GetDisplayList.ret" .. ret->string())
    return ret
  enddef
endclass

