CODES = {
    native = { [true]='', [false]='' }
}

local function LINE (me, line)
    me.code = me.code..'\n'
    if CEU.opts.ceu_line_directives then
        me.code = me.code..[[
#line ]]..me.ln[2]..' "'..me.ln[1]..[["
]]
    end
    me.code = me.code..line
end

local function CONC (me, sub)
    me.code = me.code..sub.code
end

local function CONC_ALL (me)
    for _, sub in ipairs(me) do
        if AST.is_node(sub) then
            CONC(me, sub)
        end
    end
end

local function CASE (me, lbl)
    LINE(me, 'case '..lbl.id..':;')
end

local function GOTO (me, lbl)
    LINE(me, [[
_ceu_lbl = ]]..lbl.id..[[;
goto _CEU_GOTO_;
]])
end

local function CLEAR (me)
    LINE(me, [[
ceu_stack_clear(_ceu_stk, &CEU_APP.trails[]]..me.trails[1]..[[],
                          &CEU_APP.trails[]]..me.trails[2]..[[]);
]])
end

local function HALT (me, t)
    if not t then
        LINE(me, 'return;')
        return
    end
    LINE(me, [[
_ceu_stk->trl->evt = ]]..t.evt..[[;
_ceu_stk->trl->lbl = ]]..t.lbl..[[;
return;
case ]]..t.lbl..[[:;
]])
end

F = {
    ROOT = CONC_ALL,
    Block = CONC_ALL,
    Stmts = CONC_ALL,
    Await_Until = CONC_ALL,

    Node__PRE = function (me)
        me.code = ''
    end,

    ROOT__PRE = function (me)
        CASE(me, me.lbl_in)
    end,

    Nat_Block = function (me)
        local pre, code = unpack(me)
        pre = pre and true

        -- unescape `##´ => `#´
        code = string.gsub(code, '^%s*##',  '#')
        code = string.gsub(code, '\n%s*##', '\n#')

        CODES.native[pre] = CODES.native[pre]..code
    end,

    Do = function (me)
        CONC_ALL(me)

        local _,_,set = unpack(me)
        if set then
            LINE(me, [[
ceu_out_assert_msg(0, "reached end of `do´");
]])
            CASE(me, me.lbl_out)
        end
    end,
    Escape = function (me)
        GOTO(me, me.do_.lbl_out)
    end,

    If = function (me)
        local c, t, f = unpack(me)
        LINE(me, [[
if (]]..V(c)..[[) {
    ]]..t.code..[[
} else {
    ]]..f.code..[[
}
]])
    end,

    Stmt_Call = function (me)
        local call = unpack(me)
        LINE(me, [[
]]..V(call)..[[;
]])
    end,

    ---------------------------------------------------------------------------

    Par_Or  = 'Par',
    Par_And = 'Par',
    Par = function (me)
        for i, sub in ipairs(me) do
            -- Par_And: close gates
            if me.tag == 'Par_And' then
                LINE(me, [[
]]..V(me,i)..[[ = 0;
]])
            end

            if i < #me then
                LINE(me, [[
CEU_GO_LBL_ABORT(_ceu_evt, _ceu_stk,
                 &CEU_APP.trails[]]..sub.trails[1]..[[],
                 ]]..me.lbls_in[i].id..[[);
]])
            else
                LINE(me, [[
_ceu_stk->trl = &CEU_APP.trails[]]..sub.trails[1]..[[];
]])
            end
        end

        -- inverse order to execute me[#me] directly
        for i=#me, 1, -1 do
            local sub = me[i]
            if i < #me then
                CASE(me, me.lbls_in[i])
            end
            CONC(me, sub)

            if me.tag == 'Par' then
                LINE(me, [[
return;
]])
            else
                -- Par_And: open gates
                if me.tag == 'Par_And' then
                LINE(me, [[
    ]]..V(me,i)..[[ = 1;
]])
                end
                GOTO(me, me.lbl_out)
            end
        end

        if me.lbl_out then
            CASE(me, me.lbl_out)
        end

        -- Par_And: test gates
        if me.tag == 'Par_And' then
            for i, sub in ipairs(me) do
                LINE(me, [[
if (!]]..V(me,i)..[[) {
    return;
}
]])
            end

        -- Par_Or: clear trails
        elseif me.tag == 'Par_Or' then
            CLEAR(me)
        end
    end,

    ---------------------------------------------------------------------------

    Set_Exp = function (me)
        local fr, to = unpack(me)

        if to.info.dcl.id == '_ret' then
            LINE(me, [[
{
    int __ceu_ret = ]]..V(fr)..[[;
    ceu_callback(CEU_CALLBACK_TERMINATING, __ceu_ret, NULL);
#ifdef CEU_OPT_GO_ALL
    ceu_callback_go_all(CEU_CALLBACK_TERMINATING, __ceu_ret, NULL);
#endif
}
]])
        else
            LINE(me, [[
]]..V(to)..' = '..V(fr)..[[;
]])
        end
    end,

    Set_Await_many = function (me)
        local Await_Until, Namelist = unpack(me)
        local ID_ext = AST.asr(Await_Until,'Await_Until', 1,'Await_Ext', 1,'ID_ext')
        CONC(me, Await_Until)
        for i, name in ipairs(Namelist) do
            local ps = '((tceu_input_'..ID_ext.dcl.id..'*)(_ceu_evt->params))'
            LINE(me, [[
]]..V(name)..' = '..ps..'->_'..i..[[;
]])
        end
    end,

    ---------------------------------------------------------------------------

    Await_Forever = function (me)
        HALT(me)
    end,

    Await_Ext = function (me)
        local ID_ext = unpack(me)
        HALT(me, {
            evt = ID_ext.dcl.id_,
            lbl = me.lbl_out.id,
        })
    end,

    Emit_Ext_emit = function (me)
        local ID_ext, Explist = unpack(me)
        local Typelist, inout = unpack(ID_ext.dcl)
assert(inout == 'input', 'TODO')

        local ps = 'NULL'
        if Explist then
            LINE(me, [[
{
    tceu_]]..inout..'_'..ID_ext.dcl.id..' __ceu_ps = { '..table.concat(V(Explist),',')..[[ };
]])
            ps = '&__ceu_ps'
        end

        LINE(me, [[
    ceu_go_ext(]]..ID_ext.dcl.id_..', '..ps..[[);
    if (!_ceu_stk->is_alive) {
        return;
    }
}
#ifdef CEU_OPT_GO_ALL
ceu_callback_go_all(CEU_CALLBACK_PENDING_ASYNC, 0, NULL);
#endif
]])
        HALT(me, {
            evt  = 'CEU_INPUT__ASYNC',
            lbl  = me.lbl_out.id,
        })
    end,

    Async = function (me)
        local _,blk = unpack(me)
        LINE(me, [[
ceu_callback(CEU_CALLBACK_PENDING_ASYNC, 0, NULL);
#ifdef CEU_OPT_GO_ALL
ceu_callback_go_all(CEU_CALLBACK_PENDING_ASYNC, 0, NULL);
#endif
]])
        HALT(me, {
            evt = 'CEU_INPUT__ASYNC',
            lbl = me.lbl_in.id,
        })
        CONC(me, blk)
    end,
}

