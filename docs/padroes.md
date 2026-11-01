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
| 4100–4129 | aplicações (uma dezena por produto) | offer web 4101; trinketos api 4110, web 4111, workspace 4112, design 4113, learn 4114; ebooks web 4121; portfolio web 4122; systemfix web 4123; pea api 4124, web 4125 |
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
- **Observabilidade compartilhada** (`platform/observability`, OpenObserve, portas 4140 e 4141): logs, métricas e traces por OTLP. Uma **organização e um usuário por produto** (`scripts/observability-create-org.sh`); o usuário só existe na própria organização. Os apps enviam pela rede `data`; o painel sai pelo proxy (e, enquanto não houver domínio, só por túnel SSH). A imagem `-debug` é usada só pelo `curl` do healthcheck. `scripts/observability-selftest.sh` prova o isolamento. Defina `ZO_WEB_URL` (endereço público do painel) no `.env` da observabilidade: sem ele, os links dos alertas apontam para `http://localhost:5080`.

## 7. Diagrama

Todo escopo novo (serviço, banco, domínio, integração externa, rotina de backup ou etapa de pipeline) atualiza [diagrama.md](diagrama.md) no mesmo trabalho. `scripts/validate.sh` falha se um serviço não constar nele. A mesma mudança vai para a página 15 da Wiki.

## Origem atrás da Cloudflare

- **Estado em 01/11/2026 (verificado de fora):** o IP da VPS (187.41.103.163) aceita HTTPS direto em `443` e responde `200` para os sites por `--resolve` (ex.: `curl -sk --resolve pea.antoniobsilva.com.br:443:187.41.103.163 https://pea.antoniobsilva.com.br/`). **Não há trava que limite a origem à Cloudflare**; nada no `platform/proxy/Caddyfile` nem registrado no vault a aplica.
- **Consequência:** quem acessar o IP direto contorna o WAF e as regras da Cloudflare e pode forjar `CF-Connecting-IP`, que o PEA usa no limite de envios por IP.
- **Caminhos possíveis (escolher um e registrar aqui):** (1) Authenticated Origin Pulls: ligar na zona e exigir o certificado de cliente da Cloudflare no Caddy (`client_auth` com o CA de origin pull); (2) firewall da VPS liberando `443` só para as faixas de IP da Cloudflare (lista publicada em cloudflare.com/ips); (3) os dois.
- **Teste de aceite:** o `curl` acima deve falhar (recusa ou erro de handshake) e o site pelo domínio deve continuar abrindo.

## Registro de migrações

| Data | Produto | Resumo |
|---|---|---|
| 01/11/2026 | System Fix | Site estático em Caddy (4123) na VPS nova, traces no OpenObserve; container e imagem antigos removidos. |
| 01/11/2026 | PEA | API (4124) e web (4125) na VPS nova, Redis compartilhado (usuário `pea`, chaves `pea:*`, sem TTL no placar), traces no OpenObserve; web em Caddy encaminha `/api` e `/_vercel/insights`; sem micro-cache (a API já manda `s-maxage=5`); contêineres, volume e imagens antigos removidos. |

## Página de status (Better Stack)
Página pública `status.antoniobsilva.com.br` no Better Stack (conta `t478697`, plano gratuito), com monitores HTTP a cada 3 minutos: API, Web, Learn e Workspace do TrinketOS, PEA (`/api/health`), System Fix, portfólio e ebooks. Seções por produto, em inglês e pt-BR. Todo serviço novo ganha um monitor e entra na seção do seu produto. O domínio próprio usa o CNAME `status` → `statuspage.betteruptime.com` no Cloudflare, em "Somente DNS" (com proxy dá 526); no ar desde 01/11/2026. Detalhes em `projetos/trinketos/limpeza-servidores-antigos-2026-11-01.md` no vault.
