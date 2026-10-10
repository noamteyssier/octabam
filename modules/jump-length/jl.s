| JUMP LENGTH -- ColdFire unit (ROM cave), GNU as, -mcpu=5475.
|
| A pattern's CHAIN BEHAVIOR byte (+0x8e56) carries JUMP as a negative value
| below stock's -1 (USE PRJ SET.):
|
|   -2 INS   the next step
|   -3 EOP   every 16 steps (the page), or the pattern end
|   -4 1X    the pattern end
|   -5 2X  -6 4X  -7 8X  -8 16X   every length/N steps
|
| When the PLAYING pattern carries one and a change is queued, the tick
| handler's boundary decision is taken here; the switch itself (the Part,
| per-track positions, LEDs, notices) stays stock, and the new pattern starts
| at its step 1 as on a stock change. Any other byte value, an arranger row
| (an absolute change-at) or the arranger running leaves stock's decision
| untouched. Stock readers of the byte see any negative as USE PRJ SET., and
| a stock unit's validator resets -2..-8 to -1.
|
| Length L: the tick handler's d7 -- MASTER LENGTH (+0x8e50, word, -1 = INF)
| in PER TRACK, LENGTH (+0x8e53) in NORMAL (0x400a3fa6..0x400a3fc4). With INF
| the multiples fall back to EOP. A multiple's boundaries are where
| floor(c * N / L) steps up, i.e. (c * N) mod L < N; c >= L always switches.
|
| Two detours (kind "jsr", wired by symbol; each returns to the stock
| continuation or rewrites its own return address to a stock exit):
|   jl_main  at 0x400a4352  the decision at tick 0, counter c = 0x800065b2
|            exits: 0x400a43a0 switch, 0x400a4b9e no switch
|   jl_pre   at 0x400a4196  the tick-2 pre-check, c = counter + 1; stock
|            sends the MIDI program change there two ticks early
|            exits: 0x400a41e8 send it, 0x400a4b9e no
| A selection that lands after tick 2 of the step before its boundary misses
| the pre-check, so jl_main sends the program change at the switch when
| jl_pre did not (jl_pc_at).
|
| Registers (from the disassembly, RECON.md): a4 = the playing pattern's
| record, d7 = L, d2 = c (main) / d1 = queued, d2 = c + 1 (pre), d3 = an
| absolute change-at is set, d6 = queued (main). d0 is dead on every exit
| taken from here; everything else is preserved.

        .text

| ---- jl_main: 0x400a4352, displaced `mvz.w 0x800065b2,%d2` ------------------
        .globl  jl_main
jl_main:
        mvz.w   0x800065b2,%d2          | displaced: the step counter
        tst.l   %d6                     | a change queued?
        beq     jl_ret
        tst.l   %d3                     | an absolute change-at (arranger row)
        bne     jl_ret
        move.l  %d2,%d0
        bsr     jl_decide
        tst.l   %d0
        bmi     jl_ret                  | not ours: stock
        beq     jl_m_hold
        bsr     jl_owed                 | the program change, if the pre-check missed it
        move.l  #0x400a43a0,(%sp)       | switch
        rts
jl_m_hold:
        move.l  #0x400a4b9e,(%sp)       | no switch this step
jl_ret:
        rts

| ---- jl_pre: 0x400a4196, displaced `mvz.w 0x800065b2,%d0; move.l %d0,%d2;
| addq.l #1,%d2` (10 bytes; the detour pads with two nops) -----------------
        .globl  jl_pre
jl_pre:
        mvz.w   0x800065b2,%d0          | displaced
        move.l  %d0,%d2                 | displaced
        addq.l  #1,%d2                  | displaced: the next step's count
        tst.l   %d1                     | a change queued?
        beq     jl_ret
        tst.l   %d3
        bne     jl_ret
        move.l  %d2,%d0
        bsr     jl_decide
        tst.l   %d0
        bmi     jl_ret
        beq     jl_p_hold
        move.l  %a0,-(%sp)
        lea     jl_pc_at(%pc),%a0
        move.w  %d2,(%a0)               | the program change goes out for boundary c
        move.l  (%sp)+,%a0
        move.l  #0x400a41e8,(%sp)       | stock: send it
        rts
