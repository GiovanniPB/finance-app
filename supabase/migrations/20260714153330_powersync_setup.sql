-- =========================================================================
-- Configuração de replicação para o PowerSync.
-- O PowerSync consome o WAL do Postgres via uma publication de replicação
-- lógica chamada `powersync`. FOR ALL TABLES inclui automaticamente novas
-- tabelas sincronizáveis criadas em migrations futuras.
-- =========================================================================

create publication powersync for all tables;

-- REPLICA IDENTITY FULL: garante que updates/deletes gravem a linha completa no
-- WAL, necessário para o PowerSync processar essas mudanças corretamente.
alter table public.profiles replica identity full;
alter table public.accounts replica identity full;
