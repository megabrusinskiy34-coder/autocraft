# 🔧 Create AutoCraft

Web-based ME System interface for Create mod autocrafting with ComputerCraft integration.

Полная система для автоматизации крафта в Minecraft Create через ComputerCraft и веб-интерфейс в стиле Applied Energistics.

## ✨ Features

- 🎨 **AE2-inspired dark UI** - точная копия интерфейса ME System
- 🔍 **5449 рецептов** из Create и всех аддонов
- 🖼️ **1297 текстур предметов** (inventory sprites)
- 🤖 **ComputerCraft интеграция** - полный контроль через Lua
- 🌐 **REST API** для HTTP запросов из игры
- 🚀 **Railway ready** - готов к деплою в один клик
- ⚙️ **Mechanical Crafter support** - автоматическая раскладка по сетке 3x3
- 📦 **Smart inventory** - автоматический поиск предметов в хранилищах

## 🚀 Quick Start

### Локально:
```bash
npm install
npm start
```
Открой http://localhost:3000

### Railway деплой:
Смотри **[QUICK_START.md](QUICK_START.md)** для пошаговой инструкции

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
