vim9script 

class Logger
  def new()
    ch_logfile('/tmp/vim-fuzzy.log', 'w')
  enddef
  def Debug(...msgs: list<string>)
    ch_log("vim-fuzzy.vim > " .. msgs->reduce((a, v) => a .. " > " .. v) )
  enddef
endclass

interface MessageHandler
  def OnStdOut(ch: channel, msg: string)
  def OnStdErr(ch: channel, msg: string)
  def OnExit(ch: job, status: number)
endinterface

class Job
  var _job: job
  var _handler: MessageHandler
  def new(s: MessageHandler)
    this._handler = s
  enddef
  def Start(cmd: string)
    this._job = job_start(cmd, {out_cb: this._handler.OnStdOut, err_cb: this._handler.OnStdErr, exit_cb: this._handler.OnExit})
  enddef
  def IsDead(): bool
    return job_status(this._job) ==# 'dead'
  enddef
endclass

interface Runnable
  def Run()
endinterface

class Timer
  # var _logger: Logger
  var _delay: number
  var _name: string
  var _runnable: Runnable
  var _options: dict<any>
  var _timerId: number
  def new(name: string, runnable: Runnable, delay: number = 0, repeat: number = 0)
    # this._logger = Logger.new()
    this._delay = delay
    this._name = name
    this._runnable = runnable
    this._options = { 'repeat': repeat }
  enddef
  def Start()
    try
      # this._logger.Debug('Timer.Start() ' .. this._name .. ' runnable ' .. this._runnable->string())
      echo "..." # just indication for now which command is run async
      this._timerId = timer_start(this._delay, this._HandleTimer, this._options)
    catch
      echom 'Error from ' .. this._name .. ': ' .. v:exception->string()
    endtry
  enddef
  def _HandleTimer(timerId: number)
    this._runnable.Run()
  enddef
  def Stop()
    timer_stop(this._timerId)
  enddef
endclass

class Channel
endclass

