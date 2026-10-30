"""Packs the surroundings data (the submodule mapdata/WowVision_Surroundings, written as readable text by the
wv-surroundings exporter) for the game: the same data, smaller to load at login. git keeps the text; the packed
files are generated, git-ignored, and are what the TOCs load (mapdata/WowVision_SurroundingsPacked/<client>/data.xml,
the way tools/wownav-pack.lua packs the WowNav data).

- A zone file: its frame as it is, its JSON text compressed (zlib, Base64), decoded on zone entry
  (camelot/surroundings/store.lua: C_EncodingUtil.DecodeBase64 and DecompressString, then DeserializeJSON).
- A surfaces file: per layer its rows in bands of BAND rows, each band one compressed string of its rows (one line
  each, an empty line for a row with no surfaces), decoded only near the player (store.lua logic.bandRows).
- A places list file: copied as it is (small).

Every packed file names the SHA-1 of the text it was packed from. Nothing is lost: each packed file is unpacked
again and compared with its source before it is written. Deterministic: the same text gives the same files.

  py tools/surroundings-pack.py                   (from the repo root: every client folder of the data)
  py tools/surroundings-pack.py --check           (only report; exit code 1 when a packed file is stale)
  py tools/surroundings-pack.py --data <folder>   (another data checkout, e.g. the main one's from a worktree)
  py tools/surroundings-pack.py --client tbc      (one client folder only: the exporter's call after an export)
"""
import argparse
import base64
import hashlib
import os
import re
import sys
import zlib

BAND = 32           # rows per surfaces band (the tracker reads 16 rows around the player at most: 2 bands)
MARKER = "-- WowVision surroundings, packed by tools/surroundings-pack.py"
CLIENTS = ("forever", "tbc", "era")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "mapdata", "WowVision_Surroundings")
TARGET = os.path.join(ROOT, "mapdata", "WowVision_SurroundingsPacked")

ZONE_RE = re.compile(r"\A(?P<head>.*?)^addon\.addZone\((?P<frame>\{[^\n]*\}), \[=\[\n(?P<json>.*)\]=\]\)\n\Z", re.S | re.M)
SURF_HEAD_RE = re.compile(r'\A(?P<head>.*?)^addon\.addSurfaces\("(?P<key>[\w-]+)", \{\n', re.S | re.M)
LAYER_RE = re.compile(r"^  (?P<name>\w+) = \{ (?P<frame>x0 = -?\d+, y0 = -?\d+, rec = \d+), rows = \{\n(?P<rows>.*?)^  \} \},\n", re.S | re.M)
ROW_RE = re.compile(r'^    \[(\d+)\] = "([^"\\\n]*)",\n', re.M)


def pack_text(text):
    return base64.b64encode(zlib.compress(text.encode("utf-8"), 9)).decode("ascii")


def unpack_text(packed):
    return zlib.decompress(base64.b64decode(packed)).decode("utf-8")


