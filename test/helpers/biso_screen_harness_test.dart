import 'package:biso/core/theme/biso_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'biso_screen_harness.dart';

void main() {
  testWidgets('harness pumps a BisoPage in every appearance', (tester) async {
    await expectBuildsCleanly(
      tester,
      () => const BisoPage(
        title: 'Harness',
        slivers: [SliverToBoxAdapter(child: Text('Content'))],
      ),
    );
  });
}
