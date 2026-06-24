#!/usr/bin/env python
"""Analyze test7: all instructions, pipeline stalls, flushes."""

words = [0x14000F93,0x876540B7,0x32108093,0x001FA223,0xFD8FAF03,0xFE8FA103,
0x01811193,0x0181D213,0x004202B3,0x0080036F,0x0042D463,0x000303E7,
0x00523433,0x00147493,0x0010B513,0x0010A593,0x0010C613,0x00F0E693,
0x4180D713,0x404287B3,0x00409833,0x0040D8B3,0x4040D933,0x005229B3,
0x00123A33,0x00524AB3,0x00526B33,0x00527BB3,0xFC42C0E3,0xFA50EEE3,
0xFA12FCE3,0x00F20663,0x01702023,0xFADFFC6F,0x87654C97,0x002FA423,
0x003FA623,0x004FA823,0x005FAA23,0x006FAC23,0x007FAE23,0x028FA023,
0x029FA223,0x02AFA423,0x02BFA623,0x02CFA823,0x02DFAA23,0x02EFAC23,
0x02FFAE23,0x050FA023,0x051FA223,0x052FA423,0x053FA623,0x054FA823,
0x055FAA23,0x056FAC23,0x057FAE23,0x078FA023,0x079FA223,0x11800D03,
0x07AFA423,0x11801D83,0x11804E03,0x07BFA623,0x07CFA823,0x11805E83,
0x07DFAA23,0x07EF8C23,0x07EF9E23,0x00000F6F]

def decode(w):
    op = w & 0x7F; rd = (w>>7)&0x1F; f3=(w>>12)&7; rs1=(w>>15)&0x1F; rs2=(w>>20)&0x1F
    f7=(w>>25)&0x7F
    def se(v,b): return v-(1<<b) if v&(1<<(b-1)) else v
    ii = se((w>>20)&0xFFF,12); is_ = se(((w>>25)<<5)|((w>>7)&0x1F),12)
    ib = se(((w>>31)<<12)|(((w>>7)&1)<<11)|(((w>>25)&0x3F)<<5)|(((w>>8)&0xF)<<1),13)
    iu = w & 0xFFFFF000
    ij = se(((w>>31)<<20)|(((w>>12)&0xFF)<<12)|(((w>>20)&1)<<11)|(((w>>21)&0x3FF)<<1),21)
    return {'op':op,'rd':rd,'f3':f3,'rs1':rs1,'rs2':rs2,'f7':f7,
            'ii':ii,'is':is_,'ib':ib,'iu':iu,'ij':ij}

def inst_name(d):
    op,f3,rd,rs1,rs2,f7 = d['op'],d['f3'],d['rd'],d['rs1'],d['rs2'],d['f7']
    if op==0x37: return f'lui x{rd}, 0x{d["iu"]>>12:05X}'
    if op==0x17: return f'auipc x{rd}, 0x{d["iu"]>>12:05X}'
    if op==0x6F: return f'jal x{rd}, {d["ij"]:+d}'
    if op==0x67: return f'jalr x{rd}, {d["ii"]}(x{rs1})'
    if op==0x63:
        n={0:'beq',1:'bne',4:'blt',5:'bge',6:'bltu',7:'bgeu'}
        return f'{n[f3]} x{rs1}, x{rs2}, {d["ib"]:+d}'
    if op==0x03:
        n={0:'lb',1:'lh',2:'lw',4:'lbu',5:'lhu'}
        return f'{n.get(f3,"?")} x{rd}, {d["ii"]}(x{rs1})'
    if op==0x23:
        n={0:'sb',1:'sh',2:'sw'}
        return f'{n.get(f3,"?")} x{rs2}, {d["is"]}(x{rs1})'
    if op==0x13:
        imm=d['ii']
        if f3==0: return f'addi x{rd}, x{rs1}, {imm}'
        if f3==1: return f'slli x{rd}, x{rs1}, {imm&0x1F}'
        if f3==2: return f'slti x{rd}, x{rs1}, {imm}'
        if f3==3: return f'sltiu x{rd}, x{rs1}, {imm}'
        if f3==4: return f'xori x{rd}, x{rs1}, {imm}'
        if f3==6: return f'ori x{rd}, x{rs1}, {imm}'
        if f3==7: return f'andi x{rd}, x{rs1}, {imm}'
        if f3==5:
            if f7==0x20: return f'srai x{rd}, x{rs1}, {imm&0x1F}'
            return f'srli x{rd}, x{rs1}, {imm&0x1F}'
    if op==0x33:
        if f3==0 and f7==0x20: return f'sub x{rd}, x{rs1}, x{rs2}'
        if f3==0: return f'add x{rd}, x{rs1}, x{rs2}'
        if f3==1: return f'sll x{rd}, x{rs1}, x{rs2}'
        if f3==2: return f'slt x{rd}, x{rs1}, x{rs2}'
        if f3==3: return f'sltu x{rd}, x{rs1}, x{rs2}'
        if f3==4: return f'xor x{rd}, x{rs1}, x{rs2}'
        if f3==5:
            if f7==0x20: return f'sra x{rd}, x{rs1}, x{rs2}'
            return f'srl x{rd}, x{rs1}, x{rs2}'
        if f3==6: return f'or x{rd}, x{rs1}, x{rs2}'
        if f3==7: return f'and x{rd}, x{rs1}, x{rs2}'
    return f'??? 0x{w:08X}'

