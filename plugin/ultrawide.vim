vim9script

if exists('g:ultrawide_loaded')
  finish
endif
g:ultrawide_loaded = true

import autoload 'ultrawide.vim'

augroup Win
  autocmd!
  autocmd WinNew *            timer_start(0, (_) => ultrawide#Check_layout(win_getid()))
  autocmd User WinClosedPost* timer_start(0, (_) => ultrawide#Check_layout(expand('<amatch>')[13 :]->str2nr()))
  autocmd WinNewPre * unsilent ultrawide#Wininfo_save()
  autocmd WinClosed * unsilent ultrawide#Wininfo_save() | execute 'doautocmd User WinClosedPost' .. expand('<amatch>')

  autocmd WinNew *            unsilent ultrawide#Adopot_width('WinNew', win_getid())
  autocmd User WinClosedPost* unsilent ultrawide#Adopot_width('WinClosed', expand('<amatch>')[13 :]->str2nr())

  autocmd VimEnter *        ultrawide#Cell_size_update()
  autocmd OptionSet guifont ultrawide#Cell_size_update()
augroup END
