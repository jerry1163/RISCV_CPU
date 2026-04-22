#!/usr/bin/env python3
"""Small RV32I single-cycle simulator for this project.

The code is intentionally organized like the Verilog datapath:
fetch -> decode/imm -> execute/branch -> memory -> write-back.

It supports the RV32I subset used by test6/test7:
R-type ALU, I-type ALU, loads/stores of byte/half/word, branches,
jal/jalr, lui, and auipc.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


MASK32 = 0xFFFFFFFF


def u32(value: int) -> int:
    return value & MASK32


def s32(value: int) -> int:
    value &= MASK32
    return value - 0x100000000 if value & 0x80000000 else value


def sign_extend(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    sign = 1 << (bits - 1)
    return value - (1 << bits) if value & sign else value


def parse_coe_words(path: Path) -> List[int]:
    words: List[int] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("memory_"):
            continue
        line = line.rstrip(",;").strip()
        if not line:
            continue
        words.append(int(line, 16) & MASK32)
    return words


def reg_name(index: int) -> str:
    return f"x{index}"


def load_words_little_endian(memory: Dict[int, int], words: Iterable[int], base: int = 0) -> None:
    for word_index, word in enumerate(words):
        addr = base + word_index * 4
        for byte_index in range(4):
            memory[addr + byte_index] = (word >> (8 * byte_index)) & 0xFF


LOAD_NAMES = {"lb", "lh", "lw", "lbu", "lhu"}
STORE_NAMES = {"sb", "sh", "sw"}
BRANCH_NAMES = {"beq", "bne", "blt", "bge", "bltu", "bgeu"}
R_ALU_NAMES = {"add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"}
I_ALU_NAMES = {"addi", "slti", "sltiu", "xori", "ori", "andi", "slli", "srli", "srai"}


def instruction_sources(dec: "DecodedInstruction") -> Tuple[int, ...]:
    """Return the register source indexes really consumed by an instruction."""
    if dec.name in R_ALU_NAMES or dec.name in STORE_NAMES or dec.name in BRANCH_NAMES:
        return dec.rs1, dec.rs2
    if dec.name in I_ALU_NAMES or dec.name in LOAD_NAMES or dec.name == "jalr":
        return (dec.rs1,)
    return ()


@dataclass
class DecodedInstruction:
    inst: int
    opcode: int
    rd: int
    funct3: int
    rs1: int
    rs2: int
    funct7: int
    name: str
    imm: int = 0

    @property
    def writes_rd(self) -> bool:
        return self.rd != 0 and self.name not in {
            "sb",
            "sh",
            "sw",
            "beq",
            "bne",
            "blt",
            "bge",
            "bltu",
            "bgeu",
            "unknown",
            "system",
            "nop",
        }


@dataclass
class StepInfo:
    cycle: int
    pc: int
    inst: int
    asm: str
    next_pc: int
    rd: Optional[int] = None
    rd_value: Optional[int] = None
    mem: Optional[str] = None


@dataclass
class PipeReg:
    valid: bool = False
    pc: int = 0
    inst: int = 0
    dec: Optional[DecodedInstruction] = None
    asm: str = "bubble"
    rs1_val: int = 0
    rs2_val: int = 0
    alu_result: int = 0
    store_data: int = 0
    wb_value: int = 0
    mem: Optional[str] = None
    halt_after: bool = False


@dataclass
class PipelineCycleInfo:
    cycle: int
    pc: int
    if_stage: str
    id_stage: str
    ex_stage: str
    mem_stage: str
    wb_stage: str
    stall: bool = False
    flush: bool = False
    forward_a: str = "REG"
    forward_b: str = "REG"
    mem: Optional[str] = None
    wb: Optional[str] = None


class RiscVSingleCycleSim:
    def __init__(
        self,
        memory: Optional[Dict[int, int]] = None,
        inst_memory: Optional[Dict[int, int]] = None,
        max_addr_mask: int = MASK32,
    ):
        self.regs = [0] * 32
        self.pc = 0
        self.cycle = 0
        self.memory: Dict[int, int] = dict(memory or {})
        self.inst_memory: Dict[int, int] = self.memory if inst_memory is None else dict(inst_memory)
        self.max_addr_mask = max_addr_mask
        self.halted = False
        self.halt_reason = ""
        self.history: List[StepInfo] = []

    @classmethod
    def from_tdp_coe(cls, path: Path) -> "RiscVSingleCycleSim":
        memory: Dict[int, int] = {}
        load_words_little_endian(memory, parse_coe_words(path))
        return cls(memory)

    @classmethod
    def from_split_coe(cls, inst_path: Path, data_path: Path) -> "RiscVSingleCycleSim":
        inst_memory: Dict[int, int] = {}
        data_memory: Dict[int, int] = {}
        load_words_little_endian(inst_memory, parse_coe_words(inst_path), base=0)
        load_words_little_endian(data_memory, parse_coe_words(data_path), base=0)
        return cls(data_memory, inst_memory=inst_memory)

    def norm_addr(self, addr: int) -> int:
        return addr & self.max_addr_mask

    def read_u8(self, addr: int) -> int:
        return self.memory.get(self.norm_addr(addr), 0) & 0xFF

    def read_inst_u8(self, addr: int) -> int:
        return self.inst_memory.get(self.norm_addr(addr), 0) & 0xFF

    def write_u8(self, addr: int, value: int) -> None:
        self.memory[self.norm_addr(addr)] = value & 0xFF

    def read_u16(self, addr: int) -> int:
        return self.read_u8(addr) | (self.read_u8(addr + 1) << 8)

    def write_u16(self, addr: int, value: int) -> None:
        self.write_u8(addr, value)
        self.write_u8(addr + 1, value >> 8)

    def read_u32(self, addr: int) -> int:
        return (
            self.read_u8(addr)
            | (self.read_u8(addr + 1) << 8)
            | (self.read_u8(addr + 2) << 16)
            | (self.read_u8(addr + 3) << 24)
        )

    def write_u32(self, addr: int, value: int) -> None:
        for byte_index in range(4):
            self.write_u8(addr + byte_index, value >> (8 * byte_index))

    def fetch(self) -> int:
        return (
            self.read_inst_u8(self.pc)
            | (self.read_inst_u8(self.pc + 1) << 8)
            | (self.read_inst_u8(self.pc + 2) << 16)
            | (self.read_inst_u8(self.pc + 3) << 24)
        )

    def decode(self, inst: int) -> DecodedInstruction:
        opcode = inst & 0x7F
        rd = (inst >> 7) & 0x1F
        funct3 = (inst >> 12) & 0x7
        rs1 = (inst >> 15) & 0x1F
        rs2 = (inst >> 20) & 0x1F
        funct7 = (inst >> 25) & 0x7F

        name = "unknown"
        imm = 0

        if opcode == 0x37:
            name = "lui"
            imm = inst & 0xFFFFF000
        elif opcode == 0x17:
            name = "auipc"
            imm = inst & 0xFFFFF000
        elif opcode == 0x6F:
            name = "jal"
            imm_raw = (
                ((inst >> 31) & 0x1) << 20
                | ((inst >> 12) & 0xFF) << 12
                | ((inst >> 20) & 0x1) << 11
                | ((inst >> 21) & 0x3FF) << 1
            )
            imm = sign_extend(imm_raw, 21)
        elif opcode == 0x67:
            name = "jalr"
            imm = sign_extend(inst >> 20, 12)
        elif opcode == 0x63:
            branch_names = {
                0b000: "beq",
                0b001: "bne",
                0b100: "blt",
                0b101: "bge",
                0b110: "bltu",
                0b111: "bgeu",
            }
            name = branch_names.get(funct3, "unknown")
            imm_raw = (
                ((inst >> 31) & 0x1) << 12
                | ((inst >> 7) & 0x1) << 11
                | ((inst >> 25) & 0x3F) << 5
                | ((inst >> 8) & 0xF) << 1
            )
            imm = sign_extend(imm_raw, 13)
        elif opcode == 0x03:
            load_names = {
                0b000: "lb",
                0b001: "lh",
                0b010: "lw",
                0b100: "lbu",
                0b101: "lhu",
            }
            name = load_names.get(funct3, "unknown")
            imm = sign_extend(inst >> 20, 12)
        elif opcode == 0x23:
            store_names = {
                0b000: "sb",
                0b001: "sh",
                0b010: "sw",
            }
            name = store_names.get(funct3, "unknown")
            imm_raw = ((inst >> 25) << 5) | rd
            imm = sign_extend(imm_raw, 12)
        elif opcode == 0x13:
            if funct3 == 0b001:
                name = "slli"
                imm = (inst >> 20) & 0x1F
            elif funct3 == 0b101:
                name = "srai" if funct7 == 0x20 else "srli"
                imm = (inst >> 20) & 0x1F
            else:
                op_imm_names = {
                    0b000: "addi",
                    0b010: "slti",
                    0b011: "sltiu",
                    0b100: "xori",
                    0b110: "ori",
                    0b111: "andi",
                }
                name = op_imm_names.get(funct3, "unknown")
                imm = sign_extend(inst >> 20, 12)
        elif opcode == 0x33:
            r_names = {
                (0b000, 0x00): "add",
                (0b000, 0x20): "sub",
                (0b001, 0x00): "sll",
                (0b010, 0x00): "slt",
                (0b011, 0x00): "sltu",
                (0b100, 0x00): "xor",
                (0b101, 0x00): "srl",
                (0b101, 0x20): "sra",
                (0b110, 0x00): "or",
                (0b111, 0x00): "and",
            }
            name = r_names.get((funct3, funct7), "unknown")
        elif opcode == 0x73:
            name = "system"

        return DecodedInstruction(inst, opcode, rd, funct3, rs1, rs2, funct7, name, imm)

    def format_asm(self, dec: DecodedInstruction, pc: int) -> str:
        n = dec.name
        if n in {"add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and"}:
            return f"{n} {reg_name(dec.rd)}, {reg_name(dec.rs1)}, {reg_name(dec.rs2)}"
        if n in {"addi", "slti", "sltiu", "xori", "ori", "andi"}:
            return f"{n} {reg_name(dec.rd)}, {reg_name(dec.rs1)}, {dec.imm}"
        if n in {"slli", "srli", "srai"}:
            return f"{n} {reg_name(dec.rd)}, {reg_name(dec.rs1)}, {dec.imm}"
        if n in {"lb", "lh", "lw", "lbu", "lhu"}:
            return f"{n} {reg_name(dec.rd)}, {dec.imm}({reg_name(dec.rs1)})"
        if n in {"sb", "sh", "sw"}:
            return f"{n} {reg_name(dec.rs2)}, {dec.imm}({reg_name(dec.rs1)})"
        if n in {"beq", "bne", "blt", "bge", "bltu", "bgeu"}:
            return f"{n} {reg_name(dec.rs1)}, {reg_name(dec.rs2)}, 0x{u32(pc + dec.imm):08x}"
        if n == "jal":
            return f"jal {reg_name(dec.rd)}, 0x{u32(pc + dec.imm):08x}"
        if n == "jalr":
            return f"jalr {reg_name(dec.rd)}, {dec.imm}({reg_name(dec.rs1)})"
        if n == "lui":
            return f"lui {reg_name(dec.rd)}, 0x{dec.imm >> 12:x}"
        if n == "auipc":
            return f"auipc {reg_name(dec.rd)}, 0x{dec.imm >> 12:x}"
        if n == "system":
            return "system"
        return f"unknown 0x{dec.inst:08x}"

    def execute_alu(self, dec: DecodedInstruction) -> Optional[int]:
        a = self.regs[dec.rs1]
        b = self.regs[dec.rs2]
        imm = dec.imm
        n = dec.name

        if n == "add":
            return u32(a + b)
        if n == "sub":
            return u32(a - b)
        if n == "sll":
            return u32(a << (b & 0x1F))
        if n == "slt":
            return 1 if s32(a) < s32(b) else 0
        if n == "sltu":
            return 1 if a < b else 0
        if n == "xor":
            return u32(a ^ b)
        if n == "srl":
            return u32(a >> (b & 0x1F))
        if n == "sra":
            return u32(s32(a) >> (b & 0x1F))
        if n == "or":
            return u32(a | b)
        if n == "and":
            return u32(a & b)

        if n == "addi":
            return u32(a + imm)
        if n == "slti":
            return 1 if s32(a) < imm else 0
        if n == "sltiu":
            return 1 if a < u32(imm) else 0
        if n == "xori":
            return u32(a ^ u32(imm))
        if n == "ori":
            return u32(a | u32(imm))
        if n == "andi":
            return u32(a & u32(imm))
        if n == "slli":
            return u32(a << imm)
        if n == "srli":
            return u32(a >> imm)
        if n == "srai":
            return u32(s32(a) >> imm)

        return None

    def branch_taken(self, dec: DecodedInstruction) -> bool:
        a = self.regs[dec.rs1]
        b = self.regs[dec.rs2]
        n = dec.name
        if n == "beq":
            return a == b
        if n == "bne":
            return a != b
        if n == "blt":
            return s32(a) < s32(b)
        if n == "bge":
            return s32(a) >= s32(b)
        if n == "bltu":
            return a < b
        if n == "bgeu":
            return a >= b
        return False

    def step(self, stop_on_self_loop: bool = True) -> StepInfo:
        if self.halted:
            raise RuntimeError(f"simulator halted: {self.halt_reason}")

        pc = self.pc
        inst = self.fetch()
        dec = self.decode(inst)
        asm = self.format_asm(dec, pc)
        next_pc = u32(pc + 4)
        rd_value: Optional[int] = None
        mem_desc: Optional[str] = None

        if dec.name == "unknown":
            self.halted = True
            self.halt_reason = f"unknown instruction 0x{inst:08x} at 0x{pc:08x}"
        elif dec.name == "system":
            self.halted = True
            self.halt_reason = f"system instruction at 0x{pc:08x}"
        elif dec.name == "lui":
            rd_value = u32(dec.imm)
        elif dec.name == "auipc":
            rd_value = u32(pc + dec.imm)
        elif dec.name == "jal":
            rd_value = u32(pc + 4)
            next_pc = u32(pc + dec.imm)
        elif dec.name == "jalr":
            rd_value = u32(pc + 4)
            next_pc = u32((self.regs[dec.rs1] + dec.imm) & ~1)
        elif dec.name in {"beq", "bne", "blt", "bge", "bltu", "bgeu"}:
            if self.branch_taken(dec):
                next_pc = u32(pc + dec.imm)
        elif dec.name in {"lb", "lh", "lw", "lbu", "lhu"}:
            addr = u32(self.regs[dec.rs1] + dec.imm)
            if dec.name == "lb":
                rd_value = u32(sign_extend(self.read_u8(addr), 8))
            elif dec.name == "lh":
                rd_value = u32(sign_extend(self.read_u16(addr), 16))
            elif dec.name == "lw":
                rd_value = self.read_u32(addr)
            elif dec.name == "lbu":
                rd_value = self.read_u8(addr)
            elif dec.name == "lhu":
                rd_value = self.read_u16(addr)
            mem_desc = f"load {dec.name} [0x{addr:08x}] -> 0x{rd_value:08x}"
        elif dec.name in {"sb", "sh", "sw"}:
            addr = u32(self.regs[dec.rs1] + dec.imm)
            value = self.regs[dec.rs2]
            if dec.name == "sb":
                self.write_u8(addr, value)
                mem_desc = f"store sb 0x{value & 0xFF:02x} -> [0x{addr:08x}]"
            elif dec.name == "sh":
                self.write_u16(addr, value)
                mem_desc = f"store sh 0x{value & 0xFFFF:04x} -> [0x{addr:08x}]"
            else:
                self.write_u32(addr, value)
                mem_desc = f"store sw 0x{value:08x} -> [0x{addr:08x}]"
        else:
            rd_value = self.execute_alu(dec)

        if rd_value is not None and dec.rd != 0:
            self.regs[dec.rd] = u32(rd_value)
        self.regs[0] = 0

        self.pc = next_pc
        self.cycle += 1

        info = StepInfo(
            cycle=self.cycle,
            pc=pc,
            inst=inst,
            asm=asm,
            next_pc=next_pc,
            rd=dec.rd if rd_value is not None and dec.rd != 0 else None,
            rd_value=u32(rd_value) if rd_value is not None and dec.rd != 0 else None,
            mem=mem_desc,
        )
        self.history.append(info)

        if stop_on_self_loop and dec.name == "jal" and next_pc == pc:
            self.halted = True
            self.halt_reason = f"self-loop jal at 0x{pc:08x}"

        return info

    def run(self, max_cycles: int = 1000, stop_on_self_loop: bool = True) -> None:
        while not self.halted and self.cycle < max_cycles:
            self.step(stop_on_self_loop=stop_on_self_loop)
        if not self.halted and self.cycle >= max_cycles:
            self.halted = True
            self.halt_reason = f"max cycle limit {max_cycles} reached"

    def dump_registers(self, first: int = 1, last: int = 31) -> str:
        lines = []
        for index in range(first, last + 1):
            lines.append(f"x{index:02d}=0x{self.regs[index]:08x}")
        return "\n".join(lines)

    def dump_words(self, base: int, count: int) -> str:
        lines = []
        for i in range(count):
            addr = base + i * 4
            lines.append(f"0x{addr:08x}: 0x{self.read_u32(addr):08x}")
        return "\n".join(lines)

    def dump_bytes(self, base: int, count: int) -> str:
        lines = []
        for offset in range(0, count, 16):
            chunk = [self.read_u8(base + offset + i) for i in range(min(16, count - offset))]
            text = " ".join(f"{b:02x}" for b in chunk)
            lines.append(f"0x{base + offset:08x}: {text}")
        return "\n".join(lines)


class RiscVPipelineSim(RiscVSingleCycleSim):
    """Five-stage pipeline simulator with forwarding, stall, and flush logic."""

    def __init__(
        self,
        memory: Optional[Dict[int, int]] = None,
        inst_memory: Optional[Dict[int, int]] = None,
        max_addr_mask: int = MASK32,
    ):
        super().__init__(memory=memory, inst_memory=inst_memory, max_addr_mask=max_addr_mask)
        self.if_id = PipeReg()
        self.id_ex = PipeReg()
        self.ex_mem = PipeReg()
        self.mem_wb = PipeReg()
        self.pipe_history: List[PipelineCycleInfo] = []
        self.halt_pending = False
        self.halt_marker_committed = False
        self.self_loop_pc: Optional[int] = None

    def pipe_reg_writes(self, reg: PipeReg) -> bool:
        return bool(reg.valid and reg.dec and reg.dec.writes_rd and reg.dec.rd != 0)

    def pipe_reg_is_load(self, reg: PipeReg) -> bool:
        return bool(reg.valid and reg.dec and reg.dec.name in LOAD_NAMES)

    def format_pipe_reg(self, reg: PipeReg) -> str:
        if not reg.valid:
            return "bubble"
        return f"pc=0x{reg.pc:08x} {reg.asm}"

    def execute_alu_values(self, dec: DecodedInstruction, a: int, b: int) -> Optional[int]:
        imm = dec.imm
        n = dec.name

        if n == "add":
            return u32(a + b)
        if n == "sub":
            return u32(a - b)
        if n == "sll":
            return u32(a << (b & 0x1F))
        if n == "slt":
            return 1 if s32(a) < s32(b) else 0
        if n == "sltu":
            return 1 if a < b else 0
        if n == "xor":
            return u32(a ^ b)
        if n == "srl":
            return u32(a >> (b & 0x1F))
        if n == "sra":
            return u32(s32(a) >> (b & 0x1F))
        if n == "or":
            return u32(a | b)
        if n == "and":
            return u32(a & b)

        if n == "addi":
            return u32(a + imm)
        if n == "slti":
            return 1 if s32(a) < imm else 0
        if n == "sltiu":
            return 1 if a < u32(imm) else 0
        if n == "xori":
            return u32(a ^ u32(imm))
        if n == "ori":
            return u32(a | u32(imm))
        if n == "andi":
            return u32(a & u32(imm))
        if n == "slli":
            return u32(a << imm)
        if n == "srli":
            return u32(a >> imm)
        if n == "srai":
            return u32(s32(a) >> imm)

        return None

    def branch_taken_values(self, dec: DecodedInstruction, a: int, b: int) -> bool:
        if dec.name == "beq":
            return a == b
        if dec.name == "bne":
            return a != b
        if dec.name == "blt":
            return s32(a) < s32(b)
        if dec.name == "bge":
            return s32(a) >= s32(b)
        if dec.name == "bltu":
            return a < b
        if dec.name == "bgeu":
            return a >= b
        return False

    def select_forward(self, src: int, original: int) -> Tuple[int, str]:
        if src == 0:
            return 0, "x0"
        if (
            self.pipe_reg_writes(self.ex_mem)
            and self.ex_mem.dec
            and self.ex_mem.dec.rd == src
            and self.ex_mem.dec.name not in LOAD_NAMES
        ):
            return self.ex_mem.wb_value, "EX/MEM"
        if self.pipe_reg_writes(self.mem_wb) and self.mem_wb.dec and self.mem_wb.dec.rd == src:
            return self.mem_wb.wb_value, "MEM/WB"
        return original, "REG"

    def load_use_stall(self) -> bool:
        if not self.pipe_reg_is_load(self.id_ex) or not self.if_id.valid or not self.id_ex.dec:
            return False
        load_rd = self.id_ex.dec.rd
        if load_rd == 0:
            return False
        id_dec = self.decode(self.if_id.inst)
        return load_rd in instruction_sources(id_dec)

    def load_value(self, name: str, addr: int) -> int:
        if name == "lb":
            return u32(sign_extend(self.read_u8(addr), 8))
        if name == "lh":
            return u32(sign_extend(self.read_u16(addr), 16))
        if name == "lw":
            return self.read_u32(addr)
        if name == "lbu":
            return self.read_u8(addr)
        if name == "lhu":
            return self.read_u16(addr)
        raise ValueError(f"not a load: {name}")

    def store_value(self, name: str, addr: int, value: int) -> str:
        if name == "sb":
            self.write_u8(addr, value)
            return f"store sb 0x{value & 0xFF:02x} -> [0x{addr:08x}]"
        if name == "sh":
            self.write_u16(addr, value)
            return f"store sh 0x{value & 0xFFFF:04x} -> [0x{addr:08x}]"
        if name == "sw":
            self.write_u32(addr, value)
            return f"store sw 0x{value:08x} -> [0x{addr:08x}]"
        raise ValueError(f"not a store: {name}")

    def make_id_ex(self, if_id: PipeReg) -> PipeReg:
        if not if_id.valid:
            return PipeReg()
        dec = self.decode(if_id.inst)
        return PipeReg(
            valid=True,
            pc=if_id.pc,
            inst=if_id.inst,
            dec=dec,
            asm=self.format_asm(dec, if_id.pc),
            rs1_val=self.regs[dec.rs1],
            rs2_val=self.regs[dec.rs2],
        )

    def step(self, stop_on_self_loop: bool = True) -> PipelineCycleInfo:
        if self.halted:
            raise RuntimeError(f"simulator halted: {self.halt_reason}")

        cycle = self.cycle + 1
        stage_if = f"pc=0x{self.pc:08x}"
        stage_id = self.format_pipe_reg(self.if_id)
        stage_ex = self.format_pipe_reg(self.id_ex)
        stage_mem = self.format_pipe_reg(self.ex_mem)
        stage_wb = self.format_pipe_reg(self.mem_wb)
        wb_desc: Optional[str] = None
        mem_desc: Optional[str] = None

        # WB: commit the value from the previous MEM/WB register first. This
        # gives ID-stage register reads the same-cycle write behavior that most
        # simple FPGA register files rely on.
        if self.mem_wb.valid and self.mem_wb.dec:
            if self.pipe_reg_writes(self.mem_wb):
                self.regs[self.mem_wb.dec.rd] = u32(self.mem_wb.wb_value)
                wb_desc = f"{reg_name(self.mem_wb.dec.rd)}=0x{self.mem_wb.wb_value:08x}"
            if self.mem_wb.halt_after:
                self.halt_marker_committed = True
        self.regs[0] = 0

        # MEM: loads and stores use the data port. IF can still fetch through
        # the instruction port, matching a true dual-port RAM.
        next_mem_wb = PipeReg()
        if self.ex_mem.valid and self.ex_mem.dec:
            dec = self.ex_mem.dec
            next_mem_wb = PipeReg(
                valid=True,
                pc=self.ex_mem.pc,
                inst=self.ex_mem.inst,
                dec=dec,
                asm=self.ex_mem.asm,
                alu_result=self.ex_mem.alu_result,
                wb_value=self.ex_mem.wb_value,
                halt_after=self.ex_mem.halt_after,
            )
            if dec.name in LOAD_NAMES:
                value = self.load_value(dec.name, self.ex_mem.alu_result)
                next_mem_wb.wb_value = value
                mem_desc = f"load {dec.name} [0x{self.ex_mem.alu_result:08x}] -> 0x{value:08x}"
            elif dec.name in STORE_NAMES:
                mem_desc = self.store_value(dec.name, self.ex_mem.alu_result, self.ex_mem.store_data)
            next_mem_wb.mem = mem_desc

        # EX: ALU, branch, and jump target calculation. Source operands are
        # forwarded here, including store data.
        next_ex_mem = PipeReg()
        flush = False
        branch_target = u32(self.pc + 4)
        forward_a = "REG"
        forward_b = "REG"

        if self.id_ex.valid and self.id_ex.dec:
            dec = self.id_ex.dec
            if dec.name in {"unknown", "system"}:
                self.halted = True
                self.halt_reason = f"{dec.name} instruction 0x{dec.inst:08x} reached EX at 0x{self.id_ex.pc:08x}"

            srcs = instruction_sources(dec)
            a = self.id_ex.rs1_val
            b = self.id_ex.rs2_val
            if dec.rs1 in srcs:
                a, forward_a = self.select_forward(dec.rs1, self.id_ex.rs1_val)
            if dec.rs2 in srcs:
                b, forward_b = self.select_forward(dec.rs2, self.id_ex.rs2_val)

            wb_value = 0
            alu_result = 0
            store_data = b
            halt_after = False

            if dec.name == "lui":
                wb_value = u32(dec.imm)
            elif dec.name == "auipc":
                wb_value = u32(self.id_ex.pc + dec.imm)
            elif dec.name == "jal":
                wb_value = u32(self.id_ex.pc + 4)
                branch_target = u32(self.id_ex.pc + dec.imm)
                flush = True
            elif dec.name == "jalr":
                wb_value = u32(self.id_ex.pc + 4)
                branch_target = u32((a + dec.imm) & ~1)
                flush = True
            elif dec.name in BRANCH_NAMES:
                if self.branch_taken_values(dec, a, b):
                    branch_target = u32(self.id_ex.pc + dec.imm)
                    flush = True
            elif dec.name in LOAD_NAMES or dec.name in STORE_NAMES:
                alu_result = u32(a + dec.imm)
            else:
                alu_value = self.execute_alu_values(dec, a, b)
                wb_value = 0 if alu_value is None else alu_value

            if dec.name not in LOAD_NAMES and dec.name not in STORE_NAMES:
                alu_result = wb_value

            if stop_on_self_loop and dec.name == "jal" and branch_target == self.id_ex.pc:
                self.halt_pending = True
                self.self_loop_pc = self.id_ex.pc
                halt_after = True

            next_ex_mem = PipeReg(
                valid=True,
                pc=self.id_ex.pc,
                inst=self.id_ex.inst,
                dec=dec,
                asm=self.id_ex.asm,
                alu_result=alu_result,
                store_data=u32(store_data),
                wb_value=u32(wb_value),
                halt_after=halt_after,
            )

        stall = self.load_use_stall()

        # ID and IF update. A taken branch/jump wins over a load-use stall
        # because the ID instruction is on the wrong path and must be killed.
        if flush:
            next_id_ex = PipeReg()
            next_if_id = PipeReg()
            next_pc = branch_target
        elif stall:
            next_id_ex = PipeReg()
            next_if_id = self.if_id
            next_pc = self.pc
        else:
            next_id_ex = self.make_id_ex(self.if_id)
            if self.halt_pending:
                next_if_id = PipeReg()
                next_pc = self.pc
            else:
                inst = self.fetch()
                dec = self.decode(inst)
                next_if_id = PipeReg(
                    valid=True,
                    pc=self.pc,
                    inst=inst,
                    dec=dec,
                    asm=self.format_asm(dec, self.pc),
                )
                next_pc = u32(self.pc + 4)

        self.mem_wb = next_mem_wb
        self.ex_mem = next_ex_mem
        self.id_ex = next_id_ex
        self.if_id = next_if_id
        self.pc = next_pc
        self.cycle = cycle

        if (
            self.halt_pending
            and self.halt_marker_committed
            and not (self.if_id.valid or self.id_ex.valid or self.ex_mem.valid or self.mem_wb.valid)
        ):
            self.halted = True
            self.halt_reason = f"self-loop jal at 0x{self.self_loop_pc:08x}"

        info = PipelineCycleInfo(
            cycle=cycle,
            pc=self.pc,
            if_stage=stage_if,
            id_stage=stage_id,
            ex_stage=stage_ex,
            mem_stage=stage_mem,
            wb_stage=stage_wb,
            stall=stall and not flush,
            flush=flush,
            forward_a=forward_a,
            forward_b=forward_b,
            mem=mem_desc,
            wb=wb_desc,
        )
        self.pipe_history.append(info)
        return info

    def run(self, max_cycles: int = 1000, stop_on_self_loop: bool = True) -> None:
        while not self.halted and self.cycle < max_cycles:
            self.step(stop_on_self_loop=stop_on_self_loop)
        if not self.halted and self.cycle >= max_cycles:
            self.halted = True
            self.halt_reason = f"max cycle limit {max_cycles} reached"


def print_trace(history: List[StepInfo]) -> None:
    for info in history:
        parts = [
            f"{info.cycle:04d}",
            f"pc=0x{info.pc:08x}",
            f"inst=0x{info.inst:08x}",
            info.asm,
            f"next=0x{info.next_pc:08x}",
        ]
        if info.rd is not None:
            parts.append(f"{reg_name(info.rd)}=0x{info.rd_value:08x}")
        if info.mem:
            parts.append(info.mem)
        print(" | ".join(parts))


def print_pipe_trace(history: List[PipelineCycleInfo]) -> None:
    for info in history:
        print(f"cycle {info.cycle:04d}: pc_next=0x{info.pc:08x}")
        print(f"  IF : {info.if_stage}")
        print(f"  ID : {info.id_stage}")
        print(f"  EX : {info.ex_stage}")
        print(f"  MEM: {info.mem_stage}")
        print(f"  WB : {info.wb_stage}")
        actions = []
        if info.stall:
            actions.append("stall")
        if info.flush:
            actions.append("flush")
        if info.forward_a != "REG":
            actions.append(f"fwdA={info.forward_a}")
        if info.forward_b != "REG":
            actions.append(f"fwdB={info.forward_b}")
        if info.mem:
            actions.append(info.mem)
        if info.wb:
            actions.append(f"WB {info.wb}")
        if actions:
            print("  " + " | ".join(actions))


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the project RV32I single-cycle Python simulator.")
    parser.add_argument("--tdp", type=Path, default=Path("test7_tdp.coe"), help="unified instruction/data COE")
    parser.add_argument("--inst", type=Path, help="split instruction COE")
    parser.add_argument("--data", type=Path, help="split data COE")
    parser.add_argument("--pipeline", action="store_true", help="run the five-stage pipeline model")
    parser.add_argument("--max-cycles", type=int, default=300)
    parser.add_argument("--trace", action="store_true", help="print every executed instruction")
    parser.add_argument("--trace-pipe", action="store_true", help="print every pipeline cycle")
    parser.add_argument("--no-stop-on-self-loop", action="store_true", help="keep running through jal-to-self loops")
    parser.add_argument("--dump-base", type=lambda x: int(x, 0), help="memory word dump base")
    parser.add_argument("--dump-words", type=int, default=32, help="number of words to dump")
    parser.add_argument("--dump-bytes", type=int, default=0, help="number of bytes to dump after the word dump")
    return parser


def main() -> int:
    args = build_arg_parser().parse_args()

    sim_cls = RiscVPipelineSim if args.pipeline else RiscVSingleCycleSim

    if args.inst or args.data:
        if not args.inst or not args.data:
            raise SystemExit("--inst and --data must be used together")
        sim = sim_cls.from_split_coe(args.inst, args.data)
        source = f"split inst={args.inst} data={args.data}"
    else:
        sim = sim_cls.from_tdp_coe(args.tdp)
        source = str(args.tdp)

    sim.run(max_cycles=args.max_cycles, stop_on_self_loop=not args.no_stop_on_self_loop)

    print(f"source: {source}")
    print(f"mode: {'pipeline' if args.pipeline else 'single-cycle'}")
    print(f"cycles: {sim.cycle}")
    print(f"halt: {sim.halt_reason}")
    print(f"pc: 0x{sim.pc:08x}")

    if args.trace:
        if args.pipeline:
            print("\ntrace:")
            print_pipe_trace(sim.pipe_history)
        else:
            print("\ntrace:")
            print_trace(sim.history)
    elif args.trace_pipe:
        print("\ntrace:")
        if not args.pipeline:
            raise SystemExit("--trace-pipe requires --pipeline")
        print_pipe_trace(sim.pipe_history)

    print("\nregisters:")
    print(sim.dump_registers(1, 31))

    dump_base = args.dump_base if args.dump_base is not None else sim.regs[31]
    print(f"\nmemory words from 0x{dump_base:08x}:")
    print(sim.dump_words(dump_base, args.dump_words))
    if args.dump_bytes:
        print(f"\nmemory bytes from 0x{dump_base:08x}:")
        print(sim.dump_bytes(dump_base, args.dump_bytes))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
