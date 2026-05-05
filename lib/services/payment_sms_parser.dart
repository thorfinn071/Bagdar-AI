import '../models/constants.dart';
import '../models/strings.dart';

enum PaymentDirection { incoming, outgoing }

class PaymentSmsEvent {
  final PaymentDirection direction;
  final double amount;
  final String currency;
  final String? counterparty;
  final double? balance;
  final String? bankTag;

  const PaymentSmsEvent({
    required this.direction,
    required this.amount,
    required this.currency,
    this.counterparty,
    this.balance,
    this.bankTag,
  });

  String dedupKey() =>
      '${direction.name}|${amount.toStringAsFixed(2)}|$currency|${counterparty ?? ""}';
}

class PaymentSmsParser {
  PaymentSmsParser._();

  static const List<String> _bankSenderTags = [
    'kaspi',
    'halyk',
    'jusan',
    'bcc',
    'centercredit',
    'forte',
    'fortebank',
    'eurasian',
    'eub',
    'sber',
    'сбер',
    'tinkoff',
    't-bank',
    'tbank',
    'alfa',
    'альфа',
    'raif',
    'райф',
    'beeline',
    'билайн',
    'tele2',
    'теле2',
    'aktiv',
    'актив',
    'kcell',
    'кселл',
    'altel',
    'алтел',
    'халык',
    'жусан',
    'каспи',
  ];

  static final RegExp _amount = RegExp(
    r'(?<!\d)(\d{1,3}(?:[ \u00A0]\d{3})+|\d+)(?:[.,](\d{1,2}))?\s*'
    r'(₸|kzt|тг\.?|тенге|теңге|руб\.?|rub|₽|usd|\$|€|eur)',
    caseSensitive: false,
  );

  static final RegExp _incomingKw = RegExp(
    r'зачислен|пополнен|поступил|перечислен|получен|принят|кредитован|'
    r'түсті|қабылданды|'
    r'received|credit(ed)?|incoming|deposit',
    caseSensitive: false,
  );

  static final RegExp _outgoingKw = RegExp(
    r'списан|списание|снят|оплач|оплата|покупка|перевед[её]н|отправлен|'
    r'шығыс|аударылды|'
    r'sent|debit(ed)?|withdrawn|paid|purchase',
    caseSensitive: false,
  );

  static final RegExp _counterpartyRu = RegExp(
    r'(?:от(?:правител[ья])?[.:]?\s+)([A-ZА-ЯЁ][A-Za-zА-Яа-яЁё]+(?:\s+[A-ZА-ЯЁ][A-Za-zА-Яа-яЁё\.]*)?)',
    caseSensitive: true,
  );

  static final RegExp _counterpartyEn = RegExp(
    r'(?:from[.:]?\s+)([A-Z][a-zA-Z]+(?:\s+[A-Z][a-zA-Z\.]*)?)',
    caseSensitive: true,
  );

  static final RegExp _balanceKw = RegExp(
    r'(?:баланс|қалдық|balance)[:\s]*',
    caseSensitive: false,
  );

  static const double _minReasonableAmount = 0.01;
  static const double _maxReasonableAmount = 9999999999.0;

  static PaymentSmsEvent? parse({
    required String sender,
    required String body,
  }) {
    if (body.isEmpty) return null;
    final trimmed = body.length > kPaymentSmsMaxBodyLen
        ? body.substring(0, kPaymentSmsMaxBodyLen)
        : body;

    final bankTag = _detectBankTag(sender, trimmed);
    final inMatch = _incomingKw.firstMatch(trimmed);
    final outMatch = _outgoingKw.firstMatch(trimmed);
    if (inMatch == null && outMatch == null) return null;

    final amountMatch = _firstValidAmount(trimmed);
    if (amountMatch == null) return null;

    final direction = _directionFromMatches(inMatch, outMatch);
    final counterparty = _extractCounterparty(trimmed);
    final balance = _extractBalance(trimmed, amountMatch);

    return PaymentSmsEvent(
      direction: direction,
      amount: amountMatch.value,
      currency: amountMatch.currency,
      counterparty: counterparty,
      balance: balance,
      bankTag: bankTag,
    );
  }

  static String? _detectBankTag(String sender, String body) {
    final senderLower = sender.toLowerCase();
    for (final tag in _bankSenderTags) {
      if (senderLower.contains(tag)) return tag;
    }
    final bodyLower = body.toLowerCase();
    for (final tag in _bankSenderTags) {
      if (bodyLower.contains(tag)) return tag;
    }
    return null;
  }

