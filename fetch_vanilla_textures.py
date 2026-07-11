#!/usr/bin/env python3
"""
Downloads vanilla Minecraft item textures from the official Minecraft assets
GitHub mirror (InventivetalentDev/minecraft-assets) for 1.21.1.

Usage: python fetch_vanilla_textures.py
"""

import json
import urllib.request
import urllib.error
from pathlib import Path

OUTPUT_DIR = Path("output")
TEXTURES_DIR = OUTPUT_DIR / "textures"
ITEM_TEXTURES_FILE = OUTPUT_DIR / "item_textures.json"

# Minecraft 1.21.1 assets mirror on GitHub
BASE_URL_ITEM = "https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.1/assets/minecraft/textures/item"
BASE_URL_BLOCK = "https://raw.githubusercontent.com/InventivetalentDev/minecraft-assets/1.21.1/assets/minecraft/textures/block"

# Items that appear in our recipes_db as minecraft: namespace
# We'll scan recipes_db to find which ones we need


def get_needed_items():
    """Read recipes_db.json and find all minecraft: items used as ingredients or results."""
    recipes_db_file = OUTPUT_DIR / "recipes_db.json"
    if not recipes_db_file.exists():
        print("ERROR: output/recipes_db.json not found. Run extract.py first.")
        return set()

    db = json.loads(recipes_db_file.read_text(encoding="utf-8"))
    items = set()

    for recipe_id, recipe in db.items():
        data = recipe.get("data", {})

        # Collect result items
        result = data.get("result")
        if result:
            if isinstance(result, str) and result.startswith("minecraft:"):
                items.add(result.split(":")[1])
            elif isinstance(result, dict):
                r = result.get("item") or result.get("id")
                if r and r.startswith("minecraft:"):
                    items.add(r.split(":")[1])

        # Collect ingredient items from keys (shaped recipes)
        key = data.get("key", {})
        for k, v in key.items():
            ingredient = None
            if isinstance(v, dict):
                ingredient = v.get("item")
            elif isinstance(v, list) and v:
                ingredient = v[0].get("item") if isinstance(v[0], dict) else None
            if ingredient and isinstance(ingredient, str) and ingredient.startswith("minecraft:"):
                items.add(ingredient.split(":")[1])

        # Collect from ingredients list
        ingredients = data.get("ingredients", [])
        if isinstance(ingredients, list):
            for ing in ingredients:
                if isinstance(ing, dict):
                    ingredient = ing.get("item")
                    if ingredient and isinstance(ingredient, str) and ingredient.startswith("minecraft:"):
                        items.add(ingredient.split(":")[1])
                elif isinstance(ing, str) and ing.startswith("minecraft:"):
                    items.add(ing.split(":")[1])

    return items


def download_texture(item_name):
    """Try to download texture for a vanilla item. Returns bytes or None.
    Tries item/ folder first, then block/ folder as fallback."""
    for base_url in [BASE_URL_ITEM, BASE_URL_BLOCK]:
        url = f"{base_url}/{item_name}.png"
        try:
            with urllib.request.urlopen(url, timeout=10) as response:
                return response.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                continue  # try next folder
            print(f"  HTTP {e.code} for {item_name}")
            return None
        except Exception as e:
            print(f"  Error for {item_name}: {e}")
            return None
    return None


