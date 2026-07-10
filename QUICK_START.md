# ⚡ Quick Start - Create AutoCraft

## 📋 Checklist

- [ ] Создать GitHub репозиторий
- [ ] Залить код на GitHub
- [ ] Создать проект на Railway
- [ ] Получить Railway URL
- [ ] Обновить API_URL в .lua файлах
- [ ] Настроить ComputerCraft HTTP
- [ ] Загрузить скрипты в игру
- [ ] Подключить периферию
- [ ] Протестировать

---

## 🚀 Быстрые команды

### 1. Создать GitHub репозиторий
Открой: https://github.com/new

### 2. Залить на GitHub
```bash
git remote add origin https://github.com/YOUR_USERNAME/autocraft.git
git push -u origin master
```

### 3. Deploy на Railway
Открой: https://railway.app → New Project → Deploy from GitHub repo

### 4. Обновить API URL
После получения Railway URL:
```bash
# Windows
update_url.bat https://your-app.railway.app

# Или вручную через Python
python update_api_url.py https://your-app.railway.app
```

### 5. Закоммитить изменения
```bash
git add .
git commit -m "Update API URL for Railway"
git push
```

---

## 🎮 В Minecraft

### Настроить HTTP в config/computercraft-server.toml:
```toml
[http]
    enabled = true
```

### Скопировать .lua файлы в:
```
saves/<world>/computercraft/computer/<id>/
```

### Или использовать wget в игре:
```lua
wget https://raw.githubusercontent.com/YOUR_USERNAME/autocraft/master/computercraft/autocrafter_advanced.lua startup.lua
```

### Запустить:
```lua
startup
```

---

## 🔌 Схема подключения

```
Computer + Wired Modem
    |
Cable Network:
    ├── depot_1 (press input)
    ├── depot_2 (press input)  
    ├── depot_3 (press input)
    ├── mechanical_crafter_1
    ├── mechanical_crafter_2
    ├── ... (до 9)
    ├── depot_4 (output)
    └── Storage Chest
```

**Важно:**
- Правый клик на каждом Wired Modem (должен гореть красным)
- Все соединено кабелями
- Storage Chest для материалов

---

## ✅ Быстрый тест

1. **Тест API:**
```lua
quick_test
```

2. **Проверка периферии:**
```lua
test_setup
```

3. **Запуск системы:**
```lua
autocrafter_advanced
```

4. **Тест крафта:**
   - Scan Devices
   - Положить предметы в Storage Chest
   - Craft Item → `create:brass_ingot`

---

## 📊 Доступные предметы

Система поддерживает **5449 рецептов** из модов:
- ✅ Create
- ✅ Create: New Age
- ✅ Create: Stuff & Additions
- ✅ Create: Big Cannons
- ✅ Create: Aeronautics
- ✅ Create Addition (электричество)
- ✅ И все другие Create аддоны
- ✅ Vanilla Minecraft

---

## 🌐 API Endpoints (для разработки)

```bash
# Все предметы
GET /api/items?search=brass&namespace=create

# Рецепты для предмета
GET /api/recipes/create__brass_ingot

# Поиск
GET /api/search?q=gear

# Статистика
GET /api/stats
```

---

## 🐛 Проблемы?

**Смотри полный гайд:** [DEPLOYMENT.md](DEPLOYMENT.md)

**ComputerCraft не подключается:**
- Проверь HTTP в конфиге
- Используй `https://` в URL
- Railway должен быть запущен

**Периферия не найдена:**
- Активируй Wired Modem (красный свет)
- Проверь названия (depot_1, не depot1)
- Все соединено кабелями

---

## 🎯 Результат

После настройки ты сможешь:
- 🔍 Искать предметы через веб-интерфейс
- 📖 Смотреть рецепты с картинками
- 🤖 Автоматически крафтить через ComputerCraft
- 📦 Управлять инвентарём и очередью
- 🌐 Использовать из любой точки мира (Railway)

**Удачи! 🚀**
