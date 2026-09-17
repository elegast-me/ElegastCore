#!/usr/bin/env python3
"""
Unit tests: SpeedBuff's display math, executed under a real Lua.

Covers the two things Issue #24 is about:

  * `SpeedPercentForStacks` -- the per-stack percentage the frame reports.
    Before the fix this was `stacks * 20`, a value the client hardcoded while
    the server applied `SpeedBuff.SpeedIncreasePerStack` (config, currently
    20). The client readout and the server application diverged the moment the
    knob moved, with nothing to say so. The server now sends the value
    (elegast-me/ElegastCore-Classless#595, SPEEDBUFF:STACK wire format), and the
    client uses it, falling back to 20 for an older stacks-only server.

  * `ParseSpeedStackMessage` -- the server-message parser. It reads the new
    optional fields (`<pctPerStack>:<travelFormPct>`) with one match and falls
    back to the stack-count-only pattern, so a message from a pre-change server
    still parses and a post-change one carries the fields the client needs.

These are `local` to modules/SpeedBuff/SpeedBuff.lua, not exposed on the module
table, so nothing outside the file can call them directly. Rather than
re-implementing their logic in Python (which would drift from the real file
silently -- exactly the failure this issue is about), this loads the actual
file under liblua5.4 via ctypes, with a handful of WoW API stubs, and calls the
real functions through a test-only export (`SpeedBuffModule._test`, gated
behind the global EGC_TEST_HOOKS, which the shipped client never sets -- see the
bottom of SpeedBuff.lua).

Skipped (not failed) if liblua5.4 isn't installed, matching
test_lua_syntax.py's convention. NOTE: this runs under whichever liblua the
host has -- 5.4 here. The 3.3.5a client embeds Lua 5.1. A 5.4-only construct
(`//`, bitwise `&`/`|`, `::labels::`, `<const>`) would parse clean here and
still break the client; this suite cannot catch that direction of drift.
"""
import ctypes, ctypes.util, pathlib, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEED_BUFF_LUA = ROOT / "modules" / "SpeedBuff" / "SpeedBuff.lua"

LUA_TNIL = 0
LUA_TBOOLEAN = 1
LUA_TNUMBER = 3
LUA_TSTRING = 4
LUA_TTABLE = 5

# Minimal WoW API surface needed to *load* SpeedBuff.lua and call the two
# test hooks. OnInitialize (which needs the real UI API) is never invoked; the
# hooks only touch the pure functions we expose.
STUB_PRELUDE = """
EGC_TEST_HOOKS = true

ElegastCoreDB = {}

ElegastCore = {
    Easing = {
        EaseOutElastic = function(t) return t end,
        EaseOutBack = function(t) return t end,
    },
    RegisterModule = function() end,
}

function CreateFrame(...)
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
end
"""


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


class LuaError(RuntimeError):
    pass


