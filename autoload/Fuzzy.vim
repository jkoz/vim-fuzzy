vim9script 

class Logger
  var _debug: bool = true
  def new()
    ch_logfile('/tmp/vim-fuzzy.log', 'w')
  enddef
  def Debug(str: string)
    if (this._debug)
      ch_log("vim-fuzzy.vim [Debug] " .. str)
    endif
  enddef
  def DebugList(msgs: list<any>)
    if (this._debug)
      for it in msgs
        ch_log("vim-fuzzy.vim [Debug] " .. it->string())
      endfor
    endif
  enddef
endclass

interface MessageHandler
  def Message(ch: channel, msg: string)
  def Error(ch: channel, msg: string)
  def Exit(ch: job, status: number)
endinterface

class Job
  var _job: job
  var _handler: MessageHandler
  def new(s: MessageHandler)
    this._handler = s
  enddef
  def Start(cmd: string)
    this._job = job_start(cmd, {out_cb: this._handler.Message, err_cb: this._handler.Error, exit_cb: this._handler.Exit})
  enddef
  def IsDead(): bool
    return job_status(this._job) ==# 'dead'
  enddef
endclass

interface Runnable
  def Run()
endinterface

class Timer
  var _delay: number = 0
  var _runnable: Runnable
  var _name: string
  var _options: dict<any>
  var _timerId: number = 0
  def new(name: string, delay: number = 0, repeat: number = 0)
    this._delay = delay
    this._name = name
    this._options = { 'repeat': repeat }
  enddef
  def Start(runnable: Runnable)
    try
      this._runnable = runnable
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
  var _logger: Logger = Logger.new()
  var _popup_opts = {
        mapping: 0, 
        filtermode: 'a',
        highlight: '',
        padding: [0, 1, 0, 1],
        border: [1, 1, 1, 1],
        borderhighlight: ['FuzzyBorderNormal'], 
        scrollbar: 0,
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
      }
  var _key_maps: list<dict<any>> = [
    { 'keys': ["\<ScrollWheelLeft>", "\<ScrollWheelRight>"]},
    { 'keys': ["\<ScrollWheelUp>"]},
    { 'keys': ["\<ScrollWheelDown>"]},
    { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
    { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
    { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>"], 'cb': this.Up, 'format': this.Format},
    { 'keys': ["\<C-n>", "\<Tab>", "\<Down>"], 'cb': this.Down, 'format': this.Format},
    { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText, 'format': this.Format}, 
    { 'keys': [], 'cb': this.Regular, 'match': this.Match, 'settext': this.SetText, 'format': this.Format }]
  var _selected_id: number = 0  # current selected index
  var _input_list: list<any>  # input list 
  # [['fkalackdlakdflala', 'claylakclac'], [[13, 14, 15, 16], [1, 2, 4, 5]], [192, 164]]
  var _matched_list: list<list<any>> # return by matchfuzzypos() 
  var _bufnr: number
  var _popup_id: number
  var _prompt: string = ""
  var _searchstr: string
  var _key: string # user input key

  def Format()
    clearmatches(this._popup_id)
    matchaddpos('FuzzyMatch', [this._selected_id + 2], 10, -1, { window: this._popup_id })
  enddef
  def SetText()
    # just display number of lines popup can show
    var popup_display_list = this._matched_list[0]->slice(0, &lines)
    if (this._matched_list->len() > 1 && !this._matched_list[1]->empty())
        popup_display_list = popup_display_list->mapnew((i, t) => {
          return { 'text': t.text, 'props': this._matched_list[1][i]->mapnew((j, k) => ({'col': k + 1, 'length': 1, 'type': 'FuzzyMatchCharacter' }))}
        })
    endif
    popup_settext(this._popup_id, [{'text': this._prompt .. this._searchstr}] + popup_display_list)
    this.SetStatus()
  enddef
  def SetText2()
    this._matched_list = [this._input_list]
    popup_settext(this._popup_id, [{'text': this._prompt .. this._searchstr}] + this._matched_list[0])
    this.SetStatus()
  enddef

  def SetStatus()
    popup_setoptions(this._popup_id, { "title": $' {this._matched_list[0]->len()} ' })
  enddef

  def MatchFuzzyPos(ss: string, items: list<dict<any>>): list<list<any>>
    var b = reltime()
    var ret = items->matchfuzzypos(ss, {'key': 'text'})
    this._logger.Debug("Matching [" .. ss .. "] on " .. items->len() .. " records. Took " .. b->reltime()->reltimefloat() * 1000)
    return ret
  enddef

  def Match()
    if this._searchstr->empty() 
      this._matched_list = [this._input_list]
    else
      this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
    endif
  enddef         

  # implements by subclass, fetch orginal list, start timer, jobs etc..
  def Before()
  enddef
  def Search(searchstr: string = "")
    this._searchstr = searchstr
    this.Before()  # subclass fuzzy to populate _input_list
    this._matched_list = [this._input_list] # results[0] will be set to _input_list as first run, matchfuzzypos() is not called yet

    this._popup_id = popup_create([{'text': this._prompt .. this._searchstr }] + this._matched_list[0], this._popup_opts->extend({
        minwidth: float2nr(&columns * 0.6),
        maxwidth: float2nr(&columns * 0.6),
        maxheight: float2nr(&lines * 0.6),
        minheight: float2nr(&lines * 0.6),
        filter: this._OnKeyDown,
      }))
    this._bufnr = winbufnr(this._popup_id)
    this.Format()
    this.After()
  enddef
  def After()
    this.SetStatus()
  enddef
  def _OnKeyDown(winid: number, key: string): bool
    this._key = key
    for item in this._key_maps
      if (item.keys->empty() || item.keys->index(key) > -1)
        if (!item->has_key('cb')) 
          this._logger.Debug("No call back, ignored key")
          return false
        endif
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
    if (!this._matched_list[0]->empty())
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
    this._selected_id = min([this._selected_id + 1, this._matched_list[0]->len() - 1])
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
    return this._matched_list[0][this._selected_id].text
  enddef
  def Jump()
    if (!this._matched_list[0]->empty())
      execute($"exec 'normal m`' | :{this._matched_list[0][this._selected_id].lnum} | norm zz")
    endif
  enddef
  def Execute()
    this.PrintOnly()
  enddef
  def PrintOnly()
    feedkeys($":{this.GetSelected()}", "n") # feed keys to command only, don't execute it 
  enddef
endclass 

abstract class AbstractCachedFuzzy extends AbstractFuzzy
  var _cached_list: dict<dict<any>>

  def Before()
    this._cached_list = {}
  enddef

  def Match()
    if this._searchstr->empty() 
      this._matched_list = [this._input_list]
      return
    endif

    var previous_matched_list = this._cached_list->get(this._searchstr, [])
    if (previous_matched_list->empty())
      this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
      this._cached_list[this._searchstr] = { 'data': this._matched_list, 'input_list_size': this._input_list->len()}
    else
      if (previous_matched_list.input_list_size !=# this._input_list->len())
        var chopped_list = this._input_list->slice(previous_matched_list.input_list_size, this._input_list->len() - 1)

        this._logger.Debug("Cached record out of update! Reperform fuzzy search on " .. chopped_list->len() .. " addition records")

        this._matched_list = this.MatchFuzzyPos(this._searchstr, previous_matched_list.data[0] + chopped_list)
        # this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
        this._cached_list[this._searchstr] = { 'data': this._matched_list, 'input_list_size': this._input_list->len()}
      else
        this._matched_list = previous_matched_list.data
      endif
    endif
  enddef         
endclass

export class ShellFuzzy extends AbstractCachedFuzzy implements Runnable, MessageHandler
  public static final Instance: ShellFuzzy = ShellFuzzy.new()
  var _job: Job
  var _poll_timer: Timer 
  var _buffer: list<any>
  var _cmd: string # external commands, grep, find, etc.
  var _error_msg: list<string>

  def _OnEnter()
    this.PrintOnly()
  enddef
  def GetSelected(): string
    return this._matched_list[0][this._selected_id].realtext
  enddef
  def Before()
    super.Before()
    this._cmd = this._searchstr
    this._searchstr = "" # reset search back to empty, as it not intend to fuzzy search on that path
    this._input_list = []
    this._buffer = []
    this._error_msg = []
  enddef
  def Search(searchstr: string = "")
    super.Search(searchstr)

    var tmp_file = tempname()
    writefile([this._cmd], tmp_file)

    this._job = Job.new(this)
    this._job.Start("sh " .. tmp_file) 

    this._logger.Debug("Running command: " .. this._cmd)

    this._poll_timer = Timer.new('Poll timer', 100, -1)
    this._poll_timer.Start(this)

    popup_setoptions(this._popup_id, { borderhighlight: ['FuzzyBorderRunning'] })
  enddef
  def Run()
    if (popup_getpos(this._popup_id)->empty())
      this._poll_timer.Stop()
      popup_setoptions(this._popup_id, { borderhighlight: ['FuzzyBorderNormal'] })
      this._logger.Debug("Popup close, killed polling timer")
      if (!this._error_msg->empty())
        this._logger.Debug("Error while executing cmd: " .. this._cmd)
        this._logger.DebugList(this._error_msg)
      endif
      return
    endif

    if (this._buffer->empty()) 
      if (this._job.IsDead())  # job dead, buffer is empty. Let's stop the timer
        this._poll_timer.Stop()
        popup_setoptions(this._popup_id, { borderhighlight: ['FuzzyBorderNormal'] })
        this._logger.Debug("Buffer is empty, data stream end, stop polling timer")
        if (!this._error_msg->empty())
          this._logger.Debug("Error while executing cmd: " .. this._cmd)
          this._logger.DebugList(this._error_msg)
        endif
      endif
    else # buffer is not empty, lets match it
      var payload = this._buffer->remove(0, this._buffer->len() - 1) # consume the buffer
      this._logger.Debug("Fetching iput list, payloads: " .. payload->len() .. " records -  total: " .. this._input_list->len())
      this.Match()
      this.SetText()
    endif
  enddef

  def Message(ch: channel, msg: string)
    var message: dict<any> = { 'text': msg->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': msg }
    this._input_list->add(message)    
    this._buffer->add(message)
  enddef
  def Error(ch: channel, msg: string)
    this._error_msg->add(msg)
  enddef
  def Exit(ch: job, status: number)
  enddef
endclass

export class MRU extends AbstractFuzzy
  public static final Instance: MRU = MRU.new()
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this._matched_list[0][this._selected_id].realtext
  enddef
  def Before()
    this._input_list = v:oldfiles->copy()->filter((_, v) => 
        filereadable(fnamemodify(v, ":p")))->mapnew((_, v) => 
          ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))                                       
  enddef
endclass

export class Line extends AbstractFuzzy implements Runnable
  public static final Instance: Line = Line.new()
  def _OnEnter()
    this.Jump()
  enddef
  def Before()
    Timer.new("Line").Start(this)
  enddef
  def Run()
    this._input_list = matchbufline(winbufnr(0), '\S.*', 1, '$') 
    this.SetText2()
  enddef
endclass

export class CmdHistory extends AbstractFuzzy implements Runnable
  public static final Instance: CmdHistory = CmdHistory.new()
  def Before()
    Timer.new("CmdHistory").Start(this)
  enddef
  def _OnEnter()
    this.Execute()
  enddef
  def Run()
    # convert list of id to list of string commands
    this._input_list = [ { 'text': histget('cmd') } ] + range(1, histnr('cmd'))
      ->mapnew((_, v) => ({'text': 'cmd'->histget(v)->substitute('^[ \t]*\(.*\)[ \t]*$', '\1', '')}))
      ->sort()->uniq()  
    
    this.SetText2()
  enddef
endclass

export class Cmd extends AbstractFuzzy implements Runnable
  public static final Instance: Cmd = Cmd.new()
  def Before()
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
    return this._matched_list[0][this._selected_id].realtext
  enddef
  def Before()
    this._input_list = getcompletion('', 'buffer')->filter((_, v) => 
      bufnr(v) != bufnr())->mapnew((_, v) =>
        ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))
  enddef
endclass

export class VimKeyMap extends AbstractFuzzy implements Runnable
  public static final Instance: VimKeyMap = VimKeyMap.new()

  def Before()
    Timer.new("KeyMap").Start(this)
  enddef
  def _OnEnter()
    this.Execute()
  enddef
  def GetSelected(): string
    return this._matched_list[0][this._selected_id].text
  enddef
  def Run()
    this._input_list = execute('map')->split("\n")->mapnew((_, v) => ({'text': v})) 
    this.SetText2()
  enddef
endclass

export class Explorer extends AbstractFuzzy
  public static final Instance: Explorer = Explorer.new()
  def new()
    this._key_maps = [{ 'keys': ["-"], 'cb': this.ParentDir}]->extend(this._key_maps)
  enddef
  def Enter()
    if (!this._matched_list[0]->empty())
      if (this.GetSelected()->filereadable())
        this.Edit()
        this.Cancel()
      else
        this.ChangeDir(this.GetSelected())
      endif
    endif
  enddef
  def Before()
    this._input_list = getcompletion('', 'file')->mapnew((_, v) => ({'text': v})) 
  enddef
  def SetStatus()
    popup_setoptions(this._popup_id, { "title": $' {this._matched_list[0]->len()} {getcwd()} ' })
  enddef
  def ParentDir()
    this.ChangeDir("..")
  enddef
  def ChangeDir(dir: string)
    win_execute(this._popup_id, $"cd {dir}")
    this.Before() # update list of file/directories
    this._searchstr = ""
    this.SetText2()
  enddef
endclass

export class Find extends ShellFuzzy
  public static final Instance: Find = Find.new()
  def Before()
    super.Before()
    # ShellFuzzy store all args in _cmd, in this case it is just a file path 
    var pat = this._cmd->empty() ? expand('%:p:h') : this._cmd
    this._cmd = 'find ' .. pat .. ' -type f -not -path "*/\.git/*"'
  enddef
  def _OnEnter()
    this.Edit()
  enddef
endclass

export class GitFile extends ShellFuzzy
  public static final Instance: GitFile = GitFile.new()
  var _file_pwd: string

  def Before()
    super.Before()
    this._file_pwd = expand('%:p:h')
    this._cmd = 'sh -c "git -C ' .. this._file_pwd .. ' rev-parse --show-toplevel | xargs git -C ' .. this._file_pwd .. ' ls-files"'
  enddef
  def GetSelected(): string
    return this._file_pwd .. "/" .. this._matched_list[0][this._selected_id].realtext
  enddef
  def _OnEnter()
    this.Edit()
  enddef
endclass

export class Help extends AbstractFuzzy
  public static final Instance: Help = Help.new()
  def Before()
    this._input_list = globpath(&runtimepath, 'doc/tags', 1)->split('\n')->sort()->mapnew((_, v) =>  ({ 'text': v}))
  enddef
  def _OnEnter()
    this.PrintOnly()
  enddef
endclass
