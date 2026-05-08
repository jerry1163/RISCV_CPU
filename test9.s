        li     x1,  0x7fffffff
        li     x2,  0xffffffff
        li     x31, 0x320
        mul    x3, x2, x1
        mulh   x4, x2, x1
        mulhu  x5, x2, x1
        mulhsu x6, x2, x1
        mulhsu x7, x1, x2
        div    x8, x1, x2
        div    x9, x2, x1
        rem    x10,x2, x1
        divu   x11,x2, x1
        remu   x12,x2, x1
        bgeu   x12,x11,dddd
        sw     x3, 12(x31)
        sw     x4, 16(x31)
        sw     x5, 20(x31)
        sw     x6, 24(x31)
        sw     x7, 28(x31)
        sw     x8, 32(x31)
        sw     x9, 36(x31)
        sw     x10, 40(x31)
        sw     x11, 44(x31)
        sw     x12, 48(x31)
dddd:   jal    x30, dddd
.end
