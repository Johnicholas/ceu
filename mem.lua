MEM = {
    tops_h = '',
    tops_c = '',
    tops_init = '',
    native_pre = '',
}

function SPC ()
    return string.rep(' ',AST.iter()().__depth*2)
end

function pred_sort (v1, v2)
    return (v1.len or TP.types.word.len) > (v2.len or TP.types.word.len)
end

function CUR (me, id)
    if id then
        return '(('..TP.toc(CLS().tp)..'*)_STK_ORG)->'..id
    else
        return '(('..TP.toc(CLS().tp)..'*)_STK_ORG)'
    end
end

function MEM.tp2dcl (pre, tp, id, _dcl_id)
    local dcl = ''

    local tp_id = TP.id(tp)
    local tp_c  = TP.toc(tp)
    local cls = ENV.clss[tp_id]
    local adt = ENV.adts[tp_id]
    local top = adt or cls

    local _adt = adt and ENV.top(tp, nil, pre)
    local _cls = cls and ENV.top(tp, nil, pre)

    if _dcl_id == tp_id then
        tp_c = 'struct '..tp_c  -- for types w/ pointers for themselves
    end

    if pre == 'var' then

-- TODO: OPT
        if cls and (not cls.is_ifc) and (_dcl_id ~= tp_id) then
            dcl = dcl..'struct ' -- due to recursive spawn
        end

        if TP.check(tp,'[]','-&&','-&') then
            local tp_elem = TP.pop( TP.pop(tp,'&'), '[]' )
            local cls = cls and TP.check(tp_elem,tp_id)
            if cls or TP.is_ext(tp,'_') then
                if TP.check(tp,'&&') or TP.check(tp,'&') then
                    local tp_c = TP.toc( TP.pop(tp) )
                    return dcl .. tp_c..' '..id
                else
                    local tp_c = string.sub(tp_c,1,-2)  -- remove leading `*´
                    return dcl .. tp_c..' '..id..'['..tp.arr.cval..']'
                end
            else
                if TP.check(tp,'&&') or TP.check(tp,'&') then
                    return dcl .. 'tceu_vector* '..id
                else
                    local max = (tp.arr.cval or 0)
                    local tp_c = string.sub(tp_c,1,-2)  -- remove leading `*´
                    return dcl .. [[
CEU_VECTOR_DCL(]]..id..','..tp_c..','..max..[[)
]]
                end
            end
        elseif (not _adt) and TP.check(tp,TP.id(tp)) and ENV.adts[TP.id(tp)] then
            -- var List list;
            return dcl .. tp_c..'* '..id
        else
            return dcl .. tp_c..' '..id
        end

    elseif pre == 'pool' then

        -- ADT:
        -- tceu_adt_root id = { root=?, pool=_id };
        -- CEU_POOL_DCL(_id);
        if adt then
            assert(not TP.check(tp,'&&','&&'), 'bug found')
            local ptr = (TP.check(tp,'&') and '*') or ''
            dcl = dcl .. [[
/*
 * REF:
 * tceu_adt_root* x;  // root/pool always the same as the parent
 * PTR:
 * tceu_adt_root x;   // pool: the same // root: may point to the middle
 */
tceu_adt_root]]..ptr..' '..id..[[;
]]
        end

        -- static pool: "var T[N] ts"
        if (_adt or _cls) and type(tp.arr)=='table' then
            local ID = (adt and '_' or '') .. id  -- _id for ADT pools
            if top.is_ifc then
                return dcl .. [[
CEU_POOL_DCL(]]..ID..',CEU_'..tp_id..'_delayed,'..tp.arr.sval..[[)
]]
                       -- TODO: bad (explicit CEU_)
            else
                return dcl .. [[
CEU_POOL_DCL(]]..ID..',CEU_'..tp_id..','..tp.arr.sval..[[)
]]
                       -- TODO: bad (explicit CEU_)
            end
        elseif (not adt) then   -- (top_pool or cls)
            -- ADT doesn't require this NULL pool field
            --  (already has root->pool=NULL)
            if TP.check(tp,'&&') or TP.check(tp,'&') then
                local ptr = ''
                for i=#tp.tt, 1, -1 do
                    local v = tp.tt[i]
                    if v=='&&' or v=='&' then
                        ptr = ptr..'*'
                    else
                        break
                    end
                end
                return dcl .. [[
tceu_pool_]]..ptr..' '..id..[[;
]]
            else
                return dcl .. [[
tceu_pool_ ]]..id..[[;
]]
            end
        else
            return dcl
        end
    else
        error'bug found'
    end
