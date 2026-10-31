<div align="center">

<img src="assets/icon.svg" alt="Ícone do Infra VPS" width="150"/>

# Infra VPS

### A receita da VPS do ecossistema Trinket OS.

Serviços de plataforma (PostgreSQL, Redis, RabbitMQ, observabilidade, proxy e backup) e as aplicações do ecossistema descritos em Docker Compose, padronizados em nomes, redes, portas, limites de recursos e *healthchecks*, e que sobem com um único comando.

[Repositório](https://github.com/Trinket-OS-BR/infra-vps) · [Wiki (passo a passo)](https://github.com/Trinket-OS-BR/infra-vps/wiki) · [Contato](mailto:support@trinket.com.br)

</div>

---

## Para que serve este repositório

O **Infra VPS** é a fonte única do que roda na VPS de produção. Em vez de configurar o servidor à mão, a receita fica no Git: você clona na VPS, preenche os segredos e sobe tudo com `scripts/up.sh`. A mesma receita recria o ambiente em outro servidor.

- Cada serviço mora em uma pasta com seu `compose.yaml` e entra em `services.list`, **um por vez**, só depois que o anterior estiver estável.
- Nomes, redes, portas e limites seguem um padrão único, cobrado por `scripts/validate.sh`.
- **Nenhum segredo vai para o Git.** O repositório tem só os `*.example`; senhas são geradas na VPS e ficam em arquivos com permissão 600.
- Só o proxy publica portas no host. Bancos ficam em uma rede Docker interna, sem acesso à internet.

As aplicações têm repositórios próprios e se conectam a esta infraestrutura pelas redes Docker. Aqui ficam só a receita de cada serviço (`apps/<produto>/production/<serviço>`) e o deploy; o código e a esteira de build ficam no repositório de cada aplicação.

## O que roda hoje

| Produto   | Serviços (porta interna)                                                    | Dados que usa                                        |
| --------- | --------------------------------------------------------------------------- | ---------------------------------------------------- |
| Offer     | web (4101)                                                                  | PostgreSQL (uploads vão para o R2)                   |
| Ebooks    | web (4121)                                                                  | nenhum (site estático)                               |
| TrinketOS | api (4110), web (4111), workspace (4112), design (4113), learn (4114)        | só a API usa PostgreSQL, Redis e RabbitMQ; os demais chamam a API |

Plataforma compartilhada: PostgreSQL (4130), Redis, RabbitMQ com STOMP, OpenObserve (4140 e 4141) e o proxy Caddy, a única entrada HTTP/HTTPS. Cada produto tem banco, usuário Redis, vhost RabbitMQ e organização de observabilidade próprios.

## Tecnologias

| Área           | Tecnologia                                   |
| -------------- | -------------------------------------------- |
| Servidor       | Ubuntu LTS em uma VPS                       |
| Contêineres    | Docker e Docker Compose                      |
| Banco de dados | PostgreSQL 16 (Alpine)                       |
| Cache e filas  | Redis e RabbitMQ (AMQP e STOMP)              |
| Observabilidade | OpenObserve (OTLP: logs, métricas e traces) |
| Entrada        | Caddy (HTTPS automático, sites por produto) atrás da Cloudflare (DNS e proxy, SSL Full strict) |
| Acesso ao painel | Cloudflare Zero Trust (Access) + login do OpenObserve |
| Armazenamento de objetos | Cloudflare R2: uploads dos apps e backups (Restic) |
| Imagens e CI/CD | GitHub Actions e GitHub Container Registry (GHCR) |
| Automação      | Scripts Bash e timers do systemd             |
| Backup         | pg_dump + Restic (criptografado) no Cloudflare R2 |
| Entrega        | Git: clone na VPS, `git pull` para atualizar |

## Como executar na VPS

Pré-requisito: VPS com Docker e o usuário `deploy` configurados (passo a passo na [Wiki](https://github.com/Trinket-OS-BR/infra-vps/wiki)).

1. Clone o repositório:

   ```bash
   sudo mkdir -p /srv && sudo chown deploy:deploy /srv
   git clone https://github.com/Trinket-OS-BR/infra-vps.git /srv/infra-vps
   cd /srv/infra-vps
   ```

2. Crie os segredos, que ficam só na VPS:

   ```bash
   cp platform/postgres/.env.example platform/postgres/.env
   sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" platform/postgres/.env
   ```

3. Valide e suba:

   ```bash
   scripts/validate.sh && scripts/up.sh
   ```

4. Crie o banco de um produto (a senha é gerada e gravada em arquivo, nunca impressa):

   ```bash
   scripts/postgres-create-db.sh offer /srv/secrets/offer-db.env
   ```

Para atualizar depois de uma mudança na receita: `git pull && scripts/up.sh`.

## Segurança e acesso

- **Zero Trust:** o painel de observabilidade só é alcançado depois de uma política do Cloudflare Zero Trust (Access) que libera o administrador; o login do OpenObserve é a segunda camada.
- **Sem porta de administração aberta:** acesso por SSH com chave (usuário sem root) ou túnel SSH; só o proxy publica portas no host.
- **R2:** uploads dos apps e backups usam credenciais separadas. O backup é criptografado pelo Restic antes de sair da VPS.
- **Segredos:** nada vai para o Git. Variáveis de infraestrutura ficam em `/srv/secrets` na VPS; as da aplicação, em secrets do repositório dela.

O mapa completo, com redes, fluxos e CI/CD, está em [docs/diagrama.md](docs/diagrama.md).

## Como uma aplicação é publicada

Cada aplicação tem uma esteira em etapas no próprio repositório (qualidade, build da imagem, varredura de vulnerabilidades, deploy, smoke test e aviso), que dispara no *push* da branch `main`. A etapa de deploy:

1. grava na VPS o `.env.production` do serviço, a partir de um secret do repositório;
2. chama `scripts/deploy-service.sh <produto> <serviço> <tag>`, que troca a imagem, espera o serviço ficar *healthy* e, se falhar, **volta sozinho para a tag anterior**;
3. o smoke test confere a URL pública. Ele só roda se a variável de repositório `KVM4_SMOKE_ENABLED` for `true`, e cada serviço tem a sua URL e o seu caminho de saúde (`/actuator/health` na API, `/api/health` nos apps Next, `/healthz` no Storybook).

Rollback manual: dispare a esteira com `workflow_dispatch` informando a tag (`image_tag`) a reimplantar. As variáveis de infraestrutura (banco, Redis, RabbitMQ) ficam em `/srv/secrets` na VPS e nunca vão para o secret da aplicação.

## Comandos principais

| Comando                                          | Descrição                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `scripts/up.sh [pasta]`                          | Sobe os serviços de `services.list` (ou só a pasta indicada) e espera ficarem *healthy* |
| `scripts/deploy-service.sh <produto> <serviço> <tag>` | Troca a imagem de um serviço, espera ficar *healthy* e volta sozinho para a tag anterior se falhar |
| `scripts/proxy-site.sh enable\|disable\|status <nome>` | Liga ou desliga um conjunto de sites do proxy; valida antes de recarregar e desfaz se falhar |
| `scripts/validate.sh`                            | Confere todo `compose.yaml` contra os padrões, sem subir nada             |
| `scripts/bootstrap.sh`                           | Cria as redes Docker da plataforma (idempotente)                          |
| `scripts/postgres-create-db.sh <nome> <arquivo>` | Cria banco e usuário próprios de um produto                               |
| `scripts/redis-create-user.sh <nome> <arquivo>` | Cria o usuário Redis de um produto (só o prefixo `<nome>:`)                |
| `scripts/redis-selftest.sh`                      | Prova que dois produtos não se enxergam no Redis (cria e apaga usuários temporários) |
| `scripts/rabbitmq-create-vhost.sh <nome> <arquivo>` | Cria o vhost e o usuário RabbitMQ de um produto (permissão só no próprio vhost) |
| `scripts/rabbitmq-selftest.sh`                   | Prova que dois produtos não se enxergam no RabbitMQ (AMQP/STOMP e API de gestão) |
| `scripts/observability-create-org.sh <nome> <arquivo>` | Cria a organização e o usuário de envio de um produto no OpenObserve (credenciais OTLP em arquivo modo 600, sem imprimir) |
| `scripts/observability-selftest.sh`              | Prova que dois produtos não se enxergam no OpenObserve (API e OTLP) |
| `scripts/backup-init.sh <nome>`                  | Prepara um alvo: senha de criptografia e repositório Restic no R2         |
| `scripts/backup-run.sh <nome>`                   | Backup de um alvo: dump, verificação, Restic para o R2, retenção e heartbeat |
| `scripts/backup-status.sh <nome>`                | Lista os snapshots do alvo no R2 e o próximo timer (só leitura)           |
| `scripts/backup-systemd.sh [--apply]`            | Mostra ou instala o timer do systemd de cada alvo (agenda por banco)      |
| `scripts/backup-restore.sh <nome> <latest\|id> <banco>` | Restaura um snapshot em um banco novo                              |

## Estrutura do projeto

```
infra-vps/
├── platform/
│   ├── postgres/          # compose.yaml e .env.example
│   ├── redis/             # Redis compartilhado: compose.yaml, redis.conf e .env.example
│   ├── rabbitmq/          # RabbitMQ + STOMP (preparado): compose.yaml, rabbitmq.conf e enabled_plugins
│   ├── observability/     # OpenObserve (logs, métricas, traces): compose.yaml e .env.example
│   ├── proxy/             # Caddy: compose.yaml, Caddyfile e .env.example
│   │                      #   (única entrada HTTP/HTTPS da VPS); sites-disponiveis/ guarda os
│   │                      #   sites por produto, ligados por scripts/proxy-site.sh
│   └── backup/            # modelos de r2.env e heartbeat.env
├── backups.list           # bancos com backup: contêiner, agenda (systemd) e retenção
├── apps/                  # um serviço por produto/ambiente (offer/production/web, trinketos/production/{api,web,workspace,design,learn})
├── scripts/               # up, bootstrap, deploy-service, proxy-site, validate, postgres-*, redis-*, rabbitmq-*, observability-*, backup-*
├── docs/
│   ├── padroes.md         # nomes, redes, portas, recursos, segredos e dados
│   └── diagrama.md        # diagrama da plataforma (atualizar a cada escopo novo)
└── services.list          # o que sobe, em ordem
```

## Padrões

Contêineres `platform-<serviço>` e `<produto>-<serviço>-production`; redes `data` (interna, sem internet) e `proxy`; portas internas fora do padrão em faixa observável (apps 4100–4129, dados 4130–4139); limites de CPU e memória em todo serviço; imagens sempre versionadas. Regras completas em [docs/padroes.md](docs/padroes.md).

## Como contribuir

Antes de criar um serviço, leia [docs/padroes.md](docs/padroes.md) e copie um serviço parecido. Todo serviço novo entra com um `compose.yaml` que passe em `scripts/validate.sh`, o `.env.example` com os nomes das variáveis (nunca valores reais), uma linha em `services.list` e **a atualização do [diagrama da plataforma](docs/diagrama.md)** (a validação falha se o serviço não constar nele; copie a mudança para a página 15 da Wiki). Ao abrir um pull request, informe como foi verificado.

Este repositório é **público**: nunca inclua senhas, tokens, chaves, endereços internos ou dados de clientes em arquivos, logs ou capturas de tela.

## Documentação e contato

O passo a passo completo, da VPS vazia ao Postgres no ar, está na **[Wiki](https://github.com/Trinket-OS-BR/infra-vps/wiki)**.

Para conversar sobre o ecossistema, acesse a **[Comunidade Trinket OS](https://github.com/Trinket-OS-BR/community/discussions)**. Questões de acesso, dados de uma organização ou incidentes de segurança devem ir para **[support@trinket.com.br](mailto:support@trinket.com.br)**.

---

<div align="center">

**IA que trabalha para o seu time de suporte.**

Criado por Antonio Silva · Desenvolvido no Brasil

[trinket.com.br](https://www.trinket.com.br) · [@trinketos.app](https://www.instagram.com/trinketos.app/)

</div>
