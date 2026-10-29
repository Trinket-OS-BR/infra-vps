# Diagrama da plataforma

Mapa de tudo que roda e de como as peças se falam. Os diagramas abaixo são texto (Mermaid) e o GitHub os desenha.

> **Regra: todo escopo novo atualiza este diagrama no mesmo trabalho.** Serviço de plataforma novo (`platform/`), tipo novo de app, banco, domínio, integração externa, rotina de backup ou etapa de pipeline entram aqui **antes** de o trabalho ser dado como concluído. O `scripts/validate.sh` falha se um serviço de `platform/` não aparecer em `docs/diagrama.md`. A fonte versionada é `docs/diagrama.md` no repositório; esta página é a mesma cópia, para leitura na Wiki.

## 1. Arquitetura (o que roda e em quais redes)

```mermaid
flowchart LR
  visitante([Visitante]) -->|HTTPS| cf["CDN / proxy de DNS<br/>(ex.: Cloudflare, SSL Full strict)"]
  cf -->|80, 443| proxy

  subgraph vps["VPS (Docker)"]
    subgraph rproxy["rede proxy (entrada e saída)"]
      proxy["platform-proxy<br/>Caddy · 80/443 · HTTPS automático"]
      app["[produto]-[serviço]-production<br/>porta interna 41xx"]
    end
    subgraph rdata["rede data (interna, sem internet)"]
      postgres[("platform-postgres<br/>:4130")]
      redis[("platform-redis<br/>:4131 · 1 usuário ACL por produto")]
      rabbit[("platform-rabbitmq (preparado, desligado)<br/>AMQP 4132 · STOMP 4133 · 1 vhost por produto")]
    end
    proxy -->|reverse_proxy| app
    app -->|"DATABASE_URL (rede data)"| postgres
    app -->|"REDIS_URL (só o prefixo do produto)"| redis
    app -.->|"AMQP ou STOMP relay (só o vhost do produto)"| rabbit
  end

  app -->|"arquivos enviados"| r2[("Armazenamento de objetos (opcional)")]
  proxy -.->|"emite e renova certificado"| le["Autoridade de certificados"]
```

| Serviço | Pasta | Redes | Porta interna | Publicada no host |
|---|---|---|---|---|
| proxy | `platform/proxy` | proxy | — | 80, 443, 443/udp |
| postgres | `platform/postgres` | data | 4130 | não |
| redis | `platform/redis` | data | 4131 | não |
| rabbitmq (preparado) | `platform/rabbitmq` | data | 4132, 4133, 4134 | não |
| app (um por produto e serviço) | `apps/<produto>/production/<serviço>` | proxy, data | 4100–4129 | não |

## 2. CI/CD (do push ao ar)

```mermaid
flowchart LR
  dev([git push na main]) --> quality["quality<br/>lint, tipos, testes"]
  quality --> build["build<br/>imagem, tag = sha"]
  quality --> audit["audit<br/>dependências"]
  build --> ghcr[("GHCR")]
  build --> scan["scan<br/>Trivy"]
  build --> deploy["deploy<br/>SSH + deploy-service.sh"]
  deploy -->|"pull da tag"| ghcr
  deploy --> vps["VPS: app<br/>healthy ou rollback"]
  deploy --> smoke["smoke<br/>URL pública"]
  quality & audit & build & scan & deploy & smoke --> notify["notify<br/>Discord, sempre"]
```

## 3. Dados e backup

```mermaid
flowchart LR
  timer["timer systemd<br/>1 por banco"] --> run["backup-run.sh"]
  run -->|"pg_dump -Fc"| postgres[("platform-postgres")]
  run -->|"pg_restore --list<br/>(valida o dump)"| run
  run -->|"restic backup + forget"| repo[("Repositório Restic<br/>armazenamento de objetos")]
  run -->|"heartbeat"| hb["serviço de heartbeat"]
  restore["backup-restore.sh"] -->|"restic restore"| repo
  restore --> postgres
```

## 4. Acesso administrativo

```mermaid
flowchart LR
  eu([Administrador]) -->|"SSH com chave"| vps["VPS (usuário sem root)"]
  eu -->|"DBeaver: túnel SSH"| vps
  vps -->|"docker exec / psql"| postgres[("platform-postgres")]
  vps -->|"git pull"| repo["infra-vps (GitHub)"]
  ci(["GitHub Actions"]) -->|"SSH com chave do CI"| vps
```

## 5. Onde cada escopo está documentado

Veja a [Wiki](https://github.com/Trinket-OS-BR/infra-vps/wiki), páginas 1 a 17.

## 6. Como atualizar

1. Edite `docs/diagrama.md` no repositório: acrescente o serviço ao diagrama 1 e à tabela, e as etapas ou ligações novas aos outros.
2. Rode `scripts/validate.sh`: ele acusa serviço que ainda não está no diagrama.
3. Copie o conteúdo para esta página (mantenha a regra do topo).
4. Registre a mudança no histórico abaixo.

## 7. Histórico

| Data | Mudança |
|---|---|
| 2026-10-29 | Versão inicial: proxy, postgres, app, CI/CD, backup e acesso administrativo. |
| 2026-10-29 | Redis compartilhado com isolamento por usuário ACL e prefixo de chave. |
| 2026-10-29 | RabbitMQ com STOMP preparado (desligado): um vhost e um usuário por produto. |
