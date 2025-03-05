vim9script 

abstract class AbstractFuzzy 
  var _key_maps: list<dict<any>> = [
    { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
    { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
    { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>"], 'cb': this.Up},
    { 'keys': ["\<C-n>", "\<Tab>", "\<Down>"], 'cb': this.Down},
    { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete},
    { 'keys': [], 'cb': this.Regular},
  ]

  var _selected_id: number = 0  # current selected index
  var _input_list: list<any>    # input list 
  var _results: list<list<any>> # return by matchfuzzypos() when do fuzzy
  var _format_result_list: list<string> # cached of result list depending on fuzzy type

  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ">> "
  var _searchstr: string
  var _key: string # user input key

  def LogMsg(...msgs: list<string>)
    ch_log("vim-fuzzy.vim > " .. msgs->reduce((a, v) => a .. " > " .. v) )
  enddef

  def __Initialize()
    # run async to get input by default, unless we expect input list is very small like buffers, windows, etc..
    this._AsyncRun()
  enddef

  # this method is call for initially populating the _input_list
  def _WrapResultList()
    # if we got some result to display & the _input_list was not populated as
    # list<dict<any>: [ 'text': 'line1' , 'text': 'line2' ]. We convert it
    # to any list<dict<any>> so we can use in matchfuzzypos later
    if (!this._input_list->empty() && type(this._input_list[0]) ==# type(''))
      this._input_list = this._input_list->mapnew((_, v) => {
          return {'text': v}
        })
    endif
    # results[0] will be set to _input_list as first run, matchfuzzypos() is not called yet
    this._SetResultList([this._input_list])
    
    this._selected_id = 0 # reset selected id on new popup
  enddef

  def Initialize()
    if !hlexists('FuzzyMatch')
      hi FuzzyMatch term=reverse cterm=reverse ctermfg=64 ctermbg=0 guibg=DarkGrey
    endif
    if empty(prop_type_get('FuzzyMatch'))
      prop_type_add('FuzzyMatch', {highlight: "FuzzyMatch", override: true, priority: 999, combine: true})
    endif
    if !hlexists('FuzzyMatchCharacter')
      hi FuzzyMatchCharacter ctermfg=136 cterm=underline 
    endif
    if empty(prop_type_get('FuzzyMatchCharacter'))
      prop_type_add('FuzzyMatchCharacter', {highlight: "FuzzyMatchCharacter", override: true, priority: 1000, combine: true})
    endif

    ch_logfile('/tmp/vim-fuzzy.log', 'w')

    # subclass fuzzy to populate _input_list
    this.__Initialize() 

    this._WrapResultList()
  enddef

  def Format()
    if (!this._results[0]->empty())
      setbufvar(this._bufnr, '&filetype', '')
      prop_add(this._selected_id + 2, 1, { length: 120, type: 'FuzzyMatch', bufnr: this._bufnr })

      if (this._results->len() > 1) # ensure we got a match locations in _result[0]
        this._results[1]->foreach((lnum, pos_list) => { # iterate over pos list whic stored in _result[1]
            pos_list->foreach((k, j) => {
                prop_add(2 + lnum, pos_list[k] + 1, { length: 1, type: 'FuzzyMatchCharacter', bufnr: this._bufnr })
            })
        }) 
      endif
    endif
  enddef

  def Update()
    if (this._searchstr->empty()) # searchstr is now empty, restore _input_list
      this._SetResultList([this._input_list])
    else # got a new _searhstr, lets match
      this.DoFuzzy(this._searchstr)
    endif

    popup_settext(this._popup_id, [this._prompt .. this._searchstr] + this._format_result_list)

    # after set new result list, format it right away
    this.Format()
  enddef

  def Search(searchstr: string = ""): void
    this._searchstr = searchstr # update search string
    this.Initialize() # populate search list

    this._popup_id = popup_create( 
      extend([this._prompt], this._format_result_list), {
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
    this.Format()  # we have initial _input_list, high light first item right away
  enddef

  def _OnKeyDown(winid: number, key: string): bool
    this._key = key
    for item in this._key_maps
      if (item.keys->empty() || item.keys->index(key) > -1)
        item.cb()
        return true
      endif
    endfor
    return false
  enddef

  def _SetResultList(rt: list<any>)
      this._results = rt
      this._format_result_list = this._BuildFormatResultList()
  enddef

  def Enter()
    if (this._results[0]->empty())
      echo "Nothing to be selected"
    else
      this._OnEnter()
      popup_close(this._popup_id)
    endif
  enddef

  def Cancel()
      popup_close(this._popup_id)
  enddef

  def DoFuzzy(searchstr: string)
    #  _input_list: [{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}]
    #      :echo matchfuzzypos([{'lnum': 1, 'text': 'clay'}, {'lnum': 2, 'text': 'lacylicyc', 'hj': 55}], 'cy', {'key': 'text'})
    #  _results: [[{'lnum': 2, 'hj': 55, 'text': 'lacylicyc'}, {'lnum': 1, 'text': 'clay'}], [[2, 3], [0, 3]], [173, 157]]
    this._SetResultList(this._input_list->matchfuzzypos(searchstr, {'key': 'text'}))
  enddef

  # this function response for what will be display on popup
  def _BuildFormatResultList(): list<string> 
    return this._results[0]->mapnew((_, v) => v.text) # convert from list<dict> to list<string>
  enddef

  def GetSelectedItem(): string
    return this._results[0][this._selected_id].text
  enddef

  def Regular(): void
    this._selected_id = 0
    this._searchstr = this._searchstr .. this._key
    this.Update()
  enddef 

  def Delete(): void
    this._searchstr = this._searchstr->substitute(".$", "", "")
    this.Update()
  enddef

  def Down(): void
    this._selected_id = min([this._selected_id + 1, this._results[0]->len() - 1])
    this.Update()
  enddef

  def Up(): void
    this._selected_id = max([this._selected_id - 1, 0])
    this.Update()
  enddef

  def _AsyncRun(cmd: string = ""): void
    echo "Loading Input List..."
    timer_start(0, (id) => { # Run & update popup
      this.LogMsg('AsyncRun()', cmd)
      this._PopulateInputList(cmd)
      this._WrapResultList()
      this.Update()
      echo ""
    })
  enddef

  def _PopulateInputList(cmd: string = "")
    echo "missing populate input list"
  enddef

endclass 

abstract class EditFuzzy extends AbstractFuzzy
  def _OnEnter()
    execute($"edit {this.GetSelectedItem()}")
  enddef
endclass

export class MRU extends EditFuzzy
  public static final Instance: MRU = MRU.new()
  def __Initialize()
    this._input_list = v:oldfiles->copy()->filter((_, v) => filereadable(fnamemodify(v, ":p")))
  enddef
endclass

export class Find extends EditFuzzy
  public static final Instance: Find = Find.new()
  def __Initialize()
    var pat = this._searchstr->empty() ? expand('%:p:h') : this._searchstr
    this._AsyncRun('find ' .. pat .. ' -type f -not -path "*/\.git/*"')
    this._searchstr = "" # reset search back to empty, as it not intend to fuzzy search on that path
  enddef
  def _PopulateInputList(cmd: string = "")
    this._input_list = systemlist(cmd)
  enddef
endclass

class JumpFuzzy extends AbstractFuzzy
  def _OnEnter()
    if (!this._results[0]->empty())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef
endclass

export class Line extends JumpFuzzy
  public static final Instance: Line = Line.new()
  def __Initialize()
    this._input_list = matchbufline(winbufnr(0), '\S.*', 1, '$') 
  enddef
endclass

abstract class ExecuteFuzzy extends AbstractFuzzy
  def _OnEnter()
    feedkeys(":" .. this.GetSelectedItem(), "n") # feed keys to command only, don't execute it 
  enddef
endclass

export class CmdHistory extends ExecuteFuzzy
  public static final Instance: CmdHistory = CmdHistory.new()
  def _PopulateInputList(cmd: string)
    # convert list of id to list of string commands
    this._input_list = [ histget('cmd') ] + range(1, histnr('cmd'))->mapnew((_, v) =>  histget('cmd', v) )  
  enddef
endclass

export class Cmd extends ExecuteFuzzy
  public static final Instance: Cmd = Cmd.new()
  def _PopulateInputList(cmd: string)
    this._input_list = getcompletion('', 'command')
  enddef
endclass

export class Buffer extends EditFuzzy
  public static final Instance: Buffer = Buffer.new()
  def __Initialize()
    this._input_list = getcompletion('', 'buffer')->filter((_, v) => bufnr(v) != bufnr())
  enddef
endclass

export class GitFile extends AbstractFuzzy
  public static final Instance: GitFile = GitFile.new()
  var _file_pwd: string

  def __Initialize()
    this._file_pwd = expand('%:p:h')
    this._AsyncRun('git -C ' .. this._file_pwd .. ' ls-files `git -C ' .. this._file_pwd .. ' rev-parse --show-toplevel`')
  enddef

  def _OnEnter()
    execute($"edit {this._file_pwd .. "/" .. this._results[0][this._selected_id].realtext}")
  enddef

  def _PopulateInputList(cmd: string = "")
    this._input_list = systemlist(cmd)->mapnew((_, v) => {
      # store realtext which hold real path of file, it will be used later _OnEnter
      return {'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}
    })
  enddef

  def _BuildFormatResultList(): list<string>
    return this._results[0]->mapnew((k, v) => v.text->substitute('.*\/\(.*\)$', '\1', ''))
  enddef
endclass