end

F = {
    Host = function (me)
        local pre, code = unpack(me)
        -- unescape `##´ => `#´
        local src = string.gsub(code, '^%s*##',  '#')
              src = string.gsub(src,   '\n%s*##', '\n#')
        CLS().native[pre] = CLS().native[pre] .. [[

#line ]]..me.ln[2]..' "'..me.ln[1]..[["
]] .. src
    end,

    Dcl_adt_pre = function (me)
        local id, op = unpack(me)
        me.struct = 'typedef '
        me.auxs   = {}
        if op == 'union' then
            me.struct = me.struct..[[
struct CEU_]]..id..[[ {
    u8 tag;
    union {
]]
            if me.subs then
                --  data Y with ... end
                --  data X with
                --      ...
                --  or
                --      tag U with
                --          var Y* y;   // is_rec=true
                --      end
                --  end
                for id_sub in pairs(me.subs) do
                    me.struct = me.struct..[[
        CEU_]]..id_sub..' __'..id_sub..[[;
]]
                end
            end
            me.enum = { 'CEU_NONE'..me.n }    -- reserves 0 to catch more bugs
        end

        me.auxs[#me.auxs+1] = [[
#ifdef CEU_ADTS_WATCHING_]]..id..[[

void CEU_]]..id..'_kill (tceu_app* _ceu_app, tceu_go* go, CEU_'..id..[[* me);
#endif
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void CEU_]]..id..'_free_dynamic (tceu_app* _ceu_app, CEU_'..id..[[* me);
#endif
#ifdef CEU_ADTS_NEWS_POOL
void CEU_]]..id..'_free_static (tceu_app* _ceu_app, CEU_'..id..[[* me, void* pool);
#endif
#endif
]]
    end,
    Dcl_adt = function (me)
        local id, op = unpack(me)
        if op == 'union' then
            me.struct = me.struct .. [[
    };
}
]]
            me.enum = 'enum {\n'..table.concat(me.enum,',\n')..'\n};\n'
        else
            me.struct = string.sub(me.struct, 1, -3)    -- remove leading ';'
        end

        local kill = [[
#ifdef CEU_ADTS_WATCHING_]]..id..[[

void CEU_]]..id..'_kill (tceu_app* _ceu_app, tceu_go* go, CEU_'..id..[[* me) {
]]
        if op == 'union' then
            kill = kill .. [[
    switch (me->tag) {
]]
            for _, tag in ipairs(me.tags) do
                local id_tag = string.upper(id..'_'..tag)
                kill = kill .. [[
        case CEU_]]..id_tag..[[:
]]
                if me.is_rec and tag==me.tags[1] then
                    kill = kill .. [[
            /* base case */
]]
                else
                    kill = kill .. [[
            CEU_]]..id_tag..[[_kill(_ceu_app, go, me);
]]
                end
                kill = kill .. [[
            break;
]]
            end
            kill = kill .. [[
#ifdef CEU_DEBUG
        default:
            ceu_out_assert_msg(0, "invalid tag");
#endif
    }
]]
        end
        kill = kill .. [[
}
#endif
]]

        local free = [[
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void CEU_]]..id..'_free_dynamic (tceu_app* _ceu_app, CEU_'..id..[[* me) {
]]
        if op == 'struct' then
            free = free .. [[
    ceu_out_realloc(me, 0);
]]
        else
            assert(op == 'union')
            free = free .. [[
    switch (me->tag) {
]]
            for _, tag in ipairs(me.tags) do
                local id_tag = string.upper(id..'_'..tag)
                free = free .. [[
        case CEU_]]..id_tag..[[:
]]
                if me.is_rec and tag==me.tags[1] then
                    free = free .. [[
            /* base case */
]]
                else
                    free = free .. [[
            CEU_]]..id_tag..[[_free_dynamic(_ceu_app, me);
]]
                end
                free = free .. [[
            break;
]]
            end
            free = free .. [[
#ifdef CEU_DEBUG
        default:
            ceu_out_assert_msg(0, "invalid tag");
#endif
    }
]]
        end
        free = free .. [[
}
#endif
#ifdef CEU_ADTS_NEWS_POOL
void CEU_]]..id..'_free_static (tceu_app* _ceu_app, CEU_'..id..[[* me, void* pool) {
]]
        if op == 'struct' then
            free = free .. [[
    ceu_pool_free(pool, (void*)me);
]]
        else
            assert(op == 'union')
            free = free .. [[
    switch (me->tag) {
]]
            for _, tag in ipairs(me.tags) do
                local id_tag = string.upper(id..'_'..tag)
                free = free .. [[
        case CEU_]]..id_tag..[[:
]]
                if me.is_rec and tag==me.tags[1] then
                    free = free .. [[
            /* base case */
]]
                else
                    free = free .. [[
            CEU_]]..id_tag..[[_free_static(_ceu_app, me, pool);
]]
                end
                free = free .. [[
            break;
]]
            end
            free = free .. [[
    }
]]
        end
        free = free .. [[
}
#endif
#endif
]]

        local pack = ''
        local xx = me.__adj_from_opt
        xx =  xx and TP.pop(xx, '[]')
        --local xx = me.__adj_from_opt
        if xx and (TP.check(xx,'&&','?') or TP.check(xx,'&','?')) then
            local ID = string.upper(TP.opt2adt(xx))
            local tp = 'CEU_'..TP.opt2adt(xx)
            local some = TP.toc(me[4][2][1][1][2])
