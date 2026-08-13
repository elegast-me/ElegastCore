#!/usr/bin/env python3
"""
Unit tests: InfinitePower's pure-logic functions, executed under a real Lua.

Covers the functions named in Issue #20: `ParseServerMessage` (the protocol
parser -- the contract with mod-infinite-power's SendAddonMessage on the
server side, per elegast-me/ElegastCore-Classless), `CalculateProgress`
(picks the leading path, clamps at 1.0), and `CalculateGearBonusTotals`.

These are `local` to modules/InfinitePower/InfinitePower.lua, not exposed on
the module table, so nothing outside the file can call them directly. Rather
than re-implementing their logic in Python (which would drift from the real
file silently -- exactly the failure this issue is about), this loads and
executes the actual Core.lua + InfinitePower.lua under liblua5.4 via ctypes,
with a handful of WoW API stubs, and calls the real functions through a
test-only export (`InfinitePowerModule._test`, gated behind the global
EGC_TEST_HOOKS, which the shipped client never sets -- see the bottom of
InfinitePower.lua).

Skipped (not failed) if liblua5.4 isn't installed, matching
test_lua_syntax.py's convention. NOTE: this runs under whichever liblua the
host has -- 5.4 here. The 3.3.5a client embeds Lua 5.1. A 5.4-only construct
(`//`, bitwise `&`/`|`, `::labels::`, `<const>`) would parse clean here and
still break the client; this suite cannot catch that direction of drift.
"""
import ctypes, ctypes.util, pathlib, unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CORE_LUA = ROOT / "Core.lua"
INFINITE_POWER_LUA = ROOT / "modules" / "InfinitePower" / "InfinitePower.lua"

LUA_TNIL = 0
LUA_TBOOLEAN = 1
LUA_TNUMBER = 3
LUA_TSTRING = 4
LUA_TTABLE = 5