def main():
    print("=== Vanilla Minecraft Texture Downloader ===\n")
    TEXTURES_DIR.mkdir(parents=True, exist_ok=True)

    # Load existing texture map
    item_texture_map = {}
    if ITEM_TEXTURES_FILE.exists():
        item_texture_map = json.loads(ITEM_TEXTURES_FILE.read_text(encoding="utf-8"))
    print(f"Existing textures: {len(item_texture_map)}")

    # Get items we need
    needed = get_needed_items()
    print(f"Minecraft items needed from recipes: {len(needed)}")

    # Common vanilla items that should always be available
    common_items = {
        "iron_ingot", "gold_ingot", "copper_ingot", "netherite_ingot",
        "diamond", "emerald", "coal", "charcoal", "redstone",
        "stick", "string", "leather", "iron_nugget", "gold_nugget",
        "raw_iron", "raw_gold", "raw_copper",
        "oak_planks", "spruce_planks", "birch_planks", "jungle_planks",
        "acacia_planks", "dark_oak_planks", "mangrove_planks", "cherry_planks",
        "oak_log", "spruce_log", "birch_log",
        "cobblestone", "stone", "granite", "diorite", "andesite",
        "sand", "gravel", "clay_ball", "clay",
        "iron_block", "gold_block", "diamond_block",
        "lapis_lazuli", "lapis_block",
        "wheat", "bread", "apple", "egg",
        "bucket", "water_bucket", "lava_bucket",
        "glass", "glass_pane", "quartz",
        "magma_cream", "blaze_rod", "blaze_powder",
        "slime_ball", "gunpowder", "sugar", "paper", "book",
        "bone", "bone_meal", "feather", "arrow",
        "ender_pearl", "ender_eye", "shulker_shell",
        "glowstone_dust", "glowstone",
        "nether_brick", "nether_wart", "netherbrick",
        "obsidian", "flint", "flint_and_steel",
        "axe", "pickaxe", "shovel", "sword", "hoe",
        "iron_axe", "iron_pickaxe", "iron_shovel", "iron_sword", "iron_hoe",
        "golden_axe", "golden_pickaxe", "golden_shovel", "golden_sword", "golden_hoe",
        "diamond_axe", "diamond_pickaxe", "diamond_shovel", "diamond_sword", "diamond_hoe",
        "chainmail_helmet", "chainmail_chestplate", "chainmail_leggings", "chainmail_boots",
        "iron_helmet", "iron_chestplate", "iron_leggings", "iron_boots",
        "golden_helmet", "golden_chestplate", "golden_leggings", "golden_boots",
        "diamond_helmet", "diamond_chestplate", "diamond_leggings", "diamond_boots",
        "netherite_helmet", "netherite_chestplate", "netherite_leggings", "netherite_boots",
        "crafting_table", "furnace", "chest", "barrel",
        "lever", "stone_button", "oak_button",
        "comparator", "repeater",
        "piston", "sticky_piston",
        "dispenser", "dropper", "hopper",
        "cauldron", "brewing_stand",
        "anvil", "grindstone", "smithing_table",
        "amethyst_shard", "copper_block",
        "dripstone", "pointed_dripstone",
        "tuff", "calcite", "deepslate",
    }
    needed.update(common_items)

    downloaded = 0
    skipped = 0
    failed = 0

    items_list = sorted(needed)
    print(f"Total items to fetch: {len(items_list)}\n")

    for i, item_name in enumerate(items_list):
        item_id = f"minecraft:{item_name}"

        # Skip if already have it
        if item_id in item_texture_map:
            skipped += 1
            continue

        # Check if file already exists
        out_name = f"minecraft__{item_name}.png"
        out_path = TEXTURES_DIR / out_name
        if out_path.exists():
            item_texture_map[item_id] = f"textures/{out_name}"
            skipped += 1
            continue

        # Download
        print(f"  [{i+1}/{len(items_list)}] {item_name}... ", end="", flush=True)
        data = download_texture(item_name)

        if data:
            out_path.write_bytes(data)
            item_texture_map[item_id] = f"textures/{out_name}"
            downloaded += 1
            print(f"✓ ({len(data)} bytes)")
        else:
            failed += 1
            print("✗ not found")

    # Save updated texture map
    ITEM_TEXTURES_FILE.write_text(
        json.dumps(item_texture_map, indent=2, ensure_ascii=False),
        encoding="utf-8"
    )

    print(f"\n✓ Downloaded: {downloaded}")
    print(f"✓ Skipped (already had): {skipped}")
    print(f"✗ Not found: {failed}")
    print(f"✓ Total textures: {len(item_texture_map)}")
    print("\nDone! Vanilla textures added to output/textures/")


if __name__ == "__main__":
    main()
