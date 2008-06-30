" jptemplate.vim:
"
" A simple yet powerful interactive templating system for VIM.
"
" Version 1.3 (released 2008-07-01).
"
" Copyright (c) 2008 Jannis Pohlmann <jannis@xfce.org>.
"
" This program is free software; you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation; either version 2 of the License, or (at
" your option) any later version.
"
" This program is distributed in the hope that it will be useful, but
" WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
" General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program; if not, write to the Free Software
" Foundation, Inc., 59 Temple Place, Suite 330, Boston,
" MA  02111-1307  USA


" Reserved variable names
let s:reservedVariables = ['date']


function! jp:Initialize ()

  " List for default configuration
  let defaults = []

  " Default configuration values
  call add (defaults, ['g:jpTemplateDir', $HOME . '/.vim/jptemplate'])
  call add (defaults, ['g:jpTemplateKey', '<C-Tab>'])
  call add (defaults, ['g:jpTemplateDateFormat', '%Y-%m-%d'])
  call add (defaults, ['g:jpTemplateDefaults', {}])
  call add (defaults, ['g:jpTemplateVerbose', 0])

  " Set default configuration for non-existent variables
  for var in filter (defaults, '!exists (v:val[0])')
    exec 'let ' . var[0] . ' = ' . string (var[1])
  endfor

endfunction


function! jp:GetTemplateInfo ()

  " Prepare info dictionary
  let info = {}

  " Get part of the line before the cursor
  let part = getline  ('.')[0 : getpos ('.')[2]-1]

  " Get start and end position of the template name
  let info['start'] = match    (part, '\(\w*\)$')
  let info['end']   = matchend (part, '\(\w*\)$')

  " Get template name
  let info['name']  = part[info['start'] : info['end']]

  " Throw exception if no template name could be found
  if info['name'] == ''
    throw 'No template name found at cursor'
  endif

  " Determine indentation
  let info['indent'] = matchstr (part, '^\s\+')

  " Return template name information
  return info

endfunction


function! jp:ReadTemplate (name, filename)

  " Try to read the template file and throw exception if that fails
  try
    return readfile (a:filename)
  catch
    throw 'Template "' . a:name . '" could not be found.'
  endtry

endfunction


function! jp:SetCursorPosition (lines)

  " Flag to be set to 1 if the template contains ${cursor}
  let cursorFound = 0

  for cnt in range (0, a:lines)
    " Search for ${cursor} in the current line
    let s:str  = getline  (line ('.') + cnt)
    let start  = match    (s:str, '${cursor}')
    let end    = matchend (s:str, '${cursor}')
    let before = strpart  (s:str, 0, start)
    let after  = strpart  (s:str, end)

    if start >= 0
      " Remove ${cursor} and move the cursor to the desired position
      call setline (line ('.') + cnt, before . after)
      call cursor (line ('.') + cnt, start+1)

      " Set cursor found flag
      let cursorFound = 1

      " We're done
      break
    endif
  endfor

  " Set to 1 if ${cursor} appears somewhere in the middle of a template line
  let editInCurrentLine = 1

  if cursorFound == 0
    " Move cursor to the end of the template
    call cursor (line ('.') + cnt, '.')

    " Start editing in the next line
    let editInCurrentLine = 0
  else
    " If ${cursor} appears at the end of the line, start editing in the next line
    if match (s:str, '${cursor}$') != -1
      let editInCurrentLine = 0
    endif
  endif

  " Return information about where to start editing
  return editInCurrentLine

endfunction


function! jp:ParseExpression (expr)

  " Determine position of the separator between name and value
  let valuepos = match (a:expr, ':')

  " Extract name and value strings
  let name  = valuepos >= 0 ? strpart (a:expr, 0, valuepos) : a:expr
  let value = valuepos >= 0 ? strpart (a:expr, valuepos + 1) : ''

  " Return list with both strings
  return [name, value]

endfunction


function! jp:EvaluateReservedVariable (name, value, variables)

  let result = ''

  if a:name == 'date'
    let result = strftime (empty (a:value) ? g:jpTemplateDateFormat : a:value)
  endif

  return result

endfunction