-- TODO: OPT
            local cls = ENV.clss[string.sub(some,5,-2)]
            if cls and (not cls.is_ifc) then
                some = 'struct '..some      -- due to recursive spawn
            end
            pack = [[
]]..tp..[[ CEU_]]..ID..[[_pack (]]..some..[[ ptr) {
    ]]..tp..[[ ret;
    if (ptr == NULL) {
        ret.tag = CEU_]]..ID..[[_NIL;
    } else {
        ret.tag = CEU_]]..ID..[[_SOME;
        ret.SOME.v = ptr;
    }
    return ret;
}
#if 0
// TODO: noew requires explicit conversions
]]..some..[[ CEU_]]..ID..[[_unpack (]]..tp..[[ me) {
    if (me.tag == CEU_]]..ID..[[_NIL) {
        return NULL;
    } else {
        return me.SOME.v;
    }
}
#endif
]]
        end

        me.auxs[#me.auxs+1] = kill
        me.auxs[#me.auxs+1] = free
        me.auxs[#me.auxs+1] = pack
        me.auxs   = table.concat(me.auxs,'\n')..'\n'
        me.struct = me.struct..' CEU_'..id..';'
        MEM.tops_h = MEM.tops_h..'\n'..(me.enum or '')..'\n'..
                                   me.struct..'\n'

        -- declare a static BASE instance
        if me.is_rec then
            MEM.tops_c = MEM.tops_c..[[
static CEU_]]..id..[[ CEU_]]..string.upper(id)..[[_BASE;
]]
            MEM.tops_init = MEM.tops_init .. [[
CEU_]]..string.upper(id)..[[_BASE.tag = CEU_]]..string.upper(id..'_'..me.tags[1])..[[;
]]
        end

        MEM.tops_c = MEM.tops_c..me.auxs..'\n'
    end,
    Dcl_adt_tag_pre = function (me)
        local top = AST.par(me, 'Dcl_adt')
        local id = unpack(top)
        local tag = unpack(me)
        local enum = 'CEU_'..string.upper(id)..'_'..tag
        top.enum[#top.enum+1] = enum
        -- _ceu_app is required because of OS/assert
        top.auxs[#top.auxs+1] = [[
CEU_]]..id..'* '..enum..'_assert (tceu_app* _ceu_app, CEU_'..id..[[* me, char* file, int line) {
    ceu_out_assert_msg_ex(me->tag == ]]..enum..[[, "invalid tag", file, line);
    return me;
}
]]

        if top.is_rec and top.tags[1]==tag then
            return  -- base case, no free
        end

        local kill = [[
#ifdef CEU_ADTS_WATCHING_]]..id..[[

void ]]..enum..'_kill (tceu_app* _ceu_app, tceu_go* go, CEU_'..id..[[* me) {
]]
        -- kill all my recursive fields after myself (push them before)
        for _,item in ipairs(top.tags[tag].tup) do
            local _, tp, _ = unpack(item)
            local id_top = id
            local ok = (TP.tostr(tp) == id)
            if (not ok) and top.subs then
                for id_adt in pairs(top.subs) do
                    if TP.tostr(tp) == id_adt then
                        id_top = id_adt
                        ok = true
                    end
                end
            end
            if ok then
                kill = kill .. [[
    CEU_]]..id_top..[[_kill(_ceu_app, go, me->]]..tag..'.'..item.var_id..[[);
/*
    me->]]..tag..'.'..item.var_id..[[ = &CEU_]]..string.upper(id_top)..[[_BASE;
*/
]]
            end
        end

        -- kill myself before my recursive fields (push myself after)
        kill = kill .. [[
    ceu_sys_adt_kill(_ceu_app, go, me);
}
#endif
]]

        local free = [[
#ifdef CEU_ADTS_NEWS
#ifdef CEU_ADTS_NEWS_MALLOC
void ]]..enum..'_free_dynamic (tceu_app* _ceu_app, CEU_'..id..[[* me) {
]]

        -- free all my recursive fields
        for _,item in ipairs(top.tags[tag].tup) do
            local _, tp, _ = unpack(item)
            local id_top = id
            local ok = (TP.tostr(tp) == id)
            if (not ok) and top.subs then
                for id_adt in pairs(top.subs) do
                    if TP.tostr(tp) == id_adt then
                        id_top = id_adt
                        ok = true
                    end
                end
            end
            if ok then
                free = free .. [[
    CEU_]]..id_top..[[_free_dynamic(_ceu_app, me->]]..tag..'.'..item.var_id..[[);
]]
            end
        end

        -- free myself
        free = free .. [[
    ceu_out_realloc(me, 0);
}
#endif
#ifdef CEU_ADTS_NEWS_POOL
void ]]..enum..'_free_static (tceu_app* _ceu_app, CEU_'..id..[[* me, void* pool) {
]]

        -- free all my recursive fields
        for _,item in ipairs(top.tags[tag].tup) do
            local _, tp, _ = unpack(item)
            local id_top = id
            local ok = (TP.tostr(tp) == id)
            if (not ok) and top.subs then
                for id_adt in pairs(top.subs) do
                    if TP.tostr(tp) == id_adt then
                        id_top = id_adt
                        ok = true
                    end
                end
            end
            if ok then
                free = free .. [[
    CEU_]]..id_top..[[_free_static(_ceu_app, me->]]..tag..'.'..item.var_id..[[, pool);
]]
            end
        end

        -- free myself
        free = free .. [[
    ceu_pool_free(pool, (void*)me);
}
#endif
#endif
]]

        top.auxs[#top.auxs+1] = kill
        top.auxs[#top.auxs+1] = free
    end,

    Dcl_cls_pre = function (me)
        me.struct = [[
typedef struct CEU_]]..me.id..[[ {
#ifdef CEU_ORGS
  struct tceu_org org;
#endif
  tceu_trl trls_[ ]]..me.trails_n..[[ ];
]]
        me.native = { [true]='', [false]='' }
        me.funs = ''
    end,
    Dcl_cls_pos = function (me)
        local ifcs_dcls  = ''

        if me.is_ifc then
            me.struct = 'typedef void '..TP.toc(me.tp)..';\n'

            -- interface full declarations must be delayed to after their impls
            -- TODO: HACK_4: delayed declaration until use

            local struct = [[
typedef union CEU_]]..me.id..[[_delayed {
]]
            for v_cls, v_matches in pairs(me.matches) do
                if v_matches and (not v_cls.is_ifc) then
                    -- ifcs have no size
                    if v_cls.id ~= 'Main' then  -- TODO: doesn't seem enough
                        struct = struct..'\t'..TP.toc(v_cls.tp)..' '..v_cls.id..';\n'
                    end
                end
            end
            struct = struct .. [[
} CEU_]]..me.id..[[_delayed;
]]
            me.__env_last_match.__delayed =
                (me.__env_last_match.__delayed or '') .. struct .. '\n'

            for _, var in ipairs(me.blk_ifc.vars) do
                ifcs_dcls = ifcs_dcls ..
                    TP.toc(var.tp)..'* CEU_'..me.id..'__'..var.id..' (CEU_'..me.id..'*);\n'

                if var.pre == 'var' then
                    MEM.tops_c = MEM.tops_c..[[
]]..TP.toc(var.tp)..'* CEU_'..me.id..'__'..var.id..' (CEU_'..me.id..[[* org) {
    return (]]..TP.toc(var.tp)..[[*) (
        ((byte*)org) + _CEU_APP.ifcs_flds[((tceu_org*)org)->cls][
            ]]..ENV.ifcs.flds[var.ifc_id]..[[
        ]
    );
}
]]
                elseif var.pre == 'function' then
                    MEM.tops_c = MEM.tops_c..[[
]]..TP.toc(var.tp)..'* CEU_'..me.id..'__'..var.id..' (CEU_'..me.id..[[* org) {
    return (]]..TP.toc(var.tp)..[[*) (
        _CEU_APP.ifcs_funs[((tceu_org*)org)->cls][
            ]]..ENV.ifcs.funs[var.ifc_id]..[[
        ]
    );
}
]]
                end
            end
        else
            me.struct  = me.struct..'\n} '..TP.toc(me.tp)..';\n'
        end

        -- native/pre goes before everything
        MEM.native_pre = MEM.native_pre ..  me.native[true]

        if me.id ~= 'Main' then
            -- native goes after class declaration
            MEM.tops_h = MEM.tops_h .. me.native[false] .. '\n'
        end
        MEM.tops_h = MEM.tops_h .. me.struct .. '\n'

        -- TODO: HACK_4: delayed declaration until use
        MEM.tops_h = MEM.tops_h .. (me.__delayed or '') .. '\n'

        MEM.tops_h = MEM.tops_h .. me.funs .. '\n'
        MEM.tops_h = MEM.tops_h .. ifcs_dcls .. '\n'
--DBG('===', me.id, me.trails_n)
--DBG(me.struct)
--DBG('======================')
    end,

    Dcl_fun = function (me)
        local _, _, ins, out, id, blk = unpack(me)
        local cls = CLS()

        -- input parameters (void* _ceu_go->org, int a, int b)
        local dcl = { 'tceu_app* _ceu_app', 'CEU_'..cls.id..'* __ceu_org' }
        for _, v in ipairs(ins) do
            local _, tp, id = unpack(v)
            dcl[#dcl+1] = MEM.tp2dcl('var', tp, (id or ''), nil, nil, nil)
        end
        dcl = table.concat(dcl,  ', ')

        local tp_out = MEM.tp2dcl('var', out, '', nil, nil, nil)

        me.id = 'CEU_'..cls.id..'_'..id
        me.proto = [[
]]..tp_out..' '..me.id..' ('..dcl..[[)
]]
        if OPTS.os and ENV.exts[id] and ENV.exts[id].pre=='output' then
            -- defined elsewhere
        else
            cls.funs = cls.funs..me.proto..';\n'
        end
    end,

    Stmts_pre = function (me)
        local cls = CLS()
        if cls then
            cls.struct = cls.struct..SPC()..'union {\n'
        end
    end,
    Stmts_pos = function (me)
        local cls = CLS()
        if cls then
            cls.struct = cls.struct..SPC()..'};\n'
        end
    end,

    Block_pos = function (me)
        local top = AST.par(me,'Dcl_adt') or CLS()
        local tag = ''
        if top.tag == 'Dcl_adt' then
            local n = AST.par(me, 'Dcl_adt_tag')
            if n then
                tag = unpack(n)
            end
        end
        if me.__loop then
            top.struct = top.struct..SPC()..me.__loop..'\n'
        end
        top.struct = top.struct..SPC()..'} '..tag..';\n'
    end,
    Block_pre = function (me)
        local DCL = AST.par(me,'Dcl_adt') or CLS()

        DCL.struct = DCL.struct..SPC()..'struct { /* BLOCK ln='..me.ln[2]..' */\n'

        if DCL.tag == 'Dcl_cls' then
            for _, var in ipairs(me.vars) do
                if var.trl_orgs then
                    -- ORG_STATS (shared for sequential), ORG_POOL (unique for each)
                    var.trl_orgs.val = CUR(me, '__lnks_'..me.n..'_'..var.trl_orgs[1])
                end
            end
            if me.fins then
                for i, fin in ipairs(me.fins) do
                    fin.val = CUR(me, '__fin_'..me.n..'_'..i)
                    DCL.struct = DCL.struct .. SPC()
                                ..'u8 __fin_'..me.n..'_'..i..': 1;\n'
                end
            end
        end

        for _, var in ipairs(me.vars) do
            local len
            --if var.isTmp or var.pre=='event' then  --
            if var.isTmp then --
                len = 0
            elseif var.pre == 'event' then --
                len = 1   --
            elseif var.pre=='pool' and (not TP.check(var.tp,'&')) and (type(var.tp.arr)=='table') then
                len = 10    -- TODO: it should be big
            elseif var.cls or var.adt then
                len = 10    -- TODO: it should be big
                --len = (var.tp.arr or 1) * ?
            elseif TP.check(var.tp,'?') then
                len = 10
            elseif TP.check(var.tp,'[]') then
                len = 10    -- TODO: it should be big
--[[
                local _tp = TP.deptr(var.tp)
                len = var.tp.arr * (TP.deptr(_tp) and TP.types.pointer.len
                             or (ENV.c[_tp] and ENV.c[_tp].len
                                 or TP.types.word.len)) -- defaults to word
]]
            elseif (TP.check(var.tp,'&&') or TP.check(var.tp,'&')) then
                len = TP.types.pointer.len
            elseif (not var.adt) and TP.check(TP.id(var.tp)) and ENV.adts[TP.id(var.tp)] then
                -- var List l
                len = TP.types.pointer.len
            else
                len = ENV.c[TP.id(var.tp)].len
            end
            var.len = len
        end

        -- sort offsets in descending order to optimize alignment
        -- TODO: previous org metadata
        local sorted = { unpack(me.vars) }
        if me~=DCL.blk_ifc and DCL.tag~='Dcl_adt' then
            table.sort(sorted, pred_sort)   -- TCEU_X should respect lexical order
        end

        for _, var in ipairs(sorted) do
            local tp_c  = TP.toc(var.tp)
            local tp_id = TP.id(var.tp)

            if var.inTop then
                var.id_ = var.id
                    -- id's inside interfaces are kept (to be used from C)
            else
                var.id_ = var.id .. '_' .. var.n
                    -- otherwise use counter to avoid clash inside struct/union
            end

            if (var.pre=='var' and (not var.isTmp)) or var.pre=='pool' then
                -- avoid main "ret" if not assigned
                local go = true
                if var.id == '_ret' then
                    local setblock = AST.asr(me,'', 1,'Stmts', 2,'SetBlock')
                    go = setblock.has_escape
                end

                if go then
                    DCL.struct = DCL.struct .. SPC() .. '  ' ..
                                  MEM.tp2dcl(var.pre, var.tp, var.id_, DCL.id)
                                 ..  ';\n'
                end
            end

            -- pointers ini/end to list of orgs
            if var.cls then
                DCL.struct = DCL.struct .. SPC() ..
                   'tceu_org_lnk __lnks_'..me.n..'_'..var.trl_orgs[1]..'[2];\n'
                    -- see val.lua for the (complex) naming
            end
        end
    end,

    ParOr_pre = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'struct {\n'
    end,
    ParOr_pos = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'};\n'
    end,
    ParAnd_pre = 'ParOr_pre',
    ParAnd_pos = 'ParOr_pos',
    ParEver_pre = 'ParOr_pre',
    ParEver_pos = 'ParOr_pos',

    ParAnd = function (me)
        local cls = CLS()
        for i=1, #me do
            cls.struct = cls.struct..SPC()..'u8 __and_'..me.n..'_'..i..': 1;\n'
        end
    end,

    Loop = function (me)
        if not me.__recs then
            return
        end
error'not implemented'

        -- `recurse´ stack
        -- TODO: no cls space if no awaits inside the loop (use local C var)
        local max,iter,_,_ = unpack(me)

        if max then
            me.iter_max = max.cval
        else
            local adt = ENV.adts[TP.id(iter.tp)]
            if adt then
                local tp  = iter.lst.var.tp
                local arr = tp.arr
                if (not arr) and (not TP.check(tp,'&')) then
                    me.iter_max = iter.lst.var.n_cons * adt.n_recs
                elseif type(arr)=='table' then
                    me.iter_max = arr.cval * adt.n_recs
                else
                    error'not implemented: unbounded iter'
                end
            else
                error'not implemented: unbounded iter'
            end
        end

        me.iter_max = me.iter_max * me.__recs
        AST.par(me, 'Block').__loop = [[
int          __recurse_nxt_]]..me.n..[[;    /* TODO: int (minimum type) */
tceu_recurse __recurse_vec_]]..me.n..'['..me.iter_max..']'..[[;
]]
            -- TODO: reason about the maximum space (it's less than the above!)
    end,
--[[
    Recurse = function (me)
        local loop = AST.par(me,'Loop')
        loop.__recs = (loop.__recs or 0) + 1
                      -- stack is a multiple of inner recurses
    end,
]]

    Await = function (me)
        local _, dt = unpack(me)
        if dt then
            local cls = CLS()
            cls.struct = cls.struct..SPC()..'s32 __wclk_'..me.n..';\n'
        end
    end,

    Thread_pre = 'ParOr_pre',
    Thread = function (me)
        local cls = CLS()
        cls.struct = cls.struct..SPC()..'CEU_THREADS_T __thread_id_'..me.n..';\n'
        cls.struct = cls.struct..SPC()..'s8*       __thread_st_'..me.n..';\n'
    end,
    Thread_pos = 'ParOr_pos',
}

AST.visit(F)
