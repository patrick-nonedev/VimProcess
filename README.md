# VimProcess v0.1.0

Manage background processes from Vim, tmux-style: named jobs with output
buffers you can watch, feed stdin, kill or restart. Written in vim9script
on Vim's `job` control — no server, no dependencies. Processes live as
long as Vim does.

## Requirements

Vim with `+job` and `+channel` (`:echo has('job')` must show `1`).

## Installation

### vim-plug
```vim
Plug 'patrick-nonedev/vimprocess'
```

### Manual
Copy the `vimprocess` directory to `~/.vim/pack/vimprocess/start/`

## Usage

```vim
:ProcessStart sleep 30
:ProcessStart make -j8 build
:ProcessList
:ProcessShow make
:ProcessSend make q
:ProcessKill make
:ProcessRestart make
```

Names complete with Tab, and unique prefixes work (`:ProcessShow ma`
if only `make` matches). In `:ProcessList`: `q` closes, `r` refreshes,
`<CR>` shows output, `K` kills, `R` restarts, `D` forgets.

## Adopting foreign processes

`:ProcessAdopt <pid> [name]` tracks a process Vim didn't start: liveness
in the list, kill, show a note. There is no output capture or stdin —
the OS doesn't allow rewiring another process's file descriptors (same
reason tmux can't adopt foreign processes either).

## Outliving Vim

```vim
let g:vimprocess_stoponexit = ''   " default 'term': leave jobs running on :qa!
```

With `''`, quitting Vim leaves processes alive (orphaned). Re-capture
them later in a new Vim with `:ProcessAdopt <pid>`. No output history
survives the restart — only the PID.

## Configuration

```vim
let g:vimprocess_max_lines = 10000   " scrollback cap per buffer (default 5000)
```

## License

MIT
