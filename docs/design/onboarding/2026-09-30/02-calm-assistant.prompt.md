Use case: ui-mockup.
Create realistic, production-quality native Android / Flutter onboarding UI for Bagdar, used by blind and low-vision people. ONE coherent design direction named "Спокойный помощник", shown through four representative app screens in one design presentation board. This is one design idea demonstrated across a flow.
Target dimensions: landscape 3840 x 2160. Four equally sized complete app viewports in ONE horizontal row, each natural 390 x 844 ratio, aligned top and bottom, never stretched. Small board title outside the screens: "Спокойный помощник". App content only: no phone bodies, device bezels, notch, status bars, clocks, battery indicators, home indicators, device shadows, rounded device masks or browser chrome. All buttons fit fully inside the screens.
Grounding in Bagdar's existing light theme: white #FFFFFF app base, navy #0A1628 primary/text, #1F2A3D body, #F2F4F7 subtle surface, dark green #0F5132 verified states, dark amber #7A4F00 limitation states. Inter font with Russian and Kazakh glyphs. Use 36sp bold headlines, 20sp medium body, 18sp supporting text. Side margins 24dp, 8dp spacing system, primary touch controls 80-88dp high and secondary controls >=64dp, corner radius around 10dp, beautiful legible typography and airy whitespace.
Visual system: calm, sophisticated accessible editorial app, clear navigation, gentle gray separators, one strong navy primary action anchored at the bottom. Avoid gradients, low-contrast gray text, shadows, decorative illustrations, photos, gratuitous cards, cards inside cards, dashboard metrics. Ground this in an actual Flutter app, not a marketing page.
Distinct layout strategy: progressive disclosure and a single task per screen. On feedback screen show only the current voice-check task prominently, while vibration is clearly labelled as the next step. Thus this is structurally different from a screen showing every verification action simultaneously. Hierarchy should be natural and reassuring, unhurried, without childish imagery.
All specified text must be rendered verbatim in readable Russian or Kazakh, no invented microcopy or lorem ipsum.

SCREEN AT FAR LEFT — LANGUAGE:
Top small "Bagdar" wordmark and text "Настройка".
Large headline "Выберите язык".
Body "Язык подсказок и обучения".
Three full-width flat rows separated by fine rules: "Қазақша", "Русский", "English". Russian row is selected with a large radio indicator and an explicit check, subtle gray tint, dark navy text.
Below the choices, a flat supporting action with speaker icon "Прослушать пример".
Stable navy bottom primary button with white label "Продолжить". Supporting secondary text action "Настроить позже".

SECOND SCREEN — VOICE VERIFICATION:
Back "Назад"; progress label "Голос и вибрация".
Large headline "Слышите подсказку?"
Body "Проверьте голос в удобном темпе."
A large simple speaker/play icon, placed intentionally in the upper-middle of the page. A spacious outlined playback control "Прослушать голос".
A simple speech-speed slider with text label "Скорость речи" and endpoints "Медленнее" and "Быстрее". Make the accessible tap alternatives clear with minus and plus controls, without dense tiny labels.
Subtle next-step line at the lower-middle: "Далее — проверка вибрации".
Bottom large navy action "Да, слышу". Below it supporting action "Не слышу". No second unrelated primary CTA and no green check before confirmation.

THIRD SCREEN — SIMULATION:
Back "Назад"; a restrained but very clear label "Учебный режим".
Large headline "Потренируем остановку".
Body "Оставайтесь на месте."
A large restrained outlined stop icon or pause icon, flat navy; no photoreal objects.
Prominent central instruction text "Стоп. Препятствие впереди."
Supporting text "Это учебное предупреждение."
Outlined action with replay icon "Повторить".
At the bottom, instruction "Услышали «Стоп»? Нажмите «Пауза»."
Large navy primary button "Пауза". No real camera image, no implication of live object detection.

FOURTH SCREEN — SUMMARY:
Back "Назад"; section label "Итог обучения".
Large headline "Основы освоены".
Body "Вы можете повторить обучение в любое время."
One calm flat grouped list with separators, not many separate cards.
Row with small check icon: "Голос" and "Проверен".
Row with small check icon: "Вибрация" and "Проверена".
Row with warning icon: "Камера" and "Не проверена".
Below, a minimal amber text block "Для живого анализа нужна проверка камеры."
Large navy bottom action "Проверить камеру".
Supporting action "Повторить обучение".
Never label the whole app as ready or safe.
Hard constraints: every important status has text plus icon, never color alone. No claims of safe travel, no "путь свободен", "можно идти", "безопасно", "всё готово". No login, account creation, maps, subscriptions, premium, accuracy metrics, cloud assistants or navigation tabs. Every viewport must be a cohesive usable mobile app with only the named content. Render complete clear screens with excellent Cyrillic typography.
