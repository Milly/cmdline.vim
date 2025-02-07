function cmdline#_get() abort
  if !'s:cmdline'->exists()
    call cmdline#_init()
  endif
  return s:cmdline
endfunction
function cmdline#_init() abort
  let s:cmdline = #{
        \   buf: -1,
        \   id: -1,
        \   propmt: '',
        \ }
endfunction
function cmdline#_init_options() abort
  let s:options = #{
        \   border: 'none',
        \   col: (&columns - 80) / 2 - 10,
        \   highlight_window: 'WildMenu',
        \   row: &lines / 2 - 10,
        \   width: 80,
        \   zindex: 1000,
        \ }
endfunction
function cmdline#_options() abort
  if !'s:options'->exists()
    call cmdline#_init_options()
  endif

  let options = s:options->copy()

  return options
endfunction

function cmdline#set_option(key_or_dict, value = '') abort
  if !'s:options'->exists()
    call cmdline#_init_options()
  endif

  const dict = cmdline#util#_normalize_key_or_dict(a:key_or_dict, a:value)
  call s:check_options(dict)

  call extend(s:options, dict)
endfunction
function s:check_options(options) abort
  const default_keys = s:options->keys()

  for key in a:options->keys()
    if default_keys->index(key) < 0
      call cmdline#util#_print_error('Invalid option: ' .. key)
    endif
  endfor
endfunction

function cmdline#input(
      \ prompt='', text='', completion='custom,cmdline#_dummy') abort

  let cmdline = cmdline#_get()
  let cmdline.prompt = a:prompt

  if cmdline#enable()
    return
  endif

  call input(a:prompt, a:text, a:completion)
endfunction

function cmdline#enable() abort
  if !has('patch-9.0.1276') && !has('nvim-0.8')
    call cmdline#_print_error(
          \ 'cmdline.vim requires Vim 9.0.1276+ or neovim 0.8.0+.')
    return -1
  endif

  let cmdline = cmdline#_get()
  let options = cmdline#_options()

  const text = printf('%s %s', cmdline.prompt, getcmdline())

  if has('nvim')
    if cmdline.buf < 0
      let cmdline.buf = nvim_create_buf(v:false, v:true)
    endif

    call nvim_buf_set_lines(cmdline.buf, 0, -1, v:true, [text])

    let winopts = #{
          \   border: options.border,
          \   relative: 'editor',
          \   width: max([strwidth(text), options.width]),
          \   height: 1,
          \   row: options.row,
          \   col: options.col,
          \   anchor: 'NW',
          \   style: 'minimal',
          \   zindex: options.zindex,
          \ }

    if cmdline.id > 0
      " Reuse window
      call nvim_win_set_config(cmdline.id, winopts)
    else
      call cmdline#_close()

      " NOTE: It cannot set in nvim_win_set_config()
      let winopts.noautocmd = v:true

      " Create new window
      const id = nvim_open_win(cmdline.buf, v:false, winopts)

      call s:set_float_window_options(id, options, 'window')

      let cmdline.id = id
    endif
  else
    let winopts = #{
          \   pos: 'topleft',
          \   line: options.row + 1,
          \   col: options.col + 1,
          \   highlight: options.highlight_window,
          \   maxheight: 1,
          \   minwidth: options.width,
          \   wrap: v:true,
          \   zindex: options.zindex,
          \ }

    if cmdline.id > 0
      call popup_move(cmdline.id, winopts)
      call popup_settext(cmdline.id, [])
    else
      let cmdline.id = [text]->popup_create(winopts)
      let cmdline.buf = cmdline.id->winbufnr()
    endif
  endif

  augroup cmdline
    autocmd CmdlineChanged * call s:redraw_cmdline()
    autocmd CmdlineLeave * call cmdline#_close()
  augroup END
endfunction

function cmdline#_dummy(arglead, cmdline, cursor) abort
  return ''
endfunction

function cmdline#_close() abort
  let cmdline = cmdline#_get()
  if cmdline.id < 0
    return
  endif

  if has('nvim')
    call nvim_win_close(cmdline.id, v:true)
  else
    " NOTE: prop_remove() is not needed.
    " popup_close() removes the buffer.
    call popup_close(cmdline.id)
  endif

  let cmdline.id = -1
  let cmdline.prompt = ''

  augroup cmdline
    autocmd!
  autocmd END
endfunction

function s:redraw_cmdline() abort
  let cmdline = cmdline#_get()
  if cmdline.id < 0
    return
  endif

  const text = printf('%s %s', cmdline.prompt, getcmdline())

  call setbufline(cmdline.buf, 1, text)

  if has('nvim')
    let options = cmdline#_options()

    " NOTE: auto resize width
    call nvim_win_set_config(cmdline.id, #{
          \   width: max([strwidth(text), options.width]),
          \ })
  endif

  " NOTE: ":redraw" is needed to update screen in command line.
  redraw
endfunction

function s:set_float_window_options(id, options, highlight) abort
  let highlight = 'NormalFloat:' .. a:options['highlight_' .. a:highlight]
  let highlight ..= ',FloatBorder:FloatBorder,CursorLine:Visual'
  if &hlsearch
    " Disable 'hlsearch' highlight
    let highlight ..= ',Search:None,CurSearch:None'
  endif

  call setwinvar(a:id, '&winhighlight', highlight)
  call setwinvar(a:id, '&winblend', &l:pumblend)
  call setwinvar(a:id, '&wrap', v:true)
  call setwinvar(a:id, '&scrolloff', 0)
endfunction

function cmdline#_print_error(string) abort
  echohl Error
  echomsg printf('[cmdline] %s', a:string->type() ==# v:t_string ?
        \ a:string : a:string->string())
  echohl None
endfunction
