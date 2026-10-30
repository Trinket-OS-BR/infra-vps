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
- `proxy`: tráfego HTTP vindo do Caddy (`platform/proxy`) e saída das apps para a internet.
- Só o proxy (`platform/proxy`: 80, 443 TCP e 443 UDP) publica porta no host. Todo o resto usa `expose`.
- Portas internas fora do padrão, em faixa observável, registradas aqui antes de criar o compose:

| Faixa | Uso | Atribuídas |
|---|---|---|
| 4100–4129 | aplicações (uma dezena por produto) | offer web 4101; trinketos api 4110, web 4111, workspace 4112, design 4113, learn 4114 |
| 4130–4139 | dados | postgres 4130, redis 4131, rabbitmq 4132 (AMQP), 4133 (STOMP), 4134 (gestão) |
| 4140–4149 | observabilidade | openobserve 4140 (painel, API e OTLP HTTP), 4141 (OTLP gRPC) |

## 3. Obrigatório em todo serviço [auto]

`restart: unless-stopped`, `init: true`, `healthcheck`, `mem_limit`, `cpus`, `pids_limit`, `no-new-privileges`, logs `json-file` com `max-size`/`max-file`, rótulos `app.product`, `app.service`, `app.environment`. Apps ainda levam `cap_drop: [ALL]`. Imagem sempre com versão (nunca `:latest`); app, com tag imutável (sha).

## 4. Recursos

Limite = pico medido x 3 a 4. Soma dos limites <= 75% da RAM. Revisar após uma semana com `docker stats`.

| Serviço | `mem_limit` | `cpus` |
|---|---|---|
| Postgres | 1g | 1.0 |
| Web Node (Next) | 384m | 0.5 |

## 5. Segredos

Só em `.env`/`.env.production` na VPS (600), fora do Git. Senha gerada na VPS (`openssl rand`), nunca digitada em chat. Sem valor padrão de senha no compose; obrigatória usa `${VAR:?mensagem}`. Segredo exposto é rotacionado.

## 6. Dados

- Um banco e um usuário por produto (`scripts/postgres-create-db.sh`); o usuário da aplicação é dono só do seu banco e `PUBLIC` não conecta nos outros.
- Backup de todo banco em `backups.list`, cada um com a sua agenda (timer do systemd) e retenção: `pg_dump -Fc` verificado, enviado com **Restic** (criptografado) ao R2, `restic forget --prune` e **heartbeat obrigatório** (sem sinal, o monitor avisa). Credenciais só em `/etc/infra-backup` (600). Nunca aplique expiração de objetos do R2 sobre um repositório Restic. Backup que não foi restaurado uma vez (`scripts/backup-restore.sh`) não conta como backup.
- Acesso administrativo por `docker exec` ou túnel SSH; nunca porta aberta.
- **Redis compartilhado** (`platform/redis`, porta 4131): um usuário ACL por produto (`scripts/redis-create-user.sh`), restrito a chaves e canais com o prefixo `<produto>:`; sem `KEYS`, `SCAN`, `SELECT`, `INFO`, `CONFIG` nem `FLUSHALL`. O usuário `default` fica desligado e o administrador só é usado por `docker exec`. O app **prefixa todas as chaves** e usa **TTL em cache** (a política `volatile-lru` só descarta chaves com TTL). `scripts/redis-selftest.sh` prova o isolamento. Fila que exige `noeviction` (ex.: BullMQ) pede instância própria.
- **RabbitMQ compartilhado** (`platform/rabbitmq`, portas 4132 AMQP, 4133 STOMP e 4134 gestão): um **vhost e um usuário por produto** (`scripts/rabbitmq-create-vhost.sh`), com permissão só no próprio vhost e sem etiqueta de gestão. O STOMP (relay de mensagens dos apps) usa o mesmo usuário e informa o vhost no cabeçalho `host`. O painel de gestão não tem porta no host: só por túnel SSH. `scripts/rabbitmq-selftest.sh` prova o isolamento.
- **Observabilidade compartilhada** (`platform/observability`, OpenObserve, portas 4140 e 4141): logs, métricas e traces por OTLP. Uma **organização e um usuário por produto** (`scripts/observability-create-org.sh`); o usuário só existe na própria organização. Os apps enviam pela rede `data`; o painel sai pelo proxy (e, enquanto não houver domínio, só por túnel SSH). A imagem `-debug` é usada só pelo `curl` do healthcheck. `scripts/observability-selftest.sh` prova o isolamento.

## 7. Diagrama

Todo escopo novo (serviço, banco, domínio, integração externa, rotina de backup ou etapa de pipeline) atualiza [diagrama.md](diagrama.md) no mesmo trabalho. `scripts/validate.sh` falha se um serviço não constar nele. A mesma mudança vai para a página 15 da Wiki.
