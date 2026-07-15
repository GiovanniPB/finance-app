# Testes de integração

Pendente de uma instância PowerSync provisionada (ver README raiz → PowerSync).

## Teste-chave a implementar: prova offline → online

1. Autenticar (signup/login programático no Supabase de teste).
2. Conectar o PowerSync (`PowerSyncService.connect(SupabaseConnector(...))`).
3. Inserir uma `account` **offline** → verificar persistência local imediata
   (o stream de `accountsRepository.watchAll()` emite).
4. Reconectar/aguardar o upload → verificar que a linha chega ao Postgres
   (via `supabase` MCP / `execute_sql` na tabela `accounts`), respeitando o RLS.

Rodar com:

```bash
fvm flutter test integration_test \
  --dart-define-from-file=../../env/dev.json
```
