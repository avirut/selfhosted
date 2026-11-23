import json
import struct
import sys
import zipfile
import zlib
from pathlib import Path

SHADES = {"#": 255, "+": 224, "-": 188}

ICONS = {
    "house": [
        ".........",
        "....#....",
        "...###...",
        "..#####..",
        ".#######.",
        "..+++++..",
        "..++-++..",
        "..++-++..",
        ".........",
    ],
    "bed": [
        ".........",
        ".........",
        ".#.......",
        ".#++.....",
        ".#######.",
        ".#-----#.",
        ".#.....#.",
        ".........",
        ".........",
    ],
    "mine": [
        ".........",
        "..#####..",
        ".##.-.##.",
        ".#..-..#.",
        "....-....",
        "....-....",
        "....-....",
        "....-....",
        ".........",
    ],
    "sword": [
        ".........",
        ".......#.",
        "......##.",
        ".....##..",
        "..+.##...",
        "...##....",
        "..-++....",
        ".--......",
        ".........",
    ],
    "flag": [
        ".........",
        "..-#####.",
        "..-#####.",
        "..-#####.",
        "..-......",
        "..-......",
        "..-......",
        "..-......",
        ".........",
    ],
    "star": [
        ".........",
        "....#....",
        "....#....",
        "...###...",
        ".#######.",
        "..#####..",
        "..##.##..",
        "..#...#..",
        ".........",
    ],
    "heart": [
        ".........",
        "..##.##..",
        ".##+####.",
        ".#######.",
        ".#######.",
        "..#####..",
        "...###...",
        "....#....",
        ".........",
    ],
    "skull": [
        ".........",
        "..#####..",
        ".#######.",
        ".#..#..#.",
        ".#..#..#.",
        ".#######.",
        "..#####..",
        "..#.#.#..",
        ".........",
    ],
    "portal": [
        ".........",
        "..#####..",
        "..#---#..",
        "..#---#..",
        "..#---#..",
        "..#---#..",
        "..#---#..",
        "..#####..",
        ".........",
    ],
    "tree": [
        ".........",
        "...###...",
        "..#####..",
        ".#######.",
        ".#######.",
        "..#####..",
        "....-....",
        "....-....",
        ".........",
    ],
}


def pixels(grid):
    size = len(grid)
    out = [[(0, 0, 0, 0)] * size for _ in range(size)]
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            if ch in SHADES:
                v = SHADES[ch]
                out[y][x] = (v, v, v, 255)
    for y in range(size):
        for x in range(size):
            if out[y][x][3]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < size and 0 <= ny < size and grid[ny][nx] in SHADES:
                    out[y][x] = (0, 0, 0, 255)
                    break
    return out


def png(rows):
    height, width = len(rows), len(rows[0])
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in rows)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def pack_files():
    files = {
        "pack.mcmeta": json.dumps(
            {"pack": {"description": "Waymarks icons", "min_format": 97, "max_format": 99}}, indent=2
        ).encode()
    }
    for name, grid in ICONS.items():
        files[f"assets/waymarks/textures/gui/sprites/hud/locator_bar_dot/{name}.png"] = png(pixels(grid))
        files[f"assets/waymarks/waypoint_style/{name}.json"] = json.dumps(
            {"sprites": [f"waymarks:{name}"]}, indent=2
        ).encode()
    return files


def write(out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out / "waymarks-pack.zip", "w", zipfile.ZIP_DEFLATED) as zf:
        for path, data in sorted(pack_files().items()):
            info = zipfile.ZipInfo(path, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)
    (out / "icons.txt").write_text("".join(f"{name}\n" for name in ICONS))


if __name__ == "__main__":
    write(sys.argv[1])
