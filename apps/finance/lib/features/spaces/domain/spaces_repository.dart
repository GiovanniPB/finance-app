import 'space.dart';

/// Acesso aos Espaços do usuário. As leituras são reativas (PowerSync `watch`):
/// o SQLite local já contém apenas os espaços dos quais o usuário é membro
/// (garantido pelas sync rules + RLS — ver ADR 0004).
///
/// A criação de espaços compartilhados (household/group) entra na fase de
/// Colaboração; o Espaço Pessoal é criado no servidor no signup.
abstract interface class SpacesRepository {
  /// Todos os espaços visíveis ao usuário, ordenados por criação.
  Stream<List<Space>> watchAll();

  /// Um espaço específico (ou `null` se não estiver no banco local).
  Stream<Space?> watchById(String id);
}
