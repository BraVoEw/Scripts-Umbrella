# История изменений

## 1.0.3 (30.10.2026)

- Эффекты: «Неон» и «RGB». В неоне MMR в истории и твой текст вместо героя светятся цветом победы или поражения, у плашки светящаяся рамка. В RGB цифры переливаются по строкам, а по рамке плашки бежит перелив.
- В шестеренке у «Эффекта»: сила свечения, скорость перелива и цвета перелива, радуга или три своих цвета.

## 1.0.2 (23.10.2026)

- Калибровка и перекалибровка: вместо голого Win или Loss в таких играх пишется «Калибровка» цветом победы или поражения. На последней калибровочной игре виден итоговый MMR, например `1494 (калибровка)`. Сервер Dota не отдает рейтинг по каждой калибровочной игре, поэтому цифры есть только у итога.
- Плашка MMR пропадает сразу, как уходишь из истории в главное меню, по Esc или на другую вкладку, и сразу появляется, когда возвращаешься. Раньше она висела еще пару секунд, а иногда появлялась только секунд через 10.

## 1.0.1 (21.10.2026)

- Исправлено: у части игроков MMR и цвета не появлялись в истории. Скрипт искал строки по дате, а дата в игре выглядит по-разному в зависимости от языка и региона. Теперь строки находятся при любом формате даты.
- Скрипт включен сразу после установки. Раньше все пункты меню были серыми, пока не включишь «Включить».
- Отладка в лог пишет, сколько строк истории нашлось.

## 1.0.0 (21.10.2026)

Первая версия.

- MMR после матча и изменение вместо Win или Loss, три формата и свои цвета.
- Плашка MMR над карточкой профиля: вины, лузы и сумма MMR за 24 часа, 7 или 30 дней.
- Свой текст вместо имени героя.
- Догрузка истории для месячного итога, до 120 матчей.
- Плашка видна только на странице истории.

---

# Changelog

## 1.0.3 (2026-10-30)

- Effects: Neon and RGB. Neon makes the MMR in the history and your custom hero text glow in the win or loss color, and gives the pill a glowing frame. RGB makes the numbers flow through colors row by row and runs a color flow around the pill frame.
- In the Effect gear: glow strength, color flow speed and flow colors, rainbow or three colors of your own.

## 1.0.2 (2026-10-23)

- Calibration and recalibration: instead of a bare Win or Loss these games now say "Calibration" in the win or loss color. The last calibration game shows the final MMR, for example `1494 (calibration)`. The Dota server doesn't send the rating for each calibration game, so only the final result has numbers.
- The MMR pill disappears right away when you leave the history for the main menu, with Esc or for another tab, and shows up right away when you come back. Before, it stayed for a couple of seconds and sometimes showed up only after about 10 seconds.

## 1.0.1 (2026-10-21)

- Fixed: for some players MMR and colors never showed up in the history. The script found rows by the date, and the date looks different depending on the game language and region. Rows are now found with any date format.
- The script is on right after install. Before, every menu item stayed grey until you turned on Enable.
- The debug log shows how many history rows were found.

## 1.0.0 (2026-10-21)

First release.

- MMR after the match and the change instead of Win or Loss, three formats and custom colors.
- MMR pill above the profile card with wins, losses and the MMR total for 24 hours, 7 or 30 days.
- Custom text instead of the hero name.
- Loads more history for the monthly total, up to 120 matches.
- The pill shows only on the history page.
