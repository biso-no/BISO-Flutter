import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingApi implements BenefitsApi {
  int fetches = 0;

  @override
  Future<List<CampusBenefit>> fetchBenefits({String? campusId}) async {
    fetches++;
    return const [];
  }

  @override
  Future<String> reveal(String benefitId) => throw UnimplementedError();
}

void main() {
  test('fetches the list again on the next visit', () async {
    final api = _CountingApi();
    final container = ProviderContainer(
      overrides: [benefitsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    // First visit: a screen watches the list, then leaves.
    final first = container.listen(campusBenefitsProvider('2'), (_, _) {});
    await container.read(campusBenefitsProvider('2').future);
    first.close();
    await container.pump();

    // Next visit: a new deal or an ended one must show up.
    final second = container.listen(campusBenefitsProvider('2'), (_, _) {});
    await container.read(campusBenefitsProvider('2').future);
    second.close();

    expect(api.fetches, 2);
  });

  test('keeps one fetch while the screen stays open', () async {
    final api = _CountingApi();
    final container = ProviderContainer(
      overrides: [benefitsApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(campusBenefitsProvider('2'), (_, _) {});
    await container.read(campusBenefitsProvider('2').future);
    await container.read(campusBenefitsProvider('2').future);
    sub.close();

    expect(api.fetches, 1);
  });
}
