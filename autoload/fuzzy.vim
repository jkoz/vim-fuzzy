vim9script

class Logger
  var _debug: bool = true
  def new()
    ch_logfile('/tmp/vim-fuzzy.log', 'w')
  enddef
  def Debug(str: string)
    if this._debug | ch_log("vim-fuzzy.vim [Debug] " .. str) | endif 
  enddef
  def DebugList(msgs: list<any>)
    if this._debug | msgs->foreach((_, v) => ch_log("vim-fuzzy.vim [Debug] " .. v->string())) | endif
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
      this._logger.Debug('_TimerCB()' .. this._name .. ': ' .. v:exception)
    endtry
  enddef
endclass

abstract class AbstractFuzzy
  var _logger: Logger = Logger.new()
  var _popup_opts = {
        mapping: 0, 
        filtermode: 'a',
        highlight: 'Normal',
        padding: [0, 1, 0, 1],
        border: [1, 1, 1, 1],
        borderhighlight: ['FuzzyBorderNormal'], 
        scrollbar: 0,
        borderchars: ['─', '│', '─', '│', '┌', '┐', '┘', '└'],
      }
  
  var _mode_maps:  dict<list<dict<any>>> = { 
    'insert': [
      { 'keys': ["\<ScrollWheelLeft>", "\<ScrollWheelRight>"]},
      { 'keys': ["\<PageUp>", "\<PageDown>"]},
      { 'keys': ["\<ScrollWheelUp>", "\<ScrollWheelDown>"]},
      { 'keys': [";"], 'cb': this.NormalMode},
      { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
      { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
      { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>", "\<C-k>"], 'cb': this.Up, 'setstatus': this.SetStatus },
      { 'keys': ["\<C-n>", "\<Tab>", "\<Down>", "\<C-j>"], 'cb': this.Down, 'setstatus': this.SetStatus },
      { 'keys': ["\<C-d>", "\<C-u>"], 'cb': this.NormalExecute, 'setstatus': this.SetStatus }, 
      { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText }, 
      { 'keys': [], 'cb': this.Regular, 'match': this.Match, 'settext': this.SetText}
    ],
    'normal': [
      { 'keys': ["i"], 'cb': this.InsertMode},
      { 'keys': ["\<CR>", "\<C-m>"], 'cb': this.Enter },
      { 'keys': ["q", "\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Cancel },
      { 'keys': ["k"], 'cb': this.Up, 'setstatus': this.SetStatus },
      { 'keys': ["j"], 'cb': this.Down, 'setstatus': this.SetStatus },
      { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText }, 
      { 'keys': ["x"] }, # ignore delete key, so less confuse
      { 'keys': [], 'cb': this.NormalExecute}
    ] 
  }
  var _input_list: list<any>  # input list 
  var _matched_list: list<list<any>> # return by matchfuzzypos() 
  var _has_matched: bool
  var _bufnr: number
  var _popup_id: number
  var _prompt: string = "> "
  var _searchstr: string
  var _key: string # user input key
  var _mode: string

  def NormalMode()
    this._mode = 'normal'
    echo "[Normal]"
  enddef

  def InsertMode()
    this._mode = 'insert'
    echo "[Insert]"
    this.SetText()
  enddef
  def ResetCursor()
    win_execute(this._popup_id, "norm! gg")
  enddef
  def GetSelectedId(): number
    return line('.', this._popup_id) - 1
  enddef
  def SetText()
    this._has_matched = !this._input_list->empty() # has_matched is based on originial list
    if this._matched_list->empty() || this._matched_list[0]->empty() 
      if this._searchstr->empty()
        this._matched_list = [this._input_list] 
      else # matchfuzzypos() return empty matched_list for a ligit searchstr
        this._matched_list = [[{ 'text': this._searchstr }]]
        this._has_matched = false
      endif
    endif

    # this._logger.Debug("SetText(): " .. this._matched_list[0]->string())
    popup_settext(this._popup_id, this.CreateText())
    this.SetStatus()
  enddef
  def HasMatchedCharPos(): bool # got highlight intel for matched character
    return this._matched_list->len() > 1 && !this._matched_list[1]->empty() 
  enddef
  def CreateText(): list<dict<any>>
    if this.HasMatchedCharPos()
      var pos = this._matched_list[1]
      return this._matched_list[0]->mapnew((i, t) => ({
        'text': t.text, 
        'props': pos[i]->mapnew((j, k) => ({
          'col': k + 1,
          'length': 1,
          'type': 'FuzzyMatchCharacter' }))}))
    endif

    return this._matched_list[0]
  enddef
  def AddPadding(...items: list<any>): string
    var rt = items->filter((_, v) => !v->empty())->reduce((f, l) => f .. ' ' .. l, '')
    return rt->empty() ? '' : rt .. ' '
  enddef
  def GetMatchedNumberStr(): string
    return this._has_matched ? this._matched_list[0]->len()->string() : ''
  enddef
  def SetStatus()
    popup_setoptions(this._popup_id, { "title": $'{this.AddPadding(this.GetSelectedRealText(), this.GetMatchedNumberStr())}' })
  enddef
  def MatchFuzzyPos(ss: string, items: list<dict<any>>): list<list<any>>
    var b = reltime()
    var ret = items->matchfuzzypos(ss, {'key': 'text'})
    this._logger.Debug("Matching [" .. ss .. "] on " .. items->len() .. " records. " .. ret[1]->len() .. " matched! Took " .. b->reltime()->reltimefloat() * 1000)
    return ret
  enddef

  def Match()
    this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
  enddef         

  # implements by subclass, fetch orginal list, start timer, jobs etc..
  def Before()
  enddef
  
  def Search(searchstr: string = "")
    this._mode = 'insert' # first start popup always insert mode
    this._searchstr = searchstr
    this.Before()  # subclass fuzzy to populate _input_list
    this._popup_id = popup_create([], this._popup_opts->extend({
      cursorline: 1,
      wrap: 0,
      minwidth: float2nr(&columns * 0.6),
      maxwidth: float2nr(&columns * 0.6),
      maxheight: float2nr(&lines * 0.6),
      minheight: float2nr(&lines * 0.6),
      filter: this.Filter,
    }))
    this._bufnr = winbufnr(this._popup_id)
    this.SetText()
    this.After()
  enddef
  def After()
    this._logger.Debug("SetText() bufnr=" .. this._bufnr .. " filetype=" .. this._bufnr->getbufvar('&filetype'))
  enddef
  def Filter(winid: number, key: string): bool
    this._key = key
    for item in this._mode_maps[this._mode]
      if (item.keys->empty() || item.keys->index(key) > -1)
        if item->has_key('cb') | item.cb() | else |  return false | endif # if cb is not present, key will be ignored
        if item->has_key('match') | item.match() | endif
        if item->has_key('settext') | item.settext() | endif
        if item->has_key('setstatus') | item.setstatus() | endif
        return true
      endif
    endfor
    return false
  enddef
  def Close()
      popup_close(this._popup_id)
      this._matched_list = []
      this._searchstr = ""
  enddef
  def Enter()
    if (!this._matched_list[0]->empty())
      this._OnEnter()
      this.Close() # close popup
    endif
  enddef
  def Cancel()
    this.Close()
  enddef
  def Up(): void
    win_execute(this._popup_id, $"norm! k")
  enddef
  def Down(): void
    win_execute(this._popup_id, $"norm! j")
  enddef
  def Delete(): void
    this._searchstr = this._searchstr->substitute(".$", "", "")
  enddef
  def Regular(): void
    this.ResetCursor()
    this._searchstr = this._searchstr .. this._key
  enddef 
  def NormalExecute(): void
    win_execute(this._popup_id, $"norm! " .. this._key)
  enddef
  def Edit()
    execute($"edit {this.GetSelected()}")
  enddef
  def GetSelected(): string
    # by default get selected will return text
    return this.GetSelectedItem('text')
  enddef
  def GetSelectedItem(key: string): any # there some more atttribute is passed along with items, like file size (number)
    if this._matched_list[0]->empty()
      return ''
    endif
    if this._matched_list[0]->len() <= this.GetSelectedId()
      this.ResetCursor()
    endif
    return this._matched_list[0][this.GetSelectedId()]->get(key, '')
  enddef
  def GetSelectedRealText(): string
    return this.GetSelectedItem('realtext')
  enddef
  def Jump()
    if (!this._matched_list[0]->empty())
      execute($"exec 'normal m`' | :{this._matched_list[0][this.GetSelectedId()].lnum} | norm zz")
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

  def UpdateCachedList()
    this._cached_list[this._searchstr] = { 'data': this._matched_list, 'input_list_size': this._input_list->len()}
  enddef

  def Match()
    var previous_matched_list = this._cached_list->get(this._searchstr, [])
    if (previous_matched_list->empty())
      this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
      this.UpdateCachedList()
    else
      if (previous_matched_list.input_list_size != this._input_list->len())
        this._matched_list = this.MatchFuzzyPos(this._searchstr, previous_matched_list.data[0] + 
          this._input_list->slice(previous_matched_list.input_list_size, this._input_list->len() - 1))
        this.UpdateCachedList()
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
    return this.GetSelectedRealText()
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

    this._poll_timer = Timer.new('Poll timer', 200, -1)
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
    return this.GetSelectedRealText()
  enddef
  def Before()
    this._input_list = v:oldfiles->copy()->filter((_, v) => 
        filereadable(fnamemodify(v, ":p")))->mapnew((_, v) => 
          ({'text': v->substitute('.*\/\(.*\)$', '\1', ''), 'realtext': v}))                                       
  enddef
endclass

export class Line extends AbstractFuzzy
  public static final Instance: Line = Line.new()
  var _regrex: string = '.*' # roll back to .* only to keep the format, \S.* will remove file format
  def _OnEnter()
    this.Jump()
  enddef
  def Before()
    this._regrex = '.*' # reset regrex pat to match all every search
    if !this._searchstr->empty() | this._regrex = this._searchstr->escape('|') | endif
    this._searchstr = '' # reset searchstr, so we not fuzzy search on this
    this._input_list = winbufnr(0)->matchbufline(this._regrex, 1, '$') 
  enddef
  def After()
    win_execute(this._popup_id, 'syntax clear')
    win_execute(this._popup_id, "set ft=" .. &filetype)
    super.After()
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
    this.SetText()
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
    this.SetText()
  enddef
endclass

export class Buffer extends AbstractFuzzy
  public static final Instance: Buffer = Buffer.new()
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this.GetSelectedRealText()
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
  def Run()
    this._input_list = execute('map')->split("\n")->mapnew((_, v) => ({'text': v})) 
    this.SetText()
  enddef
endclass

export class Explorer extends AbstractFuzzy
  public static final Instance: Explorer = Explorer.new()
  var _usr_dir: string
  def new()
    this._mode_maps['insert']->insert({ 'keys': ["-"], 'cb': this.ParentDir})
    this._mode_maps['normal']->insert({ 'keys': ["d"], 'cb': this.DeleteF})
    this._mode_maps['normal']->insert({ 'keys': ["r"], 'cb': this.RenameF})
    this._mode_maps['normal']->insert({ 'keys': ["n"], 'cb': this.NewFile})
    this._mode_maps['normal']->insert({ 'keys': ["-"], 'cb': this.ParentDir})
  enddef
  def Enter()
    if (!this._matched_list[0]->empty())
      if (this.GetSelected()->filereadable())
        this.Edit()
        this.Close()
      else
        this.ChangeDir(this.GetSelected())
      endif
    endif
  enddef
  def CreateText(): list<dict<any>>
    if this.HasMatchedCharPos()
      return this._matched_list[0]->mapnew((i, t) => ({ 
          'text': this.GetEntryText(t), 
          'props': this._matched_list[1][i]->mapnew((j, k) => ({
                'col': t->get('pretext', '')->len() + k + 1,
                'length': 1,
                'type': 'FuzzyMatchCharacter' })
          )}))
    endif
    return this._matched_list[0]->mapnew((_, t) => ({'text': this.GetEntryText(t)}))
  enddef
  def GetEntryText(entry: dict<any>): string
    return entry->get('pretext', '') .. entry.text .. entry->get('posttext', '')
  enddef
  def Before()
    this.PopulateInputList()
    this._usr_dir = getcwd()
  enddef
  def After()
    win_execute(this._popup_id, "set ft=fuzzydir")
    super.After()
  enddef
  def PopulateInputList()
    var [dir_info, user_w, group_w, size_w] = [readdirex(getcwd()), 0, 0, 0] 
    dir_info->foreach((_, d) => {
      user_w = d.user->len() > user_w ? d.user->len() : user_w
      group_w = d.group->len() > group_w ? d.group->len() : group_w
      d.size = d.size >= 1073741824 ? printf("%.1fG", d.size / 1073741824.0) :
        d.size >= 10485760 ?  printf("%dM", d.size / 1048576) :
        d.size >= 1048576 ? printf("%.1fM", d.size / 1048576.0) :
        d.size >= 10240 ? printf("%dK", d.size / 1024) :
        d.size >= 1024 ? printf("%.1fK", d.size / 1024.0) : d.size
      size_w = d.size->len() > size_w ? d.size->len() : size_w
    })
    this._input_list = dir_info->map((_, v) => ( v->extend({
      text: v.name, 
      pretext: printf($"%s %-{user_w}s %-{group_w}s %{size_w}s %s ",
                      (v.type == 'file' ? '-' : v.type[0]) .. (v.perm ?? '---------'),
                      v.user, v.group, v.size, '%b %d %H:%M'->strftime(v.time)),
      posttext: v.type == 'dir' ? '/' : ''
    })))
  enddef
  def SetStatus()
    var [fn, cwd] = [this.GetSelected(), getcwd()]
    var status = fn->filereadable() || fn->isdirectory() ? $' {(cwd == '/' ? '/' : cwd .. '/') .. fn} ' : $' {cwd} '
    popup_setoptions(this._popup_id, { title: status})
  enddef
  def ParentDir()
    this.ChangeDir('..')
  enddef
  def NewFile()
    inputsave()
    execute($"edit {input($"New file: ")}")
    inputrestore()
    this.Close()
  enddef
  def RenameF()
    inputsave()
    var c = input($"Rename: {this.GetSelected()} to ")
    if (!c->empty())
      rename(this.GetSelected(), c)
      echo "Rename successful"
    else
      echo "Rename cancel"
    endif
    inputrestore()
    this.RelistDirectory()
  enddef
  def DeleteF()
    inputsave()
    var c = input($"Are sure to delete: {this.GetSelected()} ? (y/N) ")
    if (c ==# "y")
      this.GetSelected()->delete("rf")
      echo $"{this.GetSelected()} is now deleted"
    else
      echo "Nothing is deleted"
    endif
    inputrestore()
    this.RelistDirectory()
  enddef
  def ChangeDir(dir: string)
    this._logger.Debug("ChangeDir() dir: " .. dir .. " selected: " .. this.GetSelected())
    if (dir->isdirectory())
      execute($"cd {dir}")
      this.RelistDirectory()
    endif
  enddef
  def RelistDirectory()
    this._searchstr = "" # clear out prompt search string, as we move to target dir
    this._matched_list = [[]] # reset matched list, so SetText() will reset matched_list to input_list
    this.ResetCursor()
    this.PopulateInputList() # update new input list
    this.SetText()
  enddef
  def Close()
    this._logger.Debug("Close() roll back orginal pwd: " .. this._usr_dir)
    execute($"cd  {this._usr_dir}")
    super.Close()
  enddef
endclass

export class Find extends ShellFuzzy
  public static final Instance: Find = Find.new()
  def Before()
    super.Before()
    # ShellFuzzy store all args in _cmd, in this case it is just a file path 
    var pat = this._cmd->empty() ? getcwd() : this._cmd
    this._cmd = 'find ' .. pat .. ' -type f -not -path "*/\.git/*"'
  enddef
  def _OnEnter()
    this.Edit()
  enddef
endclass

export class Grep extends ShellFuzzy
  public static final Instance: Grep = Grep.new()
  def Before()
    super.Before()
    var pat = this._cmd->empty() ? getcwd() : this._cmd
    this._cmd = 'grep -nr ' .. expand('<cword>') .. " " .. pat
  enddef
  def _OnEnter()
    var sel = super.GetSelected()
    if !sel->empty()
      var ch = sel->split(':')
      execute($"edit {ch[0]} | norm! {ch[1]}G")
    endif
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
    return this._file_pwd .. "/" .. this.GetSelectedRealText()
  enddef
  def _OnEnter()
    this.Edit()
  enddef
endclass

abstract class AbstractVimFuzzy extends AbstractFuzzy
  var _user_wildoptions: string
  var _type: string
  def Before()
    this._user_wildoptions = &wildoptions
    execute("set wildoptions=fuzzy")
    this.PopulateInputList()
  enddef
  def PopulateInputList()
    this._input_list = getcompletion('', this._type)->mapnew((_, v) => ({ 'text': v} ))
  enddef
  def _OnEnter()
    execute(":help " .. this.GetSelected())
  enddef
  def Close()
    super.Close()
    execute("set wildoptions=" .. this._user_wildoptions)
  enddef
  def MatchFuzzyPos(ss: string, items: list<dict<any>>): list<list<any>>
    return getcompletion("*" .. ss->map((_, v) => v .. "*" ), this._type)
      ->mapnew((_, v) => ({ 'text': v}))->matchfuzzypos(ss, {'key': 'text'})
  enddef
endclass

export class Help extends AbstractVimFuzzy
  public static final Instance: Help = Help.new()
  def new()
    this._type = 'help'
  enddef
  def _OnEnter()
    execute(":help " .. this.GetSelected())
  enddef
endclass
export class Tag extends AbstractVimFuzzy
  public static final Instance: Tag = Tag.new()
  def new()
    this._type = 'tag'
  enddef
  def _OnEnter()
    execute(":tag " .. this.GetSelected())
  enddef
  def PopulateInputList()
    system($"cd {expand('%:p:h')} && exctags {expand('%:p:h')}")
    super.PopulateInputList()
  enddef
endclass