def sha1(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def head(source_name, source):
    return f"{MARKER} from {source_name} (sha1 {sha1(source)}); do not edit, run the pack again.\nlocal _, addon = ...\n"


def pack_zone(name, text):
    m = ZONE_RE.match(text)
    if not m:
        raise SystemExit(f"{name}: not a zone file of the expected layout")
    frame = m.group("frame")
    if "deflated" in frame:
        raise SystemExit(f"{name}: already packed")
    packed = pack_text(m.group("json"))
    if unpack_text(packed) != m.group("json"):
        raise SystemExit(f"{name}: the packed JSON does not unpack to its source")
    return head(name, text) + f'addon.addZone({frame[:-2]}, deflated = true }}, "{packed}")\n'


def surface_layers(name, text):
    """[(layer name, frame text, {row: record string})], checked to hold every row line of the file."""
    m = SURF_HEAD_RE.match(text)
    if not m:
        raise SystemExit(f"{name}: not a surfaces file of the expected layout")
    layers = []
    rows_seen = 0
    for lm in LAYER_RE.finditer(text):
        rows = {int(r): s for r, s in ROW_RE.findall(lm.group("rows"))}
        if ROW_RE.sub("", lm.group("rows")) != "":
            raise SystemExit(f"{name}: layer {lm.group('name')} has lines that are no rows")
        layers.append((lm.group("name"), lm.group("frame"), rows))
        rows_seen += len(rows)
    if rows_seen != len(re.findall(r'^    \[\d+\] = "', text, re.M)):
        raise SystemExit(f"{name}: not every row was read")
    return m.group("key"), layers


def bands_of(rows):
    """{band: packed string} of a layer's rows: band b holds rows b*BAND .. b*BAND + BAND - 1, one line each."""
    out = {}
    for b in sorted({r // BAND for r in rows}):
        lines = [rows.get(r, "") for r in range(b * BAND, b * BAND + BAND)]
        out[b] = pack_text("\n".join(lines))
    return out


def rows_of(bands):
    rows = {}
    for b, packed in bands.items():
        for i, s in enumerate(unpack_text(packed).split("\n")):
            if s:
                rows[b * BAND + i] = s
    return rows


def pack_surfaces(name, text):
    key, layers = surface_layers(name, text)
    out = [head(name, text), f'addon.addSurfaces("{key}", {{\n']
    for lname, frame, rows in layers:
        bands = bands_of(rows)
        if rows_of(bands) != rows:
            raise SystemExit(f"{name}: layer {lname}: the bands do not unpack to its rows")
        out.append(f"  {lname} = {{ {frame}, band = {BAND}, bands = {{\n")
        for b, packed in bands.items():
            out.append(f'    [{b}] = "{packed}",\n')
        out.append("  } },\n")
    out.append("})\n")
    return "".join(out)


def scripts_of(data_xml):
    return re.findall(r'<Script file="([^"]+)" />', data_xml)


def plan(data, client):
    """{relative path: packed text} of one client folder, data.xml included."""
    src = os.path.join(data, client)
    with open(os.path.join(src, "data.xml"), encoding="utf-8") as f:
        xml = f.read()
    files = {}
    for rel in scripts_of(xml):
        path = os.path.join(src, *rel.split("\\"))
        with open(path, encoding="utf-8", newline="") as f:
            text = f.read()
        name = client + "/" + rel.replace("\\", "/")
        if rel.startswith("places\\"):
            files[rel] = text
        elif rel.endswith("-surfaces.lua"):
            files[rel] = pack_surfaces(name, text)
        else:
            files[rel] = pack_zone(name, text)
    lines = [
        '<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.blizzard.com/wow/ui/\n..\\FrameXML\\UI.xsd">',
        f"  <!-- Generated by WowVision tools/surroundings-pack.py from the data's {client}\\data.xml; do not edit. -->",
    ]
    lines += [f'  <Script file="{rel}" />' for rel in files]
    lines.append("</Ui>\n")
    files["data.xml"] = "\n".join(lines)
    return files


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="only report stale packed files")
    ap.add_argument("--data", default=DATA, help="the surroundings data folder (default: the submodule)")
    ap.add_argument("--out", default=TARGET, help="the packed output folder")
    ap.add_argument("--client", choices=CLIENTS, help="only this client folder")
    args = ap.parse_args()
    stale = 0
    for client in [args.client] if args.client else CLIENTS:
        if not os.path.isfile(os.path.join(args.data, client, "data.xml")):
            continue
        files = plan(args.data, client)
        before = after = 0
        for rel, text in files.items():
            path = os.path.join(args.out, client, *rel.split("\\"))
            old = None
            if os.path.isfile(path):
                with open(path, encoding="utf-8", newline="") as f:
                    old = f.read()
            if rel != "data.xml":
                src = os.path.join(args.data, client, *rel.split("\\"))
                before += os.path.getsize(src)
            after += len(text.encode("utf-8"))
            if old == text:
                continue
            stale += 1
            if args.check:
                print(f"stale: {client}/{rel}")
                continue
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8", newline="") as f:
                f.write(text)
        # packed files the data no longer has
        folder = os.path.join(args.out, client)
        for dirpath, _, names in os.walk(folder):
            for n in names:
                rel = os.path.relpath(os.path.join(dirpath, n), folder).replace("/", "\\").replace(os.sep, "\\")
                if rel not in files:
                    stale += 1
                    if args.check:
                        print(f"left over: {client}/{rel}")
                    else:
                        os.remove(os.path.join(dirpath, n))
                        print(f"removed left over {client}/{rel}")
        print(f"{client}: {len(files) - 1} files, {before / 1e6:.2f} MB of text packed to {after / 1e6:.2f} MB")
    if args.check:
        print("packed data up to date" if stale == 0 else f"{stale} packed files stale: run tools/surroundings-pack.py")
        sys.exit(1 if stale else 0)
    print(f"{stale} files written or removed")


if __name__ == "__main__":
    main()
