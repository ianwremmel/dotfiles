" Enable Pathogen
execute pathogen#infect()

" Make Vim readable
set background=dark

" Enable Vim stuff (supposedly not necessary if this file exists)
set nocompatible

" Centralize backups, swapfiles and undo history
set backupdir=~/.vim/backups
set directory=~/.vim/swaps
if exists("&undodir")
	set undodir=~/.vim/undo
endif

" Enable line numbers
set number

" Enable syntax highlighting
syntax on

" Disable error bells
set noerrorbells

" Show the cursor position
set ruler

" Ignore case of searches
set ignorecase

" Make tabs appear shorter
set tabstop=2

" Use spaces instead of tabs
set expandtab

" Automatic commands
if has("autocmd")
	" Enable file type detection
	filetype on
	" Treat .json files as .js
	autocmd BufNewFile,BufRead *.json setfiletype json syntax=javascript
	" Indent automatically
	filetype plugin indent on
endif

" Disable arrow keys
"noremap <Up> <NOP>
"noremap <Down> <NOP>
"noremap <Left> <NOP>
"noremap <Right> <NOP>
map <up> <nop>
map <down> <nop>
map <left> <nop>
map <right> <nop>
imap <up> <nop>
imap <down> <nop>
imap <left> <nop>
imap <right> <nop>

let g:solarized_termcolors=256
let g:solarized_termtrans=1
colorscheme solarized

" 2 Tab Indent
set expandtab
set shiftwidth=2
set softtabstop=2
