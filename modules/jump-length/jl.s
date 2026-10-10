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

| =============================================================================
| The SCALE SETUP field ([FUNC] + [PAGE], window 0x460d1dfc, drawer 0x40047d08).
| Stock fields (cursor 0x460d1e00): 0/1/2 in NORMAL, 0..4 in PER TRACK; the
| LEVEL encoder (0x4004c930) dispatches on it. JUMP is field 5, reached after
| the last stock field in both modes. Window coordinates are the drawer's:
| x from the left, y from the bottom (the mode icons are drawn at y 5).

        .equ    JL_X0,  0x4c                    | as the scale fields' underline
        .equ    JL_X1,  0x54
        .equ    JL_TY,  8                       | text row (from the bottom)
        .equ    JL_UY,  4                       | underline row (2 is the window border)

| a0 := the CURRENT pattern (UI: 0x46c82456 bank base + CUR_PATTERN x 0x8ed8),
| d1 := its offset; d0 clobbered. As the stock editors do (0x4004cb76..).
jl_curpat:
        mvz.b   0x80000004,%d1
        move.l  #0x8ed8,%d0
        muls.l  %d0,%d1
        move.l  0x46c82456,%d0
        add.l   %d1,%d0
        move.l  %d0,%a0
        rts

| d0 := 0 in NORMAL, nonzero in PER TRACK (pattern +0x8e55); a0, d1 clobbered
jl_pertrack:
        bsr     jl_curpat
        move.l  #0x8e55,%d0
        mvs.b   (%a0,%d0.l),%d0
        rts

| d0 := the JUMP index of the current pattern: 0 none, 1 INS .. 7 16X
jl_index:
        bsr     jl_curpat
        move.l  #0x8e56,%d0
        mvs.b   (%a0,%d0.l),%d0
        moveq   #-2,%d1
        cmp.l   %d1,%d0
        bgt     jl_ix_none
        moveq   #-8,%d1
        cmp.l   %d1,%d0
        blt     jl_ix_none
        neg.l   %d0
        subq.l  #1,%d0                          | -2 -> 1 .. -8 -> 7
        rts
jl_ix_none:
        moveq   #0,%d0
        rts

| ---- next / previous field: SymbolRefs in the key table at 0x400cb606 and
| 0x400cb5ec (stock 0x40048628 / 0x4004867c); both tail into the drawer.
        .globl  jl_next
jl_next:
        move.l  0x460d1e00,%d2
        moveq   #5,%d0
        cmp.l   %d0,%d2
        beq     jl_n_zero                       | JUMP -> the first field
        bsr     jl_pertrack
        tst.l   %d0
        bne     jl_n_pt
        moveq   #2,%d0
        cmp.l   %d0,%d2
        bge     jl_n_jump                       | NORMAL: 2 -> JUMP
        bra     jl_n_inc
jl_n_pt:
        moveq   #4,%d0
        cmp.l   %d0,%d2
        bge     jl_n_jump                       | PER TRACK: 4 -> JUMP
jl_n_inc:
        addq.l  #1,%d2
        bra     jl_n_set
jl_n_jump:
        moveq   #5,%d2
        bra     jl_n_set
jl_n_zero:
        moveq   #0,%d2
jl_n_set:
        move.l  %d2,0x460d1e00
        jmp     0x40047d08

        .globl  jl_prev
jl_prev:
        move.l  0x460d1e00,%d2
        tst.l   %d2
        beq     jl_p_jump                       | first field -> JUMP
        moveq   #5,%d0
        cmp.l   %d0,%d2
        bne     jl_p_dec
        bsr     jl_pertrack                     | JUMP -> the last stock field
        moveq   #4,%d2
        tst.l   %d0
        bne     jl_n_set
        moveq   #2,%d2
        bra     jl_n_set
jl_p_dec:
        subq.l  #1,%d2
        bsr     jl_pertrack
        tst.l   %d0
        bne     jl_n_set
        moveq   #2,%d0                          | NORMAL: a stale 3/4 -> 2
        cmp.l   %d0,%d2
        ble     jl_n_set
        move.l  %d0,%d2
        bra     jl_n_set
jl_p_jump:
        moveq   #5,%d2
        bra     jl_n_set

| ---- the drawer's NORMAL-mode clamp, 0x40047e86 (16 bytes: moveq #2,d0;
| cmp.l 0x460d1e00,d0; bcc; move.l d0,0x460d1e00): stock forces any field
| above 2 to 2; JUMP (5) is kept.
        .globl  jl_clamp
jl_clamp:
        move.l  0x460d1e00,%d0
        subq.l  #3,%d0
        bcs     jl_c_done                       | 0..2
        subq.l  #2,%d0
        bcc     jl_c_done                       | 5 (or anything past 4)
        moveq   #2,%d0                          | 3, 4 -> 2
        move.l  %d0,0x460d1e00