jl_p_hold:
        move.l  #0x400a4b9e,(%sp)
        rts

| ---- jl_decide: d0 = c in; d0 out = 1 switch, 0 hold, -1 not ours ---------
jl_decide:
        move.l  %d1,-(%sp)
        move.l  %d2,-(%sp)
        move.l  %d3,-(%sp)
        move.l  %d0,%d2                 | c
        move.l  #0x8e56,%d0
        mvs.b   (%a4,%d0.l),%d1         | the playing pattern's CHAIN BEHAVIOR
        moveq   #-2,%d0
        cmp.l   %d0,%d1
        bgt     jl_d_stock              | -1 .. 16: stock
        moveq   #-8,%d0
        cmp.l   %d0,%d1
        blt     jl_d_stock              | below -8: not ours
        tst.l   0x460d1aec              | the arranger is playing (0x40033968)
        bne     jl_d_stock
        moveq   #-2,%d0
        cmp.l   %d0,%d1
        beq     jl_d_switch             | INS: every step
        mvs.w   %d7,%d3                 | L, -1 = INF
        tst.l   %d3
        ble     jl_d_noend
        cmp.l   %d3,%d2
        bge     jl_d_switch             | c >= L: the end is always a boundary
jl_d_noend:
        moveq   #-3,%d0
        cmp.l   %d0,%d1
        beq     jl_d_eop
        tst.l   %d3
        ble     jl_d_eop                | INF: a multiple of nothing, use the page
        moveq   #-4,%d0
        sub.l   %d1,%d0                 | -4 - b = log2 N
        moveq   #1,%d1
        lsl.l   %d0,%d1                 | N
        move.l  %d2,%d0
        mulu.l  %d1,%d0                 | c * N
        remul   %d3,%d2,%d0             | d2 = (c * N) mod L (Dr != Dq: same register encodes DIVU.L)
        cmp.l   %d1,%d2
        blt     jl_d_switch
        bra     jl_d_hold
jl_d_eop:
        moveq   #15,%d0
        and.l   %d2,%d0
        beq     jl_d_switch
jl_d_hold:
        moveq   #0,%d0
        bra     jl_d_out
jl_d_switch:
        moveq   #1,%d0
        bra     jl_d_out
jl_d_stock:
        moveq   #-1,%d0
jl_d_out:
        move.l  (%sp)+,%d3
        move.l  (%sp)+,%d2
        move.l  (%sp)+,%d1
        rts

| ---- jl_owed: at a switch for boundary d2, send the MIDI program change
| unless jl_pre already let stock send it. Stock's own send (0x400a41f8..):
| skipped when the queued pattern is -1; 0x4009e884(bank, pattern). ---------
jl_owed:
        move.l  %a0,-(%sp)
        move.l  %a1,-(%sp)
        move.l  %d1,-(%sp)
        lea     jl_pc_at(%pc),%a0
        mvz.w   (%a0),%d0
        cmp.l   %d2,%d0
        beq     jl_o_done               | sent at tick 2
        mvs.b   0x800065c0,%d0          | queued pattern
        moveq   #-1,%d1
        cmp.l   %d0,%d1
        beq     jl_o_done
        move.l  %d0,-(%sp)
        mvs.b   0x800065bf,%d0          | queued bank
        move.l  %d0,-(%sp)
        jsr     0x4009e884
        addq.l  #8,%sp
jl_o_done:
        lea     jl_pc_at(%pc),%a0
        move.w  #-1,(%a0)               | consumed
        move.l  (%sp)+,%d1
        move.l  (%sp)+,%a1
        move.l  (%sp)+,%a0
        rts

        .align  2
jl_pc_at:
        .short  -1                      | the boundary the pre-check sent for
        .align  2
