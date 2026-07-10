# 🚀 Deployment Guide - Create AutoCraft

## Текущий статус
- ✅ Код готов к деплою
- ✅ Railway конфигурация готова
- ✅ Git репозиторий инициализирован
- ⏳ Нужно: залить на GitHub и подключить Railway

---

## Шаг 1: Создать GitHub репозиторий

1. Открой https://github.com/new
2. Создай новый репозиторий:
   - **Name**: `autocraft` (или любое другое имя)
   - **Public/Private**: по твоему выбору
   - ⚠️ **НЕ** ставь галочки на README, .gitignore, license (уже есть)
3. Скопируй URL репозитория (будет показан после создания)

---

## Шаг 2: Залить код на GitHub

```bash
# Добавить remote (замени YOUR_USERNAME на своё имя)
git remote add origin https://github.com/YOUR_USERNAME/autocraft.git

# Залить код
git push -u origin master
```

Если попросит авторизацию:
- Username: твой GitHub username
- Password: используй **Personal Access Token** (не пароль!)
  - Создать токен: https://github.com/settings/tokens
  - Scopes: выбери `repo`

---

## Шаг 3: Deploy на Railway

### 3.1. Создать проект
1. Открой https://railway.app
2. "New Project" → "Deploy from GitHub repo"
3. Выбери репозиторий `autocraft`

### 3.2. Railway автоматически:
- Обнаружит Node.js проект
- Прочитает `Procfile` и `nixpacks.toml`
- Установит зависимости
- Запустит `npm start`

### 3.3. Получить URL
После деплоя Railway даст публичный URL типа:
```
https://autocraft-production-xxxx.up.railway.app
```

Скопируй этот URL!

---

## Шаг 4: Обновить ComputerCraft скрипты

Открой каждый .lua файл в `computercraft/` и замени:

```lua
-- БЫЛО:
local API_URL = "http://localhost:3000"

-- СТАЛО:
local API_URL = "https://autocraft-production-xxxx.up.railway.app"
```

Файлы для обновления:
- ✅ `autocraft.lua`
- ✅ `autocrafter_advanced.lua`
- ✅ `quick_test.lua`
- ✅ `depot_monitor.lua`

---

## Шаг 5: Настроить ComputerCraft в игре

### 5.1. Включить HTTP API
В `config/computercraft-server.toml`:

```toml
[http]
    enabled = true
    
    [[http.rules]]
        host = "*"
        action = "allow"
```

Или через команду:
```
/computercraft set http_enable true
```

### 5.2. Загрузить скрипты в игру

**Вариант А: Через wget (если есть GitHub Pages или raw)**
```lua
wget https://raw.githubusercontent.com/YOUR_USERNAME/autocraft/master/computercraft/autocrafter_advanced.lua startup.lua
```

**Вариант Б: Ручное копирование**
1. Найди папку сохранения мира:
   ```
   saves/<world_name>/computercraft/computer/<computer_id>/
   ```
2. Скопируй .lua файлы туда

---

## Шаг 6: Подключить периферию

### Минимальная схема для autocrafter_advanced:

```
[Computer] + [Wired Modem]
      |
  [Cable Network] ────┬─── depot_1
                      ├─── depot_2
                      ├─── depot_3
                      ├─── mechanical_crafter_1
                      ├─── mechanical_crafter_2
                      ├─── ... (3-9)
                      ├─── depot_4 (output)
                      └─── Storage Chest(s)
```

**Важно:**
- Используй Wired Modem на каждом устройстве
- Правый клик на modem чтобы активировать (красный свет)
- Названия периферий должны соответствовать:
  - `create:depot_1`, `create:depot_2`, `create:depot_3` (input)
  - `create:mechanical_crafter_1..9` (crafters 3x3)
  - `create:depot_4` (output)

---

## Шаг 7: Запустить и протестировать

В ComputerCraft компьютере:

```lua
-- Тест подключения к API
quick_test

-- Проверка периферии
test_setup

-- Запуск полной системы
autocrafter_advanced
```

### Тест крафта:
1. В меню выбери "1. Scan Devices" - проверь что все найдено
2. Положи предметы в Storage Chest
3. Выбери "2. Craft Item"
4. Введи ID предмета, например: `create:brass_ingot`

---

## Troubleshooting

### "Connection failed" в ComputerCraft
- ✅ Проверь что HTTP API включен
- ✅ Railway URL правильный (с https://)
- ✅ Сервер на Railway запущен (открой URL в браузере)

### "Item not found" при крафте
- ✅ Предмет должен быть в Storage Chest
- ✅ Используй полный ID с namespace: `create:brass_ingot`, не просто `brass_ingot`

### Периферия не найдена
- ✅ Wired Modem активирован (красный свет)
- ✅ Все устройства соединены кабелями
- ✅ Правильные названия (depot_1, не depot1)

### Railway деплой упал
- ✅ Проверь логи в Railway dashboard
- ✅ Убедись что `output/` папка закоммичена
- ✅ Проверь что node_modules в .gitignore

---

## Следующие шаги (опционально)

1. **Автозапуск**: Переименуй скрипт в `startup.lua`
2. **Мониторы**: Подключи Advanced Monitor для GUI
3. **Redstone**: Добавь сигналы для автоматизации
4. **Очередь**: Реализуй систему заказов с приоритетами

---

## Полезные ссылки

- 🌐 Railway Dashboard: https://railway.app/dashboard
- 📚 ComputerCraft Wiki: https://tweaked.cc/
- 🔧 Create Mod Wiki: https://create.fandom.com/wiki/

---

**Готово! Теперь у тебя полноценная система автокрафта через ComputerCraft! 🎉**
