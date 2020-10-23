let s:buffers = {}
let s:buffer_by_letter = {}
let s:buffer_ids = []

" when the focus switches to another *unlisted* buffer, it does not appear in
" the tabline, thus the tabline will list starting from the first buffer. For
" this, we keep track of the last current buffer to keep the tabline "position"
" in the same place.
let s:last_current_buffer_id = -1

" when you delete a buffer with the highest ID, we will never loop up there and
" it will always stay in the buffers list, so we need to remember the largest
" buffer ID.
let s:largest_buffer_id = 1
let s:is_picking_buffer = v:false

" either a slash or backslash
let s:path_separator = fnamemodify(getcwd(),':p')[-1:]

function! buffet#update() abort
    let l:largest_buffer_id = max([bufnr('$'), s:largest_buffer_id])
    let l:letters = 0

    for l:buffer_id in range(1, l:largest_buffer_id)
        " Check if we already keep track of this buffer
        let l:is_present = 0
        if has_key(s:buffers, l:buffer_id)
            let l:is_present = 1
        endif

        " Skip if a buffer with this id does not exist
        if !buflisted(l:buffer_id)
            if l:is_present
                if l:buffer_id == s:last_current_buffer_id
                    let s:last_current_buffer_id = -1
                endif

                " forget about this buffer
                call remove(s:buffers, l:buffer_id)
                call remove(s:buffer_ids, index(s:buffer_ids, l:buffer_id))
                let s:largest_buffer_id = max(s:buffer_ids)
            endif

            continue
        endif

        " If this buffer is already tracked and listed, we're good.
        " In case if it is the only buffer, still update, because an empty new
        " buffer id is being replaced by a buffer for an existing file.
        if l:is_present && len(s:buffers) > 1
            continue
        endif

        " hide terminal and quickfix buffers
        let l:buffer_type = getbufvar(l:buffer_id, '&buftype', '')
        if index(g:buffet_hidden_buffers, l:buffer_type) >= 0
            call setbufvar(l:buffer_id, '&buflisted', 0)
            continue
        endif

        let l:buffer_name = bufname(l:buffer_id)
        let l:buffer_head = fnamemodify(l:buffer_name, ':p:h')
        let l:buffer_tail = fnamemodify(l:buffer_name, ':t')

        " Initialize the buffer object
        let l:letter = g:buffet_letters[l:letters]

        let l:buffer = {}
        let l:buffer.head = split(l:buffer_head, s:path_separator)
        let l:buffer.not_new = len(l:buffer_tail)
        let l:buffer.tail = l:buffer.not_new ? l:buffer_tail : g:buffet_new_buffer_name 
        let l:buffer.letter = l:letter

        let s:buffer_by_letter[l:letter] = l:buffer_id
        let l:letters += 1

        " Update the buffers map
        let s:buffers[l:buffer_id] = l:buffer

        if !l:is_present
            " Update the buffer IDs list
            call add(s:buffer_ids, l:buffer_id)
            let s:largest_buffer_id = max([s:largest_buffer_id, l:buffer_id])
        endif
    endfor

    let l:buffer_name_count = {}

    " Set initial buffer name, and record occurrences
    for l:buffer in values(s:buffers)
        let l:buffer.index = -1
        let l:buffer.name = l:buffer.tail
        let l:buffer.length = len(l:buffer.name)

        if l:buffer.not_new
            let l:current_count = get(l:buffer_name_count, l:buffer.name, 0)
            let l:buffer_name_count[l:buffer.name] = l:current_count + 1
        endif
    endfor

    " Disambiguate buffer names with multiple occurrences
    while len(filter(l:buffer_name_count, 'v:val > 1'))
        let l:ambiguous = l:buffer_name_count
        let l:buffer_name_count = {}

        for l:buffer in values(s:buffers)
            if has_key(l:ambiguous, l:buffer.name)
                let l:buffer_path = l:buffer.head[l:buffer['index']:]
                call add(l:buffer_path, l:buffer.tail)

                let l:buffer.index -= 1
                let l:buffer.name = join(l:buffer_path, s:path_separator)
                let l:buffer.length = len(l:buffer.name)
            endif

            if l:buffer.not_new
                let l:current_count = get(l:buffer_name_count, l:buffer.name, 0)
                let l:buffer_name_count[l:buffer.name] = l:current_count + 1
            endif
        endfor
    endwhile

    let l:current_buffer_id = bufnr('%')
    if has_key(s:buffers, l:current_buffer_id)
        let s:last_current_buffer_id = l:current_buffer_id
    elseif s:last_current_buffer_id == -1 && len(s:buffer_ids) > 0
        let s:last_current_buffer_id = s:buffer_ids[0]
    endif

    " Hide tabline if only one buffer and tab open
    if !g:buffet_always_show_tabline && len(s:buffer_ids) == 1 && tabpagenr('$') == 1
        set showtabline=0
    endif
