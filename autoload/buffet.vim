" buffers (Dict) - Track listed buffers
" ---
" +{buffer_id} (Dict): buffer_id is key
" Basic Info:
"   $head (List)-str: buffer's directory abspath, split by `s:path_separator`
"   $not_new (Number): it's not new if len(@tail) > 0; not [No Name] file ?
"   $tail (String): buffer's filename
" State Info:
"   $index (Number)(-1): index for $head[$index] + $tail = $name
"     to distinguish identical filename, decrease if still identical
"   $name (String): filename to display on tabline
"   $length (Number): filename length
let s:buffers = {}


" buffer_ids - Because buffers{} doesn't store buffers in order,
" that's why we need this for UI process
" ---
" => (List)-number:
"   ${buffet_id}: buffer id; list indexes is the order
" Future Feature: (XXX) I think we can reorder this to reorder buffer's position
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


" either a slash or backslash
let s:path_separator = fnamemodify(getcwd(),':p')[-1:]


" ======================

function! buffet#update()

    " Phase I: Init or Update buffers basic info
    " ==========================================
    let largest_buffer_id = max([bufnr('$'), s:largest_buffer_id])

    for buffer_id in range(1, largest_buffer_id)
        let is_tracked = has_key(s:buffers, buffer_id) ? 1 : 0

        " Skip if a buffer with this id does not exist in `buflisted`:
        " bdelete, floating_window, term, not exists, ...
        if !buflisted(buffer_id)
            " Clear this buffer if it is being tracked by `buffers{}`
            if is_tracked
                call remove(s:buffers, buffer_id)
                call remove(s:buffer_ids, index(s:buffer_ids, buffer_id))

                " (XXX) Reassign because the buffer of s:last_current_buffer_id is
                " clear ? For bdelete case only ?
                if buffer_id == s:last_current_buffer_id
                    let s:last_current_buffer_id = -1
                endif

                let s:largest_buffer_id = max(s:buffer_ids)
            endif
            continue
        endif

        " If this buffer is already tracked and listed, we're good.
        " In case if it is the only buffer, still update, because an empty new
        " buffer id is being replaced by a buffer for an existing file.
        if is_tracked && len(s:buffers) > 1
            continue
        endif

        " Hide & skip terminal and quickfix buffers
        if s:IsTermOrQuickfix(buffer_id)
            call setbufvar(buffer_id, "&buflisted", 0)
            continue
        endif

        " Update the buffers map
        let s:buffers[buffer_id] = s:ComposeBufferInfo(buffer_id)

        if !is_tracked
            " Update the buffer IDs list
            call add(s:buffer_ids, buffer_id)
            " FIXME: Wtf is this ? Why though ?
            let s:largest_buffer_id = max([s:largest_buffer_id, buffer_id])
        endif
    endfor

    " Phase II: Handling identical filenames
    " ======================================
    " buffer_name_count (Dict) - Memoize identical filenames
    "   +{buffer.name} (Number): count
    let buffer_name_count = {}

    " Set initial buffer name, and record occurrences
    for buffer in values(s:buffers)
        let buffer            = extend(buffer, s:InitOccState(buffer))
        let buffer_name_count = extend(buffer_name_count,
            \   s:RecordOcc(buffer_name_count, buffer))
    endfor

    " Disambiguate buffer names with multiple occurrences
    while len(filter(buffer_name_count, 'v:val > 1'))
        let ambiguous = buffer_name_count
        let buffer_name_count = {}

        " Update buffer name; and record occurrences after updated
        for buffer in values(s:buffers)
            if has_key(ambiguous, buffer.name)
                let buffer = extend(buffer, s:UpdateOccState(buffer))
            endif

            let buffer_name_count = extend(buffer_name_count,
                \   s:RecordOcc(buffer_name_count, buffer))
        endfor
    endwhile

    " Phase III: Update `s:last_current_buffer_id`
    " ==========================================
    let current_buffer_id = bufnr('%')

    if has_key(s:buffers, current_buffer_id)
        let s:last_current_buffer_id = current_buffer_id
    " (XXX) I don't know when this will be triggered
    elseif s:last_current_buffer_id == -1 && len(s:buffer_ids) > 0
        let s:last_current_buffer_id = s:buffer_ids[0]
    endif

    " Phase IV: Misc
    " ===============
    " FIXME: Break this to some where or leave it :)
    " Hide tabline if only one buffer and tab open
    if !g:buffet_always_show_tabline && len(s:buffer_ids) == 1 && tabpagenr("$") == 1
        set showtabline=0
    endif
