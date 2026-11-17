#!/usr/bin/env python3
"""Disassemble a PE64 virtual-address range with Capstone."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from capstone import Cs, CS_ARCH_X86, CS_MODE_64


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("image", type=Path)
    parser.add_argument("address", type=lambda value: int(value, 0))
    parser.add_argument("--before", type=lambda value: int(value, 0), default=0x100)
    parser.add_argument("--after", type=lambda value: int(value, 0), default=0x200)
    args = parser.parse_args()

    data = args.image.read_bytes()
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    coff = pe_offset + 4
    section_count = struct.unpack_from("<H", data, coff + 2)[0]
    optional_size = struct.unpack_from("<H", data, coff + 16)[0]
    optional = coff + 20
    image_base = struct.unpack_from("<Q", data, optional + 24)[0]
    section_table = optional + optional_size

    start_va = args.address - args.before
    end_va = args.address + args.after
    for index in range(section_count):
        pos = section_table + index * 40
        name = data[pos : pos + 8].split(b"\0", 1)[0].decode("ascii", "replace")
        virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, pos + 8)
        section_start = image_base + virtual_address
        section_end = section_start + raw_size
        if section_start <= start_va < section_end:
            end_va = min(end_va, section_end)
            file_offset = raw_offset + start_va - section_start
            code = data[file_offset : file_offset + end_va - start_va]
            md = Cs(CS_ARCH_X86, CS_MODE_64)
            print(f"section={name} range=0x{start_va:X}..0x{end_va:X}")
            for insn in md.disasm(code, start_va):
                marker = "  <==" if insn.address == args.address else ""
                print(f"0x{insn.address:011X}: {insn.bytes.hex(' '):<30} {insn.mnemonic:<8} {insn.op_str}{marker}")
            return
    raise ValueError("address is not backed by a PE section")


if __name__ == "__main__":
    main()
