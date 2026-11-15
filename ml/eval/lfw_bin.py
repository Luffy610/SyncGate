"""Safe reader for the InsightFace-format ``lfw.bin`` verification set.

The file is a Python pickle of ``(list[bytes], list[bool])``: 12,000 JPEG
crops (112x112, already 5-point aligned) and 6,000 same/different flags for
consecutive pairs. A pickle can run arbitrary code when loaded, and this file
comes from the internet, so it is **never unpickled**. Instead we walk the
opcode stream with :func:`pickletools.genops` (a tokenizer that executes
nothing) and accept only the opcodes a plain tuple of bytes and bools needs.
Anything that could import or call (``GLOBAL``, ``REDUCE``, ``BUILD``, ...)
makes the reader refuse the file.
"""

from __future__ import annotations

import pickletools
from pathlib import Path

_BYTES_OPS = {"BINBYTES", "SHORT_BINBYTES", "BINBYTES8", "BINSTRING", "SHORT_BINSTRING"}
_ALLOWED = _BYTES_OPS | {
    "PROTO", "FRAME", "STOP", "MARK", "EMPTY_LIST", "EMPTY_TUPLE", "APPEND", "APPENDS",
    "TUPLE", "TUPLE1", "TUPLE2", "TUPLE3", "NEWTRUE", "NEWFALSE", "INT", "BININT",
    "BININT1", "BININT2", "MEMOIZE", "BINPUT", "LONG_BINPUT", "PUT", "BINGET",
    "LONG_BINGET", "GET",
}


def read_lfw_bin(path: str | Path) -> tuple[list[bytes], list[bool]]:
    data = Path(path).read_bytes()
    images: list[bytes] = []
    flags: list[bool] = []
    for op, arg, _ in pickletools.genops(data):
        name = op.name
        if name not in _ALLOWED:
            raise ValueError(f"refusing lfw.bin: unexpected pickle opcode {name}")
        if name in _BYTES_OPS:
            images.append(arg if isinstance(arg, bytes) else arg.encode("latin-1"))
        elif name == "NEWTRUE":
            flags.append(True)
        elif name == "NEWFALSE":
            flags.append(False)
        elif name in {"INT", "BININT", "BININT1", "BININT2"} and arg in (0, 1):
            # Protocol-0/1 pickles store bools as ints.
            flags.append(bool(arg))
    if len(images) != 2 * len(flags):
        raise ValueError(f"lfw.bin malformed: {len(images)} images, {len(flags)} pairs")
    return images, flags
