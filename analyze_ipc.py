#!/usr/bin/env python
"""Precise pipeline IPC analysis for test7 on RISC-V 5-stage CPU."""

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
data_words = [0x89ABCDEF,0x01010101,0x02020202,0x03030330,0x04040404,
              0x05050505,0x06060606,0x07070770,0x08080808]

all_w = words + data_words
mem = {}
for i, w in enumerate(all_w):
    addr = i * 4
    for j in range(4):
        mem[addr+j] = (w >> (j*8)) & 0xFF

def rd_word(a):
    b = a & ~3
    return mem.get(b,0)|(mem.get(b+1,0)<<8)|(mem.get(b+2,0)<<16)|(mem.get(b+3,0)<<24)

def se(v,b):
    return v-(1<<b) if v&(1<<(b-1)) else v

def decode(w):
    op=w&0x7F;rd=(w>>7)&0x1F;f3=(w>>12)&7;rs1=(w>>15)&0x1F;rs2=(w>>20)&0x1F;f7=(w>>25)&0x7F
    return{'op':op,'rd':rd,'f3':f3,'rs1':rs1,'rs2':rs2,'f7':f7,
           'ii':se((w>>20)&0xFFF,12),
           'ib':se(((w>>31)<<12)|(((w>>7)&1)<<11)|(((w>>25)&0x3F)<<5)|(((w>>8)&0xF)<<1),13),
           'ij':se(((w>>31)<<20)|(((w>>12)&0xFF)<<12)|(((w>>20)&1)<<11)|(((w>>21)&0x3FF)<<1),21),
           'iu':w&0xFFFFF000}

regs=[0]*32; pc=0; imem_pc=0; imem_v=False; fb_v=False; fb_pc=0; fb_inst=0
ifid_v=False;ifid_pc=0;ifid_inst=0;idex_v=False;idex={};exmem_v=False;exmem={}
memwb_v=False;memwb_rd=0;memwb_wr=False;memwb_data=0
cyc=0;ret=0;st=0;fl=0;lu_st=0

