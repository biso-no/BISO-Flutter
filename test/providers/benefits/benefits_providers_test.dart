import 'package:biso/data/models/campus_benefit.dart';
import 'package:biso/data/models/campus_model.dart';
import 'package:biso/data/services/benefits_api_client.dart';
import 'package:biso/providers/benefits/benefits_providers.dart';
import 'package:biso/providers/campus/campus_provider.dart';
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

CampusModel _campus(String id, String name) => CampusModel(
  id: id,
  name: name,
  description: '',
  location: name,
  imageUrl: '',
  heroImageUrl: '',
  stats: const CampusStats(),
);

ProviderContainer _names({
  List<CampusModel> switcher = const [],
  bool switcherFails = false,
}) {
  final container = ProviderContainer(
    overrides: [
      filterCampusProvider.overrideWithValue(_campus('3', 'Trondheim')),
      switcherCampusesProvider.overrideWith(
        (_) async => switcherFails ? throw Exception('offline') : switcher,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
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

  group('benefitsNotDeployedProvider', () {
    Future<List<bool>> seen(Future<List<CampusBenefit>> Function() load) async {
      final container = ProviderContainer(
        overrides: [campusBenefitsProvider('3').overrideWith((_) => load())],
      );
      addTearDown(container.dispose);
      final sub = container.listen(benefitsNotDeployedProvider('3'), (_, _) {});
      addTearDown(sub.close);
      final values = <bool>[sub.read()];
      try {
        await container.read(campusBenefitsProvider('3').future);
      } on Object {
        // The error is what's being read.
      }
      values.add(sub.read());
      return values;
    }

    test('true once the API turns out to have no benefits route', () async {
      expect(
        await seen(
          () async => throw const BenefitsApiException(
            BenefitsApiErrorKind.notDeployed,
            statusCode: 404,
          ),
        ),
        [false, true],
      );
    });

    test(
      'false while loading, with a list, and after any other error',
      () async {
        expect(await seen(() async => const []), [false, false]);
        expect(
          await seen(
            () async =>
                throw const BenefitsApiException(BenefitsApiErrorKind.network),
          ),
          [false, false],
        );
        expect(await seen(() async => throw Exception('boom')), [false, false]);
      },
    );
  });

  group('benefitCampusNameProvider', () {
    test('all of BISO has no name: the widgets say "Hele BISO"', () {
      final container = _names();
      expect(container.read(benefitCampusNameProvider(null)), '');
      expect(container.read(benefitCampusNameProvider('5')), '');
    });

    test('the filter campus names itself without a fetch', () {
      final container = _names(switcherFails: true);
      expect(container.read(benefitCampusNameProvider('3')), 'Trondheim');
    });

    test('another campus takes its name from the switcher list', () async {
      final container = _names(switcher: [_campus('1', 'Oslo')]);
      final sub = container.listen(benefitCampusNameProvider('1'), (_, _) {});
      addTearDown(sub.close);
      expect(sub.read(), 'BISO');
      await container.read(switcherCampusesProvider.future);
      expect(sub.read(), 'Oslo');
    });

    test('an unknown campus, or a failed list, reads "BISO"', () async {
      final container = _names(switcher: [_campus('1', 'Oslo')]);
      final sub = container.listen(benefitCampusNameProvider('9'), (_, _) {});
      addTearDown(sub.close);
      await container.read(switcherCampusesProvider.future);
      expect(sub.read(), 'BISO');

      final failing = _names(switcherFails: true);
      final failed = failing.listen(benefitCampusNameProvider('1'), (_, _) {});
      addTearDown(failed.close);
      await expectLater(
        failing.read(switcherCampusesProvider.future),
        throwsException,
      );
      expect(failed.read(), 'BISO');
    });
  });
}
