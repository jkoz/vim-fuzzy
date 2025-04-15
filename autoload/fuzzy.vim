vim9script

export class Logger
  var _debug: bool = true
  def new()
    ch_logfile('/tmp/vim-fuzzy.log', 'w')
  enddef
  def Debug(str: string)
    if this._debug | ch_log("vim-fuzzy.vim [Debug] " .. str) | endif 
  enddef
endclass

export def Debug(str: string)
  if exists("g:fuzzy_logger") | g:fuzzy_logger.Debug(str) | endif
enddef

interface MessageHandler
  def Message(ch: channel, msg: string)
  def Error(ch: channel, msg: string)
  def Exit(ch: job, status: number)
endinterface

class Job
  var _job: job
  var _handler: MessageHandler
  def Start(cmd: string, handler: MessageHandler): number
    this._handler = handler
    this._job = job_start(cmd, {out_cb: this.Message, err_cb: this.Error, exit_cb: this.Exit})
    Debug('Job started ' .. this._job->string())
    return this.GetChannelId()
  enddef
  def Stop()
    this._job->job_stop('kill')
    Debug('Job Stopped ' .. this._job->string())
  enddef
  def Message(ch: channel, msg: string)
    this._handler.Message(ch, msg)
  enddef
  def Error(ch: channel, msg: string)
    this._handler.Error(ch, msg)
  enddef
  def Exit(ch: job, status: number)
    this._handler.Exit(ch, status)
  enddef
  def IsDead(): bool
    return job_status(this._job) ==# 'dead'
  enddef
  def GetChannelId(): number
    return this._job->job_getchannel()->ch_info().id
  enddef
endclass

interface Runnable
  def Run()
endinterface

class Timer
  var _runnable: Runnable
  var _name: string
  var _timerId: number = 0
  def new(name: string)
    this._name = name
  enddef
  def Start(runnable: Runnable, delay: number = 0, repeat: number = 0)
    try
      this._runnable = runnable
      Debug($'[{this._name}] timer started delay={delay}, repeat={repeat}')
      this._timerId = timer_start(delay, this._HandleTimer, { 'repeat': repeat })
    catch
      Debug($'[{this._name}] timer error! delay={delay}, repeat={repeat}')
    endtry
  enddef
  def _HandleTimer(timerId: number)
    this._runnable.Run()
  enddef
  def StartWithCb(Cb: func(dict<any>), args: dict<any> = {}, delay: number = 0, repeat: number = 0) 
    Debug($'[{this._name}] timer started delay={delay}, repeat={repeat}')
    this._timerId = timer_start(0, function(this._TimerCB, [Cb, args]))
  enddef
  def Stop()
    timer_stop(this._timerId)
  enddef
  def _TimerCB(Cb: func(dict<any>), items: dict<any>, timerId: number)
    try
      Cb(items)
    catch
      Debug('_TimerCB()' .. this._name .. ': ' .. v:exception)
    endtry
  enddef
endclass

