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
  var _delay: number = 0
  var _runnable: Runnable
  var _name: string
  var _options: dict<any>
  var _timerId: number = 0
  def new(name: string, delay: number = 0, repeat: number = 0)
    # this._logger = Logger.new()
    this._delay = delay
    this._name = name
    this._options = { 'repeat': repeat }
  enddef
  def Start(runnable: Runnable)
    try
      this._runnable = runnable
      # this._logger.Debug('Timer.Start() ' .. this._name .. ' runnable ' .. this._runnable->string())
      this._timerId = timer_start(this._delay, this._HandleTimer, this._options)
    catch
      echom 'Error from ' .. this._name .. ': ' .. v:exception->string()
    endtry
  enddef
  def _HandleTimer(timerId: number)
    this._runnable.Run()
  enddef
  def StartWithCb(Cb: func(dict<any>), args: dict<any> = {}): void
    this._timerId = timer_start(0, function(this._TimerCB, [Cb, args]))
  enddef
  def Stop()
    timer_stop(this._timerId)
  enddef
  def _TimerCB(Cb: func(dict<any>), items: dict<any>, timerId: number)
    try
      Cb(items)
    catch
      echo 'Error from ' .. this._name .. ': ' .. v:exception->string()
    endtry
  enddef
endclass

abstract class AbstractFuzzy
  var L: Logger = Logger.new()
  var _key_maps: list<dict<any>> = [
    { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
    { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
    { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>"], 'cb': this.Up, 'format': this.Format},
    { 'keys': ["\<C-n>", "\<Tab>", "\<Down>"], 'cb': this.Down, 'format': this.Format},
    { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText, 'format': this.Format}, 
    { 'keys': [], 'cb': this.Regular, 'match': this.Match, 'settext': this.SetText, 'format': this.Format }]
  var _selected_id: number = 0  # current selected index
  var _input_list: list<any>  # input list 
  var _results: list<list<any>> # return by matchfuzzypos() when do fuzzy
  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ">> "
  var _searchstr: string
  var _key: string # user input key
  var _cmd: string # external commands, grep, find, etc.

  # implements by subclass, fetch orginal list, start timer, jobs etc..
  def Init()
  enddef
  def Info()
  enddef
  def Format()
    clearmatches(this._popup_id)
    matchaddpos('FuzzyMatch', [this._selected_id + 2], 10, -1, { window: this._popup_id })
  enddef
  def SetText()
    if (this._results->len() > 1)
      popup_settext(this._popup_id, [{'text': this._prompt .. this._searchstr}] + this._results[0]->slice(0, &lines)->mapnew((i, t) => {
        return { 'text': t.text, 'props': this._results[1][i]->mapnew((j, k) => ({'col': k + 1, 'length': 1, 'type': 'FuzzyMatchCharacter' }))}
      }))
    else
       popup_settext(this._popup_id, [{'text': this._prompt .. this._searchstr}] + this._results[0])
    endif
    popup_setoptions(this._popup_id, { "title": $' {this._results[0]->len()} ' })
  enddef
  def SetText2()
    this._results = [this._input_list]
    popup_settext(this._popup_id, [{'text': this._prompt .. this._searchstr}] + this._results[0])
    popup_setoptions(this._popup_id, { "title": $' {this._results[0]->len()} ' })
  enddef

  def Match()
    this._results = this._searchstr->empty() ? [this._input_list] : this._input_list->matchfuzzypos(this._searchstr, {'key': 'text'})
  enddef         

  def Search(searchstr: string = "")
    this._searchstr = searchstr
    this.Init()  # subclass fuzzy to populate _input_list
    this._results = [this._input_list] # results[0] will be set to _input_list as first run, matchfuzzypos() is not called yet

    this._popup_id = popup_create([{'text': this._prompt .. this._searchstr }] + this._results[0], {
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
        borderhighlight: ['FuzzyBorderNormal'], 
        scrollbar: 0,
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
        title:  $' {this._results[0]->len()} '
      })
    this._bufnr = winbufnr(this._popup_id)
    this.Format()
  enddef
  def _OnKeyDown(winid: number, key: string): bool
    this._key = key
    for item in this._key_maps
      if (item.keys->empty() || item.keys->index(key) > -1)
        item.cb()
        (!item->has_key('match')) ?? item.match() 
        (!item->has_key('settext')) ?? item.settext() 
        (!item->has_key('format')) ?? item.format() 
        return true
      endif
    endfor
    return false
  enddef
  def Enter()
    if (!this._results[0]->empty())
      this._OnEnter()
      this.Cancel() # close popup
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
  def Edit()
    execute($"edit {this.GetSelected()}")
  enddef
  def GetSelected(): string
    return this._results[0][this._selected_id].text
  enddef
  def Jump()
    if (!this._results[0]->empty())
      execute($"exec 'normal m`' | :{this._results[0][this._selected_id].lnum} | norm zz")
    endif
  enddef
  def Execute()
    feedkeys(":" .. this._results[0][this._selected_id].text, "n") # feed keys to command only, don't execute it 
  enddef
endclass 

export class MRU extends AbstractFuzzy
  public static final Instance: MRU = MRU.new()
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this._results[0][this._selected_id].realtext
  enddef
  def Init()
    this._input_list = v:oldfiles->copy()->filter((_, v) => 
        filereadable(fnamemodify(v, ":p")))->mapnew((_, v) => 
          ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))                                       
  enddef
  def Info()
    if (!this._results[0]->empty() && !this._results[0][this._selected_id]->empty())
      echo this._results[0][this._selected_id].realtext
    endif
  enddef
endclass

export class Find extends AbstractFuzzy implements Runnable, MessageHandler
  public static final Instance: Find = Find.new()
  var _job: Job
  var _poll_timer: Timer 
  var _buffer: list<any>

  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this._results[0][this._selected_id].realtext
  enddef
  def Init()
    var pat = this._searchstr->empty() ? expand('%:p:h') : this._searchstr
    this._cmd = 'find ' .. pat .. ' -type f -not -path "*/\.git/*"'
    this._searchstr = "" # reset search back to empty, as it not intend to fuzzy search on that path

    this._input_list = []
    this._buffer = []

    this._job = Job.new(this)
    this._job.Start(this._cmd) 
    this._poll_timer = Timer.new('Poll timer', 100, -1)
    this._poll_timer.Start(this)
  enddef
  def Run()
    if (popup_getpos(this._popup_id)->empty())
      this._poll_timer.Stop()
      this.L.Debug("Popup close, killed polling timer")
      return
    endif

    if (this._buffer->empty()) # no more buffer to process stop polling timer
      this._poll_timer.Stop()
    else
      this._buffer->remove(0, this._buffer->len() - 1) # consume the buffer
      this._results[0] += this._input_list
      this.Match()
      this.SetText()
    endif
  enddef

  def Info()
    if (!this._results[0]->empty() && !this._results[0][this._selected_id]->empty())
      echo this._results[0][this._selected_id].realtext
    endif
  enddef

  def OnStdOut(ch: channel, msg: string)
    var message: dict<any> = { 'text': msg->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': msg }
    this._input_list->add(message)    
    this._buffer->add(message)
  enddef
  def OnStdErr(ch: channel, msg: string)
  enddef
  def OnExit(ch: job, status: number)
  enddef
endclass

export class Line extends AbstractFuzzy implements Runnable
  public static final Instance: Line = Line.new()
  def _OnEnter()
    this.Jump()
  enddef
  def Init()
    Timer.new("Line").Start(this)
  enddef
  def Run()
    this._input_list = matchbufline(winbufnr(0), '\S.*', 1, '$') 
    this.SetText2()
  enddef
endclass

export class CmdHistory extends AbstractFuzzy implements Runnable
  public static final Instance: CmdHistory = CmdHistory.new()
  def Init()
    Timer.new("CmdHistory").Start(this)
  enddef
  def _OnEnter()
    this.Execute()
  enddef
  def Run()
    # convert list of id to list of string commands
    this._input_list = [ { 'text': histget('cmd') } ] + range(1, histnr('cmd'))->mapnew((_, v) =>  ({ 'text': histget('cmd', v) }) )  
    this.SetText2()
  enddef
endclass

export class Cmd extends AbstractFuzzy implements Runnable
  public static final Instance: Cmd = Cmd.new()
  def Init()
    Timer.new("Cmd").Start(this)
  enddef
  def _OnEnter()
    this.Execute()
  enddef
  def Run()
    this._input_list = getcompletion('', 'command')->mapnew((_, v) => ({'text': v})) 
    this.SetText2()
  enddef
endclass

export class Buffer extends AbstractFuzzy
  public static final Instance: Buffer = Buffer.new()
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this._results[0][this._selected_id].realtext
  enddef
  def Init()
    this._input_list = getcompletion('', 'buffer')->filter((_, v) => 
      bufnr(v) != bufnr())->mapnew((_, v) =>
        ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))
  enddef
endclass

export class GitFile extends AbstractFuzzy implements Runnable
  public static final Instance: GitFile = GitFile.new()
  var _file_pwd: string

  def Init()
    this._file_pwd = expand('%:p:h')
    this._cmd = 'git -C ' .. this._file_pwd .. ' ls-files `git -C ' .. this._file_pwd .. ' rev-parse --show-toplevel`'
    Timer.new("GitFile").Start(this)
  enddef
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this._file_pwd .. "/" .. this._results[0][this._selected_id].realtext
  enddef
  def Run()
    this._input_list = systemlist(this._cmd)->mapnew((_, v) =>
      ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))
    this.SetText2()
  enddef
  def Info()
    if (!this._results[0]->empty() && !this._results[0][this._selected_id]->empty())
      echo this._results[0][this._selected_id].realtext
    endif
  enddef
endclass