class Lua:
    """Thin ctypes wrapper over the pieces of the Lua 5.4 C API this test needs."""

    def __init__(self, lib):
        self.lib = lib
        lib.luaL_newstate.restype = ctypes.c_void_p
        lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lib.luaL_loadfilex.restype = ctypes.c_int
        lib.luaL_loadfilex.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
        lib.luaL_loadstring.restype = ctypes.c_int
        lib.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_pcallk.restype = ctypes.c_int
        lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int,
                                   ctypes.c_int, ctypes.c_ssize_t, ctypes.c_void_p]
        lib.lua_getglobal.restype = ctypes.c_int
        lib.lua_getglobal.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lib.lua_getfield.restype = ctypes.c_int
        lib.lua_getfield.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_char_p]
        lib.lua_type.restype = ctypes.c_int
        lib.lua_type.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.lua_toboolean.restype = ctypes.c_int
        lib.lua_toboolean.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.lua_tolstring.restype = ctypes.c_char_p
        lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lib.lua_tonumberx.restype = ctypes.c_double
        lib.lua_tonumberx.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lib.lua_pushlstring.restype = ctypes.c_void_p
        lib.lua_pushlstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
        lib.lua_pushnumber.restype = None
        lib.lua_pushnumber.argtypes = [ctypes.c_void_p, ctypes.c_double]
        lib.lua_pushnil.argtypes = [ctypes.c_void_p]
        lib.lua_next.restype = ctypes.c_int
        lib.lua_next.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.lua_copy.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        lib.lua_settop.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.lua_gettop.restype = ctypes.c_int
        lib.lua_gettop.argtypes = [ctypes.c_void_p]

        self.L = lib.luaL_newstate()
        if not self.L:
            raise LuaError("luaL_newstate failed")
        lib.luaL_openlibs(self.L)

    def close(self):
        self.lib.lua_close(self.L)

    def _pcall(self, nargs, nresults):
        rc = self.lib.lua_pcallk(self.L, nargs, nresults, 0, 0, None)
        if rc != 0:
            msg = self.lib.lua_tolstring(self.L, -1, None)
            text = msg.decode(errors="replace") if msg else f"lua error (code {rc})"
            self.lib.lua_settop(self.L, -2)
            raise LuaError(text)

    def do_string(self, code, nresults=0):
        if self.lib.luaL_loadstring(self.L, code.encode()) != 0:
            msg = self.lib.lua_tolstring(self.L, -1, None)
            raise LuaError(msg.decode(errors="replace") if msg else "load error")
        self._pcall(0, nresults)

    def do_file(self, path):
        if self.lib.luaL_loadfilex(self.L, str(path).encode(), None) != 0:
            msg = self.lib.lua_tolstring(self.L, -1, None)
            raise LuaError(msg.decode(errors="replace") if msg else "load error")
        self._pcall(0, 0)

    def push_path(self, *parts):
        """Push the value at _SPEED_BUFF_TEST_HOOKS.<parts>, leaving only the
        final value on the stack (the intermediate tables walked to reach it are
        popped)."""
        base = self.lib.lua_gettop(self.L)
        self.lib.lua_getglobal(self.L, parts[0].encode())
        for part in parts[1:]:
            self.lib.lua_getfield(self.L, -1, part.encode())
        vtype = self.lib.lua_type(self.L, -1)
        self.lib.lua_copy(self.L, -1, base + 1)   # move final value to base+1
        self.lib.lua_settop(self.L, base + 1)     # drop everything above it
        return vtype

    def push_value(self, v):
        if isinstance(v, str):
            self.lib.lua_pushlstring(self.L, v.encode(), len(v.encode()))
        elif isinstance(v, bool):
            self.lib.lua_pushboolean(self.L, 1 if v else 0)
        elif isinstance(v, int):
            self.lib.lua_pushnumber(self.L, float(v))
        else:
            raise TypeError(type(v))

    def call(self, nargs, nresults):
        self._pcall(nargs, nresults)

    def to_number(self, idx=-1):
        return self.lib.lua_tonumberx(self.L, idx, None)

    def to_string(self, idx=-1):
        s = self.lib.lua_tolstring(self.L, idx, None)
        return s.decode(errors="replace") if s is not None else None

    def table_to_dict(self, idx=-1):
        """Snapshot a string-keyed table (ParseSpeedStackMessage's return)."""
        idx = idx if idx > 0 else self.lib.lua_gettop(self.L) + idx + 1
        result = {}
        self.lib.lua_pushnil(self.L)
        while self.lib.lua_next(self.L, idx) != 0:
            key = self.to_string(-2)
            t = self.type(-1)
            if t == LUA_TNUMBER:
                result[key] = self.to_number(-1)
            elif t == LUA_TSTRING:
                result[key] = self.to_string(-1)
            else:
                result[key] = None
            self.pop(1)
        return result

    def type(self, idx=-1):
        return self.lib.lua_type(self.L, idx)

    def pop(self, n=1):
        self.lib.lua_settop(self.L, -n - 1)

    def settop(self, n):
        self.lib.lua_settop(self.L, n)


def build_state():
    """A fresh Lua state with SpeedBuff.lua loaded."""
    lua = Lua(LUA)
    lua.do_string(STUB_PRELUDE)
    lua.do_file(SPEED_BUFF_LUA)
    return lua