abstract class AbstractFuzzy
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
  
  var _action_maps: dict<any> = {
    "\<CR>": "edit",
    "\<C-t>": "tabnew",
    "\<C-x>": "split",
    "\<C-v>": "vsplit"
  }
  var _mode_maps = { 
    'insert': { keymap: [
      { 'keys': ["\<ScrollWheelLeft>", "\<ScrollWheelRight>"], cb: this.Ignore },
      { 'keys': ["\<PageUp>", "\<PageDown>"], cb: this.Ignore },
      { 'keys': ["\<ScrollWheelUp>", "\<ScrollWheelDown>"], cb: this.Ignore },
      { 'keys': [";"], 'cb': this.NormalMode},
      { 'keys': ["\<CR>", "\<C-m>", "\<C-t>", "\<C-x>", "\<C-v>"], 'cb': this.Accept },
      { 'keys': ["\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Close},
      { 'keys': ["\<C-p>", "\<S-Tab>", "\<Up>", "\<C-k>"], 'cb': this.Up, 'setstatus': this.SetStatus },
      { 'keys': ["\<C-n>", "\<Tab>", "\<Down>", "\<C-j>"], 'cb': this.Down, 'setstatus': this.SetStatus },
      { 'keys': ["\<C-d>", "\<C-u>"], 'cb': this.NormalExecute, 'setstatus': this.SetStatus }, 
      { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText }, 
      { 'keys': ["\<C-o>"], cb: this.Preview, 'setstatus': this.SetStatus}, # ignore delete key, so less confuse
      { 'keys': ["\<C-l>"], 'cb': this.LoadAllRecords },
      { 'keys': [], 'cb': this.Regular, 'match': this.Match, 'settext': this.SetText}
    ]},
    'normal': { keymap: [
      { 'keys': ["i"], 'cb': this.InsertMode},
      { 'keys': ["\<CR>", "\<C-m>", "\<C-t>", "\<C-x>", "\<C-v>"], 'cb': this.Accept },
      { 'keys': ["q", "\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Close},
      { 'keys': ["k"], 'cb': this.Up, 'setstatus': this.SetStatus },
      { 'keys': ["j"], 'cb': this.Down, 'setstatus': this.SetStatus },
      { 'keys': ["l"], 'cb': this.LoadAllRecords },
      { 'keys': ["\<C-h>", "\<BS>"], 'cb': this.Delete, 'match': this.Match, 'settext': this.SetText }, 
      { 'keys': ["\<space>", 'J', 'x', 's', 'p'], cb: this.Ignore}, # ignore delete key, so less confuse
      { 'keys': ['o'], cb: this.Preview, 'setstatus': this.SetStatus}, # ignore delete key, so less confuse
      { 'keys': ['t'], 'cb': this.TogglePretext, 'settext': this.SetText },
      { 'keys': [], 'cb': this.NormalExecute}
    ]},
    'preview': { keymap: [
      { 'keys': ['o', "\<C-o>"], cb: this.Preview }, # ignore delete key, so less confuse
      { 'keys': ["\<CR>", "\<C-m>", "\<C-t>", "\<C-x>", "\<C-v>"], 'cb': this.Accept },
      { 'keys': ["q", "\<esc>", "\<C-g>", "\<C-[>"], 'cb': this.Close},
      { 'keys': [], 'cb': this.NormalExecute}
    ], on_exit: this.Restore}
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
  var _pres_mode: string = ""
  var _toggles = { pretext: false, posttext: false}
  var _filetype = ''
  var _name = ''

  def Ignore()
  enddef

  def Preview()
    if this._mode == 'preview'
      this.SetMode(this._pres_mode)
    elseif !this._DoPreview()
      echo $"No preview for [{this.GetSelected()}], back to [{this._mode}] mode"
    endif
  enddef
  def Restore() # called when switch mode from preview to others, this will clear screen & reset fuzzy text
    clearmatches(this._popup_id)
    win_execute(this._popup_id, $"set ft={this._filetype} | norm! '`") # jump back to marked selected record for review
    popup_settext(this._popup_id, this.CreateText(0, this._matched_list[0]->len()))
  enddef
  def LoadPreview(fn: string)
    this.SetMode('preview') # set mode before update view as we will record previous mode selected id
    win_execute(this._popup_id, $"norm! m`") # mark selected record for jumping back
    popup_settext(this._popup_id, fn->readfile())
    win_execute(this._popup_id, $'silent! doautocmd filetypedetect BufNewFile {fn}')
  enddef
  def _DoPreview(): bool
    var fn = this.GetSelectedRealText()->glob()
    if (fn->filereadable()) 
      this.LoadPreview(fn)
      return true
    endif
    return false
  enddef
  def TogglePretext()
    this._toggles.pretext = !this._toggles.pretext
  enddef
  def TogglePosttext()
    this._toggles.posttext = !this._toggles.posttext
  enddef
  def SetMode(str: string)
    this._pres_mode = this._mode
    this._mode = str
    var prevm = this._mode_maps->get(this._pres_mode)
    prevm.prev_sel = line('.', this._popup_id) - 1 # can't use this.GetSelectedId() here, not sure why ?
    Debug('SetMode cur:' .. this._mode .. ' pres:' .. this._pres_mode .. ' prev_sel:' .. prevm.prev_sel->string())
    if prevm->has_key('on_exit') | prevm->get('on_exit')() | endif
    echo str
  enddef
  def NormalMode()
    this.SetMode('normal')
  enddef
  def InsertMode()
    this.SetMode('insert')
  enddef
  def GetSelectedId(): number
    if this._mode == 'preview'
      var prevm = this._mode_maps->get(this._pres_mode)
      Debug($"prev sel {prevm.prev_sel}")
      return prevm.prev_sel 
    endif
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

    var b = reltime()
    # don't override preview mode screen with fuzzy stuff
    if this._mode != 'preview' | popup_settext(this._popup_id, this.CreateText(0, &lines)) | endif
    this.SetStatus()
    Debug("SetText() on " .. &lines .. " records. Took " .. b->reltime()->reltimefloat() * 1000)
  enddef
  def HasMatchedCharPos(): bool # got highlight intel for matched character
    return this._matched_list->len() > 1 && !this._matched_list[1]->empty() 
  enddef
  def CreateText(start: number = 0, end: number = 100): list<dict<any>>
    return this._matched_list[0]->slice(start, end)->mapnew((i, t) => this.CreateEntry(i, t))
  enddef
  def CreateEntry(i: number, entry: dict<any>): dict<any>
    var [pretext, text, posttext] = [this.GetPretext(entry), entry.text, this.GetPostText(entry)]
    var [pretextl, textl, posttextl] = [pretext->len(), text->len(), posttext->len()]
    return { 
      text: pretext .. text .. posttext, 
      props: this.CreatePreTextProp(pretext, text, posttext) + this.CreateTextMatchPosProp(i, pretext) + this.CreatePostTextProp(pretext, text, posttext)
    }
  enddef
  def CreateTextMatchPosProp(i: number, pretext: string): list<any>
    if this._matched_list->len() > 1 && !this._matched_list[1]->empty() 
      return this._matched_list[1][i]->mapnew((_, k) => ({ col: pretext->len() + k + 1, length: 1, type: 'FuzzyMatchCharacter' }))
    endif
    return []
  enddef
  def CreatePostTextProp(pretext: string, text: string, posttext: string): list<any>
    return this._toggles.posttext ? [{ col: pretext->len() + text->len() + 1, length: posttext->len(), type: 'FuzzyPostText'}] : []
  enddef
  def CreatePreTextProp(pretext: string, text: string, posttext: string): list<any>
    return this._toggles.pretext && pretext->len() > 0 ? [{ col: 1, length: pretext->len(), type: 'FuzzyPostText'}] : []
  enddef
  def GetPostText(entry: dict<any>): string
    # realtext give more detail information of the entry like real path  .. (this._toggles.realtext ? " " .. entry->get('realtext', '') : '')
    return (this._toggles.posttext ? entry->get('posttext', '') : '') 
  enddef
  def GetPretext(entry: dict<any>): string
    var pretext = ''
    if this._toggles.pretext
      pretext = entry->get('pretext', '')
      if pretext->empty()
        pretext = entry->get('realtext', '')
        if !pretext->empty()
          pretext = pretext->fnamemodify(':h') .. '/'
        endif
      endif
    endif
    return pretext
  enddef
  def AddPadding(...items: list<any>): string
    var rt = items->filter((_, v) => !v->empty())->reduce((f, l) => f .. ' ' .. l, '')
    return rt->empty() ? '' : rt .. ' '
  enddef
  def GetMatchedNumberStr(): string
    return this._has_matched ? this._matched_list[0]->len()->string() : ''
  enddef
  def SetStatus()
    if (this._mode !=# 'preview')
      popup_setoptions(this._popup_id, { "title": $'{this.AddPadding(this._name, this.GetSelectedRealText(), line("$", this._popup_id)->string(), "of", this.GetMatchedNumberStr())}' })
    endif
  enddef
  def MatchFuzzyPos(ss: string, items: list<dict<any>>): list<list<any>>
    var b = reltime()
    var ret = items->matchfuzzypos(ss, {'key': 'text'})
    Debug("Matching [" .. ss .. "] on " .. items->len() .. " records. " .. ret[1]->len() .. " matched! Took " .. b->reltime()->reltimefloat() * 1000)
    return ret
  enddef

  def Match()
    this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
  enddef         

  # implements by subclass, fetch orginal list, start timer, jobs etc..
  def Before()
  enddef
  
  def Search(searchstr: string = "")
    this._mode = 'insert'
    this._pres_mode = 'insert'
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
    win_execute(this._popup_id, $"set ft={this._filetype}")
    Debug("SetText() bufnr=" .. this._bufnr .. " filetype=" .. this._bufnr->getbufvar('&filetype'))
  enddef
  def Filter(winid: number, key: string): bool
    this._key = key
    for item in this._mode_maps[this._mode].keymap
      if (item.keys->empty() || item.keys->index(key) > -1)
        if item->has_key('cb') | item.cb() | endif # if cb is not present, key will be ignored
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
      # this._searchstr = ""
  enddef
  def DoAccept()
    this._OnEnter()
    this.Close() # close popup
  enddef
  def Accept()
    if this._has_matched | this.DoAccept() | endif
  enddef
  def Up(): void
    win_execute(this._popup_id, $"norm! k")
  enddef
  def Down(): void
    win_execute(this._popup_id, $"norm! j")
    var [c, e] = [line('.', this._popup_id), line('$', this._popup_id)]
    if c + 4 == e && e < this._matched_list[0]->len() # loading all the files if user start rolling down
      this.LoadAllRecords()
    endif
  enddef
  def LoadAllRecords()
    Timer.new('Load all matched records').StartWithCb((_) => {
      popup_settext(this._popup_id, this.CreateText(0, this._matched_list[0]->len()))
      this.SetStatus()
    })
  enddef
  def Delete(): void
    this._searchstr = this._searchstr->substitute(".$", "", "")
  enddef
  def Regular(): void
    win_execute(this._popup_id, $"norm! gg")
    this._searchstr = this._searchstr .. this._key
  enddef 
  def NormalExecute(): void
    win_execute(this._popup_id, $"norm! " .. this._key)
  enddef
  def Edit()
    var sel = this.GetSelected()
    sel->empty() ?? this.Exec(sel)
  enddef
  def Exec(cmd: string)
    Debug($"{this._action_maps->get(this._key)} {cmd}")
    execute($"{this._action_maps->get(this._key)} {cmd}")
  enddef
  def GetSelected(): string
    # by default get selected will return text
    return this.GetSelectedItem('text')
  enddef
  def GetSelectedItem(key: string): any # there some more atttribute is passed along with items, like file size (number)
    if this._matched_list[0]->empty()
      return ''
    endif
    return this._matched_list[0][this.GetSelectedId()]->get(key, '')
  enddef
  def GetSelectedRealText(): string
    return this.GetSelectedItem('realtext')
  enddef
  def Jump()
    var lnum = this.GetSelectedItem('lnum')
    if (lnum->type() == type(0))
      execute($"exec 'normal m`' | :{lnum} | norm zz")
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
    if this._searchstr->empty() && this._key->empty()| return | endif
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
  var _last_len: number = 0
  var _cmd: string # external commands, grep, find, etc.
  var _done: bool = false
  var _job: Job
  var _consumer: Timer = Timer.new('Consumer')
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
    this._last_len = 0
  enddef
  def Search(searchstr: string = "")
    super.Search(searchstr)
    this.DoSearch()
  enddef
  def DoSearch()
    var tmp_file = tempname()
    Debug($'Run --- {this._cmd}')
    writefile([this._cmd], tmp_file)
    this._job = Job.new()
    this._job.Start("sh " .. tmp_file, this)
    Debug("Running command: " .. this._cmd)
    this._consumer.Start(this)
    popup_setoptions(this._popup_id, { borderhighlight: ['FuzzyBorderRunning'] })
  enddef
  def Run()
    this.Consume()
  enddef
  def Consume()
    var curlen = this._input_list->len()
    if curlen > this._last_len # Got new data
      Debug($"Run(): {curlen - this._last_len} records fetched. Totals: {curlen}")
      this._last_len = curlen
      this._matched_list = this.MatchFuzzyPos(this._searchstr, this._input_list)
      this.SetText()
      this._consumer.Start(this)
    elseif this._job.IsDead() # No new data & job is dead, more records may be polling in on Message()
      this._done = true
      popup_setoptions(this._popup_id, { borderhighlight: ['FuzzyBorderNormal'] })
    else # job is alive, fetching data, give it 20mili before comming back
      this._consumer.Start(this, 20)
    endif
  enddef
  def ParseEntry(msg: string): dict<any>
    return { 'text': msg, 'realtext': msg }
  enddef
  def OnMessage(ch: channel, msg: string)
    this._input_list->add(this.ParseEntry(msg))    
    if this._done # consumer timer marked it done as job's dead, but data polling in
      this._done = false
      this._consumer.Start(this)
    endif
  enddef
  def Message(ch: channel, msg: string)
    this.OnMessage(ch, msg)
  enddef
  def Error(ch: channel, msg: string)
    Debug(msg)
  enddef
  def Exit(ch: job, status: number)
  enddef
endclass

export class MRU extends AbstractFuzzy
  def new()
    this._name = "Mru"
  enddef
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this.GetSelectedRealText()
  enddef
  def Before()
    this._input_list = v:oldfiles
      ->copy()->filter((_, v) => v->fnamemodify(":p")->filereadable())
      ->mapnew((_, v) => ({'text': v->fnamemodify(":t"), 'realtext': v}))                                       
  enddef
endclass

export class Line extends AbstractFuzzy
  var _regrex: string = '.*' # roll back to .* only to keep the format, \S.* will remove file format
  def new()
    this._name = 'Line'
  enddef
  def _OnEnter()
    this.Jump()
  enddef
  def Before()
    this._regrex = '.*' # reset regrex pat to match all every search
    if !this._searchstr->empty() | this._regrex = this._searchstr->escape('|') | endif
    this._searchstr = '' # reset searchstr, so we not fuzzy search on this
    this._input_list = winbufnr(0)->matchbufline(this._regrex, 1, '$') 
    this._filetype = &filetype
  enddef
endclass

export class CmdHistory extends AbstractFuzzy implements Runnable
  def new()
    this._name = 'Command History'
  enddef
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
  def new()
    this._name = 'Command'
  enddef
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
  def _DoPreview(): bool
    var mlist = []
    try | mlist = $'verbose com {this.GetSelected()}'->execute()->matchlist('\s*Last set from \(.\{-}\) line \(\d\+\)')
    catch | Debug(v:exception) | endtry
    if !mlist->empty()
      this.LoadPreview(mlist[1]->glob())
      win_execute(this._popup_id, $'norm! {mlist[2]}G | zz') # go to cmd location
      return true
    endif
    return false
  enddef
endclass

export class Buffer extends AbstractFuzzy
  def new()
    this._name = 'Buf'
  enddef
  def _OnEnter()
    this.Edit()
  enddef
  def GetSelected(): string
    return this.GetSelectedRealText()
  enddef
  def Before()
    this._input_list = getcompletion('', 'buffer')
      ->filter((_, v) => v->bufnr() != bufnr())
      ->mapnew((_, v) => ({'text': v->fnamemodify(':t'), 'realtext': v}))
  enddef
endclass

export class VimKeyMap extends AbstractFuzzy implements Runnable
  def new()
    this._name = 'Keymap'
  enddef
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
  var _usr_dir: string
  def new()
    this._mode_maps['insert'].keymap->insert({ 'keys': ["-"], 'cb': this.ParentDir})
    this._mode_maps['normal'].keymap->insert({ 'keys': ["d"], 'cb': this.DeleteF})
    this._mode_maps['normal'].keymap->insert({ 'keys': ["r"], 'cb': this.RenameF})
    this._mode_maps['normal'].keymap->insert({ 'keys': ["n"], 'cb': this.NewNode})
    this._mode_maps['normal'].keymap->insert({ 'keys': ["-"], 'cb': this.ParentDir})
    this._toggles.posttext = true # for display extra information of file, like dir, link, etc.
    this._toggles.realtext = false # dont show full path, however it is used for preview
    this._filetype = "fuzzydir"
  enddef
  def DoAccept()
    if (this.GetSelected()->filereadable())
      this.Edit()
      this.Close()
    else
      this.ChangeDir(this.GetSelected())
    endif
  enddef
  def CreatePreTextProp(pretext: string, text: string, posttext: string): list<any>
    return [] # explorer has its own syntax highlight, no need for pretext prop
  enddef
  def Before()
    this.PopulateInputList()
    this._usr_dir = getcwd()
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
      realtext: getcwd() .. '/' .. v.name, # Preview() need full path
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
  def NewNode()
    inputsave() | var name = input($'Create node: ') | inputrestore()
    if isdirectory(name) || filereadable(name) | echo "Node exists!" | return | endif
    if name[name->len() - 1] ==# '/' # dir
      try 
        mkdir(name, "p") 
        this.RelistDirectory()
      catch 
        echo v:exception 
      endtry
    else
      execute($'edit {name}')
      this.Close()
    endif
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
    Debug("ChangeDir() dir: " .. dir .. " selected: " .. this.GetSelected())
    if (dir->isdirectory())
      execute($"cd {dir}")
      this.RelistDirectory()
    endif
  enddef
  def RelistDirectory()
    this._searchstr = "" # clear out prompt search string, as we move to target dir
    this._matched_list = [[]] # reset matched list, so SetText() will reset matched_list to input_list
    this.PopulateInputList() # update new input list
    this.SetText()
  enddef
  def Close()
    Debug("Close() roll back orginal pwd: " .. this._usr_dir)
    execute($"cd  {this._usr_dir}")
    super.Close()
  enddef
endclass

export class Find extends ShellFuzzy
  def new()
    this._name = 'Find'
  enddef
  def Before()
    super.Before()
    # ShellFuzzy store all args in _cmd, in this case it is just a file path 
    var pat = this._cmd->empty() ? getcwd() : this._cmd
    this._cmd = 'find ' .. pat .. ' -type f -not -path "*/\.git/*"'
  enddef
  def _OnEnter()
    this.Edit()
  enddef
  def ParseEntry(msg: string): dict<any>
    return { 'text': msg->fnamemodify(':t'), 'realtext': msg }
  enddef
endclass

export class Grep extends ShellFuzzy
  var _pattern: string
  var _grep_cmd: string = 'grep -sniIr '
  def new()
    this._filetype = 'fuzzygrep'
    this._name = 'Grep'
  enddef
  def CreateGrepCmd(): string
    var pat = this._cmd->empty() ? getcwd() : this._cmd
    this._pattern = expand('<cword>')
    return this._grep_cmd .. this._pattern .. " " .. pat
  enddef
  def Before()
    super.Before()
    this._cmd = this.CreateGrepCmd()
  enddef
  def _OnEnter()
    # pulling realtext from super which will contains full info as <filename:lnum:matched>
    var sel = super.GetSelectedRealText()
    if !sel->empty()
      var ch = sel->split(':')
      this.Exec($"{ch[0]} | norm! {ch[1]}G")
    endif
  enddef
  def _DoPreview(): bool
    var sel = super.GetSelectedRealText() # pulling realtext from super which will contains full info as <filename:lnum:matched>
    if !sel->empty()
      var ch = sel->split(':')
      this.LoadPreview(ch[0])

      # find start column of the match,  add highlight for the match word
      var col = getbufline(this._bufnr, ch[1]->str2nr())[0]->stridx(this._pattern) + 1 
      matchaddpos("FuzzyGrepMatch", [[ch[1]->str2nr(), col, this._pattern->len()]], 101, -1,  {window: this._popup_id})

      win_execute(this._popup_id, $'norm! {ch[1]}G | zz')
      return true
    endif
    return false
  enddef
  def GetSelectedRealText(): string
    # super.GetSelectedRealText() will store full grep info as <filename:lnum:matched>
    # this.GetSelectedRealText() is what displayed in popup status, so only the full filename path
    return super.GetSelectedRealText()->substitute('\(.\{-}\):\d\+:.\+', '\1', '')
  enddef
  # regex get file name for grep results is different with regular path <filename:lnum:matched>
  def ParseEntry(msg: string): dict<any>
    # currently fuzzy search the whole line of return from grep except for path
    return { 'text': msg->substitute('\(.\{-}\)\(:\d\+:.\+\)', '\=submatch(1)->fnamemodify(":t") .. submatch(2)', ''), 'realtext': msg }
  enddef
endclass

export class LGrep extends Grep
  def new()
    this._filetype = 'fuzzygrep'
    this._name = 'Live Grep'
  enddef
  def CreateGrepCmd(): string
    return $'{this._grep_cmd} "{this._searchstr}" {getcwd()}'
  enddef
  def Match()
    if this._job != null && !this._job.IsDead() | this._job.Stop() | endif
    this._cmd = this.CreateGrepCmd()
    this._matched_list = [[]]
    this._input_list = []
    this._last_len = 0
    this._has_matched = true
    this._pattern = this._searchstr
    this.DoSearch()
  enddef
  def DoSearch()
    if !this._searchstr->empty() | super.DoSearch() | endif
  enddef
  def Consume()
    if this._searchstr->len() < 4 && this._input_list->len() > &lines # for searchstr less than 4 characters, kill job if we get something
      this._job.Stop()
    endif
    super.Consume()
  enddef
  def OnMessage(ch: channel, msg: string)
    if ch->ch_info().id == this._job.GetChannelId() # only update input_list of channel is current.
      super.OnMessage(ch, msg)
    endif
  enddef
  def MatchFuzzyPos(ss: string, items: list<dict<any>>): list<list<any>>
    return [items] # TODO: high light matched word, toggle fuzzy mode, matched word has a bug on high light, oi on MatchFuzzyPos fuzzy.vim:223
  enddef
endclass

export class GitFile extends ShellFuzzy
  var _file_pwd: string
  def new()
    this._name = 'GitFile'
  enddef
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
  def ParseEntry(msg: string): dict<any>
    return { 'text': msg->fnamemodify(':t'), 'realtext': msg }
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
  def new()
    this._type = 'help'
    this._name = 'Help'
  enddef
  def _OnEnter()
    execute(":help " .. this.GetSelected())
  enddef
endclass
export class Tag extends AbstractVimFuzzy
  def new()
    this._type = 'tag'
    this._name = 'Tag'
  enddef
  def _OnEnter()
    execute(":tag " .. this.GetSelected())
  enddef
  def PopulateInputList()
    system($"cd {expand('%:p:h')} && exctags {expand('%:p:h')}")
    super.PopulateInputList()
  enddef
endclass
export class Highlight extends AbstractFuzzy
  var _props = ['linksto', 'term', 'cterm', 'ctermfg', 'ctermbg']
  def new()
    this._name = 'Highlight'
  enddef
  def _OnEnter()
  enddef
  def ParseHighlighProp(dt: dict<any>, s: string): string
    if (!dt->has_key(s)) | return '' | endif
    var k = dt->get(s)
    if (type(k) == type('')) | return $' {s}={k}'| endif
    if (type(k) == type({})) | return $' {s}={k->keys()->join(",")}'| endif
    return ''
  enddef
  def Before()
    this._input_list = hlget()->mapnew((_, v) => ({
      text: $"xxx {v.name}{this._props->mapnew((_, k) => this.ParseHighlighProp(v, k))->reduce((f, l) => f .. l)}",
      name: v.name }))
  enddef
  def SetText()
    super.SetText()
    if this._has_matched 
      this._matched_list[0]->foreach((i, v) => (matchaddpos(v.name, [[i + 1, 1, 3]], 101, -1,  {window: this._popup_id})))
    endif
  enddef
endclass
export class QuickFix extends AbstractFuzzy
  def new()
    this._filetype = 'fuzzygrep'
    this._name = 'QuickFix'
    this._toggles.pretext = true # for display extra information lnum, error
  enddef
  def Before()
    var qflist = getqflist()
    if qflist->empty() | echo 'Quick fix empty' | return | endif
    this._input_list = qflist->mapnew((_, v) => ({
      realtext: v.bufnr->bufname(),
      col: v.col,
      lnum: v.lnum,
      end_lnum: v.end_lnum,
      pretext: $"{v.bufnr->bufname()->fnamemodify(':t')}:{v.lnum}:",
      text: $"{v.text}" 
    }))
  enddef
  def _OnEnter()
    execute($':cc! {line('.', this._popup_id)}')
  enddef
  def _DoPreview(): bool
    # pulling realtext from super which will contains full info as <filename:lnum:matched>
    var sel = super.GetSelectedRealText()
    if !sel->empty()
      this.LoadPreview(sel)
      var [lnum, end_lnum, col] = [this.GetSelectedItem('lnum'), this.GetSelectedItem('end_lnum'), this.GetSelectedItem('col')]
      matchaddpos("FuzzyGrepMatch", [[lnum, col, end_lnum]], 101, -1,  {window: this._popup_id}) # add highlight for the match word
      win_execute(this._popup_id, $'norm! {lnum}G | zz')
      return true
    endif
    return false
  enddef
endclass
