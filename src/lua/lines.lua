m = require 'lpeg'
m.setmaxstack(1000)

local LINE = 1
local FILE = CEU.opts.pre_input or CEU.opts.ceu_input
local patt

CEU.i2l = {}

local line = m.Cmt('\n',
    function (s,i)
        for i=#CEU.i2l, i do
            CEU.i2l[i] = { FILE, LINE }
        end
        LINE = LINE + 1
        return true
    end )

local S = (m.S'\t\r ' + m.P'\\'*(1-m.P'\n')^0*'\n')
local SS = S^0

-- #line N "file" :: directive to set line/filename
local dir_lins = m.Cmt( m.P'#' *SS* m.P'line'^-1
                          *SS* m.C(m.R'09'^1)             -- line
                          *SS* ( m.P'"' * m.C((1-m.P'"')^0) * m.P'"'
                              + m.Cc(false) )            -- file
                          * (S + (m.P(1)-'\n'))^0 * '\n' -- \n
                 ,
    function (s,i, line, file)
        LINE = tonumber(line)
        FILE = file
        return true
    end )

patt = (line + dir_lins + 1)^0

local f = ASR(io.open(CEU.opts.ceu_input))
CEU.source = '\n#line 1 "'..FILE..'"'..'\n'..f:read'*a'..'\n'
f:close()
patt:match(CEU.source)