while True:
    inst=rd_word(imem_pc) if imem_v else 0
    if memwb_v and memwb_wr and memwb_rd!=0:
        regs[memwb_rd]=memwb_data&0xFFFFFFFF
        ret+=1
    id_d=decode(ifid_inst) if ifid_v else None
    id_r1=regs[id_d['rs1'] if id_d else 0];id_r2=regs[id_d['rs2'] if id_d else 0]
    if memwb_v and memwb_wr and memwb_rd!=0:
        if memwb_rd==(id_d['rs1'] if id_d else 0): id_r1=memwb_data
        if memwb_rd==(id_d['rs2'] if id_d else 0): id_r2=memwb_data
    f2id_v=fb_v or imem_v; f2id_pc=fb_pc if fb_v else imem_pc
    f2id_inst=fb_inst if fb_v else inst
    lu=False
    if idex_v and idex.get('ml') and idex['rd']!=0 and ifid_v and id_d:
        u1=id_d['op'] in[0x33,0x13,0x03,0x23,0x63,0x67]
        u2=id_d['op'] in[0x33,0x23,0x63]
        if(u1 and id_d['rs1']==idex['rd'])or(u2 and id_d['rs2']==idex['rd']): lu=True
    ex_r1=idex.get('r1',0);ex_r2=idex.get('r2',0)
    if exmem_v and exmem.get('wr')and exmem['rd']!=0:
        if exmem['rd']==idex.get('rs1',0):ex_r1=exmem['wd']
        if exmem['rd']==idex.get('rs2',0):ex_r2=exmem['wd']
    if memwb_v and memwb_wr and memwb_rd!=0:
        if memwb_rd==idex.get('rs1',0):ex_r1=memwb_data
        if memwb_rd==idex.get('rs2',0):ex_r2=memwb_data
    ex_res=0;ex_ma=0;ex_fl=False;ex_bt=0
    if idex_v:
        d=idex;op=d['op'];f3=d['f3'];f7=d['f7']
        if d.get('ar')or d.get('ai'):
            r2=ex_r2 if d.get('ar')else 0;imm=d.get('imm',0)
            if f3==0:
                if op==0x33 and f7==0x20: ex_res=ex_r1-r2
                elif op==0x33: ex_res=ex_r1+r2
                else: ex_res=ex_r1+imm
            elif f3==1: ex_res=ex_r1<<((r2 if op==0x33 else imm)&0x1F)
            elif f3==2: ex_res=1 if se(ex_r1,32)<(se(r2,32)if op==0x33 else imm)else 0
            elif f3==3: ex_res=1 if(ex_r1&0xFFFFFFFF)<((r2&0xFFFFFFFF)if op==0x33 else(imm&0xFFFFFFFF))else 0
            elif f3==4: ex_res=ex_r1^(r2 if op==0x33 else imm)
            elif f3==6: ex_res=ex_r1|(r2 if op==0x33 else imm)
            elif f3==7: ex_res=ex_r1&(r2 if op==0x33 else imm)
            elif f3==5:
                sh=((r2 if op==0x33 else imm)&0x1F)
                if op==0x33 and f7==0x20: ex_res=se(ex_r1,32)>>sh
                elif op==0x33: ex_res=ex_r1>>sh
                else: ex_res=se(ex_r1,32)>>sh if(imm&0x400)else ex_r1>>sh
        elif d.get('ls'): ex_ma=ex_r1+d.get('imm',0)
        elif d.get('lu'): ex_res=d.get('iu',0)
        elif d.get('au'): ex_res=(d.get('pc',0)+d.get('iu',0))&0xFFFFFFFF
        elif d.get('jl')or d.get('jr'): ex_res=d.get('pc',0)+4
        if d.get('jl'): ex_fl=True;ex_bt=d.get('pc',0)+d.get('ij',0)
        elif d.get('jr'): ex_fl=True;ex_bt=(ex_r1+d.get('imm',0))&~1
        elif d.get('br'):
            v1=ex_r1;v2=ex_r2;t=False
            if f3==0:t=(v1==v2)
            elif f3==1:t=(v1!=v2)
            elif f3==4:t=(se(v1,32)<se(v2,32))
            elif f3==5:t=(se(v1,32)>=se(v2,32))
            elif f3==6:t=((v1&0xFFFFFFFF)<(v2&0xFFFFFFFF))
            elif f3==7:t=((v1&0xFFFFFFFF)>=(v2&0xFFFFFFFF))
            if t: ex_fl=True;ex_bt=d.get('pc',0)+d.get('ib',0)
    flush=ex_fl
    if exmem_v:
        memwb_v=True;memwb_rd=exmem['rd'];memwb_wr=exmem['wr']
        if exmem.get('ml'):
            a=exmem.get('ma',0);b=a&~3;dw=rd_word(b);sh=(a&3)*8
            mb=exmem.get('mb',0);ul=exmem.get('ul',False)
            if mb in[0,4]:sz=0
            elif mb in[1,5]:sz=1
            else:sz=2
            sgn=not(mb in[4,5]or ul)
            if sz==0:v=(dw>>sh)&0xFF;memwb_data=se(v,8)if sgn else v
            elif sz==1:v=(dw>>sh)&0xFFFF;memwb_data=se(v,16)if sgn else v
            else:memwb_data=dw
        else:memwb_data=exmem['wd']
    else:memwb_v=False
    if flush:
        fl+=1;pc=ex_bt&0xFFFFFFFF;imem_pc=pc;imem_v=False
        fb_v=False;ifid_v=False;idex_v=False;exmem_v=False
    elif lu:
        lu_st+=1;st+=1
        if not fb_v and imem_v: fb_v=True;fb_pc=imem_pc;fb_inst=inst
        imem_pc=pc;imem_v=True;idex_v=False
    else:
        pc+=4;imem_pc=pc;imem_v=True
        if fb_v:fb_v=False
        ifid_v=f2id_v;ifid_pc=f2id_pc;ifid_inst=f2id_inst
        idex_v=ifid_v
        if idex_v and id_d:
            d=id_d
            idex={'op':d['op'],'pc':ifid_pc,'rd':d['rd'],'f3':d['f3'],'f7':d['f7'],
                  'rs1':d['rs1'],'rs2':d['rs2'],'r1':id_r1,'r2':id_r2,
                  'ar':d['op']==0x33,'ai':d['op']==0x13,
                  'lu':d['op']==0x37,'au':d['op']==0x17,
                  'jl':d['op']==0x6F,'jr':d['op']==0x67,'br':d['op']==0x63,
                  'ls':d['op']in[0x03,0x23],'ml':d['op']==0x03,
                  'imm':d['ii']if d['op']in[0x13,0x03,0x67]else(d['ij']if d['op']==0x6F else 0),
                  'iu':d['iu'],'ij':d['ij'],'ib':d['ib'],
                  'wr':d['op']in[0x33,0x13,0x03,0x37,0x17,0x6F,0x67],
                  'mb':{0:0,1:1,2:15,4:4,5:5}.get(d['f3'],0)if d['op']in[0x03,0x23]else 0,
                  'ul':d['f3']in[4,5]if d['op']==0x03 else False}
        else:idex_v=False
    exmem_v=idex_v and not flush
    if exmem_v:
        exmem={'rd':idex['rd'],'wr':idex.get('wr',False),
               'ml':idex.get('ml',False),'ma':ex_ma,
               'mb':idex.get('mb',0),'ul':idex.get('ul',False),'wd':ex_res}
    if exmem_v and idex.get('ls')and not idex.get('ml'):
        a=ex_ma;val=ex_r2;b=a&~3
        sz=2
        if idex.get('mb',0)in[0]:sz=0
        elif idex.get('mb',0)in[1]:sz=1
        if sz==0:
            sh=(a&3)*8;old=rd_word(b);new=(old&~(0xFF<<sh))|((val&0xFF)<<sh)
            for j in range(4):mem[b+j]=(new>>(j*8))&0xFF
        elif sz==1:
            sh=(a&3)*8;old=rd_word(b);new=(old&~(0xFFFF<<sh))|((val&0xFFFF)<<sh)
            for j in range(4):mem[b+j]=(new>>(j*8))&0xFF
        else:
            for j in range(4):mem[b+j]=(val>>(j*8))&0xFF
    cyc+=1
    if ret >= 65: break

print(f'Total cycles: {cyc}')
print(f'Instructions retired: {ret}')
print(f'IPC = {ret}/{cyc} = {ret/cyc:.3f}')
print(f'CPI = {cyc/ret:.3f}')
print(f'Load-use stalls: {lu_st}')
print(f'Branch/jump flushes: {fl}')
print(f'Total wasted cycles: {lu_st + fl*3}')
print(f'Stall rate: {lu_st/cyc*100:.1f}%')
print(f'Flush rate: {fl/cyc*100:.1f}%')
print(f'Bubble rate: {(lu_st+fl*3)/cyc*100:.1f}%')
