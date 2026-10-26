import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Result', () {
    test('ok exposes its value', () {
      const result = Result<int, String>.ok(3);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, 3);
      expect(result.fold((v) => 'value $v', (f) => 'failure $f'), 'value 3');
    });

    test('err exposes its failure', () {
      const result = Result<int, String>.err('nope');

      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(
        result.fold((v) => 'value $v', (f) => 'failure $f'),
        'failure nope',
      );
    });

    test('map transforms ok and passes err through', () {
      expect(
        const Result<int, String>.ok(2).map((v) => v * 10),
        const Ok<int, String>(20),
      );
      expect(
        const Result<int, String>.err('x').map((v) => v * 10),
        const Err<int, String>('x'),
      );
    });
  });
}
