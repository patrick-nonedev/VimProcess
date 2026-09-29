if exists('b:current_syntax')
  finish
endif

syntax match vimprocessComment /^#.*$/
syntax match vimprocessRunning /\<running\>/
syntax match vimprocessExited /\<exited\>\|\<failed\>/
syntax match vimprocessCode /(code \d\+)/

highlight default link vimprocessComment Comment
highlight default link vimprocessRunning DiffAdd
highlight default link vimprocessExited Error
highlight default link vimprocessCode Number

let b:current_syntax = 'vimprocess'
