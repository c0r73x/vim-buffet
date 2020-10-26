if exists('g:buffet_loaded')
    finish
endif

let g:buffet_loaded = 1

let g:buffet_letters = 'aoeuidhtns1234567890qjkxbmwvzåäöpryfgcrl'
let g:buffet_always_show_tabline = get(g:, 'buffet_always_show_tabline', 1)

let g:vim_mode = 'cterm'

if has('gui') || has('termguicolors')
    let g:vim_mode = 'gui'
    if !get(g:, 'buffet_use_gui_tablne', 0)
        set guioptions-=e
    endif
endif

if get(g:, 'buffet_powerline_separators', 0)
    let g:buffet_powerline_separators = 1
    let g:buffet_noseparator = '\ue0b0'
    let g:buffet_separator = '\ue0b1'
else
    let g:buffet_powerline_separators = 0
    let g:buffet_noseparator = get(g:, 'buffet_noseparator', ' ')
    let g:buffet_separator = get(g:, 'buffet_separator', '|')
endif

let g:buffet_show_index = get(g:, 'buffet_show_index', 0)
let g:buffet_max_plug = get(g:, 'buffet_max_plug', 10)

if get(g:, 'buffet_use_devicons', 1)
    if !exists('*WebDevIconsGetFileTypeSymbol')
        let g:buffet_use_devicons = 0
    else
        let g:buffet_use_devicons = 1
    endif
else
    let g:buffet_use_devicons = 0
endif

if !exists('g:buffet_modified_icon')
    let g:buffet_modified_icon = '+'
endif

if !exists('g:buffet_left_trunc_icon')
    let g:buffet_left_trunc_icon = '<'
endif

if !exists('g:buffet_right_trunc_icon')
    let g:buffet_right_trunc_icon = '>'
endif

if !exists('g:buffet_new_buffer_name')
    let g:buffet_new_buffer_name = '*'
endif

if !exists('g:buffet_tab_icon')
    let g:buffet_tab_icon = '#'
endif

if !exists('g:buffet_hidden_buffers')
    let g:buffet_hidden_buffers = ['terminal', 'quickfix']
endif

let g:buffet_prefix = 'Buffet'
let g:buffet_has_separator = {
            \     'Tab': {
            \         'Tab': g:buffet_separator,
            \         'TabSel': g:buffet_separator,
            \         'LeftTrunc': g:buffet_separator,
            \         'End' : g:buffet_separator,
            \     },
            \     'TabSel': {
            \         'Tab': g:buffet_separator,
            \         'TabSel': g:buffet_separator,
            \         'LeftTrunc': g:buffet_separator,
            \         'End' : g:buffet_separator,
            \     },
            \     'LeftTrunc': {
            \         'Buffer': g:buffet_separator,
            \         'CurrentBuffer': g:buffet_separator,
            \         'ActiveBuffer': g:buffet_separator,
            \         'ModBuffer': g:buffet_separator,
            \     },
            \     'RightTrunc': {
            \         'Tab': g:buffet_separator,
            \         'TabSel': g:buffet_separator,
            \         'End': g:buffet_separator,
            \     },
            \ }

let g:buffet_buffer_types = [
            \    'Buffer',
            \    'ActiveBuffer',
            \    'CurrentBuffer',
            \    'ModBuffer',
            \    'ModActiveBuffer',
            \    'ModCurrentBuffer',
            \ ]

for s:type in g:buffet_buffer_types
    let g:buffet_has_separator['Tab'][s:type] = g:buffet_separator
    let g:buffet_has_separator['TabSel'][s:type] = g:buffet_separator
    let g:buffet_has_separator[s:type] = {
                \     'RightTrunc': g:buffet_separator,
                \     'Tab': g:buffet_separator,
                \     'TabSel': g:buffet_separator,
                \     'End': g:buffet_separator,
                \ }

    for s:t in g:buffet_buffer_types
        let g:buffet_has_separator[s:type][s:t] = g:buffet_separator
    endfor
endfor

function! s:GetHiAttr(name, attr)
    let l:attr_suffix = ''
    return synIDattr(synIDtrans(hlID(a:name)), a:attr . l:attr_suffix, g:vim_mode)
endfunction

function! s:SetHi(name, fg, bg)
    let l:spec = ''
    if a:fg !=# ''
        let l:fg_spec = g:vim_mode . 'fg=' . a:fg
        let l:spec = l:fg_spec
    endif

    if a:bg !=# ''
        let l:bg_spec = g:vim_mode . 'bg=' . a:bg

        if l:spec !=# ''
            let l:bg_spec = ' ' . l:bg_spec
        endif

        let l:spec .= l:bg_spec
    endif

    if l:spec !=# ''
        exec 'silent hi! ' . a:name . ' ' . l:spec
    endif
