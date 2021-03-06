LOCS = {}
INFO = {}

function INFO.asr_tag (e, cnds, err_msg)
    ASR(e.info, e, err_msg..' : expected location')
    --assert(e.info.obj.tag ~= 'Val')
    local ok do
        for _, tag in ipairs(cnds) do
            if tag == e.info.tag then
                ok = true
                break
            end
        end
    end
    ASR(ok, e, err_msg..' : '..
                'unexpected context for '..AST.tag2id[e.info.tag]
                                         ..' "'..e.info.id..'"')
end

function INFO.copy (old)
    local new = {}
    for k,v in pairs(old) do
        new[k] = v
    end
    return new
end

function INFO.new (me, tag, id, tp, ...)
    if AST.is_node(tp) and (tp.tag=='Type' or tp.tag=='Typelist') then
        assert(not ...)
    else
        assert(type(tp) == 'string')
        tp = TYPES.new(me, tp, ...)
    end
    return {
        id  = id or 'unknown',
        tag = tag,
        tp  = tp,
        --dcl
    }
end

LOCS.F = {
-- IDs

    ID_nat = function (me)
        local id = unpack(me)
        me.info = {
            id  = id,
            tag = me.dcl.tag,
            tp  = me.dcl[2],
            dcl = me.dcl,
        }
    end,

    ID_int = function (me)
        local id = unpack(me)
        me.info = {
            id  = id,
            tag = me.dcl.tag,
            tp  = me.dcl[2],
            dcl = me.dcl,
        }
    end,

-- TYPECAST: as

    Exp_as = function (me)
        local op,e,Type = unpack(me)
        if not e.info then return end   -- see EXPS below

        -- ctx
        INFO.asr_tag(e, {'Alias','Val','Nat','Var','Pool'},
                     'invalid operand to `'..op..'´')

        -- tp
        ASR(not TYPES.check(e.info.tp,'?'), me,
            'invalid operand to `'..op..'´ : unexpected option type : got "'..
            TYPES.tostring(e.info.tp)..'"')

        local dcl = e.info.tp[1].dcl

        if dcl and dcl.tag=='Data' then
            if TYPES.check(Type,'int') then
                -- OK: "d as int"
                ASR(dcl.hier, me,
                    'invalid operand to `'..op..'´ : expected `data´ type in a hierarchy : got "'..TYPES.tostring(e.info.tp)..'"')
            else
                -- NO: not alias
                --  var Dx d = ...;
                --  (d as Ex)...
                local is_alias = unpack(dcl)
                ASR(is_alias, me,
                    'invalid operand to `'..op..'´ : unexpected plain `data´ : got "'..
                    TYPES.tostring(e.info.tp)..'"')

                -- NO:
                --  var Dx& d = ...;
                --  (d as Ex)...        // "Ex" is not a subtype of Dx
                -- YES:
                --  var Dx& d = ...;
                --  (d as Dx.Sub)...
                local cast = Type[1].dcl
                if cast and cast.tag=='Data' then
                    local ok = cast.hier and dcl.hier and
                                (DCLS.is_super(cast,dcl) or     -- to dyn/call super
                                 DCLS.is_super(dcl,cast))
                    ASR(ok, me,
                        'invalid operand to `'..op..'´ : unmatching `data´ abstractions')
                end
            end
        end

        -- info
        me.info = INFO.copy(e.info)
        if AST.is_node(Type) then
            me.info.tp = AST.copy(Type)
        else
            -- annotation (/plain, etc)
DBG'TODO: type annotation'
        end
    end,

-- OPTION: !

    ['Exp_!'] = function (me)
        local op,e = unpack(me)

        -- ctx
        INFO.asr_tag(e, {'Nat','Var','Evt'}, 'invalid operand to `'..op..'´')

        -- tp
        ASR((e.info.dcl[1]=='&?') or TYPES.check(e.info.tp,'?'), me,
            'invalid operand to `'..op..'´ : expected option type : got "'..
            TYPES.tostring(e.info.tp)..'"')

        -- info
        me.info = INFO.copy(e.info)
        if e.info.dcl[1] == '&?' then
            me.info.dcl = AST.copy(e.info.dcl,nil,true)
            me.info.dcl[1] = '&'
            me.info.dcl.orig = e.info.dcl.orig or e.info.dcl   -- TODO: HACK_3
        else
            me.info.tp = TYPES.pop(e.info.tp)
        end
    end,

-- INDEX

    ['Exp_idx'] = function (me)
        local _,vec,idx = unpack(me)

        -- ctx, tp

        local tp = AST.copy(vec.info.tp)
        tp[2] = nil
        if (vec.info.tag=='Var' or vec.info.tag=='Nat') and TYPES.is_nat(tp) then
            -- _V[0][0]
            -- var _char&&&& argv; argv[1][0]
            -- v[1]._plain[0]
            INFO.asr_tag(vec, {'Nat','Var'}, 'invalid vector')
        else
            INFO.asr_tag(vec, {'Vec'}, 'invalid vector')
        end

        -- info
        me.info = INFO.copy(vec.info)
        me.info.tag = 'Var'
        if vec.info.tag=='Var' and TYPES.check(vec.info.tp,'&&') then
            me.info.tp = TYPES.pop(vec.info.tp)
        end
    end,

-- PTR: *

    ['Exp_1*'] = function (me)
        local op,e = unpack(me)

        -- ctx
        INFO.asr_tag(e, {'Nat','Var','Pool'}, 'invalid operand to `'..op..'´')
--DBG('TODO: remove pool')

        -- tp
        local _,mod = unpack(e.info.tp)
        local is_ptr = TYPES.check(e.info.tp,'&&')
        local is_nat = TYPES.is_nat(e.info.tp)
        ASR(is_ptr or is_nat, me,
            'invalid operand to `'..op..'´ : expected pointer type : got "'..
            TYPES.tostring(e.info.tp)..'"')

        -- info
        me.info = INFO.copy(e.info)
        if is_ptr then
            me.info.tp = TYPES.pop(e.info.tp)
        end
    end,

-- MEMBER: .

    ['Exp_.'] = function (me)
        local _, e, member = unpack(me)

        if type(member) == 'number' then
            local abs = TYPES.abs_dcl(e.info.dcl[2], 'Data')
            ASR(abs, me, 'invalid constructor : TODO')
            local vars = AST.asr(abs,'Data', 3,'Block').dcls
            local _,_,id = unpack(vars[member])
            member = id
            me[3] = id
        end

        if e.tag == 'Outer' then
            LOCS.F.ID_int(me)
            me.info.id = 'outer.'..member
        else
            ASR(TYPES.ID_plain(e.info.tp), me,
                'invalid operand to `.´ : expected plain type : got "'..
                TYPES.tostring(e.info.tp)..'"')

assert(e.info.dcl)
            local alias = unpack(e.info.dcl)
            ASR(alias~='&?', me,
                'invalid operand to `.´ : unexpected option alias')

            local ID_abs = unpack(e.info.tp)
            if ID_abs and ID_abs.dcl.tag=='Data' then
                -- data.member
                local data = AST.asr(ID_abs.dcl,'Data')
                local Dcl = DCLS.asr(me,data,member,false,e.info.id)
                me.info = {
                    id  = e.info.id..'.'..member,
                    tag = Dcl.tag,
                    tp  = Dcl[2],
                    dcl = Dcl,
                    dcl_obj = e.info.dcl,
                }
            else
                me.info = INFO.copy(e.info)
                me.info.id = e.info.id..'.'..member
            end
        end
    end,

-- VECTOR LENGTH: $

    ['Exp_$'] = function (me)
        local op,vec = unpack(me)

        -- ctx
        INFO.asr_tag(vec, {'Vec'}, 'invalid operand to `'..op..'´')

        -- tp
        -- any

        -- info
        me.info = INFO.copy(vec.info)
        me.info.tp = TYPES.new(me, 'usize')
        me.info.tag = 'Var'
    end,
}

AST.visit(LOCS.F)
