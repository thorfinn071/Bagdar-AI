path = r'C:\Users\Nurik\Desktop\bagdar_app\lib\models\strings.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

changes = [
    # Russian (ru) — after sos_delivered
    (
        "    'sos_delivered': 'SOS \u0434\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d.',\r\n"
        "    'sos_planned_destination': '\u041d\u0430\u043f\u0440\u0430\u0432\u043b\u044f\u043b\u0441\u044f \u043a:',",
        "    'sos_delivered': 'SOS \u0434\u043e\u0441\u0442\u0430\u0432\u043b\u0435\u043d.',\r\n"
        "    'sos_composer_opened':\r\n"
        "        '\u041e\u0442\u043a\u0440\u044b\u0442\u043e \u043e\u043a\u043d\u043e \u0441\u043e\u043e\u0431\u0449\u0435\u043d\u0438\u044f, \u043a\u043d\u043e\u043f\u043a\u0430 \u00ab\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c\u00bb \u2014 \u0432\u043d\u0438\u0437\u0443 \u0441\u043f\u0440\u0430\u0432\u0430.',\r\n"
        "    'sos_dialer_opened': '\u041e\u0442\u043a\u0440\u044b\u0442 \u043d\u0430\u0431\u0438\u0440\u0430\u0442\u0435\u043b\u044c, \u043d\u0430\u0436\u043c\u0438\u0442\u0435 \u0437\u0435\u043b\u0451\u043d\u0443\u044e \u043a\u043d\u043e\u043f\u043a\u0443 \u0432\u044b\u0437\u043e\u0432\u0430.',\r\n"
        "    'sos_planned_destination': '\u041d\u0430\u043f\u0440\u0430\u0432\u043b\u044f\u043b\u0441\u044f \u043a:',",
    ),
    # Kazakh (kk) — after sos_delivered
    (
        "    'sos_delivered': 'SOS \u0436\u0435\u0442\u043a\u0456\u0437\u0456\u043b\u0434\u0456.',\r\n"
        "    'sos_planned_destination': '\u0411\u0430\u0440\u0430 \u0436\u0430\u0442\u049b\u0430\u043d \u0436\u0435\u0440:',",
        "    'sos_delivered': 'SOS \u0436\u0435\u0442\u043a\u0456\u0437\u0456\u043b\u0434\u0456.',\r\n"
        "    'sos_composer_opened':\r\n"
        "        '\u0425\u0430\u0431\u0430\u0440 \u0436\u0430\u0437\u0443 \u0442\u0435\u0440\u0435\u0437\u0435\u0441\u0456 \u0430\u0448\u044b\u043b\u0434\u044b, \u00ab\u0416\u0456\u0431\u0435\u0440\u0443\u00bb \u0442\u04af\u0439\u043c\u0435\u0441\u0456 \u2014 \u0442\u04e9\u043c\u0435\u043d\u0433\u0456 \u043e\u04a3 \u0436\u0430\u049b\u0442\u0430.',\r\n"
        "    'sos_dialer_opened': '\u0422\u0435\u0440\u0443 \u0442\u0430\u049b\u0442\u0430\u0441\u044b \u0430\u0448\u044b\u043b\u0434\u044b, \u0436\u0430\u0441\u044b\u043b \u049b\u043e\u04a3\u044b\u0440\u0430\u0443 \u0448\u0430\u043b\u0443 \u0442\u04af\u0439\u043c\u0435\u0441\u0456\u043d \u0431\u0430\u0441\u044b\u04a3\u044b\u0437.',\r\n"
        "    'sos_planned_destination': '\u0411\u0430\u0440\u0430 \u0436\u0430\u0442\u049b\u0430\u043d \u0436\u0435\u0440:',",
    ),
    # English (en) — after sos_delivered
    (
        "    'sos_delivered': 'SOS delivered.',\r\n"
        "    'sos_planned_destination': 'Heading to:',",
        "    'sos_delivered': 'SOS delivered.',\r\n"
        "    'sos_composer_opened':\r\n"
        "        'Message composer opened. Tap the Send button at the bottom right.',\r\n"
        "    'sos_dialer_opened': 'Phone dialer opened. Press the green call button.',\r\n"
        "    'sos_planned_destination': 'Heading to:',",
    ),
]

for old, new in changes:
    if old in content:
        content = content.replace(old, new, 1)
        print('OK:', repr(old[:50]))
    else:
        # Try with LF only
        old_lf = old.replace('\r\n', '\n')
        new_lf = new.replace('\r\n', '\n')
        if old_lf in content:
            content = content.replace(old_lf, new_lf, 1)
            print('OK (LF):', repr(old_lf[:50]))
        else:
            print('MISSING:', repr(old[:80]))

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done.')
