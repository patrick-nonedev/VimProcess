vim9script

# Background process manager: named jobs with output buffers.
# start/kill/restart, stdin, bounded scrollback.

var procs: dict<dict<any>> = {}
var list_buf = 0
var seq = 0

def UniqueName(base: string): string
  var name = base == '' ? 'proc' : base
  if !has_key(procs, name)
    return name
  endif
  seq += 1
  var n = name .. '-' .. seq
  while has_key(procs, n)
    seq += 1
    n = name .. '-' .. seq
  endwhile
  return n
enddef

def Append(p: dict<any>, lines: list<string>): void
  if empty(lines) || !bufexists(p.buf)
    return
  endif
  appendbufline(p.buf, '$', lines)
  var maxl: number = get(g:, 'vimprocess_max_lines', 5000)
  var n = len(getbufline(p.buf, 1, '$'))
  if n > maxl
    silent! deletebufline(p.buf, 1, n - maxl)
  endif
enddef

def StartJob(p: dict<any>): void
  p.run += 1
  var run: number = p.run
  var name: string = p.name
  p.status = 'running'
  try
    p.job = job_start(p.cmd, {
      in_io: 'pipe',
      out_io: 'pipe',
      err_io: 'pipe',
      out_mode: 'raw',
      err_mode: 'raw',
      stoponexit: get(g:, 'vimprocess_stoponexit', 'term'),
      out_cb: (ch, msg) => ProcessOut(name, run, msg),
      err_cb: (ch, msg) => ProcessOut(name, run, msg),
      exit_cb: (j, code) => ProcessExit(name, run, code),
    })
  catch
    p.status = 'failed'
    Append(p, ['[vimprocess] failed to start: ' .. v:exception])
    return
  endtry
  if job_status(p.job) != 'run'
    p.status = 'failed'
    Append(p, ['[vimprocess] failed to start'])
  endif
enddef

def ProcessOut(name: string, run: number, msg: string): void
  if !has_key(procs, name) || procs[name].run != run
    return
  endif
  var p = procs[name]
  var text: string = p.partial .. msg
  var lines = split(text, "\n", 1)
  p.partial = remove(lines, -1)
  if empty(lines)
    return
  endif
  Append(p, lines)
enddef

def ProcessExit(name: string, run: number, code: number): void
  if !has_key(procs, name) || procs[name].run != run
    return
  endif
  var p = procs[name]
  p.status = 'exited'
  p.code = code
  if p.partial != ''
    Append(p, [p.partial])
    p.partial = ''
  endif
  Append(p, ['[vimprocess] exited (code ' .. code .. ') ' .. strftime('%H:%M:%S')])
  DoRefreshList()
enddef

# Exact name or unambiguous prefix.
def Resolve(raw: string): dict<any>
  if has_key(procs, raw)
    return procs[raw]
  endif
  var found: list<string> = []
  for name in keys(procs)
    if name[: len(raw) - 1] ==# raw
      add(found, name)
    endif
  endfor
  if len(found) == 1
    return procs[found[0]]
  endif
  return {}
enddef

# External PID alive check (no output capture possible, OS limitation).
def AlivePid(pid: string): bool
  if isdirectory('/proc')
    return isdirectory('/proc/' .. pid)
  endif
  call system('kill -0 ' .. pid .. ' 2>/dev/null')
  return v:shell_error == 0
enddef

def IsRunning(p: dict<any>): bool
  if has_key(p, 'pid')
    return AlivePid(p.pid)
  endif
  return job_status(p.job) == 'run'
enddef

def EnsureBuf(p: dict<any>): void
  if bufexists(p.buf)
    return
  endif
  p.buf = bufadd('vimprocess://' .. p.name)
  bufload(p.buf)
  setbufvar(p.buf, '&buftype', 'nofile')
  setbufvar(p.buf, '&bufhidden', 'hide')
  setbufvar(p.buf, '&swapfile', 0)
  setbufvar(p.buf, '&buflisted', 0)
