vim9script

const KEYS = {
  Enter: ["\<CR>", "\<C-m>"],
  Tab: ["\<C-t>"],
  Cancel: ["\<esc>"],
  Up: ["\<C-p>"],
  Down: ["\<C-n>"],
  Delete: ["\<C-h>", "\<BS>"]
}

export interface KeyHandler
  def Accept(props: dict<any>): bool
endinterface

export interface KeyHandlerManager
  def OnKeyDown(props: dict<any>): bool
endinterface

export class KeyHandlerManagerImpl implements KeyHandlerManager

  # RegularKeyHandler should be at the end of the list 
  # this rely on list implementation is ordered list
  const _handlers: list<KeyHandler> = [
    EnterHandler.new(), 
    CancelHandler.new(),
    UpHandler.new(),
    DownHandler.new(),
    DeleteHandler.new(),
    RegularKeyHandler.new(),
  ]

  # define factory singleton here
  def OnKeyDown(props: dict<any>): bool
    for item in this._handlers
      if (item.Accept(props))
        return true
      endif
    endfor

    return false
  enddef

endclass

abstract class AbstractKeyHandler implements KeyHandler
  var _key_list: list<string>

  def Accept(props: dict<any>): bool
    if (this._key_list->index(props.key) > -1)
      return this.__Accept(props)
    endif
    return false
  enddef

  def __Accept(props: dict<any>): bool
    return true
  enddef

endclass

export class EnterHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Enter
  enddef
  def __Accept(props: dict<any>): bool
    props.on_enter_cb()
    popup_close(props.winid)
    return true
  enddef
endclass

export class CancelHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Cancel
  enddef

  def __Accept(props: dict<any>): bool
    popup_close(props.winid)
    return true
  enddef
endclass

export class UpHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Up
  enddef
  def __Accept(props: dict<any>): bool
    props.on_item_up_cb()

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr) 
    props.format_cb()
    return true
  enddef
endclass

export class DownHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Down
  enddef
  def __Accept(props: dict<any>): bool
    props.on_item_down_cb()

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr) 
    props.format_cb()
    return true
  enddef
endclass

export class RegularKeyHandler implements KeyHandler
  def Accept(props: dict<any>): bool

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr .. props.key)
    props.format_cb()
    return true
  enddef
endclass

export class DeleteHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Delete
  enddef
  def __Accept(props: dict<any>): bool

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(substitute(props.searchstr, ".$", "", "")) 
    props.format_cb()
    return true
  enddef
endclass