endfunction

function! s:GetVisibleRange(length_limit, buffer_padding) abort
    let l:current_buffer_id = s:last_current_buffer_id

    if l:current_buffer_id == -1
        return [-1, -1]
    endif

    let l:current_buffer_id_i = index(s:buffer_ids, l:current_buffer_id)

    let l:current_buffer = s:buffers[l:current_buffer_id]
    let l:capacity = a:length_limit - l:current_buffer.length - a:buffer_padding
    let l:left_i = l:current_buffer_id_i
    let l:right_i = l:current_buffer_id_i

    for l:left_i in range(l:current_buffer_id_i - 1, 0, -1)
        let l:buffer = s:buffers[s:buffer_ids[l:left_i]]
        if (l:buffer.length + a:buffer_padding) <= l:capacity
            let l:capacity = l:capacity - l:buffer.length - a:buffer_padding
        else
            let l:left_i = l:left_i + 1
            break
        endif
    endfor

    for l:right_i in range(l:current_buffer_id_i + 1, len(s:buffers) - 1)
        let l:buffer = s:buffers[s:buffer_ids[l:right_i]]
        if (l:buffer.length + a:buffer_padding) <= l:capacity
            let l:capacity = l:capacity - l:buffer.length - a:buffer_padding
        else
            let l:right_i = l:right_i - 1
            break
        endif
    endfor

    return [l:left_i, l:right_i]
endfunction

function! s:GetBufferElements(capacity, buffer_padding) abort
    let [l:left_i, l:right_i] = s:GetVisibleRange(a:capacity, a:buffer_padding)
    " TODO: evaluate if calling this ^ twice will get better visuals

    if l:left_i < 0 || l:right_i < 0
        return []
    endif

    let l:buffer_elems = []

    let l:trunced_left = l:left_i
    if l:trunced_left
        let l:left_trunc_elem = {}
        let l:left_trunc_elem.type = 'LeftTrunc'
        let l:left_trunc_elem.value = g:buffet_left_trunc_icon . ' ' . l:trunced_left
        call add(l:buffer_elems, l:left_trunc_elem)
    endif

    for l:i in range(l:left_i, l:right_i)
        let l:buffer_id = s:buffer_ids[l:i]
        let l:buffer = s:buffers[l:buffer_id]

        if l:buffer_id == winbufnr(0)
            let l:type_prefix = 'Current'
        elseif bufwinnr(l:buffer_id) > 0
            let l:type_prefix = 'Active'
        else
            let l:type_prefix = ''
        endif

        let l:elem = {}
        let l:elem.index = l:i + 1
        let l:elem.value = l:buffer.name
        let l:elem.letter = l:buffer.letter
        let l:elem.buffer_id = l:buffer_id
        let l:elem.is_modified = getbufvar(l:buffer_id, '&mod')

        if l:elem.is_modified
            let l:type_prefix = 'Mod' . l:type_prefix
        endif

        let l:elem.type = l:type_prefix . 'Buffer'

        call add(l:buffer_elems, l:elem)
    endfor

    let l:trunced_right = (len(s:buffers) - l:right_i - 1)
    if l:trunced_right > 0
        let l:right_trunc_elem = {}
        let l:right_trunc_elem.type = 'RightTrunc'
        let l:right_trunc_elem.value = l:trunced_right . ' ' . g:buffet_right_trunc_icon
        call add(l:buffer_elems, l:right_trunc_elem)
    endif

    return l:buffer_elems
endfunction