endfunction


" IsTermOrQuickfix: Return TRUE(1) if it's a Terminal or Quickfix buffer.
" @bufid (Number): buffer id is used to check
" => (Boolean): FALSE(0) if not
" ===
function! s:IsTermOrQuickfix(bufid) abort
    let buffer_type = getbufvar(a:bufid, "&buftype", "")
    if index(["terminal", "quickfix"], buffer_type) >= 0
        return v:true
    endif
    return v:false
endfunction


" ComposeBufferInfo: Compose basic info: $head, $not_new, $tail based on
" the buffer id is given.
" @bufid (Number) buffer id used to retrieve
"
" => buffer{} (Dict): return a dictionary contains 3 items:
"   $head (String): UNDERSTAND THESE 3 at `s:buffers`
"   $now_new (Number)
"   $tail (String)
" ===
function! s:ComposeBufferInfo(bufid) abort
    let buffer_name = bufname(a:bufid)
    let buffer_head = fnamemodify(buffer_name, ':p:h')
    let buffer_tail = fnamemodify(buffer_name, ':t')

    " Initialize the buffer object
    let buffer = {}
    let buffer.head = split(buffer_head, s:path_separator)
    let buffer.not_new = len(buffer_tail)
    let buffer.tail = buffer.not_new ? buffer_tail : g:buffet_new_buffer_name

    return buffer
endfunction


" InitOccState: Init buffer's state.
" @buf (Dict): the buffer
"
" => buffer{} (Dict): UNDERSTAND THESE 3 at `s:buffers{}`
"    $index (Number)
"    $name (String)
"    $length (Number)
" ===
function! s:InitOccState(buf) abort
    let buffer = {}
    let buffer.index = -1           " default value of $index
    let buffer.name = a:buf.tail
    let buffer.length = len(buffer.name)

    return buffer
endfunction


" RecordOcc: Record occurrences.
" @buffer_name_count (Dict): `buffer_name_count`
" @buf (Dict): the buffer
"
" => (Dict): return the following Dict OR an Empty Dict {} if $not_new == 0
"   ${buf.name} (Number): {current_count}
" ===
function! s:RecordOcc(buffer_name_count, buf) abort
    if a:buf.not_new
        let l:current_count = get(a:buffer_name_count, a:buf.name, 0)
        return { a:buf.name: l:current_count+1 }
    endif
    return {}
endfunction


" UpdateOccState: Update buffers's state.
" @buf (Dict): a buffer item from `s:buffers`
"
" => buffer{} (Dict)
"   $index (Number): decrease the index
"   $name (String)
"   $length (Number)
function! s:UpdateOccState(buf) abort
    let buffer_path = a:buf.head[a:buf.index:]
    call add(buffer_path, a:buf.tail)

    let buffer = {}
    let buffer.index = a:buf.index - 1
    let buffer.name = join(buffer_path, s:path_separator)
    let buffer.length = len(buffer.name)

    return buffer
endfunction


" UI ==========================================================================



function! buffet#render()
    call buffet#update()

    let [capacity, buffer_padding] = s:GetCapacityAndPadding()

    let [left_idx, right_idx] = s:GetVisibleRange(capacity, buffer_padding)

    let elements = s:GetAllElements(left_idx, right_idx)

    let render = ""

    for i in range(0, len(elements) - 2)
        let left = elements[i]
        let elem = left
        let right = elements[i + 1]

        if elem.type == "Tab"
            let render = render . "%" . elem.value . "T"
        elseif s:IsBufferElement(elem) && has("nvim")
            let render = render . "%" . elem.buffer_id . "@SwitchToBuffer@"
        endif

        let highlight = s:GetTypeHighlight(elem.type)
        let render = render . highlight

        if g:buffet_show_index && s:IsBufferElement(elem)
            let render = render . " " . elem.index
        endif

        let icon = ""
        if g:buffet_use_devicons && s:IsBufferElement(elem)
            let icon = " " . WebDevIconsGetFileTypeSymbol(elem.value)
        elseif elem.type == "Tab"
            let icon = " " . g:buffet_tab_icon
        endif

        let render = render . icon

        if elem.type != "Tab"
            let render = render . " " . elem.value
        endif

        if s:IsBufferElement(elem)
            if elem.is_modified && g:buffet_modified_icon != ""
                let render = render . g:buffet_modified_icon
            endif
        endif

        let render = render . " "

        let separator =  g:buffet_has_separator[left.type][right.type]
        let separator_hi = s:GetTypeHighlight(left.type . right.type)
        let render = render . separator_hi . separator

        if elem.type == "Tab" && has("nvim")
            let render = render . "%T"
        elseif s:IsBufferElement(elem) && has("nvim")
            let render = render . "%T"
        endif
    endfor

    if !has("nvim")
        let render = render . "%T"
    endif

    let render = render . s:GetTypeHighlight("Buffer")

    return render
