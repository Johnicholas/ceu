_LBLS = {
    list = {},      -- { [lbl]={}, [i]=lbl }
    code = '',
}

function new (lbl)
    lbl.id = lbl[1] .. (lbl[2] and '' or '_' .. #_LBLS.list)
    lbl.id = string.gsub(lbl.id, '%*','_')
    lbl.id = string.gsub(lbl.id, '%.','_')
    lbl.id = string.gsub(lbl.id, '%$','_')
    _LBLS.list[lbl] = true
    lbl.n = #_LBLS.list                   -- starts from 0
    _LBLS.list[#_LBLS.list+1] = lbl

    for n in _AST.iter() do
        if n.lbls_all then
            n.lbls_all[lbl] = true
        end
    end

    return lbl
end

F = {
    Node_pre = function (me)
        me.lbls = { #_LBLS.list }
    end,
    Node = function (me)
        me.lbls[2] = #_LBLS.list-1
    end,

    Root_pre = function (me)
        new{'Inactive', true}
    end,

    Root = function (me)
        -- enum of labels
        for i, lbl in ipairs(_LBLS.list) do
            _LBLS.code = _LBLS.code..'    '..lbl.id..' = '..lbl.n..',\n'
        end

        _ENV.types.tceu_nlbl = _TP.n2bytes(#_LBLS.list)
    end,

    Block = function (me)
        -- TODO: inneficient
        if me.ns.orgs > 0 then
            me.lbl_out  = new{'Block_out', prio=me.depth}
            me.lbl_out2 = new{'Block_out2'}
        end
    end,

    Dcl_cls = function (me)
        me.lbl = new{'Class_'..me.id, true}
    end,

    Dcl_var = function (me)
        if me.var.cls or _ENV.clss[_TP.deref(me.var.tp)] then
            me.var.lbl_par = new{'Par_org'}
        end
    end,

    SetBlock_pre = function (me)
        me.lbl_out  = new{'Set_out',  prio=me.depth}
        me.lbl_out2 = new{'Set_out2'}
    end,

    _Par_pre = function (me)
        me.lbls_in  = {}
        for i, sub in ipairs(me) do
            me.lbls_in[i] = new{me.tag..'_sub_'..i}
        end
    end,
    ParEver_pre = function (me)
        F._Par_pre(me)
        me.lbl_out = new{'ParEver_out'}
    end,
    ParOr_pre = function (me)
        F._Par_pre(me)
        me.lbl_out  = new{'ParOr_out',  prio=me.depth}
        me.lbl_out2 = new{'ParOr_out2'}
    end,
    ParAnd_pre = function (me)
        F._Par_pre(me)
        me.lbl_tst = new{'ParAnd_chk'}
        me.lbl_out = new{'ParAnd_out'}
    end,

    If = function (me)
        local c, t, f = unpack(me)
        me.lbl_t = new{'True'}
        me.lbl_f = f and new{'False'}
        me.lbl_e = new{'EndIf'}
    end,

    Async = function (me)
        me.lbl = new{'Async'}
    end,

    Loop_pre = function (me)
        me.lbl_ini  = new{'Loop_ini'}
        me.lbl_out  = new{'Loop_out',  prio=me.depth }
        me.lbl_out2 = new{'Loop_out2'}
    end,

    EmitExtS = function (me)
        me.lbl_cnt = new{'Async_cont'}
    end,
    EmitT = function (me)
        me.lbl_cnt = new{'Async_cont'}
    end,

    EmitInt = function (me)
        local int = unpack(me)
        me.lbl_mch = new{'Emit_mch_'..int.var.id}
        me.lbl_cnt = new{'Emit_cnt_'..int.var.id}
    end,

    AwaitT = function (me)
        if me[1].tag == 'WCLOCKE' then
            me.lbl = new{'Awake_'..me[1][1][1]}
        else
            me.lbl = new{'Awake_'..me[1][1]}
        end
    end,
    AwaitExt = function (me)
        me.lbl = new{'Awake_'..me[1][1]}
    end,
    AwaitInt = function (me)
        local int = unpack(me)
        me.lbl_awt = new{'Await_'..me[1][1]}
        me.lbl_awk = new{'Awake_'..me[1][1]}
    end,
}

_AST.visit(F)