# System Fix Service na VPS

Uma origem pública (o domínio do `systemfix.caddy`) e três contêineres, todos pelo pipeline de `System Fix Production VPS` no repositório do produto.

```
Cloudflare → platform-proxy → systemfix-web-production :4123 (gateway Caddy)
                                  ├─ /            landing page (arquivos estáticos)
                                  ├─ /lp/_next/*  assets da landing page
                                  └─ demais rotas → systemfix-app-production :4126 (painel Next.js)
                                                        └─ /api/backend → systemfix-api-production :4127 (Fastify)
                                                                              ├─ platform-postgres :4130 (banco systemfix, papel system_fix_runtime)
                                                                              └─ platform-redis :4131 (usuário systemfix, chaves systemfix:*)
```

A landing page é a página inicial. O painel começa em `/login` e, depois do login, abre `/dashboard`. A API não é pública: só o painel fala com ela, pela rede `data`.

| Serviço | Contêiner | Porta | Imagem (GHCR) |
|---|---|---|---|
| web | `systemfix-web-production` | 4123 | `system-fix` |
| app | `systemfix-app-production` | 4126 | `system-fix-app` |
| api | `systemfix-api-production` | 4127 | `system-fix-api` |

## Primeira vez (uma vez só, na ordem)

1. Banco e Redis do produto (as credenciais ficam em `/srv/secrets`, modo 600, sem imprimir):
   ```bash
   scripts/postgres-create-db.sh systemfix /srv/secrets/systemfix-db.env
   scripts/redis-create-user.sh systemfix /srv/secrets/systemfix-redis.env
   apps/systemfix/production/api/make-infra-env.sh
   ```
   O último junta os dois em `systemfix-api-infra.env` (a API em execução usa o papel restrito `system_fix_runtime`) e cria `systemfix-migrate.env`, com a conexão administrativa que só a migração usa.
2. Em cada pasta `api`, `app` e `web` de `apps/systemfix/production`, copie `.env.example` para `.env` e preencha `IMAGE_OWNER` (minúsculas). O deploy do CI grava `IMAGE_TAG` e `.env.production`.
3. Migração do banco, depois que a primeira imagem da API existir no GHCR (o deploy da API falha e volta sozinho sem as tabelas):
   ```bash
   cd apps/systemfix/production/api
   docker compose --profile migrate run --rm migrate
   cd ../../../.. && apps/systemfix/production/api/make-infra-env.sh --cleanup
   ```
   A migração cria o papel `system_fix_runtime` e define a senha dele a partir de `systemfix-runtime.pass`. Apague `systemfix-migrate.env` em seguida: ele guarda a senha do administrador.
4. Cadastro inicial do SUPER_ADMIN (opcional, só enquanto precisar): adicione `PLATFORM_SETUP_TOKEN` ao `.env.production` da API **na VPS** (nunca no CI; gere com `pnpm setup:platform-key` no repositório do produto) e reinicie. Depois do cadastro, remova a linha.
5. Observabilidade (opcional): `scripts/observability-create-org.sh systemfix /srv/secrets/systemfix-web-observability.env` liga os traces do gateway.

## Variáveis do GitHub (ambiente KVM4)

`KVM4_SYSTEMFIX_URL` é a origem pública com `https://` e sem barra final. O deploy a grava como `ADMIN_ORIGIN` no painel, que a usa para recusar escritas vindas de outra origem. Sem ela o painel recusa todas as escritas em produção.

## Deploy e rollback

O push em `main` constrói as três imagens, escaneia e implanta em ordem: API, painel, gateway. Cada passo espera ficar `healthy` e volta sozinho à tag anterior se falhar. Rollback total: rode o workflow à mão com `image_tag` = tag anterior (vale para os três). A migração **nunca** roda no deploy: uma imagem nova que precisa de tabela nova exige rodar o passo 3 antes de fazer o merge em `main`.

## Verificação

```bash
docker ps --format "table {{.Names}}\t{{.Status}}" | grep systemfix
curl -fsS https://<dominio>/healthz            # gateway
curl -fsS https://<dominio>/ | grep -c "/lp/_next"   # landing page na raiz
curl -s -o /dev/null -w '%{http_code}\n' https://<dominio>/login   # painel (200)
```