function! s:GetAllElements(capacity, buffer_padding) abort
    let l:last_tab_id = tabpagenr('$')
    let l:current_tab_id = tabpagenr()
    let l:buffer_elems = s:GetBufferElements(a:capacity, a:buffer_padding)
    let l:tab_elems = []

    for l:tab_id in range(1, l:last_tab_id)
        let l:elem = {}
        let l:elem.value = l:tab_id
        let l:elem.type = 'Tab'
        call add(l:tab_elems, l:elem)

        if l:tab_id == l:current_tab_id
            let l:tab_elems += l:buffer_elems
            let l:elem.type = 'TabSel'
        endif
    endfor

    let l:end_elem = {'type': 'End', 'value': ''}
    call add(l:tab_elems, l:end_elem)

    return l:tab_elems
endfunction

function! s:IsBufferElement(element) abort
    if index(g:buffet_buffer_types, a:element.type) >= 0
        return 1
    endif

    return 0
endfunction

function! s:Len(string) abort
    return len(substitute(a:string, '[^\d0-\d127]', '-', 'g'))
endfunction

function! s:GetPickerHighlight(type) abort
    return '%#' . g:buffet_prefix . 'Picker' . a:type . '#'
endfunction

function! s:GetTypeHighlight(type) abort
    return '%#' . g:buffet_prefix . a:type . '#'
endfunction

