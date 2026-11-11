import 'package:sg_domain/sg_domain.dart';
import 'package:test/test.dart';

void main() {
  group('Worker.copyWith', () {
    final worker = Worker(
      id: 'w1',
      code: 'W-0001',
      name: 'Asha Devi',
      dateOfBirth: DateTime(1990, 5, 2),
      department: 'Packing',
      designation: 'Packer',
      shiftId: 's1',
      contractor: 'Shree Manpower',
      phone: '98765 43210',
    );

    test('keeps optional fields that are not given', () {
      final copy = worker.copyWith(name: 'Asha D');
      expect(copy.contractor, 'Shree Manpower');
      expect(copy.phone, '98765 43210');
    });

    test('can remove the contractor and the phone', () {
      final copy = worker.copyWith(clearContractor: true, clearPhone: true);
      expect(copy.contractor, isNull);
      expect(copy.phone, isNull);
      expect(copy.name, 'Asha Devi');
    });
  });
}