endfunction


" GetCapacityAndPadding:
" What is these numbers ?
" - 
" ===================== {{{
function! s:GetCapacityAndPadding()
    let gutter_len = 0
    if g:buffet_margin_left ==# 'gutter'
        let gutter_len = len(line('$'))+1
    endif

    let tabs_count = tabpagenr("$")
    let tabs_len   = (s:Len(g:buffet_tab_icon) + 1) * tabs_count

    " Same for both side
    let sep_len         = s:Len(g:buffet_separator_left)
    let trunc_icon_len  = s:Len(g:buffet_left_trunc_icon)
    " this's tricky, we calc trunced nums after this, so 2 for safe case
    " TODO: <pri:LOW> find a way to fix this issue
    let trunc_nums_len  = 2
    let trunc_len = (sep_len + trunc_icon_len + 1+trunc_nums_len + sep_len+1)*2

    "let left_trunc_len  = 1 + s:Len(g:buffet_left_trunc_icon) + 1 + 2 + 1 + sep_len
    "let right_trunc_len =  1 + 2 + 1 + s:Len(g:buffet_right_trunc_icon) + 1 + sep_len
    "let trunc_len       = left_trunc_len + right_trunc_len

    "let capacity       = &columns - tabs_len - trunc_len - 5
    let capacity = $columns - gutter_len - tabs_len - trunc_len - 5
    let buffer_padding = 1 + (g:buffet_use_devicons ? 1+1 : 0) + 1 + sep_len

    return [capacity, buffer_padding]
endfunction
" ===================== }}}


" GetVisibleRange: Return the start and end index of the visible range.
" ================ {{{
" @length_limit (Number)
" @buffer_padding (Number)
" => (List)-number:
"   $1|left_idx
"   $2|right_idx
" What Is Visible Range:?
" - The visible range is the start and end index of `s:buffer_ids`. What's in it
"   will be displayed and of course what's not in it will be trunced.
" ===
function! s:GetVisibleRange(length_limit, buffer_padding)
    let current_buffer_id = s:last_current_buffer_id

    if current_buffer_id == -1
        return [-1, -1]
    endif

    " Current buffer block:
    " calculate the capacity left after extracted for the current bufer
    let current_buffer_id_idx = index(s:buffer_ids, current_buffer_id)
    let current_buffer        = s:buffers[current_buffer_id]
    let capacity = a:length_limit - current_buffer.length - a:buffer_padding

    let [left_idx, capacity] = s:GetVisibleIndex(current_buffer_id_idx,
        \   capacity, a:buffer_padding, 'left')
    let [right_idx, capacity] = s:GetVisibleIndex(current_buffer_id_idx,
        \   capacity, a:buffer_padding, 'right')

    return [left_idx, right_idx]
endfunction

