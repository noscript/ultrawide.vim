vim9script

const s_cols_per_vsplit = &columns # set on Vim start
g:ultrawide#wininfo = []
g:ultriwide#layout = ''
g:ultrawide#cell_width = 0

def S__is_gui_hmaximized(): bool
  if has('x11')
    system('xwininfo -wm -id ' .. v:windowid .. ' | grep -q "Maximized Horz"')
  else
    # TODO
    echoerr 'this platform is not supported'
    return true
  endif
  return v:shell_error == 0
enddef

def S__gui_width(): number
  if has('x11')
    return systemlist("xwininfo -id " .. v:windowid .. " | grep Width | grep -o '[0-9]\\+'")[0]->str2nr()
  else
    # TODO
    echoerr 'this platform is not supported'
    return -1
  endif
enddef

export def Cell_size_update()
  g:ultrawide#cell_width = S__gui_width() / &columns
enddef

def S__window_depth_type(layout__a: list<any>, winid__a: number, depth__a = 0, split_type__a = ''): list<any>
  if empty(layout__a)
    return []
  endif
  if layout__a[0] == 'leaf'
    if layout__a[1] == winid__a
      var split_type = 'row'
      if split_type__a == 'row'
        split_type = 'col'
      endif
      return [depth__a, split_type]
    else
      return []
    endif
  endif

  var split_type = layout__a[0]
  for sub_layout in layout__a[1]
    var res = sub_layout->S__window_depth_type(winid__a, depth__a + 1, split_type)
    if !res->empty()
      return res
    endif
  endfor

  return []
enddef

# F_skip_node_func__a returns true if should skip the node
def S__layout_filter(layout__a: list<any>, F_skip_node_func__a: func, depth__a = 0): list<any>
  if layout__a->empty()
    return []
  endif

  if F_skip_node_func__a(layout__a, depth__a)
    return []
  endif

  if layout__a[0] == 'leaf'
    return layout__a
  endif

  var new_layout = []
  for sub_layout in layout__a[1]
    var res = sub_layout->S__layout_filter(F_skip_node_func__a, depth__a + 1)
    add(new_layout, res)
  endfor

  return [layout__a[0], new_layout]
enddef

def S__layout_unpack(layout__a: list<any>): list<any>
  if layout__a->empty()
    return []
  endif

  if layout__a[0] == 'leaf'
    return layout__a
  endif

  var new_layout = []
  for i in range(len(layout__a[1]))
    var res = S__layout_unpack(layout__a[1][i])
    # if no columns / rows - skip it:
    if res->empty() || res[1]->empty()
      continue
    endif
    add(new_layout, res)
  endfor

  # if there is only one element -> unpack it:
  if new_layout->len() == 1
    return new_layout[0]
  endif

  var res = [layout__a[0], new_layout]

  if res != layout__a
    return S__layout_unpack(res)
  endif

  return res
enddef

export def Adopot_width(event__a: string, winid__a: number)
  if exists('g:SessionLoad') || S__is_gui_hmaximized()
    if !exists('g:SessionLoad')
      if event__a == 'WinNew'
        horiz wincmd =
      else # event__a == 'WinClosed'
        # since window is not closed yet, equalizing is postponed:
        timer_start(0, (_) => {
          horiz wincmd =
        })
      endif
    endif
    return
  endif

  var layout = winlayout()
  var depth_type = S__window_depth_type(layout, winid__a)
  if depth_type->empty()
    return
  endif
  var resize_needed = false
  var [depth, split_type] = depth_type
  if depth == 1
    if split_type == 'col' # vertically maximized split
      resize_needed = true
    endif
  else
    # remove windows which span across whole width or height:
    def S__skip_full_size_windows(layout__a: list<any>, depth__a: number): bool
      if layout__a[0] != 'leaf'
        return false
      endif
      if depth__a > 1
        return false
      endif
      return S__window_depth_type(layout__a, layout__a[1])[0] < 3
    enddef
    # remove windows with fixed width or height:
    def S__skip_fixed_size_windows(layout__a: list<any>, depth__a: number): bool
      if layout__a[0] == 'leaf'
        var winnr = layout__a[1]->win_id2win()
        return getwinvar(winnr, '&winfixheight') || getwinvar(winnr, '&winfixwidth')
      endif
      return false
    enddef
    var layout_no_full_size = layout
      ->S__layout_filter(S__skip_full_size_windows)
      ->S__layout_filter(S__skip_fixed_size_windows)
      ->S__layout_unpack()
    depth_type = S__window_depth_type(layout_no_full_size, winid__a)
    if depth_type->empty()
      return
    endif
    [depth, split_type] = depth_type

    # evaluate again, but now without full size or fixed windows:
    if depth == 1
      if split_type == 'col'
        resize_needed = true
      endif
    endif
  endif

  if !resize_needed
    return
  endif

  var columns_new = 0
  if event__a == 'WinNew'
    if winid__a->getwinvar('&winfixwidth', false)
      columns_new = &columns + winid__a->winwidth()
    else
      columns_new = &columns + s_cols_per_vsplit
    endif
    columns_new += 1 # splitter
  else # event__a == 'WinClosed'
    columns_new = &columns - winid__a->winwidth()
    columns_new -= 1 # splitter
  endif

  var [x, y] = getwinpos()
  var x_offset = (columns_new - &columns) * g:ultrawide#cell_width / 2
  x = max([x - x_offset, 0])
  y = getwinposy()
  execute 'winpos' x y

  &columns = columns_new

  # if &columns hasn't changed, then gui width must be exceeding screen width:
  if &columns != columns_new
    horiz wincmd =
    return
  endif

  # exclude winid__a and normalize winnrs:
  var restcmds = []
  var event_winnr = winid__a->win_id2win()
  for info in g:ultrawide#wininfo
    if info.winid == winid__a
      continue
    endif
    var nr = info.winid->win_id2win()
    if event__a == 'WinClosed' && nr > event_winnr
      --nr
    endif
    restcmds += [$'vertical :{nr} resize {info.width}']
  endfor

  var restcmd = restcmds->join('|')
  execute restcmd
  # known vim bug https://github.com/vim/vim/issues/10661 :
  timer_start(100, (_) => execute(restcmd))
enddef

export def Check_layout(winid__a: number)
  var layout = winlayout()->string() .. winrestcmd()
  if g:ultriwide#layout != layout
    g:ultriwide#layout = layout
    doautocmd User WinLayoutChanged
  endif
enddef

export def Wininfo_save()
  g:ultrawide#wininfo = getwininfo()
enddef
