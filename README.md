<div align="center">

<img src="docs/assets/icon.svg" alt="Ícone do Infra VPS" width="150"/>

# Infra VPS

### A receita da VPS do ecossistema Trinket OS.

Serviços de plataforma (começando pelo PostgreSQL) descritos em Docker Compose, padronizados em nomes, redes, portas, limites de recursos e *healthchecks*, e que sobem com um único comando.

[Repositório](https://github.com/Trinket-OS-BR/infra-vps) · [Wiki (passo a passo)](https://github.com/Trinket-OS-BR/infra-vps/wiki) · [Contato](mailto:support@trinket.com.br)

</div>

---

## Para que serve este repositório

O **Infra VPS** é a fonte única do que roda na VPS de produção. Em vez de configurar o servidor à mão, a receita fica no Git: você clona na VPS, preenche os segredos e sobe tudo com `scripts/up.sh`. A mesma receita recria o ambiente em outro servidor.

- Cada serviço mora em uma pasta com seu `compose.yaml` e entra em `services.list`, **um por vez**, só depois que o anterior estiver estável.
- Nomes, redes, portas e limites seguem um padrão único, cobrado por `scripts/validate.sh`.
- **Nenhum segredo vai para o Git.** O repositório tem só os `*.example`; senhas são geradas na VPS e ficam em arquivos com permissão 600.
- Só o proxy publica portas no host. Bancos ficam em uma rede Docker interna, sem acesso à internet.

As aplicações (como o Offer) têm repositórios próprios e se conectam a esta infraestrutura pelas redes Docker.

## Tecnologias

| Área           | Tecnologia                                   |
| -------------- | -------------------------------------------- |
| Servidor       | Ubuntu 26.04 LTS (VPS Hostinger)             |
| Contêineres    | Docker e Docker Compose                      |
| Banco de dados | PostgreSQL 16 (Alpine)                       |
| Automação      | Scripts Bash                                 |
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

## Comandos principais

| Comando                                          | Descrição                                                                 |
| ------------------------------------------------ | ------------------------------------------------------------------------- |
| `scripts/up.sh [pasta]`                          | Sobe os serviços de `services.list` (ou só a pasta indicada) e espera ficarem *healthy* |
| `scripts/validate.sh`                            | Confere todo `compose.yaml` contra os padrões, sem subir nada             |
| `scripts/bootstrap.sh`                           | Cria as redes Docker da plataforma (idempotente)                          |
| `scripts/postgres-create-db.sh <nome> <arquivo>` | Cria banco e usuário próprios de um produto                               |
| `scripts/postgres-backup.sh [pasta] [dias]`      | Dump comprimido de todos os bancos, com retenção (padrão 7 dias)          |

## Estrutura do projeto

```
infra-vps/
├── platform/
│   └── postgres/          # compose.yaml e .env.example
├── scripts/               # up, bootstrap, validate, postgres-*
├── docs/
│   └── padroes.md         # nomes, redes, portas, recursos, segredos e dados
└── services.list          # o que sobe, em ordem
```

## Padrões

Contêineres `platform-<serviço>` e `<produto>-<serviço>-production`; rede `data` interna; portas internas fora do padrão em faixa observável (apps 4100–4129, dados 4130–4139); limites de CPU e memória em todo serviço; imagens sempre versionadas. Regras completas em [docs/padroes.md](docs/padroes.md).

## Como contribuir

Antes de criar um serviço, leia [docs/padroes.md](docs/padroes.md) e copie um serviço parecido. Todo serviço novo entra com um `compose.yaml` que passe em `scripts/validate.sh`, o `.env.example` com os nomes das variáveis (nunca valores reais) e uma linha em `services.list`. Ao abrir um pull request, informe como foi verificado.

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
