import 'package:bagdar/services/payment_sms_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PaymentSmsParser.parse — admission guard', () {
    test('drops empty body', () {
      expect(
        PaymentSmsParser.parse(sender: 'Kaspi', body: ''),
        isNull,
      );
    });

    test('drops balance-only SMS (regression for direction-keyword guard)', () {
      final e = PaymentSmsParser.parse(
        sender: 'Jusan',
        body: 'Jusan: Ваш баланс на 01.12 составляет 85 200 тг',
      );
      expect(e, isNull);
    });

    test('drops promotional SMS with amount but no direction keyword', () {
      final e = PaymentSmsParser.parse(
        sender: 'Technodom',
        body: 'Скидка 500 тенге в Technodom!',
      );
      expect(e, isNull);
    });

    test('drops non-financial chatter', () {
      final e = PaymentSmsParser.parse(
        sender: '+77771234567',
        body: 'Привет, как дела?',
      );
      expect(e, isNull);
    });

    test('drops bank SMS without amount', () {
      final e = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Kaspi Gold: вам зачислен подарочный бонус!',
      );
      expect(e, isNull);
    });
  });

  group('PaymentSmsParser.parse — incoming', () {
    test('Kaspi Gold in Russian with counterparty and balance', () {
      final e = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Kaspi Gold: Вам поступило 15 000 ₸ от Айжан К. '
            'Баланс: 125 430 ₸. 12:34',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 15000);
      expect(e.currency, 'KZT');
      expect(e.counterparty, contains('Айжан'));
      expect(e.balance, 125430);
      expect(e.bankTag, 'kaspi');
    });

    test('Halyk in Russian with decimal amount', () {
      final e = PaymentSmsParser.parse(
        sender: 'HALYK',
        body: 'HALYK: Зачислено 50 000,00 тг от Иванов И. '
            'Баланс: 250 000,00 тг',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 50000);
      expect(e.currency, 'KZT');
      expect(e.bankTag, 'halyk');
    });

    test('Kazakh language — "түсті" keyword triggers incoming', () {
      final e = PaymentSmsParser.parse(
        sender: 'Halyk',
        body: 'Halyk: 10 000 теңге түсті. Қалдық: 50 000 теңге',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 10000);
      expect(e.currency, 'KZT');
      expect(e.balance, 50000);
    });

    test('English "received" with USD', () {
      final e = PaymentSmsParser.parse(
        sender: 'Bank',
        body: 'Received 25 USD from John. Balance 100 USD',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 25);
      expect(e.currency, 'USD');
      expect(e.counterparty, 'John');
    });

    test('Beeline with phone-number sender → no counterparty', () {
      final e = PaymentSmsParser.parse(
        sender: 'Beeline',
        body: 'Beeline: Вам поступило 2 000 тенге от +77012345678. '
            'Баланс: 5 000 тенге.',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 2000);
      expect(e.counterparty, isNull);
    });
  });

  group('PaymentSmsParser.parse — outgoing', () {
    test('Kaspi purchase (оплата) is outgoing', () {
      final e = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Kaspi Gold: Оплата 1 250 ₸ в MAGNUM. '
            'Баланс: 124 180 ₸. 14:22',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.outgoing);
      expect(e.amount, 1250);
      expect(e.currency, 'KZT');
    });

    test('Halyk withdrawal (списано) is outgoing', () {
      final e = PaymentSmsParser.parse(
        sender: 'HALYK',
        body: 'HALYK: Списано 3500 тг. Покупка RAMSTORE. '
            'Баланс 246 500 тг',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.outgoing);
      expect(e.amount, 3500);
    });
  });

  group('PaymentSmsParser.parse — currency + edge cases', () {
    test('RUB parsed from ₽ symbol', () {
      final e = PaymentSmsParser.parse(
        sender: 'Sber',
        body: 'Зачислено 1000,50 ₽ от Ivan',
      );
      expect(e, isNotNull);
      expect(e!.amount, 1000.5);
      expect(e.currency, 'RUB');
    });

    test('mixed direction keywords: first occurrence wins', () {
      final e = PaymentSmsParser.parse(
        sender: 'Bank',
        body: 'Поступило 1000 ₸ от Ольги. Списано 0 ₸ комиссии.',
      );
      expect(e, isNotNull);
      expect(e!.direction, PaymentDirection.incoming);
      expect(e.amount, 1000);
    });

    test('long body is truncated safely and still parses', () {
      final long = 'Поступило 500 ₸ от Anna. ${'x' * 2000}';
      final e = PaymentSmsParser.parse(sender: 'Kaspi', body: long);
      expect(e, isNotNull);
      expect(e!.amount, 500);
      expect(e.direction, PaymentDirection.incoming);
    });
  });

  group('PaymentSmsEvent.dedupKey', () {
    test('identical events produce identical keys', () {
      final a = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Поступило 1000 ₸ от Иван',
      );
      final b = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Поступило 1000 ₸ от Иван',
      );
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!.dedupKey(), b!.dedupKey());
    });

    test('different amounts yield different keys', () {
      final a = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Поступило 1000 ₸ от Иван',
      )!;
      final b = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Поступило 2000 ₸ от Иван',
      )!;
      expect(a.dedupKey(), isNot(b.dedupKey()));
    });

    test('different directions yield different keys', () {
      final a = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Поступило 1000 ₸ от Иван',
      )!;
      final b = PaymentSmsParser.parse(
        sender: 'Kaspi',
        body: 'Оплата 1000 ₸ в MAGNUM',
      )!;
      expect(a.dedupKey(), isNot(b.dedupKey()));
    });
  });

  group('PaymentSmsParser.formatAmount', () {
    test('integer values get thousand separators', () {
      expect(PaymentSmsParser.formatAmount(15000), '15 000');
      expect(PaymentSmsParser.formatAmount(1250), '1 250');
      expect(PaymentSmsParser.formatAmount(100), '100');
    });

    test('decimal values use comma separator and two fraction digits', () {
      expect(PaymentSmsParser.formatAmount(1000.5), '1 000,50');
    });

    test('integer-valued doubles are printed without decimals', () {
      expect(PaymentSmsParser.formatAmount(25.0), '25');
    });
  });
}