def call_test_hook(lua, name, *args):
    """Call _SPEED_BUFF_TEST_HOOKS.<name>(*args) and return its single result.

    Both hooks return exactly one value (a number, or a table). Requesting one
    result avoids the pcall padding a variable-return call with nils, so the
    result count is exact."""
    lua.settop(0)
    lua.push_path("_SPEED_BUFF_TEST_HOOKS", name)
    for a in args:
        lua.push_value(a)
    lua.call(len(args), 1)
    t = lua.type()
    if t == LUA_TNUMBER:
        return lua.to_number()
    if t == LUA_TBOOLEAN:
        return bool(lua.lib.lua_toboolean(lua.L, -1))
    if t == LUA_TSTRING:
        return lua.to_string()
    if t == LUA_TTABLE:
        return lua.table_to_dict()
    return None


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class SpeedPercentForStacks(unittest.TestCase):
    def test_default_matches_server_config(self):
        """With the server's default per-stack rate (20), the readout equals
        stacks * 20 -- the value the old hardcoded code reported, so nothing
        changes for a server still on the default."""
        lua = build_state()
        try:
            self.assertEqual(60.0, call_test_hook(lua, "SpeedPercentForStacks", 3, 20))
            self.assertEqual(80.0, call_test_hook(lua, "SpeedPercentForStacks", 4, 20))
        finally:
            lua.close()

    def test_uses_server_rate_not_hardcoded_20(self):
        """A tuned server rate is applied, so the readout tracks the server
        instead of the client's stale 20."""
        lua = build_state()
        try:
            self.assertEqual(3.0 * 25.0, call_test_hook(lua, "SpeedPercentForStacks", 3, 25))
            self.assertEqual(4.0 * 15.0, call_test_hook(lua, "SpeedPercentForStacks", 4, 15))
        finally:
            lua.close()

    def test_zero_stacks_is_zero(self):
        lua = build_state()
        try:
            self.assertEqual(0.0, call_test_hook(lua, "SpeedPercentForStacks", 0, 20))
        finally:
            lua.close()


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class ParseSpeedStackMessage(unittest.TestCase):
    def test_parses_all_three_fields(self):
        """The new wire format carries stacks, per-stack rate, and Travel Form
        bonus; all three come back as strings (Lua string.match returns
        strings)."""
        lua = build_state()
        try:
            got = call_test_hook(
                lua, "ParseSpeedStackMessage", "SPEEDBUFF:STACK:3:20:10")
            self.assertEqual("3", got["stack"])
            self.assertEqual("20", got["pctPerStack"])
            self.assertEqual("10", got["travelFormPct"])
        finally:
            lua.close()

    def test_parses_stack_count_only(self):
        """An older server sends stacks only; the fallback pattern still reads
        the count, and the absent fields come back nil (so the caller's
        `pctPerStack or 20` fallback applies)."""
        lua = build_state()
        try:
            got = call_test_hook(lua, "ParseSpeedStackMessage", "SPEEDBUFF:STACK:3")
            self.assertEqual("3", got["stack"])
            self.assertNotIn("pctPerStack", got)
            self.assertNotIn("travelFormPct", got)
        finally:
            lua.close()

    def test_zero_fields_parse(self):
        """Both expiry sites emit 0 stacks; Travel Form bonus is 0 when not in
        form. Zero is a real field value, distinct from the absent-field
        (nil) case."""
        lua = build_state()
        try:
            got = call_test_hook(
                lua, "ParseSpeedStackMessage", "SPEEDBUFF:STACK:0:20:0")
            self.assertEqual("0", got["stack"])
            self.assertEqual("20", got["pctPerStack"])
            self.assertEqual("0", got["travelFormPct"])
        finally:
            lua.close()

    def test_old_pattern_still_matches_count(self):
        """The pre-change client matched only the stack count
        (string.match(msg, 'SPEEDBUFF:STACK:(%d+)')); the appended fields are
        invisible to it, so the change is strictly additive."""
        old = "SPEEDBUFF:STACK:3:20:10"
        import re
        m = re.search(r"SPEEDBUFF:STACK:(\d+)", old)
        self.assertEqual("3", m.group(1))


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class BackwardCompat(unittest.TestCase):
    def test_fallback_rate_when_fields_absent(self):
        """The display path uses the sent rate or 20 when absent. We cannot call
        UpdateSpeedBuffDisplay (it drives the UI), but we assert the two halves
        compose the way the shipped code does: parse yields nil fields, and the
        rate falls back to 20, so an old server still reads stacks * 20."""
        lua = build_state()
        try:
            got = call_test_hook(
                lua, "ParseSpeedStackMessage", "SPEEDBUFF:STACK:4")
            self.assertEqual("4", got["stack"])
            self.assertNotIn("pctPerStack", got)
            fallback = 20
            rate = got.get("pctPerStack", fallback)
            pct = call_test_hook(lua, "SpeedPercentForStacks", 4, rate)
            self.assertEqual(4 * rate, pct)
        finally:
            lua.close()


if __name__ == "__main__":
    unittest.main()
