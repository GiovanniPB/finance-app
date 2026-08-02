import 'dart:io';

import 'package:database/database.dart';
import 'package:finance/di/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUser extends Mock implements User {}

/// Um app rodando sobre um PowerSync **de verdade**, sem servidor.
///
/// É o que diferencia estes testes dos de unidade: aqui as tabelas são as views
/// com triggers `INSTEAD OF` que o PowerSync cria a partir do `appSchema`, e
/// não um dublê. SQL que o SQLite recusa falha aqui — que foi exatamente o caso
/// do `UPSERT` de orçamento, verde por meses num mock de conexão.
///
/// O que **não** está aqui: o connector, o upload e o Supabase. Autenticar e
/// sincronizar exigem rede e credenciais; a fronteira de sessão entra como
/// mock, porque o que se quer provar é a camada local.
class LocalStack {
  LocalStack._(this.service, this.container, this._directory);

  /// Abre um banco novo num diretório temporário e monta o container do
  /// Riverpod com os repositories reais por cima dele.
  ///
  /// [userId] é o dono da sessão que os repositories enxergam.
  static Future<LocalStack> open({String userId = 'user-1'}) async {
    final directory = await Directory.systemTemp.createTemp('finance_it');
    final service = await PowerSyncService.open(
      path: '${directory.path}/finance.db',
    );

    final supabase = _MockSupabaseClient();
    final auth = _MockGoTrueClient();
    final user = _MockUser();
    when(() => supabase.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.id).thenReturn(userId);

    final container = ProviderContainer(
      overrides: [
        powerSyncServiceProvider.overrideWithValue(service),
        supabaseClientProvider.overrideWithValue(supabase),
      ],
    );

    return LocalStack._(service, container, directory);
  }

  final PowerSyncService service;
  final ProviderContainer container;
  final Directory _directory;

  /// Acesso direto ao banco, para as verificações que não passam por
  /// repository (existência de tabela, contagem de linha).
  PowerSyncDatabase get db => service.db;

  /// Fecha o banco e apaga o diretório. Registre com `addTearDown`.
  Future<void> dispose() async {
    container.dispose();
    await service.close();
    if (_directory.existsSync()) {
      _directory.deleteSync(recursive: true);
    }
  }
}

/// Abre um [LocalStack] já com o `tearDown` registrado.
Future<LocalStack> localStack({String userId = 'user-1'}) async {
  final stack = await LocalStack.open(userId: userId);
  addTearDown(stack.dispose);
  return stack;
}

/// Insere um espaço direto no banco local.
///
/// Espaço nasce no servidor (trigger de signup) e chega pelo sync; nestes
/// testes não há sync, então ele entra pela porta dos fundos para as tabelas
/// com escopo de espaço terem onde se pendurar.
Future<void> seedSpace(
  PowerSyncDatabase db, {
  String id = 'space-1',
  String ownerId = 'user-1',
  String spaceType = 'personal',
  String? name,
}) {
  final spaceName = name ?? (spaceType == 'personal' ? 'Pessoal' : 'República');
  return db.execute(
    'INSERT INTO spaces (id, space_type, name, owner_id, privacy_policy, '
    'status, settlement_currency, created_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      id,
      spaceType,
      spaceName,
      ownerId,
      'shared_only',
      'active',
      'BRL',
      '2026-07-01T00:00:00.000Z',
      '2026-07-01T00:00:00.000Z',
    ],
  );
}

/// Insere uma membership direto no banco local.
///
/// [joinedAt] importa: o rateio sai na ordem de entrada, e um teste que não
/// controla essa ordem passa por coincidência de uuid.
Future<void> seedMember(
  PowerSyncDatabase db, {
  required String id,
  required String userId,
  String spaceId = 'space-1',
  String role = 'editor',
  String status = 'active',
  String? displayName,
  String joinedAt = '2026-07-01T00:00:00.000Z',
}) => db.execute(
  'INSERT INTO space_members (id, space_id, user_id, role, status, '
  'display_name, joined_at, created_at, updated_at) '
  'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
  [
    id,
    spaceId,
    userId,
    role,
    status,
    displayName,
    joinedAt,
    joinedAt,
    joinedAt,
  ],
);

/// Insere uma categoria de sistema direto no banco local (elas vêm do bucket
/// global do PowerSync, que aqui não existe).
Future<void> seedSystemCategory(
  PowerSyncDatabase db, {
  String id = 'cat-1',
  String name = 'Alimentação',
}) => db.execute(
  'INSERT INTO categories (id, space_id, name, icon_key, color_index, '
  'is_system, created_at, updated_at) VALUES (?, NULL, ?, ?, NULL, 1, ?, ?)',
  [id, name, 'food', '2026-07-01T00:00:00.000Z', '2026-07-01T00:00:00.000Z'],
);
