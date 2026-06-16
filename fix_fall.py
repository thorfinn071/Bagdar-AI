path = r'C:\Users\Nurik\Desktop\bagdar_app\lib\camera\fall_countdown_controller.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = (
    "    final delivered = result == SosResult.sent ||\n"
    "        result == SosResult.sentFallback ||\n"
    "        result == SosResult.sentWithoutLocation;\n"
    "    if (delivered) onSosSent?.call();\n"
    "    final msg = switch (result) {\n"
    "      SosResult.sent => S.get('sos_fall_sent'),\n"
    "      SosResult.sentFallback =>\n"
    "        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',\n"
    "      SosResult.sentWithoutLocation => S.get('sos_sent_no_location'),\n"
    "      SosResult.noLocation => S.get('sos_no_location'),\n"
    "      SosResult.launchFailed => S.get('sos_launch_failed'),\n"
    "      SosResult.noContact => S.get('sos_no_contact'),\n"
    "      SosResult.error => S.get('sos_error'),\n"
    "    };\n"
    "    tts.say(msg, SpeechPriority.critical, pan: 0.0);"
)

new = (
    "    final delivered = result == SosResult.sent ||\n"
    "        result == SosResult.sentFallback ||\n"
    "        result == SosResult.sentWithoutLocation;\n"
    "    // E-2: composerOpened / dialerOpened mean the user still has to take\n"
    "    // manual action — do NOT mark the SOS as sent or start the lockout.\n"
    "    if (delivered) onSosSent?.call();\n"
    "    // E-2: guide the user to complete the send / call manually.\n"
    "    if (result == SosResult.composerOpened ||\n"
    "        result == SosResult.dialerOpened) {\n"
    "      HapticService.vibrate(const [0, 200, 100, 200]);\n"
    "    }\n"
    "    final msg = switch (result) {\n"
    "      SosResult.sent => S.get('sos_fall_sent'),\n"
    "      SosResult.sentFallback =>\n"
    "        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',\n"
    "      SosResult.sentWithoutLocation => S.get('sos_sent_no_location'),\n"
    "      SosResult.noLocation => S.get('sos_no_location'),\n"
    "      SosResult.launchFailed => S.get('sos_launch_failed'),\n"
    "      SosResult.noContact => S.get('sos_no_contact'),\n"
    "      SosResult.error => S.get('sos_error'),\n"
    "      SosResult.composerOpened => S.get('sos_composer_opened'),\n"
    "      SosResult.dialerOpened => S.get('sos_dialer_opened'),\n"
    "    };\n"
    "    tts.say(msg, SpeechPriority.critical, pan: 0.0);"
)

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('OK: fall_countdown_controller patched')
else:
    print('MISSING — showing context:')
    idx = content.find('final delivered')
    print(repr(content[idx:idx+500]))
