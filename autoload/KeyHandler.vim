vim9script

const KEYS = {
  enter: ["\<CR>", "\<C-m>"],
  tab: ["\<C-t>"],
  cancel: ["\<esc>"],
  up: ["\<C-p>"],
  down: ["\<C-n>"],
  Delete: ["\<C-h>", "\<BS>"]
}

export interface KeyHandler

  def Accept(key: string, props: dict<any>): bool

endinterface


abstract class AbstractKeyHandler implements KeyHandler
  var _key_list: list<string>

  def Accept(key: string, props: dict<any>): bool
    if (this._key_list->index(key) > -1)
      return this.__Accept(key, props)
    endif
    return false
  enddef

  def __Accept(key: string, props: dict<any>): bool
    return true
  enddef

endclass

export class EnterHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.enter
  enddef
  def __Accept(key: string, props: dict<any>): bool
    props.on_enter_cb()
    popup_close(props.winid)
    return true
  enddef
endclass

export class CancelHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.cancel
  enddef

  def __Accept(key: string, props: dict<any>): bool
    popup_close(props.winid)
    return true
  enddef
endclass

export class UpHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.up
  enddef
  def __Accept(key: string, props: dict<any>): bool
    props.on_item_up_cb()

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr) 
    props.format_cb()
    return true
  enddef
endclass

export class DownHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.down
  enddef
  def __Accept(key: string, props: dict<any>): bool
    props.on_item_down_cb()

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr) 
    props.format_cb()
    return true
  enddef
endclass

export class RegularKeyHandler implements KeyHandler
  def Accept(key: string, props: dict<any>): bool

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(props.searchstr .. key)
    props.format_cb()
    return true
  enddef
endclass

export class DeleteHandler extends AbstractKeyHandler
  def new()
    this._key_list = KEYS.Delete
  enddef
  def __Accept(key: string, props: dict<any>): bool

    # call update to reset popup buffer, so all old highlight is gone
    props.update_cb(substitute(props.searchstr, ".$", "", "")) 
    props.format_cb()
    return true
  enddef
endclass
