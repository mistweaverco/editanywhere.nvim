if exists("g:loaded_editanywhere")
        finish
endif
let g:loaded_editanywhere = 1

let s:PluginName = "editanywhere.nvim"

let s:EDITANYWHERE_BASE_URL = "http://127.0.0.1:6789/"

let s:EDITANYWHERE_TMP_DIR='/tmp/EditAnywhere/'

function! s:nr2hex(nr)
  let n = a:nr
  let r = ""
  while n
    let r = '0123456789ABCDEF'[n % 16] . r
    let n = n / 16
  endwhile
  return r
endfunction

function! s:encodeURIComponent(instr)
  let instr = iconv(a:instr, &enc, "utf-8")
  let len = strlen(instr)
  let i = 0
  let outstr = ''
  while i < len
    let ch = instr[i]
    if ch =~# '[0-9A-Za-z-._~!''()*]'
      let outstr .= ch
    elseif ch == ' '
      let outstr .= '+'
    else
      let outstr .= '%' . substitute('0' . s:nr2hex(char2nr(ch)), '^.*\(..\)$', '\1', '')
    endif
    let i = i + 1
  endwhile
  return outstr
endfunction

function! s:GetBasedir(...)
        let buffername = bufname("%")
        let filepath = get(a:, 1, buffername)
        let basedir = fnamemodify(filepath, ":h")
        if basedir == "."
                return ""
        else
                return basedir
endfunction

function! s:GetCurrentBufferContentsAsString()
	let buff=join(getline(1, '$'), "\n")
	return buff
endfunction

function! editanywhere#syncTempFileWithServer(...)
        let buffername = bufname("%")
        let basedir = s:GetBasedir()
        let filepath = get(a:, 1, buffername)
	let parts = split(filepath, '/\+')

	if len(parts) < 4
		return
	endif

	if parts[0] != "tmp"
		return
	endif

	if parts[1] != "EditAnywhere"
		return
	endif

	let appId = parts[2]
	let ressourceId = s:GetFilenameWithoutExtension()
	let file_extension = s:GetFileExtension()
	let contents = s:encodeURIComponent(s:GetCurrentBufferContentsAsString())
        let cmd =  'curl -s ' . s:EDITANYWHERE_BASE_URL . appId . '/' . ressourceId . ' -d "content='.contents.'&file_extension='.file_extension.'" | jq -r .'
	let response = system(cmd)
endfunction

function! s:RegisterAutoCommandOnBufWrite(enable)
        if a:enable == 1
                augroup AutoEditAnywhereSyncOnBufWriteAugroup
                        autocmd!
                        autocmd! BufWritePost * :call editanywhere#syncTempFileWithServer()
                augroup END
        else
                augroup AutoEditAnywhereSyncOnBufWriteAugroup
                        autocmd!
                augroup END
        endif
endfunction

function! s:GetFilenameWithoutExtension()
	return expand('%:t:r')
endfunction

function! s:GetFileExtension()
	return '.' . expand('%:t:e')
endfunction

function! s:FileExists(filepath)
        if filereadable(a:filepath)
                return 1
        else
                return 0
        endif
endfunction

function! s:getAllApps()
        let cmd =  'curl -s ' . s:EDITANYWHERE_BASE_URL . ' | jq -r .[]'
	let applist = systemlist(cmd)
        return applist
endfunction

function! s:getRessourcesForAppId(appId)
        let cmd =  'curl -s ' . s:EDITANYWHERE_BASE_URL . a:appId . ' | jq -r .[]'
	let ressourcelist = systemlist(cmd)
        return ressourcelist
endfunction

function! s:editanywhereAppCompletion(appstring)
        let s:applist = s:getAllApps()
        return filter(s:applist, 'v:val =~ "^'. a:appstring .'"')
endfunction

function! s:editanywhereRessourceCompletion(appstring, ressourcestring)
        let s:ressourcelist = s:getRessourcesForAppId(a:appstring)
        return filter(s:ressourcelist, 'v:val =~ "^'. a:ressourcestring .'"')
endfunction

function! s:editanywhereCompletion(arg, line, pos)
	let parts = split(a:line, '\s\+')
	if len(parts) > 2
	" then we're definitely finished with the first argument:
		return s:editanywhereRessourceCompletion(parts[1], a:arg)
	elseif len(parts) > 1 && a:arg =~ '^\s*$'
	" then we've entered the first argument, but the current one is still blank:
		return s:editanywhereRessourceCompletion(parts[1], a:arg)
	else
	" we're still on the first argument:
		return s:editanywhereAppCompletion(a:arg)
	endif
endfunction

function! editanywhere#openRessource(appId, ressourceId)
        let cmd =  'curl -s ' . s:EDITANYWHERE_BASE_URL . a:appId . '/' . a:ressourceId . ' | jq -r .'
	let fileExtension = trim(system(cmd . 'file_extension'))
	let content = system(cmd . 'content')
	let dir_loc = s:EDITANYWHERE_TMP_DIR . a:appId . '/'
	let file_loc = a:ressourceId . fileExtension
	let loc = dir_loc . file_loc
	call mkdir(expand(dir_loc), 'p')
	call writefile(split(content, "\n", 1), loc, 'b')
	exec 'edit' . loc
        call s:RegisterAutoCommandOnBufWrite(1)
endfunction

function! s:OnJobEventHandler(job_id, data, event) dict
        if a:event == 'stdout'
                let str = self.shell.' stdout: '.join(a:data)
        elseif a:event == 'stderr'
                let str = self.shell.' stderr: '.join(a:data)
        else
                let str = self.shell.' finished'
        endif
        echom str
endfunction

let s:jobEventCallbacks = {
        \ 'on_stdout': function('s:OnJobEventHandler'),
        \ 'on_stderr': function('s:OnJobEventHandler'),
        \ 'on_exit': function('s:OnJobEventHandler')
\ }

function! s:ExecExternalCommand(command)
        if has("nvim") == 1
                call jobstart(["bash", "-c", a:command])
        elseif v:version >= 800
                call job_start("bash -c " . a:command)
        else
                silent execute "!" . a:command
        endif
endfunction

" command! EditAnywhereBrowse call editanywhere#browse()
command! -bang -complete=customlist,s:editanywhereCompletion -nargs=* EditAnywhere call editanywhere#openRessource(<f-args>)
