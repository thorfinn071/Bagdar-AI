path = r'C:\Users\Nurik\Desktop\bagdar_app\lib\camera_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = (
    "    final msg = switch (result) {\n"
    "      SosResult.sent => S.get('sos_sent'),\n"
    "      SosResult.sentFallback =>\n"
    "        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',\n"
    "      SosResult.sentWithoutLocation => S.get('sos_sent_no_location'),\n"
    "      SosResult.noContact => S.get('sos_no_contact'),\n"
    "      SosResult.noLocation => S.get('sos_no_location'),\n"
    "      SosResult.launchFailed => S.get('sos_launch_failed'),\n"
    "      SosResult.error => S.get('sos_error'),\n"
    "    };\n"
    "    _fieldLog.logSosTrigger(source, result: result.name);\n"
    "    _vm.tts.say(msg, SpeechPriority.critical, pan: 0.0);"
)

new = (
    "    final msg = switch (result) {\n"
    "      SosResult.sent => S.get('sos_sent'),\n"
    "      SosResult.sentFallback =>\n"
    "        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',\n"
    "      SosResult.sentWithoutLocation => S.get('sos_sent_no_location'),\n"
    "      SosResult.noContact => S.get('sos_no_contact'),\n"
    "      SosResult.noLocation => S.get('sos_no_location'),\n"
    "      SosResult.launchFailed => S.get('sos_launch_failed'),\n"
    "      SosResult.error => S.get('sos_error'),\n"
    "      // E-2: guide the user to complete the action manually; no lockout.\n"
    "      SosResult.composerOpened => S.get('sos_composer_opened'),\n"
    "      SosResult.dialerOpened => S.get('sos_dialer_opened'),\n"
    "    };\n"
    "    _fieldLog.logSosTrigger(source, result: result.name);\n"
    "    _vm.tts.say(msg, SpeechPriority.critical, pan: 0.0);\n"
    "    // E-2: additional haptic cue to draw attention to the manual step.\n"
    "    if (result == SosResult.composerOpened ||\n"
    "        result == SosResult.dialerOpened) {\n"
    "      HapticService.vibrate(const [0, 200, 100, 200]);\n"
    "    }"
)

if old in content:
    content = content.replace(old, new, 1)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('OK: camera_screen patched')
else:
    print('MISSING — showing context:')
    idx = content.find("SosResult.sent => S.get('sos_sent')")
    print(repr(content[max(0,idx-50):idx+500]))
