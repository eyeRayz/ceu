STMTS = {}

STMTS.F = {

-- SETS

    Set_Exp = function (me)
        local fr, to = unpack(me)

        local err do
            if AST.get(me.__par,'Stmts', me.__i+1,'Escape') then
                err = 'invalid `escape´'
            else
                err = 'invalid assignment'
            end
        end

        if to.info.dcl.is_read_only then
            ASR(me.set_read_only, me,
                'invalid assignment : read-only variable "'..to.info.id..'"')
        end

        -- ctx
        INFO.asr_tag(to, {'Nat','Var','Pool'}, err)
        INFO.asr_tag(fr, {'Val','Nat','Var'}, err)
        ASR((not fr.info.dcl) or (fr.info.dcl[1]~='&?'), me,
            err..' : expected operator `!´')

        -- tp
        EXPS.check_tp(me, to.info.tp, fr.info.tp, err)

        if not TYPES.check(to.info.tp,'?') then
            ASR(not TYPES.check(fr.info.tp,'?'), me,
                'invalid assignment : expected operator `!´')
        end

        -- abs vs abs
        local to_abs = TYPES.abs_dcl(to.info.tp, 'Data')
        if to_abs then
            local is_alias = unpack(to.info)
            if not is_alias then
                local fr_abs = TYPES.abs_dcl(fr.info.tp, 'Data')
                local is_alias = unpack(fr.info)
                assert(not is_alias)

                EXPS.check_tp(me, to.info.tp, fr.info.tp, 'invalid assignment')
                ASR(to_abs.n_vars == fr_abs.n_vars, me,
                    'invalid assignment : `data´ copy : unmatching fields')

                --ASR(to_abs.weaker=='plain', me,
                    --'invalid assignment : `data´ copy : expected plain `data´')
            end
        end
    end,

    __set_vec = function (fr, to_info)
        AST.asr(fr, 'Vec_Cons')

        -- ctx
        for _, e in ipairs(fr) do
            if e.tag=='Vec_Tup' or e.tag=='STRING' or
               e.tag=='Exp_as'  or e.tag=='Lua' or
               AST.get(e,'Loc',1,'Exp_as')
            then
                -- ok
            else
                INFO.asr_tag(e, {'Vec'}, 'invalid constructor')
            end
        end

        -- tp
        for i, e in ipairs(fr) do
            if e.tag == 'Vec_Tup' then
                local ps = unpack(e)
                if ps then
                    AST.asr(ps,'List_Exp')
                    for j, p in ipairs(ps) do
                        EXPS.check_tp(fr, to_info.tp, p.info.tp,
                            'invalid constructor : item #'..i..' : '..
                            'invalid expression list : item #'..j)
                    end
                end
            elseif e.tag == 'STRING' then
                local tp = TYPES.new(e, 'byte')
                EXPS.check_tp(fr, to_info.tp, tp,
                    'invalid constructor : item #'..i)
            elseif e.tag == 'Lua' then
            elseif e.tag=='Exp_as' or AST.get(e,'Loc',1,'Exp_as') then
            else
                assert(e.info and e.info.tag == 'Vec')
                EXPS.check_tp(fr, to_info.tp, e.info.tp,
                    'invalid constructor : item #'..i)
            end
        end
    end,
    Set_Vec = function (me)
        local fr, to = unpack(me)
        INFO.asr_tag(to, {'Vec'}, 'invalid constructor')
        STMTS.F.__set_vec(fr, to.info)

        ASR(not TYPES.is_nat(TYPES.get(to.info.tp,1)), me,
            'invalid constructor : expected internal type : got "'..TYPES.tostring(to.info.tp)..'"')

        for i, e in ipairs(fr) do
            if e.tag == 'Loc' then
                -- OK: v1 = v1 ..
                -- NO: v1 = v2 ..
                -- NO: v1 = .. v1
                if i == 1 then
                    ASR(AST.is_equal(to,e), me,
                            'invalid constructor : item #'..i..' : '..
                            'expected destination as source')
                else
                    ASR(not AST.is_equal(to,e), me,
                            'invalid constructor : item #'..i..' : '..
                            'unexpected destination as source')
                end
            end
        end
    end,

    Set_Alias = function (me)
        local fr, to = unpack(me)

        -- ctx
        INFO.asr_tag(to, {'Var','Vec','Pool','Evt'}, 'invalid binding')
        INFO.asr_tag(fr, {'Alias'}, 'invalid binding')

        -- NO: var int x = &...
        -- NO: d.x = &...
        -- NO: x! = &...
        local Loc = AST.asr(to,'Loc')
        local ID_int = AST.get(Loc,'', 1,'ID_int')
        local op = unpack(Loc[1])
        ASR(ID_int, me, 'invalid binding : unexpected context for operator `'..op..'´')
        ASR(ID_int.dcl[1], me, 'invalid binding : expected declaration with `&´')

        if to.__dcls_is_escape then
            ASR(to.info.dcl[1] == '&?', to, 'invalid binding : expected `&?´ modifier')
        end

        -- tp

        EXPS.check_tp(me, to.info.tp, fr.info.tp, 'invalid binding', true)

        local is_call = false
        if fr[2].tag=='Nat_Call' or fr[2].tag=='Abs_Call' then
            is_call = true
            if fr[2].tag == 'Nat_Call' then
                assert(fr.info.dcl and fr.info.dcl.tag=='Nat')
                ASR(TYPES.is_nat(to.info.tp), me,
                    'invalid binding : expected `native´ type')
            else
                local ID_abs = AST.asr(fr,'', 2,'Abs_Call', 2,'Abs_Cons',
                                              1,'ID_abs')
                local tp = AST.asr(ID_abs.dcl,'Code', 4,'Block', 1,'Stmts', 3,'Code_Ret', 1,'', 2,'Type')
                EXPS.check_tp(me, to.info.tp, tp, 'invalid binding', true)
            end
        else
            EXPS.check_tag(me, to.info.tag, fr.info.dcl.tag, 'invalid binding')

            -- NO: ... = &_V        // native ID
            ASR(fr.info.dcl.tag~='Nat', me,
                'invalid binding : unexpected native identifier')

            if fr.info.dcl[1] then
                ASR(to.info.dcl[1] == fr.info.dcl[1], me,
                    'invalid binding : unmatching alias `&´ declaration')
            end
        end

        -- option type
        if TYPES.check(to.info.tp,'?') then
            --if TYPES.check(fr.info.tp,'_') and
               --TYPES.is_nat(TYPES.pop(to.info.tp,'?'))
            --then
            if is_call and TYPES.is_nat(TYPES.pop(to.info.tp,'?')) then
                -- OK:
                --  var& _TP? = &_f();
                --  var& _TP? = &Ff();
            else
                -- NO:
                -- var  int  x;
                -- var& int? i = &x;
                ASR(TYPES.check(fr.info.tp,'?'), me,
                    'invalid binding : types mismatch : "'..TYPES.tostring(to.info.tp)..
                                                  '" <= "'..TYPES.tostring(fr.info.tp)..'"')
            end
        end

        -- dim
        if to.info.tag == 'Vec' then
            local _,_,_,to_dim = unpack(to.info.dcl)
            local _,_,_,fr_dim = unpack(fr.info.dcl)
            ASR(EXPS.check_dim(to_dim,fr_dim), me,
                'invalid binding : dimension mismatch')
        end
    end,

    Set_Lua = function (me)
        local _,to = unpack(me)
        INFO.asr_tag(to, {'Nat','Var'}, 'invalid Lua assignment')
    end,

    Set_Async_Thread = function (me)
        local _,to = unpack(me)

        -- ctx
        INFO.asr_tag(to, {'Nat','Var'}, 'invalid `async/thread´ assignment')

        -- tp
        ASR(TYPES.check(to.info.tp,'bool'), me,
            'invalid `async/thread´ assignment : expected `bool´ destination')
    end,

-- ABS

    Set_Abs_Val = function (me)
        local fr, to = unpack(me)
        local Abs_Cons = AST.asr(fr,'Abs_Val', 2,'Abs_Cons')
        local ID_abs = unpack(Abs_Cons)

        -- ctx
        INFO.asr_tag(to, {'Var'}, 'invalid constructor')
        ASR(ID_abs.dcl.tag == 'Data', me,
            'invalid constructor : expected `data´ abstraction : got `code´ "'..
            ID_abs.dcl.id..'" ('..ID_abs.dcl.ln[1]..':'..ID_abs.dcl.ln[2]..')')

        -- tp
        EXPS.check_tp(me, to.info.tp, Abs_Cons.info.tp, 'invalid constructor')

        -- NO: instantiate "nothing" data
        --  data Dd as nothing;
        --  var Dd d = val Dd();
        local _, num = unpack(ID_abs.dcl)
        ASR(num ~= 'nothing', me,
            'invalid constructor : cannot instantiate `data´ "'..ID_abs.dcl.id..'"')

        -- exact match on constructor
        local to_str = TYPES.tostring(to.info.tp)
        local fr_str = TYPES.tostring(Abs_Cons.info.tp)
        if to_str ~= fr_str then
            local _,_,blk = unpack(ID_abs.dcl)
            -- or source has no extra fields
            local super = to.info.tp[1]
            ASR(#AST.asr(ID_abs.dcl,'Data',3,'Block').dcls ==
                #AST.asr(super.dcl ,'Data',3,'Block').dcls, me,
                'invalid constructor : types mismatch : "'..to_str..'" <= "'..fr_str..'"')
        end
    end,
    Set_Abs_New = function (me)
        local _, to = unpack(me)

        -- ctx
        INFO.asr_tag(to, {'Var','Pool'}, 'invalid constructor')
    end,
    Set_Abs_Spawn_Pool = function (me)
        local _, to = unpack(me)

        -- ctx
        INFO.asr_tag(to, {'Var'}, 'invalid constructor')

        -- tp
        ASR(TYPES.check(to.info.tp,'bool'), me,
            'invalid constructor : expected `bool´ destination')
    end,

-- EMIT

    Set_Emit_Ext_emit = function (me)
        local ID_ext = AST.asr(me,'', 1,'Emit_Ext_emit', 1,'ID_ext')
        local io,_ = unpack(ID_ext.dcl)
        ASR(io=='output', me,
            'invalid assignment : `input´')
    end,

    Set_Await_one = function (me)
        local fr, to = unpack(me)
        assert(fr.tag=='Await_Wclock' or fr.tag=='Abs_Await' or fr.tag=='Await_Int')

        if fr.tag == 'Abs_Await' then
            ASR(fr.tp, me,
                'invalid assignment : `code´ executes forever')
        end

        EXPS.check_tp(me, to.info.tp, fr.tp or fr.info.tp, 'invalid assignment')

        if me.__adjs_is_watching then
            -- var int? us = watching 1s do ... end
            ASR(TYPES.check(to.info.tp,'?'), me,
                'invalid `watching´ assignment : expected option type `?´ : got "'..TYPES.tostring(to.info.tp)..'"')
        end
    end,

    Set_Await_many = function (me)
        local fr, to = unpack(me)

        -- ctx
        for _, Loc in ipairs(to) do
            if Loc.tag ~= 'ID_any' then
                INFO.asr_tag(Loc, {'Nat','Var'}, 'invalid assignment')
            end
        end

        -- tp
        EXPS.check_tp(me, to.tp, fr.tp, 'invalid assignment')

        if me.__adjs_is_watching then
            for _, e in ipairs(to) do
                -- var int? us = watching 1s do ... end
                ASR(TYPES.check(e.info.tp,'?'), me,
                    'invalid `watching´ assignment : expected option type `?´ : got "'..TYPES.tostring(e.info.tp)..'"')
            end
        end
    end,

-- AWAITS

    __await_ext_err = function (ID_ext, inout_expected)
        if ID_ext.tag ~= 'ID_ext' then
            return false, 'expected external identifier'
        end

        local inout_have = unpack(ID_ext.dcl)

        if inout_have == inout_expected then
            return true
        else
            return false, 'expected `'..inout_expected..'´ external identifier'
        end
    end,

    Await_Ext = function (me)
        local ID_ext = unpack(me)

        -- ctx
        local ok, msg = STMTS.F.__await_ext_err(ID_ext, 'input')
        ASR(ok, me, msg and 'invalid `await´ : '..msg)

        me.tp = ID_ext.dcl[2]
    end,

    Await_Pause = function (me)
        me.tp = AST.node('Typelist', me.ln, TYPES.new(me, 'bool'))
    end,

    Await_Wclock = function (me)
        local e = unpack(me)
        if e.tag == 'WCLOCKE' then
            local n = unpack(e)
            ASR(TYPES.is_int(n.info.tp), me, 'invalid expression : expected integer type')
        end
        me.tp = TYPES.new(me, 'int')
    end,

    __check_watching_list = function (me, pars, list, must_be_opt)
        local tag = (me.tag=='Abs_Await' and 'Watching') or me.tag
        ASR(pars and #pars==#list, me,
            'invalid `'..AST.tag2id[tag]..'´ : expected '..#pars..' argument(s)')
        for i, par in ipairs(pars) do
            local par_alias,par_tp = unpack(par)
            assert(par_alias)
            local arg = list[i]
            if arg.tag ~= 'ID_any' then
                local arg_alias,arg_tp = unpack(arg.dcl)
                local err = 'invalid binding : argument #'..i
                ASR(arg_alias, me,
                    err..' : expected alias `&´ declaration')
                ASR(arg_alias == par_alias, me,
                    err..' : unmatching alias `&´ declaration')
                EXPS.check_tag(me, par.tag, arg.info.dcl.tag, err)
                EXPS.check_tp(me, par_tp, arg_tp, err)

                if must_be_opt then
                    ASR(arg_alias=='&?', me,
                        err..' : terminating `code´ : expected alias `&?´ declaration')
                end
            end
        end
    end,

    Abs_Spawn_Pool = function (me)
        local mods_call,Abs_Cons,list = unpack(me)
        local ID_abs = AST.asr(Abs_Cons,'Abs_Cons', 1,'ID_abs')
        me.__code = AST.asr(ID_abs.dcl,'Code')

        local _,mods_dcl = unpack(me.__code)
        ASR(mods_dcl.await, me,
            'invalid `'..AST.tag2id[me.tag]..'´ : expected `code/await´ declaration '..
                '('..me.__code.ln[1]..':'..me.__code.ln[2]..')')

        if mods_dcl.dynamic then
            ASR(mods_call.dynamic or mods_call.static, me,
                'invalid `'..AST.tag2id[me.tag]..'´ : expected `/dynamic´ or `/static´ modifier')
        else
            local mod = (mods_call.dynamic or mods_call.static)
            ASR(not mod, me, mod and
                'invalid `'..AST.tag2id[me.tag]..'´ : unexpected `/'..mod..'´ modifier')
        end

        if list then
            local must_be_opt = (me.tag~='Abs_Await' or me.__adjs_is_spawn) and
                                 AST.get(me.__code,'', 4,'Block',
                                                       1,'Stmts', 3,'Code_Ret', 1,'', 2,'Type')

            local pars = AST.asr(me.__code,'', 4,'Block', 1,'Stmts', 2,'Code_Pars')
            STMTS.F.__check_watching_list(me, pars, list, must_be_opt)
        end
    end,

    Abs_Await = function (me)
        STMTS.F.Abs_Spawn_Pool(me)

        ASR(AST.par(me,'Code') ~= me.__code, me,
            'invalid `'..AST.tag2id[me.tag]..'´ : unexpected recursive invocation')

        local ret = AST.get(me.__code,'', 4,'Block',
                                          1,'Stmts', 3,'Code_Ret', 1,'', 2,'Type')
        me.tp = ret and AST.copy(ret)

        local watch = AST.par(me, 'Watching')
        local me1 = AST.get(watch,'', 1,'Par_Or', 1,'Block', 1,'Stmts', 1,'Abs_Await')
        if me1 == me then
            ASR(ret, watch, 'invalid `watching´ : `code´ executes forever')
        end
     end,

    Await_Int = function (me, tag)
        local e = unpack(me)
        local alias, _ = unpack(e.info.dcl)

        -- ctx
        INFO.asr_tag(e, {'Var','Evt','Pool'}, 'invalid `await´')
        if e.info.tag == 'Var' then
            ASR(e.info.dcl[1] == '&?', me,
                'invalid `await´ : expected `var´ with `&?´ modifier')
        end

        -- tp
        if alias == '&?' then
            me.tp = TYPES.new(e, 'void')
        else
            me.tp = e.info.tp
        end
    end,

-- STATEMENTS

    Await_Until = function (me)
        local _, cond = unpack(me)
        if cond then
            ASR(TYPES.check(cond.info.tp,'bool'), me,
                'invalid expression : `until´ condition must be of boolean type')
        end
    end,

    Pause_If = function (me)
        local e = unpack(me)

        -- ctx
        local ok, msg = STMTS.F.__await_ext_err(e, 'input')
        if not ok then
            INFO.asr_tag(e, {'Evt'}, 'invalid `pause/if´')
        end

        -- tp
        local Typelist = AST.asr((e.dcl and e.dcl[2]) or e.info.tp,'Typelist')
        ASR(#Typelist==1 and TYPES.check(Typelist[1],'bool'), me,
            'invalid `pause/if´ : expected event of type `bool´')
    end,

    Do = function (me)
        local _,_,e = unpack(me)
        if e then
            INFO.asr_tag(e, {'Nat','Var'}, 'invalid assignment')
        end
    end,

    If = function (me)
        local cnd = unpack(me)
        ASR(TYPES.check(cnd.info.tp,'bool'), me,
            'invalid `if´ condition : expected boolean type')
    end,

    Loop_Num = function (me)
        local _, i, range = unpack(me)
        local fr,_,to,step = unpack(range)
        local i_tp, fr_tp, to_tp, s_tp = i.info.tp,
                                         fr.info.tp,
                                         (to.info and to.info.tp or step.info.tp),
                                         step.info.tp
        ASR(TYPES.is_num(i_tp), me, 'invalid `loop´ : expected numeric variable')
        ASR(TYPES.contains(i_tp,fr_tp), me,
            'invalid control variable : types mismatch : "'..TYPES.tostring(i_tp)..'" <= "'..TYPES.tostring(fr_tp)..'"')
        ASR(TYPES.contains(i_tp,to_tp), me,
            'invalid control variable : types mismatch : "'..TYPES.tostring(i_tp)..'" <= "'..TYPES.tostring(to_tp)..'"')
        ASR(TYPES.contains(i_tp,s_tp), me,
            'invalid control variable : types mismatch : "'..TYPES.tostring(i_tp)..'" <= "'..TYPES.tostring(s_tp)..'"')
    end,

    Loop_Pool = function (me)
        local _,list,pool = unpack(me)

        -- ctx
        INFO.asr_tag(pool, {'Pool'}, 'invalid `pool´ iterator')

        if list then
            local Code = AST.asr(pool.info.tp[1].dcl, 'Code')
            local pars = AST.asr(Code,'', 4,'Block', 1,'Stmts', 2,'Code_Pars')
            STMTS.F.__check_watching_list(me, pars, list)
        end
    end,

-- CALL, EMIT

    Emit_Evt = function (me)
        local e, ps = unpack(me)

        -- ctx
        INFO.asr_tag(e, {'Evt'}, 'invalid `emit´')

        -- tp
        EXPS.check_tp(me, e.info.tp, ps.tp, 'invalid `emit´')

        ASR(e.info.dcl[1] ~= '&?', me,
            'invalid `emit´ : unexpected `event´ with `&?´ modifier')
    end,

    Emit_Ext_emit = function (me)
        local ID_ext, ps = unpack(me)

        -- ctx
        local have = unpack(ID_ext.dcl)
        local expects do
            if ID_ext.dcl.tag ~= 'Ext' then
                expects = 'error'
            elseif AST.par(me,'Async') or AST.par(me,'Async_Isr') then
                expects = 'input'
            else
                expects = 'output'
            end
        end

        ASR(have==expects, me,
            'invalid `emit´ : '..
            'unexpected context for '..AST.tag2id[ID_ext.dcl.tag]..' `'..
            have..'´ "'..ID_ext.dcl.id..'"')

        -- tp
        EXPS.check_tp(me, ID_ext.dcl[2], ps.tp, 'invalid `emit´')
    end,

    Emit_Ext_call = function (me)
        local ID_ext, ps = unpack(me)

        -- tp
        local _,_,_,ins = unpack(ID_ext.dcl)
        local Typelist = AST.node('Typelist', me)
        for i, item in ipairs(ins) do
            local Type = AST.asr(item,'', 4,'Type')
            Typelist[i] = Type
        end
        EXPS.check_tp(me, Typelist, ps.tp, 'invalid call')
    end,

    Nat_Call = function (me)
        local _, e, ps = unpack(me)

        -- tp
        for _,p in ipairs(ps) do
            -- tp
            local is_opt = (p.info.dcl and p.info.dcl[1]=='&?')
            ASR(not (is_opt or TYPES.check(p.info.tp,'?')), me,
                'invalid call : unexpected context for operator `?´')

            if p.info.tag ~= 'Nat' then
                local is_alias = unpack(p.info)
                ASR(not is_alias, me,
                    'invalid call : unexpected context for operator `&´')
            end
        end
    end,

-- VARLIST, EXPLIST

    List_Exp = function (me)
        local Typelist = AST.node('Typelist', me.ln)
        for i, e in ipairs(me) do
            -- ctx
-- TODO: call/emit, argument
            INFO.asr_tag(e, {'Val','Nat','Var'},
                'invalid expression list : item #'..i)

            -- info
            Typelist[i] = AST.copy(e.info.tp)
        end
        me.tp = Typelist
    end,

    List_Loc = function (me)
        -- ctx
        for _, var in ipairs(me) do
            if var.tag ~= 'ID_any' then
                INFO.asr_tag(var, {'Nat','Var'}, 'invalid variable')
            end
        end

        -- info
        local Typelist = AST.node('Typelist', me.ln)
        for i, var in ipairs(me) do
            if var.tag == 'ID_any' then
                Typelist[i] = true
            else
                Typelist[i] = AST.copy(var.info.tp)
            end
        end
        me.tp = Typelist
    end,

    List_Var = function (me)
        -- ctx
        for _, var in ipairs(me) do
            if var.tag ~= 'ID_any' then
                INFO.asr_tag(var, {'Var','Vec','Evt'}, 'invalid variable')
            end
        end

        -- info
        local Typelist = AST.node('Typelist', me.ln)
        for i, var in ipairs(me) do
            if var.tag ~= 'ID_any' then
                Typelist[i] = AST.copy(var.info.tp)
            end
        end
        me.tp = Typelist
    end,
}

AST.visit(STMTS.F)
