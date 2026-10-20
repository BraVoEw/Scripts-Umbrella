# History Changer

![Downloads](https://img.shields.io/github/downloads/BraVoEw/Scripts-Umbrella/total?label=%D0%B7%D0%B0%D0%B3%D1%80%D1%83%D0%B7%D0%BE%D0%BA)

Скрипт для Umbrella (Dota 2). Показывает в истории матчей твой настоящий MMR после каждой игры и его изменение, а над карточкой профиля ставит плашку с винами, лузами и суммой MMR за сутки, неделю или месяц.

Все изменения видны только у тебя на экране. В чужом клиенте, на Dotabuff и OpenDota и в самом рейтинге ничего не меняется.

**[Скачать последнюю версию](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/history-changer-v1.0.1/history_changer.lua)**

## Возможности

- MMR после матча и изменение вместо Win или Loss. Три формата: `1569 (+25)`, `Победа 1569 (+25)` и `+25`.
- Свои цвета для победы, поражения и матча без изменения MMR.
- Плашка MMR над карточкой профиля: вины, лузы и сумма MMR за 24 часа, 7 или 30 дней. Матч считается по времени окончания.
- Свой текст вместо имени героя в каждой строке, со своим цветом.
- Для месячного итога скрипт сам догружает твою историю, до 120 матчей.
- Плашка видна только на странице истории и сразу пропадает при уходе в другое меню.
- Меню на русском и английском, язык переключается вместе с языком Umbrella.

## Установка

1. Скачай `history_changer.lua` по ссылке выше.
2. Положи его в папку `scripts` Umbrella.
3. Перезагрузи Lua-скрипты.
4. Открой `Scripts → Scripts → History Changer`, скрипт включен сразу.
5. Зайди в Профиль → History.

## Настройки

| Пункт | Что делает |
| --- | --- |
| Включить | Включает скрипт. В шестеренке: отладка в лог и клавиша, которая пишет устройство панели истории в лог |
| Плашка MMR | Плашка с итогом над карточкой профиля |
| Период | За сутки, за неделю или за месяц |
| MMR в результате | MMR и изменение вместо Win или Loss. В шестеренке формат |
| Цвет победы, поражения, без изменения | Цвета текста результата и суммы MMR на плашке |
| Свой текст вместо героя | Заменяет имя героя твоим текстом. Цвет справа от переключателя |
| Текст | Сам текст |

## Как это работает

- Рейтинг до матча, изменение, результат и время скрипт берет из ответа сервера Dota на запрос истории матчей. Это тот же ответ, который получает сам клиент.
- Скрипт ничего не отправляет на сторонние сервера.
- В чужих профилях MMR показывается, только если сервер Dota его отдает. Свой текст вместо героя работает везде.

## Благодарности

Локализация меню сделана на библиотеке qLocalization от qfun (qfun_g9s), она встроена в файл скрипта.

---

## English

Umbrella script for Dota 2. Shows your real MMR after every match and its change in the match history, and puts a pill above the profile card with wins, losses and the MMR total for 24 hours, a week or a month.

Everything changes only on your screen. Other clients, Dotabuff, OpenDota and your actual rank stay the same.

**[Download the latest version](https://github.com/BraVoEw/Scripts-Umbrella/releases/download/history-changer-v1.0.1/history_changer.lua)**

### Features

- MMR after the match and the change instead of Win or Loss, in three formats: `1569 (+25)`, `Win 1569 (+25)` and `+25`.
- Your own colors for wins, losses and matches with no change.
- MMR pill above the profile card with wins, losses and the MMR total for 24 hours, 7 or 30 days.
- Your own text instead of the hero name in every row.
- Loads up to 120 matches of your history for the monthly total.
- The pill shows only on the history page.

### Install

1. Download `history_changer.lua` from the link above.
2. Put it into the Umbrella `scripts` folder.
3. Reload Lua scripts.
4. Open `Scripts → Scripts → History Changer`, the script is on by default.
5. Go to Profile → History.

### Credits

Menu localization uses the qLocalization library by qfun (qfun_g9s), embedded in the script file.
