# ComputerCraft Scripts

Скрипты для интеграции Create AutoCraft с ComputerCraft.

## Установка

### Шаг 1: Настройка HTTP API
В `config/computercraft-server.toml` или в игре через команду:
```
/computercraft set http_enable true
```

### Шаг 2: Добавить ваш сервер в whitelist
```toml
[http]
    enabled = true
    [[http.rules]]
        host = "your-app.up.railway.app"
        action = "allow"
```

### Шаг 3: Загрузить скрипты
```lua
-- В ComputerCraft компьютере:
wget https://your-github-url/autocraft.lua autocraft.lua
```

Или скопируй файлы вручную в папку:
`saves/<world>/computercraft/computer/<id>/`

## Скрипты

### 1. `autocraft.lua` - Главная система
Полноценный интерфейс для работы с API и депо.

**Использование:**
```lua
autocraft
```

**Функции:**
- Просмотр инвентаря депо
- Поиск предметов через API
- Получение рецептов
- Статистика системы

### 2. `quick_test.lua` - Быстрый тест
Проверка соединения с API.

```lua
quick_test
```

### 3. `depot_monitor.lua` - Мониторинг депо
Real-time отслеживание всех подключённых хранилищ.

```lua
depot_monitor
```

### 4. `autocrafter_advanced.lua` - Продвинутый авто-крафт
Полноценная система управления mechanical crafters и депо.

**Поддерживаемая схема:**
- 3 депо для mechanical press (depot_1, depot_2, depot_3)
- 9 mechanical crafter в сетке 3x3 (mechanical_crafter_1..9)
- 1 выходное депо (depot_4)

```lua
autocrafter_advanced
```

**Функции:**
- Автоматическое сканирование периферии
- Раскладка предметов по сетке крафта
- Поддержка shaped и mechanical crafting
- Интеграция с хранилищами

### 5. `test_setup.lua` - Тест конфигурации
Проверка подключения всех периферий.

```lua
test_setup
```

## Настройка

В начале каждого скрипта измени:
```lua
local API_URL = "http://localhost:3000"  -- → "https://your-app.railway.app"
local DEPOT_SIDE = "bottom"  -- сторона где подключен depot
```

## Подключение периферии

### Минимальная схема (для autocrafter_advanced)
```
                    [Computer]
                         |
                 [Wired Modem Network]
                         |
    ┌────────────────────┼────────────────────┐
    |                    |                    |
[depot_1]           [depot_2]            [depot_3]
(press input)       (press input)        (press input)
    |                    |                    |
[Mechanical Press]  [Mechanical Press]  [Mechanical Press]
    |                    |                    |
    └────────────────────┼────────────────────┘
                         |
              [Mechanical Crafters 3x3]
           (mechanical_crafter_1..9)
                         |
                    [depot_4]
                   (output)
```

### Расширенная сеть с хранилищами
```
[Computer] -- [Wired Modem] -- [Cable Network]
                                    |
                                +-- depot_1, depot_2, depot_3
                                +-- mechanical_crafter_1..9
                                +-- depot_4 (output)
                                +-- item_vault_5, item_vault_6 (Create Item Vaults)
                                +-- Storage Chest (опционально)
```

**Важно:** Create Item Vaults автоматически определяются по паттерну `item_vault_X`

## API Примеры

### Получить все предметы Create
```lua
local response = http.get(API_URL .. "/api/items?namespace=create")
local data = textutils.unserialiseJSON(response.readAll())
for _, item in ipairs(data.items) do
    print(item.id)
end
```

### Найти рецепт
```lua
local response = http.get(API_URL .. "/api/recipes/create__brass_ingot")
local data = textutils.unserialiseJSON(response.readAll())
print("Found " .. #data.recipes .. " recipes")
```

### Поиск
```lua
local response = http.get(API_URL .. "/api/search?q=gear")
local data = textutils.unserialiseJSON(response.readAll())
```

## Будущие фичи

- [ ] Автоматический крафт через mechanical arms
- [ ] Очередь заказов
- [ ] Расчёт цепочки крафта (дерево зависимостей)
- [ ] Интеграция с Applied Energistics через bridge
- [ ] Управление через redstone