  static PaymentDirection _directionFromMatches(
    RegExpMatch? inMatch,
    RegExpMatch? outMatch,
  ) {
    if (inMatch != null && outMatch != null) {
      return inMatch.start <= outMatch.start
          ? PaymentDirection.incoming
          : PaymentDirection.outgoing;
    }
    return outMatch != null
        ? PaymentDirection.outgoing
        : PaymentDirection.incoming;
  }

  static _AmountHit? _firstValidAmount(String body) {
    for (final m in _amount.allMatches(body)) {
      final hit = _amountFromMatch(m);
      if (hit != null) return hit;
    }
    return null;
  }

  static _AmountHit? _amountFromMatch(RegExpMatch m) {
    final intPart = m.group(1);
    final fracPart = m.group(2);
    final cur = m.group(3);
    if (intPart == null || cur == null) return null;
    final cleanedInt = intPart.replaceAll(RegExp(r'[ \u00A0]'), '');
    final numStr = fracPart == null ? cleanedInt : '$cleanedInt.$fracPart';
    final value = double.tryParse(numStr);
    if (value == null) return null;
    if (value < _minReasonableAmount || value > _maxReasonableAmount) {
      return null;
    }
    return _AmountHit(
      value: value,
      currency: _normalizeCurrency(cur),
      start: m.start,
      end: m.end,
    );
  }

  static String _normalizeCurrency(String raw) {
    final lower = raw.toLowerCase().replaceAll('.', '').trim();
    switch (lower) {
      case '₸':
      case 'kzt':
      case 'тг':
      case 'тенге':
      case 'теңге':
        return 'KZT';
      case 'руб':
      case 'rub':
      case '₽':
        return 'RUB';
      case 'usd':
      case r'$':
        return 'USD';
      case '€':
      case 'eur':
        return 'EUR';
      default:
        return 'KZT';
    }
  }

  static String? _extractCounterparty(String body) {
    final ruM = _counterpartyRu.firstMatch(body);
    final enM = _counterpartyEn.firstMatch(body);
    String? candidate;
    if (ruM != null && enM != null) {
      candidate = ruM.start <= enM.start ? ruM.group(1) : enM.group(1);
    } else {
      candidate = ruM?.group(1) ?? enM?.group(1);
    }
    if (candidate == null) return null;
    var cleaned = candidate.trim().replaceAll(RegExp(r'[,;:!?]+$'), '');
    if (cleaned.isEmpty) return null;
    final digitRatio = _digitRatio(cleaned);
    if (digitRatio > 0.4) return null;
    if (cleaned.length > kPaymentSmsMaxSenderNameLen) {
      cleaned = cleaned.substring(0, kPaymentSmsMaxSenderNameLen).trim();
    }
    return cleaned;
  }

  static double _digitRatio(String s) {
    if (s.isEmpty) return 0;
    int d = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) d++;
    }
    return d / s.length;
  }

  static double? _extractBalance(String body, _AmountHit mainHit) {
    final balMatch = _balanceKw.firstMatch(body);
    if (balMatch == null) return null;
    final rest = body.substring(balMatch.end);
    for (final m in _amount.allMatches(rest)) {
      final hit = _amountFromMatch(m);
      if (hit == null) continue;
      return hit.value;
    }
    return null;
  }

  static String formatAmount(double value) {
    final isInt = value == value.roundToDouble();
    final fixed = isInt ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intStr = parts[0];
    final withSpaces = StringBuffer();
    final digits = intStr.codeUnits;
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        withSpaces.write(' ');
      }
      withSpaces.writeCharCode(digits[i]);
    }
    if (parts.length == 2) {
      withSpaces.write(',');
      withSpaces.write(parts[1]);
    }
    return withSpaces.toString();
  }

  static String currencyWord(String currency) {
    switch (currency) {
      case 'RUB':
        return S.get('sms_currency_rub');
      case 'USD':
        return S.get('sms_currency_usd');
      case 'EUR':
        return S.get('sms_currency_eur');
      case 'KZT':
      default:
        return S.get('sms_currency_kzt');
    }
  }

  static String formatTts(PaymentSmsEvent event) {
    final amountStr = formatAmount(event.amount);
    final cur = currencyWord(event.currency);
    final verb = event.direction == PaymentDirection.outgoing
        ? S.get('sms_payment_sent')
        : S.get('sms_payment_received');
    final buf = StringBuffer('$verb $amountStr $cur');
    final cp = event.counterparty;
    if (cp != null && cp.isNotEmpty) {
      buf.write(' ${S.get('sms_payment_from')} $cp');
    }
    buf.write('.');
    return buf.toString();
  }
}

class _AmountHit {
  final double value;
  final String currency;
  final int start;
  final int end;
  const _AmountHit({
    required this.value,
    required this.currency,
    required this.start,
    required this.end,
  });
}