endfunction

function! s:LinkHi(name, target)
    exec 'silent hi! link ' . a:name . ' ' . a:target
endfunction

function! s:SetColors() abort
    " TODO: try to match user's colorscheme
    " Issue: https://github.com/bagrat/vim-buffet/issues/5
    " if get(g:, 'buffet_match_color_scheme', 1)

    hi! BuffetPicker cterm=NONE ctermfg=1 guifg=#FF0000
    hi! BuffetCurrentBuffer cterm=NONE ctermbg=2 ctermfg=8 guibg=#00FF00 guifg=#000000
    hi! BuffetActiveBuffer cterm=NONE ctermbg=10 ctermfg=2 guibg=#999999 guifg=#00FF00
    hi! BuffetBuffer cterm=NONE ctermbg=10 ctermfg=8 guibg=#999999 guifg=#000000

    hi! link BuffetModCurrentBuffer BuffetCurrentBuffer
    hi! link BuffetModActiveBuffer BuffetActiveBuffer
    hi! link BuffetModBuffer BuffetBuffer

    hi! BuffetTrunc cterm=bold ctermbg=11 ctermfg=8 guibg=#999999 guifg=#000000
    hi! BuffetTab cterm=NONE ctermbg=4 ctermfg=8 guibg=#0000FF guifg=#000000

    hi! link BuffetLeftTrunc BuffetTrunc
    hi! link BuffetRightTrunc BuffetTrunc
    hi! link BuffetEnd BuffetBuffer

    if exists('*g:BuffetSetCustomColors')
        call g:BuffetSetCustomColors()
    endif

    let l:picker_fg = s:GetHiAttr(g:buffet_prefix . 'Picker', 'fg')
    for l:type in g:buffet_buffer_types
        let l:buf_hi = g:buffet_prefix . l:type
        let l:buf_bg = s:GetHiAttr(l:buf_hi, 'bg')

        if l:picker_fg==# ''
            let l:picker_fg = 'NONE'
        endif

        if l:buf_bg ==# ''
            let l:buf_bg = 'NONE'
        endif

        call s:SetHi(g:buffet_prefix . 'Picker'. l:type, l:picker_fg, l:buf_bg)
    endfor

    for l:left in keys(g:buffet_has_separator)
        for l:right in keys(g:buffet_has_separator[l:left])
            let l:left_hi = g:buffet_prefix . l:left
            let l:right_hi = g:buffet_prefix . l:right
            let l:left_bg = s:GetHiAttr(l:left_hi, 'bg')
            let l:right_bg = s:GetHiAttr(l:right_hi, 'bg')

            if l:left_bg ==# ''
                let l:left_bg = 'NONE'
            endif

            if l:right_bg ==# ''
                let l:right_bg = 'NONE'
            endif

            let l:sep_hi = g:buffet_prefix . l:left . l:right
            if l:left_bg != l:right_bg
                let g:buffet_has_separator[l:left][l:right] = g:buffet_noseparator

                call s:SetHi(l:sep_hi, l:left_bg, l:right_bg)
            else
                let g:buffet_has_separator[l:left][l:right] = g:buffet_separator

                call s:LinkHi(l:sep_hi, l:left_hi)
            endif
        endfor
    endfor
endfunction

" Set solors also at the startup
call s:SetColors()

if has('nvim')
    function! SwitchToBuffer(buffer_id, clicks, btn, flags)
        exec 'silent buffer ' . a:buffer_id
    endfunction
endif

function! buffet#bwipe_nerdtree_filter(bang, buffer)
    if exists('t:NERDTreeBufName')
        if winnr() == bufwinnr(t:NERDTreeBufName)
            return 0
        endif
    endif

    return 0
endfunction

let g:buffet_bwipe_filters = ['buffet#bwipe_nerdtree_filter']

for s:n in range(1, g:buffet_max_plug)
    execute printf('noremap <silent> <Plug>BuffetSwitch(%d) :call buffet#bswitch(%d)<cr>', s:n, s:n)
endfor

command! -bang -complete=buffer -nargs=? Bw call buffet#bwipe(<q-bang>, <q-args>)
command! -bang -complete=buffer -nargs=? Bonly call buffet#bonly(<q-bang>, <q-args>)
command! -bang -complete=buffer -nargs=? BuffetPick call buffet#pick()

augroup buffet
    autocmd!
    autocmd VimEnter,BufAdd,TabEnter * set showtabline=2
    autocmd BufEnter,BufLeave,BufDelete,BufWritePost * call buffet#render()
    autocmd ColorScheme * call s:SetColors()
augroup end
