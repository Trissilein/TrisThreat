const fs = require("fs");
const path = require("path");
const fengariPath = process.env.TRISTHREAT_FENGARI || "fengari";
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(fengariPath);

const root = path.resolve(__dirname, "..");
const files = ["Locales/enUS.lua", "Locales/deDE.lua", "Core.lua", "Element.lua", "Capsule.lua", "Options.lua", "Launcher.lua"];
// Each addon file becomes a function(addonName, ns) so `local x, ns = ...` works as in the game.
const modules = files.map((f) => "function(...)\n" + fs.readFileSync(path.join(root, f), "utf8") + "\nend").join(",\n");
const checks = fs.readFileSync(path.join(__dirname, "Test-Smoke.lua"), "utf8");
const program = ["ns = {}", "MODULES = {" + modules + "}", "LibStub = nil", checks].join("\n");

const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(program));
if (status !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(state, -1)));
  process.exit(1);
}
