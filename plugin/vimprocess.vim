if exists('g:loaded_vimprocess')
  finish
endif
let g:loaded_vimprocess = 1

let s:save_cpo = &cpo
set cpo&vim

command! -nargs=+ ProcessStart call vimprocess#Start(<f-args>)
command! -nargs=0 ProcessList call vimprocess#List()
command! -nargs=1 -complete=customlist,vimprocess#CompleteNames ProcessShow call vimprocess#Show(<q-args>)
command! -bang -nargs=1 -complete=customlist,vimprocess#CompleteNames ProcessKill call vimprocess#Kill(<q-args>, <bang>0)
command! -nargs=1 -complete=customlist,vimprocess#CompleteNames ProcessInterrupt call vimprocess#Interrupt(<q-args>)
command! -nargs=1 -complete=customlist,vimprocess#CompleteNames ProcessRestart call vimprocess#Restart(<q-args>)
command! -nargs=1 -complete=customlist,vimprocess#CompleteNames ProcessForget call vimprocess#Forget(<q-args>)
command! -nargs=+ -complete=customlist,vimprocess#CompleteNames ProcessSend call vimprocess#Send(<f-args>)
command! -nargs=+ ProcessAdopt call vimprocess#Adopt(<f-args>)

let &cpo = s:save_cpo
unlet s:save_cpo
