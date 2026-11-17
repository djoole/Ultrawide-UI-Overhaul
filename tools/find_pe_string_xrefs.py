#!/usr/bin/env python3
"""Locate a string in a PE64 image and find direct RIP-relative code references."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from capstone.x86 import X86_OP_IMM, X86_OP_MEM, X86_REG_RIP


def read_sections(data: bytes):
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe_offset : pe_offset + 4] != b"PE\0\0":
        raise ValueError("not a PE image")
    coff = pe_offset + 4
    section_count = struct.unpack_from("<H", data, coff + 2)[0]
    optional_size = struct.unpack_from("<H", data, coff + 16)[0]
    optional = coff + 20
    image_base = struct.unpack_from("<Q", data, optional + 24)[0]
    section_table = optional + optional_size
    sections = []
    for index in range(section_count):
        pos = section_table + index * 40
        name = data[pos : pos + 8].split(b"\0", 1)[0].decode("ascii", "replace")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, pos + 8)
        characteristics = struct.unpack_from("<I", data, pos + 36)[0]
        sections.append((name, virtual_address, virtual_size, raw_offset, raw_size, characteristics))
    return image_base, sections


def file_to_rva(offset: int, sections):
    for name, va, vsize, raw, rsize, characteristics in sections:
        if raw <= offset < raw + rsize:
            return va + offset - raw, name
    return None, None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("needle", nargs="?")
    parser.add_argument("--target", action="append", type=lambda value: int(value, 0), default=[])
    args = parser.parse_args()

    data = args.image.read_bytes()
    image_base, sections = read_sections(data)
    hits = []
    if args.needle:
        needle = args.needle.encode("utf-8")
        start = 0
        while True:
            hit = data.find(needle, start)
            if hit < 0:
                break
            rva, section = file_to_rva(hit, sections)
            if rva is not None:
                hits.append((hit, image_base + rva, section))
            start = hit + 1

    print(f"image_base=0x{image_base:X}")
    for hit, address, section in hits:
        print(f"string file=0x{hit:X} va=0x{address:X} section={section}")

    targets = {address for _, address, _ in hits} | set(args.target)
    if not targets:
        parser.error("provide a needle and/or at least one --target address")
    md = Cs(CS_ARCH_X86, CS_MODE_64)
    md.detail = True
    for name, va, vsize, raw, rsize, characteristics in sections:
        if not characteristics & 0x20000000:  # IMAGE_SCN_MEM_EXECUTE
            continue
        code = data[raw : raw + rsize]
        base = image_base + va
        for instruction in md.disasm(code, base):
            for operand in instruction.operands:
                if operand.type == X86_OP_IMM and operand.imm in targets:
                    print(
                        f"xref va=0x{instruction.address:X} {instruction.mnemonic} "
                        f"{instruction.op_str} -> 0x{operand.imm:X}"
                    )
                if operand.type == X86_OP_MEM and operand.mem.base == X86_REG_RIP:
                    target = instruction.address + instruction.size + operand.mem.disp
                    if target in targets:
                        print(
                            f"xref va=0x{instruction.address:X} {instruction.mnemonic} "
                            f"{instruction.op_str} -> 0x{target:X}"
                        )


if __name__ == "__main__":
    main()
