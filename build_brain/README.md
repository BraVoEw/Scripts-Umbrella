# Build Brain

![Downloads](https://img.shields.io/github/downloads/BraVoEw/Scripts-Umbrella/total?label=%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BE%D0%BA)

Скрипт для Umbrella (Dota 2). Показывает в магазине сборку на твоего героя и роль по свежим пабам высокого рейтинга, а сверху подсказывает, что собрать против конкретных врагов в этой игре и зачем.

**[Скачать последнюю версию](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/build-brain-v2.2.0/build_brain.lua)**

## Что умеет

**Панель в магазине** вместо гайда Доты:
- Роль сверху, можно переключить на любую из пяти.
- Начальный закуп и ранняя игра собраны по играм топ-игроков на этом герое, основные предметы по статистике текущего патча. На каждом предмете минута, когда его обычно берут.
- «Против врагов»: предметы под твоих врагов с их портретами. Наведи, и увидишь причину и чем предмет поможет. Например, Гост → Нуллифаер, пассивки Бристлбэка → Сильвер Эдж, хекс Лиона → Линка. Предлагаются только предметы, которые твой герой на этой позиции реально покупает.
- Порядок прокачки и таланты, которые берут чаще всего.
- ЛКМ открывает рецепт предмета: из чего собирается и во что входит. Ctrl или Shift + ЛКМ кидает предмет в квикбай, его можно и перетащить мышкой. ПКМ покупает то, на что хватает золота.
- Автобай (в настройках): только стартовый закуп или вся сборка по частям по мере золота, каждая покупка пишется в чат.

**Панель на пиках** появляется сама, когда начинается выбор героев:
- Шанс на победу и пики обеих команд.
- Кого взять на твою роль: мета-герои этой позиции, отсортированные по винрейту на ней и по тому, как они играют против уже выбранных врагов. Советы есть с первого пика. Если отметил своих героев, сверху 2 лучших из них.
- Клик по герою отмечает его, кнопка «Пикнуть» берёт его.
- «Тиммейтам»: по 3 героя на каждого тиммейта без героя, под его роль и против выбранных врагов. Клик по герою предлагает его команде через чат Доты.
- Разведка: на ком каждый враг играл последние 30 дней и с каким винрейтом, рамка подсказывает бан.
- Топ-3 подсвечиваются прямо в сетке героев Доты.
- Панель можно перетащить за шапку, место запоминается. Кнопка справа открывает полное окно.

**Окно** (по клавише):
- Драфт: кого пикнуть на твою роль и почему, кого опасаться у врагов и что против них брать, шанс на победу и таблица «кто кого».
- Сборка: следующий предмет сверху, вся сборка одной лентой по этапам с минутами по твоему доходу, против каждой угрозы несколько вариантов предметов и кто тебя убивает в этой игре. Любой предмет можно пропустить или заменить, наведя на него.
- Бой: какой урон тебе наносят вражеские герои и кто именно, разбор последней смерти, у кого из врагов ульта или BKB на кулдауне и кого можно бить прямо сейчас.

Если тебя в основном бьют магией или ты часто стоишь в контроле, скрипт это заметит и подскажет защиту.

## Откуда сборки

- Сборки считаются по матчам Божества и Титана на текущем патче, данные STRATZ.
- Робот на GitHub пересобирает их два раза в неделю, а после нового патча, как только наберутся игры.
- Скрипт раз в час проверяет, есть ли свежий файл, и скачивает его, около 0.8 МБ. Если интернета нет, работает с последним скачанным. Если GitHub недоступен, файл качается через зеркало jsDelivr.
- Матчапы в драфте и роли героев считаются по пабам высокого рейтинга (STRATZ), общий винрейт героя на твоём ранге берётся из OpenDota.
- Скрипт ничего не отправляет о тебе и твоём аккаунте. Для разведки он спрашивает у OpenDota открытую статистику врагов по их ID.

## Установка

1. Скачай `build_brain.lua` по ссылке выше.
2. Положи его в папку `scripts` Umbrella.
3. Перезагрузи Lua-скрипты.
4. В `Scripts → Scripts → Build Brain` назначь клавишу окна.
5. Открой магазин в игре.

При первом запуске откроется короткая настройка (роль, свои герои, режим игры), а скрипт скачает файл со сборками, это занимает пару секунд.

## Настройки

В меню Umbrella: «Включить», клавиша окна и кнопка нашего Telegram канала. Остальное в самом окне на вкладке «Настройки»: роль, ранг для винрейта героев (выбранный ранг и выше), режим игры, свои герои, автобай, стиль окна, панель на стадии пиков, панель в магазине и размер окна.

## Обновления

Скрипт сам проверяет новую версию на GitHub при каждом запуске и дальше раз в час. Если в настройках включено «Обновлять автоматически» (включено сразу), он скачает её сам, а заработает она после перезагрузки скриптов, кнопка есть там же. Если автообновление выключить, на вкладке «Настройки» будет кнопка «Обновить».

## Благодарности

- Данные о сборках, ролях и матчапах: [STRATZ](https://stratz.com).
- Локализация меню сделана на библиотеке qLocalization от qfun (qfun_g9s), она встроена в файл скрипта.

---

## English

Umbrella script for Dota 2. Shows a build for your hero and role in the shop, based on fresh high-MMR pubs, and tells you what to buy against your actual enemies in this game and why.

**[Download the latest version](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/build-brain-v2.2.0/build_brain.lua)**

### Features

- A shop panel instead of the Dota guide: role switch, starting items and laning from top players of the hero, core items with usual minutes, counters to your enemies with reasons (only items your hero actually buys in that role), skill order and talents.
- Left click opens the item recipe (built from and builds into), Ctrl or Shift + left click or drag puts it into quick buy, right click buys what you can afford.
- Auto-buy (in Settings): starting items only, or the whole build part by part as gold comes in, each buy is written to your chat.
- A draft panel that opens by itself on hero pick: win chance, both teams' picks and who to pick for your role from the first pick (meta heroes of that position, ranked by matchups against the enemy picks). Click a hero to mark it, then Pick to take it. A "For teammates" block gives 3 heroes for every teammate without a hero, click one to suggest it to your team. The top 3 are highlighted in the Dota hero grid, and the panel can be dragged.
- Enemy scouting: each enemy's main heroes for the last 30 days with win rates from OpenDota, a frame marks ban candidates.
- A window (on a key) with Draft, Build and Fight tabs: who to pick, who to watch out for, what kills you, enemy ult and BKB cooldowns and when you can fight.
- Skip or replace any item of the build from its hover card, and remember the choice for the hero. Item minutes follow your real income, Turbo gets its own minutes.
- Your own hero pool: mark the heroes you play and the draft shows your 2 best of them on top of the meta picks.
- A short first-run setup (role, heroes, game mode) and window styles: Scoreboard, Mono, Gold, Ruby.
- Live counters: when an enemy buys an item like Butterfly, the counter (for example MKB) moves into your build as the next item.
- Builds come from Divine and Immortal matches on the current patch, matchups from Legend to Immortal pubs over two weeks (STRATZ data). A GitHub bot rebuilds them twice a week and after a new patch, the script checks for a new file hourly, through the jsDelivr mirror when GitHub is not reachable.

### Install

1. Download `build_brain.lua` from the link above.
2. Put it into the Umbrella `scripts` folder.
3. Reload Lua scripts.
4. Set the window key in `Scripts → Scripts → Build Brain`.
5. Open the shop in game.

### Updates

The script checks GitHub for a new version on every start and then hourly. With "Update automatically" on (the default) it downloads it by itself, and the new version starts after you reload scripts, the button is on the Settings tab. With it off, use the Update button there.

### Credits

Build, role and matchup data by [STRATZ](https://stratz.com). Menu localization uses the qLocalization library by qfun (qfun_g9s), embedded in the script file.
