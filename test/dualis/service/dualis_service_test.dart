import 'package:dhbwstudentapp/dualis/service/dualis_service.dart';
import 'package:test/test.dart';

void main() {
  test('String interpolation', () async {
    var service = DualisService();

    var result = await service.makeRequest();
  });
}
