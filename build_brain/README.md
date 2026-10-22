# Build Brain

![Downloads](https://img.shields.io/github/downloads/BraVoEw/Scripts-Umbrella/total?label=%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BE%D0%BA)

Скрипт для Umbrella (Dota 2). Показывает в магазине сборку на твоего героя и роль по свежим пабам высокого рейтинга, а сверху подсказывает, что собрать против конкретных врагов в этой игре и зачем.

**[Скачать последнюю версию](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/build-brain-v1.0.1/build_brain.lua)**

## Что умеет

**Панель в магазине** вместо гайда Доты:
- Роль сверху, можно переключить на любую из пяти.
- Начальный закуп и ранняя игра собраны по играм топ-игроков на этом герое, основные предметы по статистике текущего патча. На каждом предмете минута, когда его обычно берут.
- «Против врагов»: предметы под твоих врагов с их портретами. Наведи, и увидишь причину и чем предмет поможет. Например, Гост → Нуллифаер, пассивки Бристлбэка → Сильвер Эдж, хекс Лиона → Линка.
- Порядок прокачки и таланты, которые берут чаще всего.
- Клик кладёт предмет в квикбай. Предмет можно перетащить в квикбай мышкой, ПКМ покупает то, на что хватает золота.

**Панель на пиках** появляется сама, когда начинается выбор героев:
- Шанс на победу и пики обеих команд.
- Кого взять на твою роль: только мета-герои этой позиции, отсортированные по тому, как они играют против уже выбранных врагов.
- Топ-3 подсвечиваются прямо в сетке героев Доты.
- Панель можно перетащить за шапку, место запоминается. Кнопка справа открывает полное окно.

**Окно** (по клавише):
- Драфт: кого пикнуть на твою роль и почему, кого опасаться у врагов и что против них брать, шанс на победу и таблица «кто кого».
- Сборка: следующий предмет с полоской золота, вся сборка по этапам, против каждой угрозы несколько вариантов предметов и кто тебя убивает в этой игре.
- Бой: какой урон ты получаешь, от кого, у кого из врагов ульта или BKB на кулдауне и кого можно бить прямо сейчас.

Если тебя в основном бьют магией или ты часто стоишь в контроле, скрипт это заметит и подскажет защиту.

## Откуда сборки

- Сборки считаются по матчам Божества и Титана на текущем патче, данные STRATZ.
- Робот на GitHub пересобирает их два раза в неделю, а после нового патча, как только наберутся игры.
- Скрипт сам скачивает свежий файл раз в сутки, около 0.7 МБ. Если интернета нет, работает с последним скачанным.
- Матчапы в драфте и роли героев считаются по пабам высокого рейтинга (STRATZ), общий винрейт героя на твоём ранге берётся из OpenDota.
- Скрипт ничего не отправляет о тебе и твоём аккаунте.

## Установка

1. Скачай `build_brain.lua` по ссылке выше.
2. Положи его в папку `scripts` Umbrella.
3. Перезагрузи Lua-скрипты.
4. В `Scripts → Scripts → Build Brain` назначь клавишу окна.
5. Открой магазин в игре.

При первом запуске скрипт скачает файл со сборками, это занимает пару секунд.

## Настройки

В меню Umbrella: «Включить» и клавиша окна. Остальное в самом окне на вкладке «Настройки»: роль, ранг для статистики, панель на стадии пиков, панель в магазине и размер окна.

## Обновления

Скрипт сам проверяет новую версию на GitHub при каждом запуске и дальше раз в час. Если в настройках включено «Обновлять автоматически» (включено сразу), он скачает её сам, а заработает она после перезагрузки скриптов, кнопка есть там же. Если автообновление выключить, на вкладке «Настройки» будет кнопка «Обновить».

## Благодарности

- Данные о сборках, ролях и матчапах: [STRATZ](https://stratz.com).
- Локализация меню сделана на библиотеке qLocalization от qfun (qfun_g9s), она встроена в файл скрипта.

---

## English

Umbrella script for Dota 2. Shows a build for your hero and role in the shop, based on fresh high-MMR pubs, and tells you what to buy against your actual enemies in this game and why.

**[Download the latest version](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/build-brain-v1.0.1/build_brain.lua)**

### Features

- A shop panel instead of the Dota guide: role switch, starting items and laning from top players of the hero, core items with usual minutes, counters to your enemies with reasons, skill order and talents.
- Click puts an item into quick buy, drag it onto quick buy, right click buys what you can afford.
- A draft panel that opens by itself on hero pick: win chance, both teams' picks and who to pick for your role (meta heroes of that position only, ranked by matchups against the enemy picks). The top 3 are highlighted in the Dota hero grid, and the panel can be dragged.
- A window (on a key) with Draft, Build and Fight tabs: who to pick, who to watch out for, what kills you, enemy ult and BKB cooldowns and when you can fight.
- Builds come from Divine and Immortal matches on the current patch, matchups from Legend to Immortal pubs over two weeks (STRATZ data). A GitHub bot rebuilds them twice a week and after a new patch, the script downloads the file once a day.

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
