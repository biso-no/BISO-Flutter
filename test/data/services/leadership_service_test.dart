import 'dart:convert';

import 'package:biso/data/services/leadership_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<Uri> requested;

  LeadershipService serviceReturning(http.Response response) {
    requested = [];
    return LeadershipService(
      httpClient: MockClient((request) async {
        requested.add(request.url);
        return response;
      }),
    );
  }

  final okBody = jsonEncode({
    'success': true,
    'count': 1,
    'departmentName': 'Ledelsen Oslo',
    'campus': 'Oslo',
    'members': [
      {
        'name': 'Kari Nordmann',
        'email': 'kari@biso.no',
        'phone': '',
        'role': 'President Oslo',
        'officeLocation': 'Oslo',
        'profilePhotoUrl': 'data:image/jpeg;base64,AAAA',
      },
    ],
  });

  test(
    'a department board is fetched from the campus/department route',
    () async {
      final service = serviceReturning(http.Response(okBody, 200));

      final response = await service.getBoardMembers(
        campusId: '1',
        departmentId: '2',
      );

      expect(
        requested.single.toString(),
        'https://api.biso.no/api/campus/1/2/board',
      );
      expect(response.success, isTrue);
      expect(response.departmentName, 'Ledelsen Oslo');
      expect(response.members.single.name, 'Kari Nordmann');
      expect(response.members.single.profilePhotoUrl, startsWith('data:image'));
    },
  );

  test(
    "a campus board without a department asks for the campus's default",
    () async {
      final service = serviceReturning(http.Response(okBody, 200));

      await service.getBoardMembers(campusId: '1');

      expect(
        requested.single.toString(),
        'https://api.biso.no/api/campus/1/undefined/board',
      );
    },
  );

  test('path segments are encoded', () async {
    final service = serviceReturning(http.Response(okBody, 200));

    await service.getBoardMembers(
      campusId: '1',
      departmentId: 'Control Committee/x',
    );

    expect(
      requested.single.path,
      '/api/campus/1/Control%20Committee%2Fx/board',
    );
  });

  test("a server error surfaces the server's message", () async {
    final service = serviceReturning(
      http.Response(
        jsonEncode({'success': false, 'message': 'Department 9 not found'}),
        404,
      ),
    );

    final response = await service.getBoardMembers(
      campusId: '1',
      departmentId: '9',
    );

    expect(response.success, isFalse);
    expect(response.members, isEmpty);
    expect(response.error, 'Department 9 not found');
  });

  test('a non-JSON error page does not throw', () async {
    final service = serviceReturning(
      http.Response('<!DOCTYPE html><html></html>', 404),
    );

    final response = await service.getBoardMembers(campusId: '1');

    expect(response.success, isFalse);
    expect(response.error, isNotEmpty);
  });

  test('a network failure is reported, not thrown', () async {
    final service = LeadershipService(
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
    );

    final response = await service.getBoardMembers(campusId: '1');

    expect(response.success, isFalse);
    expect(response.error, contains('offline'));
  });
}
