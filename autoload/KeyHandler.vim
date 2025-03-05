vim9script

const KEYS = {
  Enter: ["\<CR>", "\<C-m>"],
  Tab: ["\<C-t>"],
  Cancel: ["\<esc>", "\<C-g>", "\<C-[>"],
  Up: ["\<C-p>", "\<S-Tab>", "\<Up>"],
  Down: ["\<C-n>", "\<Tab>", "\<Down>"],
  Delete: ["\<C-h>", "\<BS>"]
}

export interface KeyHandler
  def Accept(params: dict<any>): bool
endinterface

export interface KeyHandlerManager
  def OnKeyDown(params: dict<any>): bool
endinterface


abstract class AbstractKeyHandler implements KeyHandler
  var _key_list: list<string>
  var _params: dict<any>

  def _GetFuzzy(): any
    return this._params.fuzzy
  enddef

  def _GetKey(): string
    return this._params.key
  enddef

  def Accept(params: dict<any>): bool
    this._params = params

    # key list empty is regular key
    if (this._key_list->empty() || this._key_list->index(this._GetKey()) > -1)
      this._OnAccept()
      return true
    endif
    return false
  enddef

  abstract def _OnAccept(): void 
endclass

export class EnterHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Enter
  enddef
  def _OnAccept()
    this._GetFuzzy().Enter()
  enddef
endclass

export class CancelHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Cancel
  enddef

  def _OnAccept()
    this._GetFuzzy().Cancel()
  enddef
endclass

export class UpHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Up
  enddef
  def _OnAccept()
    this._GetFuzzy().Up()
  enddef
endclass

export class DownHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Down
  enddef
  def _OnAccept()
    this._GetFuzzy().Down()
  enddef
endclass

export class RegularKeyHandler extends AbstractKeyHandler
  def _OnAccept()
    this._GetFuzzy().ResetSelectedIndex()
    this._GetFuzzy().SetSearchString((s: string) => s .. this._GetKey())
  enddef
endclass

export class DeleteHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Delete
  enddef
  def _OnAccept()
    this._GetFuzzy().SetSearchString((s: string) => s->substitute(".$", "", ""))
  enddef
endclass

export class KeyHandlerManagerImpl implements KeyHandlerManager

  static const Handlers: list<KeyHandler> = [
    EnterHandler.new(), 
    CancelHandler.new(),
    UpHandler.new(),
    DownHandler.new(),
    DeleteHandler.new(),
    RegularKeyHandler.new(),
  ]

  def OnKeyDown(params: dict<any>): bool
    for item in KeyHandlerManagerImpl.Handlers
      if (item.Accept(params))
        return true
      endif
    endfor
    return false
  enddef

endclass