abstract class AbstractFuzzy
  var _key_maps: list<dict<any>> = [
    { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
    { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
    { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>"], 'cb': this.Up, 'upd': this.Update},
    { 'keys': ["\<C-n>", "\<Tab>", "\<Down>"], 'cb': this.Down, 'upd': this.Update},
    { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'upd': this.Update},
    { 'keys': [], 'cb': this.Regular, 'upd': this.Update}]
  var _selected_id: number = 0  # current selected index
  var _input_list: list<any> = []   # input list 
  var _results: list<list<any>> = [] # return by matchfuzzypos() when do fuzzy
  var _format_result_list: list<string> # cached of result list depending on fuzzy type
  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ">> "
  var _searchstr: string
  var _key: string # user input key
  var _cmd: string # external commands, grep, find, etc.

  def __Initialize()
  enddef

  # this method is call for initially populating the _input_list, either async or sync
  def _WrapResultList()
    # if we got some result to display & the _input_list was not populated as
    # list<dict<any>: [ 'text': 'line1' , 'text': 'line2' ]. We convert it
    # to any list<dict<any>> so we can use in matchfuzzypos later
    if (!this._input_list->empty() && type(this._input_list[0]) ==# type(''))
      this._input_list = this._input_list->mapnew((_, v) => {
          return {'text': v}
        })
    endif
    this._results = [this._input_list] # results[0] will be set to _input_list as first run, matchfuzzypos() is not called yet
    this._FormatResultList()
    this._selected_id = 0 # reset selected id on new popup
  enddef
  def Initialize()
    if empty(prop_type_get('FuzzyMatchCharacter'))
      prop_type_add('FuzzyMatchCharacter', {highlight: "FuzzyMatchCharacter", override: true, priority: 1000, combine: true})
    endif
    this.__Initialize()  # subclass fuzzy to populate _input_list
    this._WrapResultList()
  enddef
  def Format()
    if (!this._results->empty() && !this._results[0]->empty())
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
  def _FormatResultList() # a filter for the list gonna be display
    this._format_result_list = this._results[0]->mapnew((_, v) => v.text) # convert from list<dict> to list<string>
  enddef
  def Update()
    # searchstr is now empty, restore _input_list, otherwise, we got a new _searhstr, lets match
    this._results = this._searchstr->empty() ? [this._input_list] : this._input_list->matchfuzzypos(this._searchstr, {'key': 'text'})
    this._FormatResultList()
    popup_settext(this._popup_id, [this._prompt .. this._searchstr] + this._format_result_list)
    this.Format() # after set new result list, highlight matching characters, current line...
  enddef
  def _UpdatePopupFromTimer() # Runnable implement for subclass that run async
    this._WrapResultList()
    this.Update()
  enddef
  def Search(searchstr: string = ""): void
    this._searchstr = searchstr # update search string
    this.Initialize() # populate search list

    this._popup_id = popup_create([this._prompt] + this._format_result_list, {
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
        if (item->has_key('upd'))
          item.upd()
        endif
        return true
      endif
    endfor
    return false
  enddef
  def Enter()
    if (!this._results[0]->empty())
      this._OnEnter()
      this.Cancel()
    endif
  enddef
  def Cancel()
      popup_close(this._popup_id)
      echo ""
  enddef
  def Up(): void
    this._selected_id = max([this._selected_id - 1, 0])
  enddef
  def Down(): void
    this._selected_id = min([this._selected_id + 1, this._results[0]->len() - 1])
  enddef
  def Delete(): void
    this._searchstr = this._searchstr->substitute(".$", "", "")
  enddef
  def Regular(): void
    this._selected_id = 0
    this._searchstr = this._searchstr .. this._key
  enddef 
endclass 

abstract class EditFuzzy extends AbstractFuzzy
  def _OnEnter()
    execute($"edit {this._results[0][this._selected_id].text}")
  enddef
endclass

export class MRU extends EditFuzzy
  public static final Instance: MRU = MRU.new()
  def __Initialize()
    this._input_list = v:oldfiles->copy()->filter((_, v) => filereadable(fnamemodify(v, ":p")))
  enddef
endclass

export class Find extends EditFuzzy implements Runnable, MessageHandler
  public static final Instance: Find = Find.new()
  public static final L: Logger = Logger.new()
  var _job: Job = Job.new(this)
  var _poll_timer: Timer 

  def __Initialize()
    var pat = this._searchstr->empty() ? expand('%:p:h') : this._searchstr
    this._cmd = 'find ' .. pat .. ' -type f -not -path "*/\.git/*"'
    this._searchstr = "" # reset search back to empty, as it not intend to fuzzy search on that path

    this._input_list = [] # reset the list as we start a new search
    this._job.Start(this._cmd) 
    this._poll_timer = Timer.new('Poll timer', this, 100, -1)
    this._poll_timer.Start()
  enddef
  def Run()
    if (popup_getpos(this._popup_id)->empty())
      this._poll_timer.Stop()
      L.Debug("Popup close, killed polling timer")
      return
    endif

    if (this._job.IsDead() && !this._input_list->empty())
      this._poll_timer.Stop()
      L.Debug("Job done, got result, killed polling timer")
    endif

    # update new polled list, format display, highlight & setpopup_text
    this._results = [this._input_list] 
    this._FormatResultList()
    this.Update()
  enddef
  def OnStdOut(ch: channel, msg: string)
    this._input_list->add({ 'text': msg })
  enddef
  def OnStdErr(ch: channel, msg: string)
  enddef
  def OnExit(ch: job, status: number)
  enddef
endclass

class JumpFuzzy extends AbstractFuzzy
  def _OnEnter()
    if (!this._results[0]->empty())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef
endclass

export class Line extends JumpFuzzy implements Runnable
  public static final Instance: Line = Line.new()
  def __Initialize()
    Timer.new("Line", this).Start()
  enddef
  def Run()
    this._input_list = matchbufline(winbufnr(0), '\S.*', 1, '$') 
    this._UpdatePopupFromTimer()
  enddef
endclass

abstract class ExecuteFuzzy extends AbstractFuzzy
  def _OnEnter()
    feedkeys(":" .. this._results[0][this._selected_id].text, "n") # feed keys to command only, don't execute it 
  enddef
endclass

export class CmdHistory extends ExecuteFuzzy implements Runnable
  public static final Instance: CmdHistory = CmdHistory.new()
  def __Initialize()
    Timer.new("CmdHistory", this).Start()
  enddef
  def Run()
    # convert list of id to list of string commands
    this._input_list = [ histget('cmd') ] + range(1, histnr('cmd'))->mapnew((_, v) =>  histget('cmd', v) )  
    this._UpdatePopupFromTimer()
  enddef
endclass

export class Cmd extends ExecuteFuzzy implements Runnable
  public static final Instance: Cmd = Cmd.new()
  def __Initialize()
    Timer.new("Cmd", this).Start()
  enddef
  def Run()
    this._input_list = getcompletion('', 'command')
    this._UpdatePopupFromTimer()
  enddef
endclass

export class Buffer extends EditFuzzy
  public static final Instance: Buffer = Buffer.new()
  def __Initialize()
    this._input_list = getcompletion('', 'buffer')->filter((_, v) => bufnr(v) != bufnr())
  enddef
endclass

export class GitFile extends AbstractFuzzy implements Runnable
  public static final Instance: GitFile = GitFile.new()
  var _file_pwd: string

  def __Initialize()
    this._file_pwd = expand('%:p:h')
    this._cmd = 'git -C ' .. this._file_pwd .. ' ls-files `git -C ' .. this._file_pwd .. ' rev-parse --show-toplevel`'
    Timer.new("GitFile", this).Start()
  enddef
  def _OnEnter()
    execute($"edit {this._file_pwd .. "/" .. this._results[0][this._selected_id].realtext}")
  enddef
  def Run()
    this._input_list = systemlist(this._cmd)->mapnew((_, v) => {
      # store realtext which hold real path of file, it will be used later _OnEnter
      return {'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}
    })
    this._UpdatePopupFromTimer()
  enddef
  def _FormatResultList()
    this._format_result_list = this._results[0]->mapnew((k, v) => v.text->substitute('.*\/\(.*\)$', '\1', ''))
  enddef
endclass
