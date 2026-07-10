#!/usr/bin/env python3
"""
Extracts recipes and item textures (inventory sprites) from mod JARs.

Strategy:
  1. Scan all JARs once, collect everything into memory dicts.
  2. For each item model JSON, resolve which texture PNG it needs.
  3. Write resolved PNGs to output/textures/
  4. Write recipes_db.json, recipes_index.json, item_textures.json
"""

import json
import zipfile
import shutil
from pathlib import Path

MODS_DIR   = Path("mods")
OUTPUT_DIR = Path("output")
TEXTURES_DIR = OUTPUT_DIR / "textures"

TARGET_NS = {
    "create", "createaddition", "create_aeronautics", "create_connected",
    "create_things_and_misc", "createbigcannons", "createdeco",
    "create_new_age", "create_stuff_additions", "createcobblestone",
    "create_netherless", "create_mobile_packages", "createoreexcavation",
    "createpropulsion", "createdieselgenerators", "create_dragons_plus",
    "tfmg", "farmersdelight", "minecraft",
}

def main():
    print("=== Create AutoCraft Extractor ===\n")

    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    TEXTURES_DIR.mkdir(parents=True, exist_ok=True)

    jars = sorted(f for f in MODS_DIR.iterdir()
                  if f.suffix == ".jar" and not f.name.endswith(".disabled"))
    print(f"Found {len(jars)} JARs\n")

    all_recipes  = []          # list of dicts
    item_models  = {}          # "ns:item" -> tex_ref string
    # raw_tex_data: "ns:path/without/ext" -> bytes  (path = e.g. "item/brass_ingot")
    raw_tex_data = {}

    # ── PASS 1: read everything from JARs ─────────────────────────────────────
    for jar_path in jars:
        print(f"  {jar_path.name}")
        try:
            with zipfile.ZipFile(jar_path, "r") as zf:
                for name in zf.namelist():
                    parts = name.split("/")

                    # RECIPES: data/<ns>/recipe(s)/...json  (Create 6.x uses /recipe/, older use /recipes/)
                    if (name.startswith("data/") and
                            (("/recipes/" in name) or ("/recipe/" in name)) and
                            name.endswith(".json") and len(parts) >= 4
                            and "advancement" not in name):
                        ns = parts[1]
                        if ns not in TARGET_NS:
                            continue
                        try:
                            data = json.loads(zf.read(name))
                        except Exception:
                            continue
                        rid = (name
                               .removeprefix("data/")
                               .replace("/recipes/", ":", 1)
                               .removesuffix(".json"))
                        all_recipes.append({
                            "id": rid, "namespace": ns,
                            "type": data.get("type", "unknown"),
                            "source_jar": jar_path.name,
                            "data": data,
                        })

                    # ITEM MODELS: assets/<ns>/models/item/<name>.json
                    elif (name.startswith("assets/") and "/models/item/" in name
                            and name.endswith(".json") and len(parts) >= 5):
                        ns = parts[1]
                        if ns not in TARGET_NS:
                            continue
                        try:
                            model = json.loads(zf.read(name))
                        except Exception:
                            continue
                        tex = model.get("textures", {})
                        ref = (tex.get("layer0") or tex.get("layer1") or
                               tex.get("all") or tex.get("texture") or
                               (next(iter(tex.values()), None) if tex else None))
                        if ref:
                            item_name = Path(name).stem
                            item_models[f"{ns}:{item_name}"] = ref

                    # RAW TEXTURES: assets/<ns>/textures/**/*.png
                    elif (name.startswith("assets/") and "/textures/" in name
                            and name.endswith(".png") and len(parts) >= 5):
                        ns = parts[1]
                        if ns not in TARGET_NS:
                            continue
                        # tex_inner = everything after "textures/" without .png
                        # e.g. "item/brass_ingot"
                        tex_idx = parts.index("textures") + 1
                        tex_inner = "/".join(parts[tex_idx:]).removesuffix(".png")
                        key = f"{ns}:{tex_inner}"
                        if key not in raw_tex_data:
                            raw_tex_data[key] = zf.read(name)

        except zipfile.BadZipFile:
            print(f"    [SKIP] bad zip")
        except Exception as e:
            print(f"    [ERROR] {e}")

    print(f"\n✓ Recipes:      {len(all_recipes)}")
    print(f"✓ Item models:  {len(item_models)}")
    print(f"✓ Raw textures: {len(raw_tex_data)}")

    # ── PASS 2: resolve item textures ──────────────────────────────────────────
    item_texture_map = {}
    saved = missing = 0

    for item_id, ref in item_models.items():
        ns, item_name = item_id.split(":", 1)

        # ref can be "create:item/foo" or "item/foo" or "block/foo"
        if ":" in ref:
            ref_ns, ref_path = ref.split(":", 1)
        else:
            ref_ns, ref_path = ns, ref

        lookup = f"{ref_ns}:{ref_path}"
        png_bytes = raw_tex_data.get(lookup)

        # fallback: try item/<item_name> in same ns
        if png_bytes is None:
            lookup2 = f"{ns}:item/{item_name}"
            png_bytes = raw_tex_data.get(lookup2)

        if png_bytes:
            # flatten any subpath slashes to __ to avoid nested dirs
            safe_name = item_name.replace("/", "__").replace("\\", "__")
            out_name = f"{ns}__{safe_name}.png"
            (TEXTURES_DIR / out_name).write_bytes(png_bytes)
            item_texture_map[item_id] = f"textures/{out_name}"
            saved += 1
        else:
            missing += 1

    # Also save every item/ texture that has no model (direct sprites)
    for key, png_bytes in raw_tex_data.items():
        ns, path = key.split(":", 1)
        if not path.startswith("item/"):
            continue
        item_name = path.removeprefix("item/")
        item_id   = f"{ns}:{item_name}"
        if item_id not in item_texture_map:
            safe_name = item_name.replace("/", "__").replace("\\", "__")
            out_name = f"{ns}__{safe_name}.png"
            (TEXTURES_DIR / out_name).write_bytes(png_bytes)
            item_texture_map[item_id] = f"textures/{out_name}"
            saved += 1

    print(f"✓ Textures saved:  {saved}  |  missing: {missing}")

    # ── PASS 3: write output files ─────────────────────────────────────────────
    db = {r["id"]: {"type": r["type"], "namespace": r["namespace"], "data": r["data"]}
          for r in all_recipes}
    (OUTPUT_DIR / "recipes_db.json").write_text(
        json.dumps(db, indent=2, ensure_ascii=False), encoding="utf-8")

    idx = {"total": len(all_recipes), "by_type": {}, "by_namespace": {}, "recipes": []}
    for r in all_recipes:
        idx["by_type"][r["type"]]           = idx["by_type"].get(r["type"], 0) + 1
        idx["by_namespace"][r["namespace"]] = idx["by_namespace"].get(r["namespace"], 0) + 1
        idx["recipes"].append({"id": r["id"], "namespace": r["namespace"], "type": r["type"]})
    (OUTPUT_DIR / "recipes_index.json").write_text(
        json.dumps(idx, indent=2, ensure_ascii=False), encoding="utf-8")

    (OUTPUT_DIR / "item_textures.json").write_text(
        json.dumps(item_texture_map, indent=2, ensure_ascii=False), encoding="utf-8")

    print(f"\n✓ recipes_db.json      → {len(db)} recipes")
    print(f"✓ item_textures.json   → {len(item_texture_map)} items")

    print("\n--- By type ---")
    for t, c in sorted(idx["by_type"].items(), key=lambda x: -x[1]):
        print(f"  {t}: {c}")
    print("\n--- By namespace ---")
    for ns, c in sorted(idx["by_namespace"].items(), key=lambda x: -x[1]):
        print(f"  {ns}: {c}")

    print("\nDone! → output/")

if __name__ == "__main__":
    main()
