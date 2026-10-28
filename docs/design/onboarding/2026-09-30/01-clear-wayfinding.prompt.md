Use case: ui-mockup.
Create realistic, production-quality native Android Flutter onboarding UI designs for Bagdar, an accessibility app for blind and low-vision people. This is ONE coherent design direction named "Чёткий ориентир", demonstrated by four consecutive representative screens on one presentation board, not multiple design ideas.
Target dimensions: landscape 3840 x 2160 design board; four equally sized, full, undistorted mobile app viewports arranged side by side in ONE row. Each viewport uses the natural 390 x 844 mobile ratio. All four top and bottom edges align. Board heading outside the viewports: "Чёткий ориентир". Background outside the screens is subdued neutral charcoal. App content ONLY: no device bezels, no phone bodies, no notch, no Dynamic Island, no OS status bars, no clocks, no battery indicators, no home indicators, no rounded device mask or device shadows. Keep all four complete screens and their bottom buttons visible.
Existing Bagdar design tokens as grounding: near-black #000000 base; elevated #0A0A0A; white #FFFFFF text; pale #E8E8E8 secondary text; yellow #FFD600 primary and focus; warning #FFB300; soft danger #FF6B6B. Inter font with readable Cyrillic and Kazakh. Typography at viewport scale: headline 36-40sp heavy, secondary heading 26-30sp, body 20sp medium, minimum meaningful label 18sp. 24dp side spacing, 8dp spacing grid, generous whitespace. Large primary controls 80-88dp high, other controls at least 64dp. Near-sharp 6dp corners, clear large mono line icons, purposeful dividing rules. Contemporary transport-wayfinding aesthetic, strong typographic rhythm, carefully aligned baselines. Flat UI with no gradients, no glassmorphism, no decorative illustrations, no photos, no tiny text.
Design structure: single strong left-aligned heading at the top, one clear primary action in a stable bottom position, supporting actions with readable text. Use typography and spacing first, then dividers; no cards inside cards, no generic dashboard panels. Variation here should feel like clear transit signage with direct visual instructions and thick rules.
Render all the following Cyrillic text exactly and cleanly, no lorem ipsum, no random text or extraneous features.
LEFT SCREEN — LANGUAGE:
Small product wordmark "Bagdar", subtle section label "Настройка".
Large heading "Выберите язык".
Body "На каком языке вам удобнее?"
Three generous selectable horizontal rows, labelled "Қазақша", "Русский", "English". Russian selected using both a radio check and a yellow edge or fill; selected state cannot rely only on color.
Bottom yellow primary button "Продолжить". Supporting text action with speaker icon "Повторить подсказку".
SECOND SCREEN — FEEDBACK VERIFICATION:
Back text "Назад"; small section label "Проверка сигналов".
Large heading "Проверьте сигналы".
Body "Прослушайте голос и проверьте вибрацию."
Two spacious, flat grouped sections separated by a divider. First has speaker icon, heading "Голос", outlined button "Прослушать", checked acknowledgement "Слышу голос". Second has vibration icon, heading "Вибрация", outlined button "Проверить", checked acknowledgement "Чувствую вибрацию".
Bottom primary "Продолжить", supporting text action "Настроить сигналы". Keep the content airy and not overloaded.
THIRD SCREEN — SAFE SIMULATION:
Back "Назад"; clear text label "Учебный режим".
Large heading "Распознайте «Стоп»".
Short body "Это тренировка. Оставайтесь на месте."
A prominent simple stop symbol and large phrase "Стоп. Препятствие впереди." in an uncluttered central area. A supporting action with replay icon "Повторить сигнал".
Instruction "Нажмите «Пауза», когда услышите «Стоп»."
Large bottom primary button "Пауза". This is a deterministic training simulation and must not suggest live camera detection.
FOURTH SCREEN — HONEST READINESS SUMMARY:
Back "Назад"; section label "Итог обучения".
Large heading "Обучение завершено".
Body "Вы освоили основные действия."
Three simple list rows with readable status words and icons: "Голос" / "Проверен"; "Вибрация" / "Проверена"; "Камера" / "Не проверена". Camera state gets an amber warning icon plus explicit text, not color alone.
Short warning "Живой анализ пока недоступен."
Bottom primary "Проверить камеру". Supporting action "Повторить тренировку".
Hard constraints: never write "путь свободен", "можно идти", "безопасно", "всё готово". Never imply validated obstacle detection. Do not add login, account, maps, subscriptions, live camera feeds, percent accuracy, premium badges or navigation tabs. The UI should be practical to recreate with native Flutter widgets and adapt to screen readers and large text. Prioritize a beautiful, legible, intentional hierarchy.
