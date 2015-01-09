local t2n = {
     us = 10^0,
     ms = 10^3,
      s = 10^6,
    min = 60*10^6,
      h = 60*60*10^6,
}

local _ceu2c = { ['or']='||', ['and']='&&', ['not']='!' }
local function ceu2c (op)
    return _ceu2c[op] or op
end

function V (me)
    ASR(me.val, me, 'invalid expression')

    local ref = me.tp and me.tp.ref and me.tp.id
    if me.byRef and
        (not (ENV.clss[me.tp.id] or ref and ENV.clss[ref]))
    then
                    -- already by ref
        local ret = '&'..me.val
        return string.gsub(ret, '%&([^)])%*', '%1')
                -- &((*(...))) => (((...)))
    else
        return me.val
    end
end

function CUR (me, id)
    if id then
        return '(('..TP.toc(CLS().tp)..'*)_STK_ORG)->'..id
    else
        return '(('..TP.toc(CLS().tp)..'*)_STK_ORG)'
    end
end

F =
{
    Block_pre = function (me)
        local cls = CLS()
        for _, var in ipairs(me.vars) do
            if var.pre == 'var' then
                if var.isTmp then
                    var.val = '__ceu_'..var.id..'_'..var.n
                else
                    var.val = CUR(me, var.id_)
                end
                if var.tp.arr then
                    -- normalize all arrays acesses to pointers to arr[0]
                    -- (because of interface accesses that must be done through a pointer)
                    var.val = '(&'..var.val..'[0])'
                elseif var.cls then
                    -- normalize all org acesses to pointers to it
                    -- (because of interface accesses that must be done through a pointer)
                    var.val = '(&'..var.val..')'
                else
                    if var.tp.ref then
                        if ENV.clss[var.tp.id] then
                            -- orgs vars byRef, do nothing
                            -- (normalized to pointer)
                        else
                            -- normal vars byRef
                            var.val = '(*('..var.val..'))'
                        end
                    end
                end
            elseif var.pre == 'pool' then
                -- normalize all pool acesses to pointers to it
                -- (because of interface accesses that must be done through a pointer)
                var.val_dcl = '&'..CUR(me, var.id_)
                var.val = '(&'..CUR(me, var.id_)..')'
            elseif var.pre == 'function' then
                var.val = 'CEU_'..cls.id..'_'..var.id
            elseif var.pre == 'isr' then
                var.val = 'CEU_'..cls.id..'_'..var.id
            elseif var.pre == 'event' then
                var.val = nil
            elseif var.pre == 'output' then
                var.val = nil
            elseif var.pre == 'input' then
                var.val = nil
            else
                error 'not implemented'
            end
            if var.trl_orgs then
                -- ORG_STATS (shared for sequential), ORG_POOL (unique for each)
                var.trl_orgs.val = CUR(me, '__lnks_'..me.n..'_'..var.trl_orgs[1])
            end
        end
        if me.fins then
            for i, fin in ipairs(me.fins) do
                fin.val = CUR(me, '__fin_'..me.n..'_'..i)
            end
        end
    end,

    ParAnd = function (me)
        me.val = CUR(me, '__and_'..me.n)
    end,

    Global = function (me)
        me.val = '(_ceu_app->data)'
    end,

    Outer = function (me)
            me.val = '_STK_ORG'
            --me.val = '(*(('..TP.toc(me.tp)..'*)'..me.val..'))'
            me.val = '(('..TP.toc(me.tp)..'*)'..me.val..')'
    end,

    This = function (me)
        if AST.iter'Dcl_constr'() then
            me.val = '__ceu_org'    -- set when calling constr
            --me.val = '(*(('..TP.toc(me.tp)..'*)'..me.val..'))'
            me.val = '(('..TP.toc(me.tp)..'*)'..me.val..')'
        else
            me.val = '_STK_ORG'
            --me.val = '(*(('..TP.toc(me.tp)..'*)'..me.val..'))'
            me.val = '(('..TP.toc(me.tp)..'*)'..me.val..')'
        end
    end,

    Var = function (me)
        me.val = me.var.val
    end,

    SetExp = function (me)
        local _, fr, to = unpack(me)
        V(fr)     -- error on reads of internal events
    end,

    -- SetExp is inside and requires .val
    Spawn_pre = function (me)
        local id,_,_ = unpack(me)
        me.val = '((CEU_'..id..'*)__ceu_new)'
                                        -- defined by _Spawn (code.lua)
    end,

    IterIni = function (me)
        local fr_exp = unpack(me)
        ASR(fr_exp.lst.var, me, 'not a pool')
        local var = fr_exp.lst.var
        assert(var.trl_orgs)
        local idx = fr_exp.ifc_idx or var.trl_orgs[1]
                    -- converted to interface access or original
        local org = fr_exp.org and V(fr_exp.org) or '_STK_ORG'
        org = '((tceu_org*)'..org..')'
        me.val = [[
( (]]..org..[[->trls[ ]]..idx..[[ ].lnks[0].nxt->n == 0) ?
    NULL :    /* marks end of linked list */
    ]]..org..[[->trls[ ]]..idx..[[ ].lnks[0].nxt )
]]
    end,
    IterNxt = function (me)
        local fr_var = unpack(me)
        me.val = '(('..V(fr_var)..'->nxt->n==0) ? NULL : '..V(fr_var)..'->nxt)'
    end,

    Thread = function (me)
        me.thread_id = CUR(me, '__thread_id_'..me.n)
        me.thread_st = CUR(me, '__thread_st_'..me.n)
        me.val = '(*('..me.thread_st..') > 0)'
    end,

    EmitExt = function (me)
        local op, ext, param_ref = unpack(me)
        assert(param_ref==false or param_ref.tag=='Op1_&', 'bug found')

        local DIR, dir, ptr

        if ext.evt.pre == 'input' then
            DIR = 'IN'
            dir = 'in'
            if op == 'call' then
                ptr = '_ceu_app->data'
            else
                ptr = '_ceu_app'
            end
        else
            DIR = 'OUT'
            dir = 'out'
            ptr = '_ceu_app'
        end

        local t1 = { }
        if ext.evt.pre=='input' and op=='call' then
            t1[#t1+1] = '_ceu_app'  -- to access `app´
            t1[#t1+1] = ptr         -- to access `this´
        end

        local t2 = { ptr, 'CEU_'..DIR..'_'..ext.evt.id }

        if param_ref then
            local val = V(param_ref)
            t1[#t1+1] = val
            t2[#t2+1] = 'sizeof('..TP.toc(ext.evt.ins)..')'
            t2[#t2+1] = '(byte*)'..val
        else
            if dir=='in' then
                t1[#t1+1] = 'NULL'
            end
            t2[#t2+1] = '0'
            t2[#t2+1] = 'NULL'
        end
        t2 = table.concat(t2, ', ')
        t1 = table.concat(t1, ', ')

        local ret = ''
        if OPTS.os and op=='call' then
            -- when the call crosses the process,
            -- the return val must be unpacked from tceu_evtp
            if me.__ast_set then
                if TP.toc(ext.evt.out) == 'int' then
                    ret = '.v'
                else
                    ret = '.ptr'
                end
            end
        end

        local op = (op=='emit' and 'emit') or 'call'

        me.val = '\n'..[[
#if defined(ceu_]]..dir..'_'..op..'_'..ext.evt.id..[[)
    ceu_]]..dir..'_'..op..'_'..ext.evt.id..'('..t1..[[)

#elif defined(ceu_]]..dir..'_'..op..[[)
    ceu_]]..dir..'_'..op..'('..t2..')'..ret..[[

#else
    #error ceu_]]..dir..'_'..op..[[_* is not defined
#endif
]]
    end,

    AwaitInt = 'AwaitExt',
    AwaitExt = function (me)
        me.val = '_STK.evtp'
    end,
    AwaitT = function (me)
        local exp = unpack(me)
        local suf = (exp.tm and '_') or ''
        me.val      = '(tceu__s32*) &_ceu_app->wclk_late'..suf
        me.val_wclk = CUR(me, '__wclk_'..me.n)
    end,
--[[
    AwaitS = function (me)
        me.val = '__ceu_'..me.n..'_AwaitS'
    end,
]]

    Op2_call = function (me)
        local _, f, exps = unpack(me)
        local ps = {}
        if f.var and f.var.fun then
            -- (tceu_app*, tceu_org*, ...)
            ps[#ps+1] = '_ceu_app'
            if f.org then
                ps[#ps+1] = V(f.org)   -- only native
            else
                ps[#ps+1] = CUR(me)
            end
            ps[#ps] = '(tceu_org*)'..ps[#ps]
        end
        for i, exp in ipairs(exps) do
            ps[#ps+1] = V(exp)
        end
        me.val = V(f)..'('..table.concat(ps,',')..')'
    end,

    Op2_idx = function (me)
        local _, arr, idx = unpack(me)
        me.val = V(arr)..'['..V(idx)..']'
        if me.tp.ptr==0 and ENV.clss[me.tp.id] then
            me.val = '(&'..me.val..')'
                -- class accesses must be normalized to references
        end
    end,

    Op2_any = function (me)
        local op, e1, e2 = unpack(me)
        me.val = '('..V(e1)..ceu2c(op)..V(e2)..')'
    end,
    ['Op2_-']   = 'Op2_any',
    ['Op2_+']   = 'Op2_any',
    ['Op2_%']   = 'Op2_any',
    ['Op2_*']   = 'Op2_any',
    ['Op2_/']   = 'Op2_any',
    ['Op2_|']   = 'Op2_any',
    ['Op2_&']   = 'Op2_any',
    ['Op2_<<']  = 'Op2_any',
    ['Op2_>>']  = 'Op2_any',
    ['Op2_^']   = 'Op2_any',
    ['Op2_==']  = 'Op2_any',
    ['Op2_!=']  = 'Op2_any',
    ['Op2_>=']  = 'Op2_any',
    ['Op2_<=']  = 'Op2_any',
    ['Op2_>']   = 'Op2_any',
    ['Op2_<']   = 'Op2_any',
    ['Op2_or']  = 'Op2_any',
    ['Op2_and'] = 'Op2_any',

    Op1_any = function (me)
        local op, e1 = unpack(me)
        me.val = '('..ceu2c(op)..V(e1)..')'
    end,
    ['Op1_~']   = 'Op1_any',
    ['Op1_-']   = 'Op1_any',
    ['Op1_+']   = 'Op1_any',
    ['Op1_not'] = 'Op1_any',

    ['Op1_*'] = function (me)
        local op, e1 = unpack(me)
        local cls = e1.tp.ptr==1 and ENV.clss[e1.tp.id]
        if cls then
            me.val = V(e1) -- class accesses should remain normalized to references
        else
            me.val = '('..ceu2c(op)..V(e1)..')'
        end
    end,
    ['Op1_&'] = function (me)
        local op, e1 = unpack(me)
        if ENV.clss[e1.tp.id] and e1.tp.ptr==0 then
            me.val = V(e1) -- class accesses are already normalized to references
        else
            me.val = '('..ceu2c(op)..V(e1)..')'
        end
    end,

    ['Op2_.'] = function (me)
        if me.org then
            local cls = me.org.tp.ptr==0 and ENV.clss[me.org.tp.id]
            local gen = '((tceu_org*)'..me.org.val..')'
            if cls and cls.is_ifc then
                if me.var.pre == 'var'
                or me.var.pre == 'pool' then
                    if me.var.tp.arr then
                        me.val = [[(
(]]..TP.toc(me.var.tp)..[[) (
        ((byte*)]]..me.org.val..[[) + _CEU_APP.ifcs_flds[]]..gen..[[->cls][
            ]]..ENV.ifcs.flds[me.var.ifc_id]..[[
        ]
))]]
                    else
                        me.val = [[(*(
(]]..TP.toc(me.var.tp)..[[*) (
        ((byte*)]]..me.org.val..[[) + _CEU_APP.ifcs_flds[]]..gen..[[->cls][
            ]]..ENV.ifcs.flds[me.var.ifc_id]..[[
        ]
            )
))]]
                    end
                    if me.var.pre == 'pool' then
                        me.ifc_idx = '(_CEU_APP.ifcs_trls['..gen..'->cls]['
                                        ..ENV.ifcs.trls[me.var.ifc_id]
                                   ..'])'
                    end
                elseif me.var.pre == 'function' then
                    me.val = [[(*(
(]]..TP.toc(me.var.tp)..[[*) (
        _CEU_APP.ifcs_funs[]]..gen..[[->cls][
            ]]..ENV.ifcs.funs[me.var.ifc_id]..[[
        ]
            )
))]]
                elseif me.var.pre == 'event' then
                    me.val = nil    -- cannot be used as variable
                    me.ifc_idx = '(_CEU_APP.ifcs_evts['..gen..'->cls]['
                                    ..ENV.ifcs.evts[me.var.ifc_id]
                               ..'])'
                else
                    error 'not implemented'
                end
            else
                if me.c then
                    me.val = me.c.id_
                elseif me.var.pre == 'var' then
                    me.val = me.org.val..'->'..me.var.id_
                    if me.var.tp.arr then
                        -- normalize all arrays acesses to pointers to arr[0]
                        -- (because of interface accesses that must be done through a pointer)
                        me.val = '(&'..me.val..'[0])'
                    elseif me.var.cls then
                        -- normalize all org acesses to pointers to it
                        -- (because of interface accesses that must be done through a pointer)
                        me.val = '(&'..me.val..')'
                    end
                elseif me.var.pre == 'pool' then
                    -- normalize all pool acesses to pointers to it
                    -- (because of interface accesses that must be done through a pointer)
                    me.val = '(&'..me.org.val..'->'..me.var.id_..')'
                elseif me.var.pre == 'event' then
                    me.val = nil    -- cannot be used as variable
                    --me.org.val = '(&'..me.org.val..')' -- always via reference
                elseif me.var.pre == 'function' then
                    me.val = me.var.val
                else
                    error 'not implemented'
                end
            end
        else
            local op, e1, id = unpack(me)
            me.val  = '('..V(e1)..ceu2c(op)..id..')'
        end
    end,

    Op1_cast = function (me)
        local tp, exp = unpack(me)
        local val = V(exp)

        local cls = tp.ptr==1 and ENV.clss[tp.id]
        if cls then
            if cls.is_ifc then
                -- TODO: out of bounds acc
                val = '(('..val..' == NULL) ? NULL : '..
                        '((_CEU_APP.ifcs_clss[((tceu_org*)'..val..')->cls]'
                            ..'['..cls.n..']) ?'..val..' : NULL)'..
                      ')'
            else
                val = '(('..val..' == NULL) ? NULL : '..
                        '((((tceu_org*)'..val..')->cls == '..cls.n..') ? '
                        ..val..' : NULL)'..
                      ')'
            end
        end

        me.val = '(('..TP.toc(tp)..')'..val..')'
    end,

    WCLOCKK = function (me)
        local h,min,s,ms,us, tm = unpack(me)
        me.us  = us*t2n.us + ms*t2n.ms + s*t2n.s + min*t2n.min + h*t2n.h
        me.val = '((s32)'..me.us..')'
        me.tm  = tm
        ASR(me.us>0 and me.us<=2000000000, me, 'constant is out of range')
    end,

    WCLOCKE = function (me)
        local exp, unit, tm = unpack(me)
        me.us   = nil
        me.val  = '((s32)'.. V(exp) .. ')*' .. t2n[unit]
        me.tm  = tm
    end,

    RawExp = function (me)
        me.val = unpack(me)
    end,

    Type = function (me)
        me.val = TP.toc(me)
    end,

    Nat = function (me)
        me.val = string.sub(me[1], 2)
    end,
    SIZEOF = function (me)
        --me.val = me.sval
        local tp = unpack(me)
        me.val = 'sizeof('..tp.val..')'
    end,
    STRING = function (me)
        me.val = me[1]
    end,
    NUMBER = function (me)
        me.val = me[1]
    end,
    NULL = function (me)
        me.val = 'NULL'
    end,
}

AST.visit(F)