function! s:Render() abort
    let l:sep_len = s:Len(g:buffet_separator)

    let l:tabs_count = tabpagenr('$')
    let l:tabs_len = 0
    for l:i in range(0, l:tabs_count)
        let l:icon = ' ' . g:buffet_tab_icon
        if exists('g:loaded_taboo') && g:loaded_taboo == 1
            let l:name = TabooTabName(l:i)
            if l:name !=# ''
                let l:icon = l:icon . ' ' . l:name
            endif
        endif
        let l:tabs_len += (1 + s:Len(l:icon) + 1 + l:sep_len)
    endfor

    let l:left_trunc_len = 1 + s:Len(g:buffet_left_trunc_icon) + 1 + 2 + 1 + l:sep_len
    let l:right_trunc_len =  1 + 2 + 1 + s:Len(g:buffet_right_trunc_icon) + 1 + l:sep_len
    let l:trunc_len = l:left_trunc_len + l:right_trunc_len

    let l:capacity = &columns - l:tabs_len - l:trunc_len - 5
    let l:buffer_padding = 1 + (g:buffet_use_devicons ? 1+1 : 0) + 1 + l:sep_len

    let l:elements = s:GetAllElements(l:capacity, l:buffer_padding)

    let l:render = ''
    for l:i in range(0, len(l:elements) - 2)
        let l:left = l:elements[l:i]
        let l:elem = l:left
        let l:right = l:elements[l:i + 1]

        if l:elem.type ==# 'Tab' || l:elem.type ==# 'TabSel'
            let l:render .= '%' . l:elem.value . 'T'
        elseif s:IsBufferElement(l:elem) && has('nvim')
            let l:render .= '%' . l:elem.buffer_id . '@SwitchToBuffer@'
        endif

        let l:highlight = s:GetTypeHighlight(l:elem.type)
        let l:render .= l:highlight

        if g:buffet_show_index && s:IsBufferElement(l:elem)
            let l:render .= ' ' . l:elem.index
        endif

        let l:icon = ''

        if l:elem.type ==# 'Tab' || l:elem.type ==# 'TabSel'
            let l:icon = ' ' . g:buffet_tab_icon
            if exists('g:loaded_taboo') && g:loaded_taboo == 1
                let l:name = TabooTabName(l:elem.value)
                if l:name !=# ''
                    let l:icon .= ' ' . l:name
                endif
            endif

            let l:render .= l:icon
        else
            if s:is_picking_buffer == v:false
                if g:buffet_use_devicons && s:IsBufferElement(l:elem) && exists('*WebDevIconsGetFileTypeSymbol')
                    let l:icon = ' ' . WebDevIconsGetFileTypeSymbol(l:elem.value)
                endif
            else
                let l:icon = s:GetPickerHighlight(l:elem.type) .
                            \ ' ' . l:elem.letter .
                            \ s:GetTypeHighlight(l:elem.type)
            endif

            let l:render .= l:icon . ' ' . l:elem.value
        endif

        if s:IsBufferElement(l:elem)
            if l:elem.is_modified && g:buffet_modified_icon !=# ''
                let l:render .= g:buffet_modified_icon
            endif
        endif

        let l:render .= ' '

        let l:separator =  g:buffet_has_separator[l:left.type][l:right.type]
        let l:separator_hi = s:GetTypeHighlight(l:left.type . l:right.type)
        let l:render .= l:separator_hi . l:separator

        if (l:elem.type ==# 'Tab' || l:elem.type ==# 'TabSel') && has('nvim')
            let l:render .= '%T'
        elseif s:IsBufferElement(l:elem) && has('nvim')
            let l:render .= '%T'
        endif
    endfor

    if !has('nvim')
        let l:render .= '%T'
    endif

    let l:render .= s:GetTypeHighlight('Buffer')

    let &tabline=l:render
    " return l:render
endfunction

function! buffet#render() abort
    call buffet#update()
    return s:Render()
endfunction

function! s:GetBuffer(buffer) abort
    if empty(a:buffer) && s:last_current_buffer_id >= 0
        let l:btarget = s:last_current_buffer_id
    elseif a:buffer =~# '^\d\+$'
        let l:btarget = bufnr(str2nr(a:buffer))
    else
        let l:btarget = bufnr(a:buffer)
    endif

    return l:btarget
endfunction

function! buffet#bswitch(index) abort
    let l:i = str2nr(a:index) - 1
    if l:i < 0 || l:i > len(s:buffer_ids) - 1
        echohl ErrorMsg
        echom 'Invalid buffer index'
        echohl None
        return
    endif
    let l:buffer_id = s:buffer_ids[l:i]
    execute 'silent buffer ' . l:buffer_id
endfunction

" inspired and based on https://vim.fandom.com/wiki/Deleting_a_buffer_without_closing_the_window
function! buffet#bwipe(bang, buffer) abort
    let l:btarget = s:GetBuffer(a:buffer)

    let l:filters = get(g:, 'buffet_bwipe_filters', [])
    if type(l:filters) == type([])
        for l:f in l:filters
            if function(l:f)(a:bang, l:btarget) > 0
                return
            endif
        endfor
    endif

    if l:btarget < 0
        echohl ErrorMsg
        echom 'No matching buffer for ' . a:buffer
        echohl None

        return
    endif

    if empty(a:bang) && getbufvar(l:btarget, '&modified')
        echohl ErrorMsg
        echom 'No write since last change for buffer ' . l:btarget . ' (add ! to override)'
        echohl None
        return
    endif

    " IDs of windows that view target buffer which we will delete.
    let l:wnums = filter(range(1, winnr('$')), 'winbufnr(v:val) == l:btarget')

    let l:wcurrent = winnr()
    for l:w in l:wnums
        " switch to window with ID 'w'
        execute 'silent ' . l:w . 'wincmd w'

        let l:prevbuf = bufnr('#')
        " if the previous buffer is another listed buffer, switch to it...
        if l:prevbuf > 0 && buflisted(l:prevbuf) && l:prevbuf != l:btarget
            buffer #
        " ...otherwise just go to the previous buffer in the list.
        else
            bprevious
        endif

        " if the 'bprevious' did not work, then just open a new buffer
        if l:btarget == bufnr('%')
            execute 'silent enew' . a:bang
        endif
    endfor

    " finally wipe the tarbet buffer
    execute 'silent bwipe' . a:bang . ' ' . l:btarget
    " switch back to original window
    execute 'silent ' . l:wcurrent . 'wincmd w'
endfunction

function! buffet#bonly(bang, buffer) abort
    let l:btarget = s:GetBuffer(a:buffer)

    for l:b in s:buffer_ids
        if l:b == l:btarget
            continue
        endif

        call buffet#bwipe(a:bang, l:b)
    endfor
endfunction

function! buffet#pick() abort
    let s:is_picking_buffer = v:true
    call buffet#render()
    redraw
    let s:is_picking_buffer = v:false

    let l:char = getchar()
    let l:letter = nr2char(l:char)

    let l:did_switch = v:false

    if !empty(l:letter)
        if has_key(s:buffer_by_letter, l:letter)
            let l:bufnr = s:buffer_by_letter[l:letter]
            execute 'buffer' l:bufnr
        end
    end

    if !l:did_switch
        call buffet#render()
        redraw
    end
endfunction