-------------------------------------------------------------------------------

local function SUB (str, from, to)
    assert(to, from)
    local i,e = string.find(str, from, 1, true)
    if i then
        return SUB(string.sub(str,1,i-1) .. to .. string.sub(str,e+1),
                   from, to)
    else
        return str
    end
end

local H = ASR(io.open(CEU.opts.ceu_output_h,'w'))
local C = ASR(io.open(CEU.opts.ceu_output_c,'w'))

AST.visit(F)

local labels do
    labels = ''
    for _, lbl in ipairs(LABELS.list) do
        labels = labels..lbl.id..',\n'
    end
end

-- CEU.C
local c = PAK.files.ceu_c
local c = SUB(c, '=== NATIVE_PRE ===',       CODES.native[true])
local c = SUB(c, '=== DATA ===',             MEMS.data)
local c = SUB(c, '=== EXTS_TYPES ===',       MEMS.exts.types)
local c = SUB(c, '=== EXTS_ENUM_INPUT ===',  MEMS.exts.enum_input)
local c = SUB(c, '=== EXTS_ENUM_OUTPUT ===', MEMS.exts.enum_output)
local c = SUB(c, '=== NATIVE ===',           CODES.native[false])
local c = SUB(c, '=== TRAILS_N ===',         AST.root.trails_n)
local c = SUB(c, '=== TCEU_NTRL ===',        TYPES.n2uint(AST.root.trails_n))
local c = SUB(c, '=== TCEU_NLBL ===',        TYPES.n2uint(#LABELS.list))
local c = SUB(c, '=== LABELS ===',           labels)
local c = SUB(c, '=== CODE ===',             AST.root.code)
C:write('\n\n/* CEU_C */\n\n'..c)

H:close()
C:close()
