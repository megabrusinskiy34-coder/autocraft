# Create AutoCraft

Web-based ME System interface for Create mod autocrafting with ComputerCraft integration.

## Features

- 🎨 AE2-inspired dark UI
- 🔍 Search & filter 5449 recipes from Create mods
- 🖼️ 1297 item textures (inventory sprites)
- 🌐 REST API for ComputerCraft HTTP integration
- 🚀 Ready for Railway deployment

## Quick Start

```bash
npm install
npm start
```

Open http://localhost:3000

## API Endpoints

- `GET /api/items` - List all craftable items
- `GET /api/recipes/:itemId` - Get recipes for an item
- `GET /api/search?q=brass` - Search items/recipes
- `GET /api/stats` - Get statistics

## ComputerCraft Example

```lua
local response = http.get("http://your-url.railway.app/api/items?namespace=create")
local data = textutils.unserialiseJSON(response.readAll())
for _, item in ipairs(data.items) do
  print(item.id)
end
```

## Deployment (Railway)

1. Push to GitHub
2. Connect to Railway
3. Set start command: `npm start`
4. Deploy

## Mods Included

- Create (1906 recipes)
- Create Deco (1569 recipes)
- TFMG (603 recipes)
- Farmer's Delight (333 recipes)
- Create: Big Cannons (148 recipes)
- And more...