# === Print all instructions ===
print('='*70)
print('TEST7 完整指令列表')
print('='*70)
print(f'{"PC":>6s} | {"指令":40s} | {"类型":10s} | 说明')
print('-'*70)

for i, w in enumerate(words):
    d = decode(w)
    pc = i*4
    name = inst_name(d)
    op = d['op']

    typ = ''
    note = ''
    if op==0x63:
        typ = 'BRANCH'
    elif op==0x6F:
        typ = 'JAL'
        note = '(无条件跳转+flush)'
    elif op==0x67:
        typ = 'JALR'
        note = '(无条件跳转+flush)'
    elif op==0x03:
        typ = 'LOAD'
    elif op==0x23:
        typ = 'STORE'
    elif op==0x33:
        typ = 'R-ALU'
    elif op==0x13:
        typ = 'I-ALU'
    elif op==0x37:
        typ = 'LUI'
    elif op==0x17:
        typ = 'AUIPC'

    print(f'0x{pc:04X} | {name:40s} | {typ:10s} | {note}')

# === Functional simulation (single-cycle) to find which branches are taken ===
print()
print('='*70)
print('分支结果分析 (确定哪些分支 taken)')
print('='*70)

regs = [0]*32
pc = 0

def se(v,b):
    if v&(1<<(b-1)): return v-(1<<b)
    return v

branches = []

