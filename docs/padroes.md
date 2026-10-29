# Padrões da plataforma

Valem para tudo que roda na VPS (somente produção). `scripts/validate.sh` cobra as regras marcadas [auto]. Novos serviços entram um a um, só depois que o anterior estiver estável.

## 1. Nomes [auto]

| Item | Padrão | Exemplo |
|---|---|---|
| Contêiner de plataforma | `platform-<serviço>` | `platform-postgres` |
| Contêiner de app | `<produto>-<serviço>-production` | `offer-web-production` |
| Projeto Compose (`name:`) | igual ao contêiner | |
| Volume | `platform-<serviço>-data`, com `name:` explícito | `platform-postgres-data` |
| Pasta | `platform/<serviço>/` e `apps/<produto>/production/<serviço>/` | |
| Arquivos | `compose.yaml`, `.env`/`.env.production` (segredos, só na VPS, 600), `*.example` versionados | |

`docker run` avulso é proibido: tudo sobe por Compose.

## 2. Redes e portas [auto]

- `data`: interna (sem internet), onde ficam os bancos e quem os consome.
- `proxy`: tráfego HTTP vindo do Caddy (entra com o proxy).
- Só o proxy publica porta no host. Todo o resto usa `expose`.
- Portas internas fora do padrão, em faixa observável, registradas aqui antes de criar o compose:

| Faixa | Uso | Atribuídas |
|---|---|---|
| 4100–4129 | aplicações (uma dezena por produto) | offer web 4101 |
| 4130–4139 | dados | postgres 4130 |

## 3. Obrigatório em todo serviço [auto]

`restart: unless-stopped`, `init: true`, `healthcheck`, `mem_limit`, `cpus`, `pids_limit`, `no-new-privileges`, logs `json-file` com `max-size`/`max-file`, rótulos `app.product`, `app.service`, `app.environment`. Apps ainda levam `cap_drop: [ALL]`. Imagem sempre com versão (nunca `:latest`); app, com tag imutável (sha).

## 4. Recursos

Limite = pico medido x 3 a 4. Soma dos limites <= 75% da RAM (15 GiB). Revisar após uma semana com `docker stats`.

| Serviço | `mem_limit` | `cpus` |
|---|---|---|
| Postgres | 1g | 1.0 |
| Web Node (Next) | 384m | 0.5 |

## 5. Segredos

Só em `.env`/`.env.production` na VPS (600), fora do Git. Senha gerada na VPS (`openssl rand`), nunca digitada em chat. Sem valor padrão de senha no compose; obrigatória usa `${VAR:?mensagem}`. Segredo exposto é rotacionado.

## 6. Dados

- Um banco e um usuário por produto (`scripts/postgres-create-db.sh`); o usuário da aplicação é dono só do seu banco e `PUBLIC` não conecta nos outros.
- Backup lógico diário (`scripts/postgres-backup.sh`, 7 dias). Backup que não foi restaurado uma vez não conta como backup.
- Acesso administrativo por `docker exec` ou túnel SSH; nunca porta aberta.