# Minimal WoW API surface needed to *load* Core.lua + InfinitePower.lua and
# call ParseServerMessage/CalculateProgress/CalculateGearBonusTotals. Neither
# file calls anything beyond this at load time or from those three
# functions -- OnInitialize (which needs the real UI API) is never invoked.
STUB_PRELUDE = """
EGC_TEST_HOOKS = true

SlashCmdList = {}

function CreateFrame(...)
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    return frame
end

function UnitName(unit)
    return "TestChar"
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
        lib.lua_next.restype = ctypes.c_int
        lib.lua_next.argtypes = [ctypes.c_void_p, ctypes.c_int]
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
        lib.lua_pushnil.argtypes = [ctypes.c_void_p]
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
        """Push the value at ElegastCore.modules.InfinitePower._test.<parts>
        etc, leaving only the final value on the stack (the intermediate
        tables walked to reach it are popped)."""
        base = self.lib.lua_gettop(self.L)
        self.lib.lua_getglobal(self.L, parts[0].encode())
        for part in parts[1:]:
            self.lib.lua_getfield(self.L, -1, part.encode())
        vtype = self.lib.lua_type(self.L, -1)
        self.lib.lua_copy(self.L, -1, base + 1)   # move final value to base+1
        self.lib.lua_settop(self.L, base + 1)     # drop everything above it
        return vtype

    def push_string(self, s):
        self.lib.lua_pushlstring(self.L, s.encode(), len(s.encode()))

    def call(self, nargs, nresults):
        self._pcall(nargs, nresults)

    def to_number(self, idx=-1):
        return self.lib.lua_tonumberx(self.L, idx, None)

    def to_string(self, idx=-1):
        s = self.lib.lua_tolstring(self.L, idx, None)
        return s.decode(errors="replace") if s is not None else None

    def type(self, idx=-1):
        return self.lib.lua_type(self.L, idx)

    def pop(self, n=1):
        self.lib.lua_settop(self.L, -n - 1)

    def settop(self, n):
        self.lib.lua_settop(self.L, n)

    def table_to_dict(self, idx=-1):
        """Snapshot a table at idx. Keys and values may be numbers or strings
        (InfinitePower.lua mixes both: playerData.stats is number-keyed,
        each gearBonuses entry is a {statType=.., amount=..} string-keyed
        sub-table)."""
        idx = idx if idx > 0 else self.lib.lua_gettop(self.L) + idx + 1
        result = {}
        self.lib.lua_pushnil(self.L)
        while self.lib.lua_next(self.L, idx) != 0:
            ktype = self.type(-2)
            key = self.to_string(-2) if ktype == LUA_TSTRING else self.to_number(-2)
            if isinstance(key, float) and key == int(key):
                key = int(key)
            vtype = self.type(-1)
            if vtype == LUA_TTABLE:
                value = self.table_to_dict(-1)
            elif vtype == LUA_TNUMBER:
                value = self.to_number(-1)
            else:
                value = self.to_string(-1)
            result[key] = value
            self.pop(1)  # keep key on top for lua_next
        return result


def build_state():
    """A fresh Lua state with Core.lua + InfinitePower.lua loaded and registered."""
    lua = Lua(LUA)
    lua.do_string(STUB_PRELUDE)
    lua.do_file(CORE_LUA)
    lua.do_file(INFINITE_POWER_LUA)
    return lua


def call_test_hook(lua, name, *args):
    lua.push_path("ElegastCore", "modules", "InfinitePower", "_test", name)
    for a in args:
        lua.push_string(a)
    lua.call(len(args), 1)
    result = lua.type()
    if result == LUA_TNUMBER:
        val = lua.to_number()
    elif result == LUA_TBOOLEAN:
        val = bool(lua.lib.lua_toboolean(lua.L, -1))
    elif result == LUA_TSTRING:
        val = lua.to_string()
    else:
        val = None
    lua.pop(1)
    return val


def reset_player_data(lua):
    call_test_hook(lua, "ResetPlayerData")


def get_player_data_field(lua, field):
    lua.push_path("ElegastCore", "modules", "InfinitePower", "_test", "GetPlayerData")
    lua.call(0, 1)  # playerData table now on top
    lua.lib.lua_getfield(lua.L, -1, field.encode())
    t = lua.type()
    if t == LUA_TTABLE:
        value = lua.table_to_dict()
    elif t == LUA_TNUMBER:
        value = lua.to_number()
    else:
        value = None
    lua.pop(2)  # field value, playerData table
    return value


def parse_message(lua, message):
    call_test_hook(lua, "ParseServerMessage", message)


def calculate_progress(lua):
    lua.push_path("ElegastCore", "modules", "InfinitePower", "_test", "CalculateProgress")
    lua.call(0, 4)
    fraction = lua.to_number(-4)
    r = lua.to_number(-3)
    g = lua.to_number(-2)
    b = lua.to_number(-1)
    lua.pop(4)
    return fraction, r, g, b


def calculate_gear_bonus_totals(lua):
    lua.push_path("ElegastCore", "modules", "InfinitePower", "_test", "CalculateGearBonusTotals")
    lua.call(0, 1)
    result = lua.table_to_dict()
    lua.pop(1)
    return result


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class TestParseServerMessage(unittest.TestCase):
    def setUp(self):
        self.lua = build_state()
        reset_player_data(self.lua)

    def tearDown(self):
        self.lua.close()

    def test_xp_and_sp_segments(self):
        parse_message(self.lua, "XP:5:42|SP:12")
        self.assertEqual(get_player_data_field(self.lua, "xpStacks"), 5)
        self.assertEqual(get_player_data_field(self.lua, "xpPercentage"), 42)
        self.assertEqual(get_player_data_field(self.lua, "statPoints"), 12)

    def test_kills_and_quests_segments(self):
        parse_message(self.lua, "KILLS:100:10:25|QUESTS:20:1:3")
        self.assertEqual(get_player_data_field(self.lua, "totalKills"), 100)
        self.assertEqual(get_player_data_field(self.lua, "killsThisStack"), 10)
        self.assertEqual(get_player_data_field(self.lua, "killsNeeded"), 25)
        self.assertEqual(get_player_data_field(self.lua, "totalQuests"), 20)
        self.assertEqual(get_player_data_field(self.lua, "questsThisStack"), 1)
        self.assertEqual(get_player_data_field(self.lua, "questsNeeded"), 3)

    def test_kills_and_quests_needed_falls_back_when_field_missing(self):
        # `tonumber(parts[4]) or 25` / `... or 3`: if a later KILLS/QUESTS
        # segment omits the "needed" field, it snaps back to the default
        # rather than keeping the last value the addon saw.
        parse_message(self.lua, "KILLS:0:0:50|QUESTS:0:0:10")
        self.assertEqual(get_player_data_field(self.lua, "killsNeeded"), 50)
        self.assertEqual(get_player_data_field(self.lua, "questsNeeded"), 10)

        parse_message(self.lua, "KILLS:100:10|QUESTS:20:1")  # needed field absent
        self.assertEqual(get_player_data_field(self.lua, "killsNeeded"), 25)
        self.assertEqual(get_player_data_field(self.lua, "questsNeeded"), 3)

    def test_stats_segment(self):
        parse_message(self.lua, "STATS:0:15,2:30")
        stats = get_player_data_field(self.lua, "stats")
        self.assertEqual(stats, {0: 15, 2: 30})

    def test_stats_segment_empty_clears_previous(self):
        parse_message(self.lua, "STATS:0:15")
        parse_message(self.lua, "STATS")
        self.assertEqual(get_player_data_field(self.lua, "stats"), {})

    def test_gear_segment(self):
        parse_message(self.lua, "GEAR:1:0:5,3:2:10")
        gear = get_player_data_field(self.lua, "gearBonuses")
        self.assertEqual(gear, {1: {"statType": 0, "amount": 5}, 3: {"statType": 2, "amount": 10}})

    def test_unconfigured_gear_slots_segment(self):
        parse_message(self.lua, "UNCFG:4")
        self.assertEqual(get_player_data_field(self.lua, "unconfiguredGearSlots"), 4)

    def test_pct_segment_maps_server_ids_to_addon_ids(self):
        # Server STA(0)->addon 2, server HASTE(8)->addon 6, per SERVER_TO_ADDON_STAT_MAP.
        parse_message(self.lua, "PCT:10,0,0,0,0,0,0,0,90")
        allocations = get_player_data_field(self.lua, "statAllocations")
        self.assertEqual(allocations, {2: 10, 6: 90})

    def test_pct_segment_drops_zero_allocations(self):
        parse_message(self.lua, "PCT:0,100,0,0,0,0,0,0,0")
        allocations = get_player_data_field(self.lua, "statAllocations")
        # Server STR(1) -> addon 0.
        self.assertEqual(allocations, {0: 100})

    def test_unknown_segment_is_ignored(self):
        parse_message(self.lua, "XP:5:42|BOGUS:99:99")
        self.assertEqual(get_player_data_field(self.lua, "xpStacks"), 5)

    def test_full_message_all_segments(self):
        parse_message(
            self.lua,
            "XP:5:42|SP:12|KILLS:100:10:25|QUESTS:20:1:3|"
            "STATS:0:15,2:30|GEAR:1:0:5|UNCFG:1|PCT:10,0,0,0,0,0,0,0,90",
        )
        self.assertEqual(get_player_data_field(self.lua, "xpStacks"), 5)
        self.assertEqual(get_player_data_field(self.lua, "statPoints"), 12)
        self.assertEqual(get_player_data_field(self.lua, "killsThisStack"), 10)
        self.assertEqual(get_player_data_field(self.lua, "questsThisStack"), 1)
        self.assertEqual(get_player_data_field(self.lua, "stats"), {0: 15, 2: 30})
        self.assertEqual(get_player_data_field(self.lua, "gearBonuses"), {1: {"statType": 0, "amount": 5}})
        self.assertEqual(get_player_data_field(self.lua, "unconfiguredGearSlots"), 1)
        self.assertEqual(get_player_data_field(self.lua, "statAllocations"), {2: 10, 6: 90})


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class TestCalculateProgress(unittest.TestCase):
    def setUp(self):
        self.lua = build_state()
        reset_player_data(self.lua)

    def tearDown(self):
        self.lua.close()

    def test_kill_leads(self):
        parse_message(self.lua, "KILLS:0:10:25|QUESTS:0:1:3")  # 0.4 vs 0.333
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 0.4)
        self.assertEqual((r, g, b), (1.0, 1.0, 0.4))

    def test_quest_leads(self):
        parse_message(self.lua, "KILLS:0:1:25|QUESTS:0:2:3")  # 0.04 vs 0.667
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 2 / 3)
        self.assertEqual((r, g, b), (0.4, 1.0, 1.0))

    def test_tie_goes_to_kill(self):
        parse_message(self.lua, "KILLS:0:5:10|QUESTS:0:1:2")  # both 0.5
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 0.5)
        self.assertEqual((r, g, b), (1.0, 1.0, 0.4))

    def test_kill_fraction_clamps_at_one(self):
        parse_message(self.lua, "KILLS:0:50:25|QUESTS:0:0:3")  # 2.0 clamped
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 1.0)
        self.assertEqual((r, g, b), (1.0, 1.0, 0.4))

    def test_quest_fraction_clamps_at_one(self):
        parse_message(self.lua, "KILLS:0:0:25|QUESTS:0:10:3")  # 3.33 clamped
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 1.0)
        self.assertEqual((r, g, b), (0.4, 1.0, 1.0))

    def test_needed_zero_treated_as_no_progress(self):
        parse_message(self.lua, "KILLS:0:10:0|QUESTS:0:5:0")
        fraction, r, g, b = calculate_progress(self.lua)
        self.assertAlmostEqual(fraction, 0.0)
        self.assertEqual((r, g, b), (1.0, 1.0, 0.4))


@unittest.skipUnless(LUA is not None, "no liblua5.4/liblua5.1 found on this host")
class TestCalculateGearBonusTotals(unittest.TestCase):
    def setUp(self):
        self.lua = build_state()
        reset_player_data(self.lua)

    def tearDown(self):
        self.lua.close()

    def test_empty_gear_gives_empty_totals(self):
        self.assertEqual(calculate_gear_bonus_totals(self.lua), {})

    def test_sums_multiple_slots_of_same_stat(self):
        parse_message(self.lua, "GEAR:1:0:5,3:0:10")  # both statType 0
        self.assertEqual(calculate_gear_bonus_totals(self.lua), {0: 15})

    def test_zero_amount_slots_excluded(self):
        parse_message(self.lua, "GEAR:1:0:0,3:2:10")
        self.assertEqual(calculate_gear_bonus_totals(self.lua), {2: 10})

    def test_different_stats_kept_separate(self):
        parse_message(self.lua, "GEAR:1:0:5,3:2:10")
        self.assertEqual(calculate_gear_bonus_totals(self.lua), {0: 5, 2: 10})


if __name__ == "__main__":
    unittest.main(verbosity=2)
