# ROMANO PARTNERS

Novo sistema de gestão da ROMANO PROPERTY CARE.

## Projeto
- Repositório independente: `romano-partners-new`
- Backend: Supabase `ztjfvqcutwlfbqmtclyv`
- Hospedagem: Cloudflare
- Interface-base: Coração 2

## Regra de isolamento
Clientes e funcionários devem acessar somente os dados autorizados no backend. A autorização deve ser aplicada por RLS/server-side, nunca apenas pela interface.

## Estado inicial
A base de dados foi limpa antes da implantação deste projeto. Nenhum dado operacional anterior deve ser reutilizado.

## Segurança e operação
- Autenticação: Supabase Auth + MFA.
- Dados operacionais: PostgreSQL + RLS/server-side.
- Offline: fila IndexedDB de mutações, idempotência por UUID e detecção de conflito por `updated_at`.
- Sincronização: replay automático ao recuperar a conexão.
- Evidências: Storage privado com URLs assinadas.
- Backup lógico: Edge Function `romano-backup` + bucket privado `romano-backups`.
- Backup/DR do projeto: utilizar os mecanismos nativos de backup/PITR da Supabase e manter cópia externa conforme a política operacional.


<!-- Cloudflare production redeploy trigger: 2026-09-23 -->