enddef

export def Start(...args: list<string>): void
  if empty(args)
    echoerr '[vimprocess] usage: ProcessStart {cmd} [args...]'
    return
  endif
  if !executable(args[0])
    echoerr '[vimprocess] not executable: ' .. args[0]
    return
  endif
  if index(['term', 'kill', 'hup', 'int', 'quit', ''], get(g:, 'vimprocess_stoponexit', 'term')) < 0
    echoerr '[vimprocess] bad g:vimprocess_stoponexit: ' .. g:vimprocess_stoponexit
    return
  endif
  var name = UniqueName(fnamemodify(args[0], ':t'))
  var p: dict<any> = {name: name, cmd: args, buf: -1, job: null_job,
    status: 'starting', code: -1, run: 0, partial: ''}
  procs[name] = p
  EnsureBuf(p)
  setbufline(p.buf, 1, ['[vimprocess] ' .. name .. ': ' .. join(args)])
  StartJob(p)
  DoRefreshList()
  echo '[vimprocess] started ' .. name
enddef

export def Kill(raw: string, force: number): void
  var p = Resolve(raw)
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. raw
    return
  endif
  if !IsRunning(p)
    echo '[vimprocess] ' .. p.name .. ' is not running'
    return
  endif
  if has_key(p, 'pid')
    call system('kill -' .. (force != 0 ? 'KILL' : 'TERM') .. ' ' .. p.pid)
    DoRefreshList()
    return
  endif
  job_stop(p.job, force != 0 ? 'kill' : 'term')
enddef

export def Interrupt(raw: string): void
  var p = Resolve(raw)
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. raw
    return
  endif
  if !IsRunning(p)
    echo '[vimprocess] ' .. p.name .. ' is not running'
    return
  endif
  if has_key(p, 'pid')
    call system('kill -INT ' .. p.pid)
    return
  endif
  job_stop(p.job, 'int')
enddef

export def Restart(raw: string): void
  var p = Resolve(raw)
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. raw
    return
  endif
  if has_key(p, 'pid')
    echoerr '[vimprocess] external process, cannot restart: ' .. p.name
    return
  endif
  if IsRunning(p)
    job_stop(p.job, 'term')
  endif
  EnsureBuf(p)
  Append(p, ['[vimprocess] restarted ' .. strftime('%H:%M:%S')])
  StartJob(p)
  DoRefreshList()
  echo '[vimprocess] restarted ' .. p.name
enddef

export def Forget(raw: string): void
  var p = Resolve(raw)
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. raw
    return
  endif
  if !has_key(p, 'pid') && IsRunning(p)
    echoerr '[vimprocess] still running, kill it first: ' .. p.name
    return
  endif
  if bufexists(p.buf)
    execute 'bwipeout! ' .. p.buf
  endif
  remove(procs, p.name)
  DoRefreshList()
  echo '[vimprocess] forgot ' .. p.name
enddef

# Track a foreign PID (alive/dead, kill). No output capture or stdin:
# the OS doesn't allow rewiring another process's fds.
export def Adopt(...args: list<string>): void
  if len(args) < 1 || args[0] !~# '^\d\+$'
    echoerr '[vimprocess] usage: ProcessAdopt {pid} [name]'
    return
  endif
  var pid = args[0]
  if !AlivePid(pid)
    echoerr '[vimprocess] no such process: ' .. pid
    return
  endif
  var name = len(args) > 1 ? args[1] : 'pid-' .. pid
  if name =~# '\s' || name == ''
    echoerr '[vimprocess] bad name: ' .. name
    return
  endif
  var pname = UniqueName(name)
  var p: dict<any> = {name: pname, pid: pid, buf: -1, job: null_job,
    status: 'running', code: -1, run: 0, partial: ''}
  procs[pname] = p
  EnsureBuf(p)
  setbufline(p.buf, 1, ['[vimprocess] ' .. pname .. ': external PID ' .. pid .. ' (no output capture)'])
  DoRefreshList()
  echo '[vimprocess] adopted ' .. pname