jl_c_done:
        rts

| ---- the LEVEL encoder, 0x4004cb50 (8 bytes: moveq #4,d1; cmp.l d0,d1;
| bne.w 0x4004cbe2), d0 = the field, d3 = the step, positive clockwise (stock
| subtracts it from the scale index, whose table runs 2x .. 1/8x).
| d0-d2/a0-a1 are free: the tail at 0x4004cbe2 restores d2-d4.
        .globl  jl_enc
jl_enc:
        moveq   #4,%d1
        cmp.l   %d0,%d1
        bne     jl_e_5
        jmp     0x4004cb58                      | stock field 4
jl_e_5:
        moveq   #5,%d1
        cmp.l   %d0,%d1
        bne     jl_e_tail
        bsr     jl_index
        move.l  %d0,%d2                         | old index
        add.l   %d3,%d0                         | clockwise (d3 > 0) steps down the list
        bge     jl_e_lo
        moveq   #0,%d0
jl_e_lo:
        moveq   #7,%d1
        cmp.l   %d1,%d0
        ble     jl_e_hi
        move.l  %d1,%d0
jl_e_hi:
        cmp.l   %d2,%d0
        beq     jl_e_tail                       | unchanged
        move.l  %d0,%d2                         | new index
        bsr     jl_curpat                       | a0 = pattern, d1 = its offset
        tst.l   %d2
        bne     jl_e_set
        moveq   #-1,%d0                         | none: USE PRJ SET.
        bra     jl_e_write
jl_e_set:
        moveq   #-1,%d0
        sub.l   %d2,%d0                         | 1 -> -2 .. 7 -> -8
jl_e_write:
        move.l  %a0,%a1
        adda.l  #0x8e56,%a1
        move.b  %d0,(%a1)
        lea     0x1001efa4,%a1                  | the UI mirror (as 0x40081df8..)
        move.b  %d0,(%a1,%d1.l)
        move.l  0x46c82456,%a1                  | bank dirty (as 0x4004cbca..)
        move.l  #0x9b332,%d0
        moveq   #1,%d1
        move.l  %d1,(%a1,%d0.l)
        move.l  %d1,0x100f8598
        jsr     0x40027e00
jl_e_tail:
        jmp     0x4004cbe2

| ---- the drawer, 0x40048610 (8 bytes: moveq #1,d0; move.l d0,0x46c7c72c),
| after the mode icons, in both modes; d4 = the drawing context. Every
| register is restored from the frame after this (0x4004861c).
        .globl  jl_draw
jl_draw:
        moveq   #1,%d0                          | displaced
        move.l  %d0,0x46c7c72c                  | displaced
        bsr     jl_index
        lsl.l   #2,%d0
        lea     jl_names(%pc),%a0
        move.l  (%a0,%d0.l),%d0
        lea     jl_strs(%pc),%a0
        add.l   %a0,%d0                         | the label (position independent)
        move.l  %d0,-(%sp)
        pea     0x400b37cf                      | "%s"
        move.l  %d0,-(%sp)
        clr.l   -(%sp)
        clr.l   -(%sp)
        pea     JL_TY
        pea     JL_X0
        move.l  %d4,-(%sp)
        pea     0x400ba876                      | the scale fields' font
        jsr     0x40013904
        lea     36(%sp),%sp
        moveq   #5,%d0
        cmp.l   0x460d1e00,%d0
        bne     jl_dr_dots
        pea     1                               | selected: two solid lines
        pea     JL_X1
        pea     JL_UY
        pea     JL_X0
        move.l  %d4,-(%sp)
        jsr     0x40011910
        lea     20(%sp),%sp
        pea     1
        pea     JL_X1
        pea     JL_UY-1
        pea     JL_X0
        move.l  %d4,-(%sp)
        jsr     0x40011910
        lea     20(%sp),%sp
        rts
jl_dr_dots:
        pea     JL_X1                           | not selected: dotted
        pea     JL_UY
        pea     JL_X0
        move.l  %d4,-(%sp)
        jsr     0x40011a58
        lea     16(%sp),%sp
        rts

        .align  2
jl_names:                                       | offsets into jl_strs
        .long   jl_s0-jl_strs, jl_s1-jl_strs, jl_s2-jl_strs, jl_s3-jl_strs
        .long   jl_s4-jl_strs, jl_s5-jl_strs, jl_s6-jl_strs, jl_s7-jl_strs
jl_strs:
jl_s0:  .asciz  "---"
jl_s1:  .asciz  "INS"
jl_s2:  .asciz  "EOP"
jl_s3:  .asciz  "1x"
jl_s4:  .asciz  "2x"
jl_s5:  .asciz  "4x"
jl_s6:  .asciz  "8x"
jl_s7:  .asciz  "16x"
        .align  2
