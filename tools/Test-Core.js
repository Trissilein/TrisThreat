const fs = require("fs");
const path = require("path");
const fengariPath = process.env.TRISTHREAT_FENGARI || "fengari";
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require(fengariPath);

const root = path.resolve(__dirname, "..");
const core = fs.readFileSync(path.join(root, "Core.lua"), "utf8").replace(
  /^local addonName, ns = \.\.\.$/m,
  "local addonName, ns = 'TrisThreat', addonNamespace",
);
const checks = fs.readFileSync(path.join(__dirname, "Test-Core.lua"), "utf8");
const program = ["local addonNamespace = {}", "local ns = addonNamespace", core, checks].join("\n");

const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const status = lauxlib.luaL_dostring(state, to_luastring(program));
if (status !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(state, -1)));
  process.exit(1);
}