function! jp:ProcessTemplate (info, template)

  let matchpos    = 0
  let expressions = []
  let variables   = {}
  let reserved    = {}

  " Make a string out of the template lines
  let s:str = join (a:template, ' ')

  " Detect all variable names of the template
  while 1
    " Find next variable start and end position
    let start = match    (s:str, '${[^${}]\+}', matchpos)
    let end   = matchend (s:str, '${[^${}]\+}', matchpos)

    if start < 0
      " Stop search if there is no variable left
      break
    else
      " Extract variable expression (remove '${' and '}')
      let expr = s:str[start+2 : end-2]

      " Extract variable name and default value */
      let [name, value] = jp:ParseExpression (expr)

      if name == 'cursor'
        " Skip the ${cursor} variable
      elseif count (s:reservedVariables, name) > 0
        let reserved[expr] = ''
      else
        " Only insert variables on their first appearance
        if !has_key (variables, name)
          " Add expression to the expression list
          call add (expressions, expr)

          " Set variable value to ''
          let variables[name] = ''
        endif

        if empty (value)
          " Use global default if the variable value is empty
          if empty (variables[name]) && has_key (g:jpTemplateDefaults, name)
            let variables[name] = g:jpTemplateDefaults[name]
          endif
        else
          " Use local default (first occurence in the template only) 
          if empty (variables[name]) || g:jpTemplateDefaults[name] == variables[name]
            let variables[name] = value
          endif
        endif
      endif

      " Start next search at the end position of this expression
      let matchpos = end
    endif
  endwhile

  " Ask the user to enter values for all variables
  for expr in expressions
    let [name, value] = jp:ParseExpression (expr)
    let variables[name] = input (name . ': ', variables[name])
  endfor

  " Evaluate reserved variables
  for expr in keys (reserved)
    let [name, value] = jp:ParseExpression (expr)
    let replacement = jp:EvaluateReservedVariable (name, value, variables)
    let reserved[expr] = replacement
  endfor

  " Expand all variables (custom and reserved)
  for index in range (len (a:template))
    for expr in expressions
      let [name, value] = jp:ParseExpression (expr)
      let expr = '${' . name . '\(:[^{}]\+\)\?}'
      let a:template[index] = substitute (a:template[index], expr, variables[name], 'g')
    endfor

    for [expr, value] in items (reserved)
      let expr = '${' . expr . '}'
      let a:template[index] = substitute (a:template[index], expr, value, 'g')
    endfor
  endfor

  " Backup content before and after the template name
  let before = strpart (getline ('.'), 0, a:info['start'])
  let after  = strpart (getline ('.'), a:info['end'])

  " Insert template into the code line by line
  for cnt in range (0, len (a:template)-1)
    if cnt == 0
      call setline (line ('.'), before . a:template[cnt])
    else
      call append (line ('.') + cnt - 1, a:info['indent'] . a:template[cnt])
    endif
    if cnt == len (a:template)-1
      call setline (line ('.') + cnt, getline (line ('.') + cnt) . after)

      " Move cursor to the end of the inserted template. ${cursor} may
      " overwrite this
      call cursor(line ('.'), len (getline (line ('.') + cnt)))
    endif
  endfor

  " Set the cursor position
  let editInCurrentLine = jp:SetCursorPosition (cnt)

  " Return to insert mode
  if editInCurrentLine
    startinsert
  else
    startinsert!
  endif

endfunction


function! jp:InsertTemplate ()

  " Determine the filetype subdirectory
  let ftDir = &ft == '' ? 'general' : &ft

  try
    " Detect bounds of the template name as well as the name itself
    let info = jp:GetTemplateInfo ()

    " Generate the full template filename
    let templateFile = g:jpTemplateDir .'/'. ftDir . '/' . info['name']

    " Load the template file
    let template = jp:ReadTemplate (info['name'], templateFile)

    " Do the hard work: Process the template
    call jp:ProcessTemplate (info, template)
  catch
    " Inform the user about errors
    echo g:jpTemplateVerbose ? v:exception . " (in " . v:throwpoint . ")" : v:exception
  endtry

endfunction


" Initialize jptemplate configuration
call jp:Initialize ()

" Map keyboard shortcut to the template system
exec 'imap ' . g:jpTemplateKey . ' <Esc>:call jp:InsertTemplate()<CR>'
