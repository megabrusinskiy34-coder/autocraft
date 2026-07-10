#!/usr/bin/env python3
"""
Script to update API_URL in all ComputerCraft Lua files
Usage: python update_api_url.py https://your-app.railway.app
"""

import sys
import os
from pathlib import Path

def update_api_url(new_url):
    """Update API_URL in all Lua files"""
    
    # Remove trailing slash
    new_url = new_url.rstrip('/')
    
    # Files to update
    lua_files = [
        'computercraft/autocraft.lua',
        'computercraft/autocrafter_advanced.lua',
        'computercraft/quick_test.lua',
        'computercraft/depot_monitor.lua',
    ]
    
    updated_count = 0
    
    for lua_file in lua_files:
        file_path = Path(lua_file)
        
        if not file_path.exists():
            print(f"⚠️  File not found: {lua_file}")
            continue
        
        # Read file
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Replace API_URL
        old_pattern = 'local API_URL = "http://localhost:3000"'
        new_pattern = f'local API_URL = "{new_url}"'
        
        if old_pattern in content:
            content = content.replace(old_pattern, new_pattern)
            
            # Write back
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            
            print(f"✅ Updated: {lua_file}")
            updated_count += 1
        else:
            print(f"⚠️  Pattern not found in: {lua_file}")
    
    print(f"\n🎉 Updated {updated_count} files!")
    print(f"New API URL: {new_url}")
    print("\nNext steps:")
    print("1. Commit changes: git add . && git commit -m 'Update API URL'")
    print("2. Push to GitHub: git push")
    print("3. Copy Lua files to ComputerCraft in-game")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python update_api_url.py <railway_url>")
        print("Example: python update_api_url.py https://autocraft-production.up.railway.app")
        sys.exit(1)
    
    new_url = sys.argv[1]
    
    if not new_url.startswith('http'):
        print("❌ Error: URL must start with http:// or https://")
        sys.exit(1)
    
    update_api_url(new_url)
