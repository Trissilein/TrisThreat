// Deterministic quarter-circle profiles, one tile for each 5% Feather slider step.
// Edges sample a tile's first row/column; corners sample the full tile.
// Every tile sits in a cell with a GUTTER: the tile's edge texels repeated outwards, so bilinear filtering and
// mip levels up to 3 (8 texels per texel, cell and tile origins are multiples of 8) never read a neighbor tile.
// Keep the constants in sync with Element.lua: --check compares them with its ATLAS table.
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const width = 512, height = 512, size = 64, gutter = 8, cell = size + 2 * gutter, cols = 6, tiles = 20;
assert(gutter % 8 === 0 && cell % 8 === 0 && cols * cell <= width && Math.ceil(tiles / cols) * cell <= height);
const image = Buffer.alloc(18 + width * height * 4);
image[2] = 2; // Uncompressed true-color TGA, BGRA, top-left origin.
image.writeUInt16LE(width, 12);
image.writeUInt16LE(height, 14);
image[16] = 32;
image[17] = 0x28;
image.fill(255, 18); // white RGB everywhere; alpha is rewritten below (0 in unused cells)
for (let i = 18 + 3; i < image.length; i += 4) image[i] = 0;
const offsetOf = (tile, x, y) => 18 + ((Math.floor(tile / cols) * cell + gutter + y) * width + (tile % cols) * cell + gutter + x) * 4;
for (let tile = 0; tile < tiles; tile++) {
    const feather = (tile + 1) / tiles;
    for (let gy = -gutter; gy < size + gutter; gy++) for (let gx = -gutter; gx < size + gutter; gx++) {
        const x = Math.max(0, Math.min(size - 1, gx)), y = Math.max(0, Math.min(size - 1, gy)); // gutter = clamped edge
        const distance = Math.hypot(x, y) / (size - 1);
        const fade = Math.max(0, Math.min(1, (distance - (1 - feather)) / feather));
        image[offsetOf(tile, gx, gy) + 3] = Math.round(255 * Math.pow(1 - fade, 1.6));
    }
}
const alpha = (tile, x, y) => image[offsetOf(tile, x, y) + 3];
for (let tile = 0; tile < tiles; tile++) {
    const last = size - 1;
    assert.equal(alpha(tile, 0, 0), 255);
    assert.equal(alpha(tile, last, 0), 0);
    assert.equal(alpha(tile, last, last), 0);
    for (let x = 1; x < size; x++) {
        assert(alpha(tile, x, 0) <= alpha(tile, x - 1, 0));
        assert.equal(alpha(tile, x, 0), alpha(tile, 0, x)); // corner edge meets the straight edge's profile
    }
    for (let g = 1; g <= gutter; g++) for (let i = 0; i < size; i++) { // gutter repeats the edge texel outwards
        assert.equal(alpha(tile, -g, i), alpha(tile, 0, i));
        assert.equal(alpha(tile, last + g, i), alpha(tile, last, i));
        assert.equal(alpha(tile, i, -g), alpha(tile, i, 0));
        assert.equal(alpha(tile, i, last + g), alpha(tile, i, last));
    }
    assert.equal(alpha(tile, -gutter, -gutter), 255);
}
for (let tile = tiles; tile < cols * Math.ceil(tiles / cols); tile++) assert.equal(alpha(tile, 0, 0), 0);
assert(alpha(0, 32, 0) > alpha(19, 32, 0));
const target = path.join(__dirname, "../Assets/Glow.tga");
if (process.argv.includes("--check")) {
    assert(fs.readFileSync(target).equals(image), "Glow.tga differs from its generator");
    const lua = fs.readFileSync(path.join(__dirname, "../Element.lua"), "utf8");
    const want = `local ATLAS = { w = ${width}, h = ${height}, tile = ${size}, gutter = ${gutter}, cell = ${cell}, cols = ${cols} }`;
    assert(lua.includes(want), "Element.lua ATLAS differs from the generator: expected " + want);
    console.log("PASS glow texture: radial corners, monotonic edges, gutters, every Feather step, reproducible asset");
} else {
    fs.writeFileSync(target, image);
    console.log("Generated " + target);
}
