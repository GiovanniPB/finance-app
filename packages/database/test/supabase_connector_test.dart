import 'package:database/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockUser extends Mock implements User {}

void main() {
  const powerSyncUrl = 'https://inst.powersync.journeyapps.com';

  late MockSupabaseClient supabase;
  late MockGoTrueClient auth;
  late SupabaseConnector connector;

  setUp(() {
    supabase = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => supabase.auth).thenReturn(auth);
    connector = SupabaseConnector(powerSyncUrl: powerSyncUrl, client: supabase);
  });

  group('fetchCredentials', () {
    test('retorna null quando não há sessão', () async {
      when(() => auth.currentSession).thenReturn(null);
      expect(await connector.fetchCredentials(), isNull);
    });

    test('retorna endpoint + token + userId quando há sessão', () async {
      final session = MockSession();
      final user = MockUser();
      when(() => user.id).thenReturn('user-1');
      when(() => session.accessToken).thenReturn('jwt-token');
      when(() => session.user).thenReturn(user);
      when(() => auth.currentSession).thenReturn(session);

      final creds = await connector.fetchCredentials();

      expect(creds, isNotNull);
      expect(creds!.endpoint, powerSyncUrl);
      expect(creds.token, 'jwt-token');
      expect(creds.userId, 'user-1');
    });
  });
}