" GetVisibleIndex: Calculate how many buffers need to truncate of @side
" from @capacity, and return visible index of that @side.
" ---
" @curr_bufid_idx (Number): s:buffer_ids holds buffers position, so we need this
" @capacity (Number): capacity
" @padding (Number): padding
" @side (String): 'left' or 'right'
" ---
" => (List)-number:
"   $1|{idx}: the visible index
"   $2|{capacity}: the capacity left after calculated
" ===
function! s:GetVisibleIndex(curr_bufid_idx, capacity, padding, side)
    " Truncate buffers below and above of current buffer,
    " left is looped down and vice versa
    let start = (a:side==#'left' ? a:curr_bufid_idx-1 : a:curr_bufid_idx+1)
    let end   = (a:side==#'left' ? 0                  : len(s:buffers)-1)
    let step  = (a:side==#'left' ? -1                 : 1)

    " If start == end, we cannot run loop, so we need something to return
    let idx   = a:curr_bufid_idx
    let cap   = a:capacity

    for idx in range(start, end, step)
        let buffer = s:buffers[s:buffer_ids[idx]]

        if (buffer.length + a:padding) <= cap
            let cap = cap - buffer.length - a:padding
        else
            " The visual index, not the truncated index
            let idx = (a:side=='left' ? idx+1 : idx-1 )
            break
        endif
    endfor

    return [idx, cap]
endfunction
" ================ }}}


" GetAllElements:
" =============== {{{
" `GetTablineElements`
"
" TODO: This will stored 1 tab and its buffers, then repeat(loop), finally 
" is the end, you need to do something to clean this
" => tab_elems[]: elements in s:Render()
"   $1|tabs{}1
"   $2|buffers_elem{}s
"   ...
"   $*|tabs{}2
"   $*|buffers_elem{}s
"   ...
"   $$|end{} =
function! s:GetAllElements(left_idx, right_idx)
    let last_tab_id     = tabpagenr('$')
    let current_tab_id  = tabpagenr()
    let buffer_elems    = s:GetBufferElements(a:left_idx, a:right_idx)
    let end_elem        = {"type": "End", "value": ""}

    let tab_elems = []

    for tab_id in range(1, last_tab_id)
        " Tab(s)
        let elem = {}
        let elem.value = tab_id
        let elem.type = "Tab"
        call add(tab_elems, elem)

        " Buffer(s)
        if tab_id == current_tab_id
            let tab_elems = tab_elems + buffer_elems
        endif
    endfor

    " End
    call add(tab_elems, end_elem)

    return tab_elems
endfunction
" =============== }}


" GetBufferElements:
" ================== {{
" => buffer_elems[{}] (List)-dict:
"   $1|left_trunc_elem{}
"   $2|visual_buffers{}:
"       index: s:buffer_ids[] start with idx:0, so we need to +1 to display
"       value: name will be displayed
"       buffer_id:
"       type_prefix:
"   ...
"   $$|right_trunc_elem{}
" ===
function! s:GetBufferElements(left_idx, right_idx)
    "let [left_i, right_i] = s:GetVisibleRange(a:capacity, a:buffer_padding)
    let left_i = a:left_idx
    let right_i = a:right_idx
    " TODO: evaluate if calling this ^ twice will get better visuals

    if left_i < 0 || right_i < 0
        return []
    endif

    let buffer_elems = []

    let trunced_left = left_i
    if trunced_left
        let left_trunc_elem = {}
        let left_trunc_elem.type = "LeftTrunc"
        let left_trunc_elem.value = g:buffet_left_trunc_icon . " " . trunced_left
        call add(buffer_elems, left_trunc_elem)
    endif

    " Visible buffers
    for i in range(left_i, right_i)
        let buffer_id = s:buffer_ids[i]
        let buffer = s:buffers[buffer_id]

        if buffer_id == winbufnr(0)
            let type_prefix = "Current"
        elseif bufwinnr(buffer_id) > 0
            let type_prefix = "Active"
        else
            let type_prefix = ""
        endif

        let elem = {}
        let elem.index = i + 1
        let elem.value = buffer.name
        let elem.buffer_id = buffer_id
        let elem.is_modified = getbufvar(buffer_id, '&mod')

        if elem.is_modified
            let type_prefix = "Mod" . type_prefix
        endif

        let elem.type = type_prefix . "Buffer"

        call add(buffer_elems, elem)
    endfor

    let trunced_right = (len(s:buffers) - right_i - 1)
    if trunced_right > 0
        let right_trunc_elem = {}
        let right_trunc_elem.type = "RightTrunc"
        let right_trunc_elem.value = trunced_right . " " . g:buffet_right_trunc_icon
        call add(buffer_elems, right_trunc_elem)
    endif

    return buffer_elems
endfunction
" ================== }}}






function! s:IsBufferElement(element)
    if index(g:buffet_buffer_types, a:element.type) >= 0
        return 1
    endif
    return 0
endfunction


function! s:Len(string)
    let visible_singles = substitute(a:string, '[^\d0-\d127]', "-", "g")

    return len(visible_singles)
endfunction

function! s:GetTypeHighlight(type)
    return "%#" . g:buffet_prefix . a:type . "#"
endfunction



function! s:GetBuffer(buffer)
    if empty(a:buffer) && s:last_current_buffer_id >= 0
        let btarget = s:last_current_buffer_id
    elseif a:buffer =~ '^\d\+$'
        let btarget = bufnr(str2nr(a:buffer))
    else
        let btarget = bufnr(a:buffer)
    endif

    return btarget
endfunction

function! buffet#bswitch(index)
    let i = str2nr(a:index) - 1
    if i < 0 || i > len(s:buffer_ids) - 1
        echohl ErrorMsg
        echom "Invalid buffer index"
        echohl None
        return
    endif
    let buffer_id = s:buffer_ids[i]
    execute 'silent buffer ' . buffer_id
endfunction

" inspired and based on https://vim.fandom.com/wiki/Deleting_a_buffer_without_closing_the_window
function! buffet#bwipe(bang, buffer)
    let btarget = s:GetBuffer(a:buffer)

    let filters = get(g:, "buffet_bwipe_filters", [])
    if type(filters) == type([])
        for f in filters
            if function(f)(a:bang, btarget) > 0
                return
            endif
        endfor
    endif

    if btarget < 0
        echohl ErrorMsg
        call 'No matching buffer for ' . a:buffer
        echohl None

        return
    endif

    if empty(a:bang) && getbufvar(btarget, '&modified')
        echohl ErrorMsg
        echom 'No write since last change for buffer ' . btarget . " (add ! to override)"
        echohl None
        return
    endif

    " IDs of windows that view target buffer which we will delete.
    let wnums = filter(range(1, winnr('$')), 'winbufnr(v:val) == btarget')

    let wcurrent = winnr()
    for w in wnums
        " switch to window with ID 'w'
        execute 'silent ' . w . 'wincmd w'

        let prevbuf = bufnr('#')
        " if the previous buffer is another listed buffer, switch to it...
        if prevbuf > 0 && buflisted(prevbuf) && prevbuf != btarget
            buffer #
        " ...otherwise just go to the previous buffer in the list.
        else
            bprevious
        endif

        " if the 'bprevious' did not work, then just open a new buffer
        if btarget == bufnr("%")
            execute 'silent enew' . a:bang
        endif
    endfor

    " finally wipe the tarbet buffer
    execute 'silent bwipe' . a:bang . " " . btarget
    " switch back to original window
    execute 'silent ' . wcurrent . 'wincmd w'
endfunction

function! buffet#bonly(bang, buffer)
    let btarget = s:GetBuffer(a:buffer)

    for b in s:buffer_ids
        if b == btarget
            continue
        endif

        call buffet#bwipe(a:bang, b)
    endfor
endfunction




function! buffet#get_hi_attr(name, attr)
    let vim_mode = "cterm"
    let attr_suffix = ""
    if has("gui")
        let vim_mode = "gui"
        let attr_suffix = "#"
    endif

    let value = synIDattr(synIDtrans(hlID(a:name)), a:attr . attr_suffix, vim_mode)

    return value
endfunction

function! buffet#set_hi(name, fg, bg)
    let vim_mode = "cterm"
    if has("gui")
        let vim_mode = "gui"
    endif

    let spec = ""
    if a:fg != ""
        let fg_spec = vim_mode . "fg=" . a:fg
        let spec = fg_spec
    endif

    if a:bg != ""
        let bg_spec = vim_mode . "bg=" . a:bg

        if spec != ""
            let bg_spec = " " . bg_spec
        endif

        let spec = spec . bg_spec
    endif

    if spec != ""
        exec "silent hi! " . a:name . " " . spec
    endif
endfunction

function! buffet#link_hi(name, target)
    exec "silent hi! link " . a:name . " " . a:target
endfunction

function! buffet#set_colors()
    " TODO: try to match user's colorscheme
    " Issue: https://github.com/bagrat/vim-buffet/issues/5
    " if get(g:, "buffet_match_color_scheme", 1)

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

    if exists("*g:BuffetSetCustomColors")
        call g:BuffetSetCustomColors()
    endif

    for left in keys(g:buffet_has_separator)
        for right in keys(g:buffet_has_separator[left])
            let vim_mode = "cterm"
            if has("gui")
                let vim_mode = "gui"
            endif

            let left_hi = g:buffet_prefix . left
            let right_hi = g:buffet_prefix . right
            let left_bg = buffet#get_hi_attr(left_hi, 'bg')
            let right_bg = buffet#get_hi_attr(right_hi, 'bg')

            if left_bg == ""
                let left_bg = "NONE"
            endif

            if right_bg == ""
                let right_bg = "NONE"
            endif

            let sep_hi = g:buffet_prefix . left . right
            if left_bg != right_bg
                let g:buffet_has_separator[left][right] = g:buffet_noseparator

                call buffet#set_hi(sep_hi, left_bg, right_bg)
            else
                let g:buffet_has_separator[left][right] = g:buffet_separator

                call buffet#link_hi(sep_hi, left_hi)
            endif
        endfor
    endfor
endfunction