while pc < len(words)*4:
    w = words[pc//4]
    d = decode(w)
    next_pc = pc + 4

    if d['op'] == 0x6F:  # JAL
        branches.append((pc, 'JAL', True, pc + d['ij']))
        if d['rd']: regs[d['rd']] = pc + 4
        next_pc = pc + d['ij']
    elif d['op'] == 0x67:  # JALR
        target = (regs[d['rs1']] + d['ii']) & ~1
        branches.append((pc, 'JALR', True, target))
        if d['rd']: regs[d['rd']] = pc + 4
        next_pc = target
    elif d['op'] == 0x63:  # Branch
        v1 = regs[d['rs1']]; v2 = regs[d['rs2']]
        taken = False
        if d['f3']==0: taken=(v1==v2)
        elif d['f3']==1: taken=(v1!=v2)
        elif d['f3']==4: taken=(se(v1,32)<se(v2,32))
        elif d['f3']==5: taken=(se(v1,32)>=se(v2,32))
        elif d['f3']==6: taken=((v1&0xFFFFFFFF)<(v2&0xFFFFFFFF))
        elif d['f3']==7: taken=((v1&0xFFFFFFFF)>=(v2&0xFFFFFFFF))
        branches.append((pc, inst_name(d), taken, pc + d['ib'] if taken else pc + 4))
        if taken:
            next_pc = pc + d['ib']
    elif d['op'] == 0x03:  # Load
        addr = regs[d['rs1']] + d['ii']
        base = addr & ~3
        data = words[base//4] if base//4 < len(words) else 0
        shift = (addr & 3) * 8
        if d['f3']==0: v=se((data>>shift)&0xFF,8)
        elif d['f3']==1: v=se((data>>shift)&0xFFFF,16)
        elif d['f3']==2: v=data
        elif d['f3']==4: v=(data>>shift)&0xFF
        elif d['f3']==5: v=(data>>shift)&0xFFFF
        else: v=0
        if d['rd']: regs[d['rd']] = v & 0xFFFFFFFF
    elif d['op'] == 0x37:
        if d['rd']: regs[d['rd']] = d['iu']
    elif d['op'] == 0x17:
        if d['rd']: regs[d['rd']] = (pc + d['iu']) & 0xFFFFFFFF
    elif d['op'] == 0x13:
        v = regs[d['rs1']]; imm = d['ii']; f3,f7 = d['f3'],d['f7']
        if f3==0: r=v+imm
        elif f3==1: r=v<<(imm&0x1F)
        elif f3==2: r=1 if se(v,32)<imm else 0
        elif f3==3: r=1 if (v&0xFFFFFFFF)<(imm&0xFFFFFFFF) else 0
        elif f3==4: r=v^imm
        elif f3==6: r=v|imm
        elif f3==7: r=v&imm
        elif f3==5:
            if f7==0x20: r=se(v,32)>>(imm&0x1F)
            else: r=v>>(imm&0x1F)
        else: r=0
        if d['rd']: regs[d['rd']] = r & 0xFFFFFFFF
    elif d['op'] == 0x33:
        v1=regs[d['rs1']]; v2=regs[d['rs2']]; f3,f7 = d['f3'],d['f7']
        if f3==0: r=v1-v2 if f7==0x20 else v1+v2  # NOTE: Verilog has SUB when funct7[5]=1
        elif f3==1: r=v1<<(v2&0x1F)
        elif f3==2: r=1 if se(v1,32)<se(v2,32) else 0
        elif f3==3: r=1 if (v1&0xFFFFFFFF)<(v2&0xFFFFFFFF) else 0
        elif f3==4: r=v1^v2
        elif f3==5: r=se(v1,32)>>(v2&0x1F) if f7==0x20 else v1>>(v2&0x1F)
        elif f3==6: r=v1|v2
        elif f3==7: r=v1&v2
        else: r=0
        if d['rd']: regs[d['rd']] = r & 0xFFFFFFFF

    if next_pc == pc:
        break
    pc = next_pc

for pc, name, taken, target in branches:
    status = 'TAKEN -> 0x%04X'%target if taken else 'NOT TAKEN'
    print(f'  PC=0x{pc:04X}: {name:40s} {status}')

# === Counts ===
jumps = sum(1 for b in branches if b[2])  # taken branches + all JAL/JALR
not_taken = sum(1 for b in branches if not b[2])

print()
print('='*70)
print('流水线事件统计')
print('='*70)

# Find load-use stalls
load_stalls = []
for i in range(len(words)-1):
    d = decode(words[i])
    if d['op'] == 0x03 and d['rd'] != 0:
        d2 = decode(words[i+1])
        ur1 = d2['op'] in [0x33,0x13,0x03,0x23,0x63,0x67]
        ur2 = d2['op'] in [0x33,0x23,0x63]
        if (ur1 and d2['rs1']==d['rd']) or (ur2 and d2['rs2']==d['rd']):
            load_stalls.append(i)

print(f'Load-use stall: {len(load_stalls)} 次')
for i in load_stalls:
    d1 = decode(words[i])
    d2 = decode(words[i+1])
    print(f'  PC=0x{i*4:04X} (load x{d1["rd"]}) -> PC=0x{(i+1)*4:04X} (use x{d1["rd"]}): 1 cycle stall')

print(f'')
print(f'Taken branch/jump (flush): {jumps} 次')
print(f'  - JAL: 3 次 (PC=0x0024,0x0048?, 0x0114)')
print(f'  - JALR: ? 次')
print(f'  - Branch taken: ? 次')
print(f'Not-taken branch: {not_taken} 次 (无 flush)')
print(f'')
print(f'每次 taken branch/jump flush 代价: 3 cycles (IF/ID/EX 全部清空)')
print(f'每次 load-use stall 代价: 1 cycle')
print(f'总 flush 代价: {jumps} x 3 = {jumps*3} cycles')
print(f'总 stall 代价: {len(load_stalls)} x 1 = {len(load_stalls)} cycles')
print(f'指令数: {len(words)} (最后一条 jal x30,0 是死循环)')
print(f'估算流水线总周期数: {len(words)} + {jumps*3} + {len(load_stalls)} + 4 (填充)')
print(f'单周期模型周期数: 68')

print()
print('='*70)
print('注意: 该CPU没有分支预测!')
print('每个taken branch/jal/jalr都会flush 3条已取指令(IF/ID/EX)')
print('='*70)
