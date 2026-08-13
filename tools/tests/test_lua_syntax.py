#!/usr/bin/env python3
"""
Unit tests: every .lua file in the repo parses as valid Lua.

Parses only (luaL_loadfilex compiles but never executes) via ctypes against
the host's liblua5.4, so a real Lua parser is doing the work rather than a
hand-rolled heuristic. Skipped (not failed) if liblua5.4 isn't installed, so
a fresh checkout still reports cleanly.

Ported from azerothcore-wotlk/tools/tests/test_lua_syntax.py -- same
approach, but this repo has no lua_scripts/ subdirectory to scope to: the
whole tree (including vendored libs/AIO) is the addon.

NOTE: this parses under whichever liblua the host has -- 5.4 here. The
3.3.5a client embeds Lua 5.1. A 5.4-only construct (`//`, bitwise `&`/`|`,
`::labels::`, `<const>`) would parse clean here and still break the client;
this test cannot catch that direction of drift.
"""
import ctypes, ctypes.util, pathlib, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SKIP_DIRS = {".git"}


def find_liblua():
    for name in ("liblua5.4.so.0", "liblua5.4.so", "liblua5.1.so.0", "liblua5.1.so"):
        try:
            return ctypes.CDLL(name)
        except OSError:
            continue
    for candidate in ("lua5.4", "lua5.1", "lua"):
        found = ctypes.util.find_library(candidate)
        if found:
            try:
                return ctypes.CDLL(found)
            except OSError:
                continue
    return None


LUA = find_liblua()


def lua_files():
    return sorted(
        str(p.relative_to(ROOT))
        for p in ROOT.rglob("*.lua")
        if not SKIP_DIRS & set(p.relative_to(ROOT).parts)
    )


def parse_error(lib, path):
    """Return None if `path` parses cleanly, else the Lua error message."""
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_loadfilex.restype = ctypes.c_int
    lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    lib.lua_close.argtypes = [ctypes.c_void_p]

    L = lib.luaL_newstate()
    try:
        rc = lib.luaL_loadfilex(L, str(ROOT / path).encode(), None)
        if rc != 0:
            msg = lib.lua_tolstring(L, -1, None)
            return msg.decode(errors="replace") if msg else "unknown parse error"
        return None
    finally:
        lib.lua_close(L)


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class TestLuaScriptsParse(unittest.TestCase):
    def test_at_least_one_file_found(self):
        # Guards against a path typo silently making every other test vacuous.
        self.assertGreater(len(lua_files()), 0, f"no .lua files found under {ROOT}")

    def test_every_lua_script_parses(self):
        failures = []
        for path in lua_files():
            err = parse_error(LUA, path)
            if err is not None:
                failures.append(f"{path}: {err}")
        self.assertEqual(failures, [], "Lua parse errors:\n" + "\n".join(failures))


if __name__ == "__main__":
    unittest.main()
