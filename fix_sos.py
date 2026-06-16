path = r'C:\Users\Nurik\Desktop\bagdar_app\lib\services\sos_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# ── 1. _tryDeliver: launchUrl(smsUri) success → composerOpened ────────────────
old1 = (
    '      return isFallback ? SosResult.sentFallback : SosResult.sent;\n'
    '    } catch (e) {\n'
    "      debugPrint('SosService: delivery error to $target: $e');\n"
    '      return SosResult.error;\n'
    '    }\n'
    '  }'
)
new1 = (
    '      // E-2: launchUrl only opens the SMS composer — the message has\n'
    '      // NOT been sent yet. Return composerOpened so callers can\n'
    '      // instruct the user to tap "Send" instead of falsely reporting\n'
    '      // delivery and starting the fall-detector lockout.\n'
    '      return SosResult.composerOpened;\n'
    '    } catch (e) {\n'
    "      debugPrint('SosService: delivery error to $target: $e');\n"
    '      return SosResult.error;\n'
    '    }\n'
    '  }'
)
assert old1 in content, 'MISSING old1'
content = content.replace(old1, new1, 1)
print('Patch 1 OK (_tryDeliver)')

# ── 2. sendSos tel: fallback → dialerOpened ───────────────────────────────────
old2 = (
    '      if (launched) {\n'
    '        return hasUserContact ? SosResult.sent : SosResult.sentFallback;\n'
    '      }\n'
    '    } catch (_) {}\n'
    '    return last;\n'
    '  }'
)
new2 = (
    '      if (launched) {\n'
    '        // E-2: launchUrl(tel:) opens the dialer (ACTION_DIAL) — no call\n'
    '        // is placed until the user taps the green button. Return\n'
    '        // dialerOpened so callers can guide the user without treating\n'
    '        // this as a successful delivery.\n'
    '        return SosResult.dialerOpened;\n'
    '      }\n'
    '    } catch (_) {}\n'
    '    return last;\n'
    '  }'
)
assert old2 in content, 'MISSING old2'
content = content.replace(old2, new2, 1)
print('Patch 2 OK (tel: fallback)')

# ── 3. sendSos loop: exit early on composerOpened ─────────────────────────────
old3 = (
    '        if (last == SosResult.sent || last == SosResult.sentFallback) {\n'
    '          \n'
    '          \n'
    '          final gpsMissing = position == null;\n'
    '          if (gpsMissing) return SosResult.sentWithoutLocation;\n'
    '          return last;\n'
    '        }'
)
new3 = (
    '        // E-2: also exit the retry loop when the composer was opened —\n'
    '        // opening it again would only spawn duplicate SMS-composer windows.\n'
    '        if (last == SosResult.composerOpened) return last;\n'
    '        if (last == SosResult.sent || last == SosResult.sentFallback) {\n'
    '          \n'
    '          \n'
    '          final gpsMissing = position == null;\n'
    '          if (gpsMissing) return SosResult.sentWithoutLocation;\n'
    '          return last;\n'
    '        }'
)
assert old3 in content, 'MISSING old3'
content = content.replace(old3, new3, 1)
print('Patch 3 OK (sendSos loop)')

# ── 4. _flushFollowUp: also stop on composerOpened ───────────────────────────
old4 = (
    '        if (result == SosResult.sent || result == SosResult.sentFallback) {\n'
    '          return;\n'
    '        }'
)
new4 = (
    '        if (result == SosResult.sent ||\n'
    '            result == SosResult.sentFallback ||\n'
    '            result == SosResult.composerOpened) {\n'
    '          return;\n'
    '        }'
)
assert old4 in content, 'MISSING old4'
content = content.replace(old4, new4, 1)
print('Patch 4 OK (_flushFollowUp)')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print('All patches written.')