enddef

export def Send(...args: list<string>): void
  if len(args) < 1
    echoerr '[vimprocess] usage: ProcessSend {name} {text...}'
    return
  endif
  var p = Resolve(args[0])
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. args[0]
    return
  endif
  if has_key(p, 'pid')
    echoerr '[vimprocess] no stdin on external processes: ' .. p.name
    return
  endif
  if !IsRunning(p)
    echoerr '[vimprocess] not running: ' .. p.name
    return
  endif
  try
    ch_sendraw(p.job, join(args[1 :], ' ') .. "\n")
  catch
    echoerr '[vimprocess] send failed: ' .. p.name
  endtry
enddef

export def Show(raw: string): void
  var p = Resolve(raw)
  if empty(p)
    echoerr '[vimprocess] no such process (or ambiguous): ' .. raw
    return
  endif
  EnsureBuf(p)
  var w = bufwinnr(p.buf)
  if w > 0
    win_gotoid(win_getid(w))
    return
  endif
  execute 'belowright sbuffer ' .. p.buf
enddef

export def List(): void
  if list_buf == 0 || !bufexists(list_buf)
    new
    setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted
    setlocal filetype=vimprocess
    file vimprocess-list
    nnoremap <buffer> q :bdelete<CR>
    nnoremap <buffer> r :call vimprocess#RefreshList()<CR>
    nnoremap <buffer> <CR> :call vimprocess#ShowUnderCursor()<CR>
    nnoremap <buffer> K :call vimprocess#KillUnderCursor()<CR>
    nnoremap <buffer> R :call vimprocess#RestartUnderCursor()<CR>
    nnoremap <buffer> D :call vimprocess#ForgetUnderCursor()<CR>
    list_buf = bufnr('')
  else
    var w = bufwinnr(list_buf)
    if w > 0
      win_gotoid(win_getid(w))
    else
      execute 'sbuffer ' .. list_buf
    endif
  endif
  DoRefreshList()
enddef

export def RefreshList(): void
  DoRefreshList()
enddef

def DoRefreshList(): void
  if list_buf == 0 || !bufexists(list_buf)
    return
  endif
  var lines = ['# vimprocess              status    code  command']
  for name in sort(keys(procs))
    var p = procs[name]
    if has_key(p, 'pid') && p.status == 'running' && !AlivePid(p.pid)
      p.status = 'exited'
    endif
    var st: string = IsRunning(p) ? 'running' : p.status
    var code: string = has_key(p, 'pid') ? (st == 'running' ? '-' : '?') : (st == 'running' ? '-' : string(p.code))
    var what: string = has_key(p, 'pid') ? 'pid ' .. p.pid .. ' (adopted)' : join(p.cmd)
    lines->add(printf('%-24s  %-8s  %-4s  %s', name, st, code, what))
  endfor
  silent! deletebufline(list_buf, 1, '$')
  setbufline(list_buf, 1, lines)
enddef

def CursorName(): string
  var line = getline('.')
  if line == '' || line[0] == '#'
    return ''
  endif
  return matchstr(line, '^\S\+')
enddef

export def ShowUnderCursor(): void
  var name = CursorName()
  if name != ''
    Show(name)
  endif
enddef

export def KillUnderCursor(): void
  var name = CursorName()
  if name != ''
    Kill(name, 0)
  endif
enddef

export def RestartUnderCursor(): void
  var name = CursorName()
  if name != ''
    Restart(name)
  endif
enddef

export def ForgetUnderCursor(): void
  var name = CursorName()
  if name != ''
    Forget(name)
  endif
enddef

export def CompleteNames(lead: string, cmdline: string, pos: number): list<string>
  return filter(sort(keys(procs)), (_, v) => v =~# '^\V' .. escape(lead, '\'))
enddef
