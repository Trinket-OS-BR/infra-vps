# infra-vps

Infraestrutura da VPS Hostinger (somente produção), montada serviço a serviço e padronizada. Rascunho anterior (proxy, Trinketos, bancos, Offer): `..\infra-vps-rascunho`, só consulta.

Estado: **Postgres**. Próximo: Offer; depois o proxy e os demais serviços, um por vez.

```
infra-vps/
├── platform/postgres/   # compose.yaml + .env.example
├── services.list        # o que sobe, em ordem
├── scripts/             # up, bootstrap, postgres-up, postgres-create-db, postgres-backup, validate
└── docs/padroes.md      # nomes, redes, portas, recursos, segredos, dados
```

## Fluxo: receita no Git, VPS só clona

```bash
# 1. uma vez, na VPS (repositório privado: chave de deploy somente leitura)
ssh-keygen -t ed25519 -f ~/.ssh/infra_vps_deploy -N "" && cat ~/.ssh/infra_vps_deploy.pub
#    cole a chave pública em GitHub > Trinket-OS-BR/infra-vps > Settings > Deploy keys (sem escrita)
sudo mkdir -p /srv && sudo chown deploy:deploy /srv
GIT_SSH_COMMAND="ssh -i ~/.ssh/infra_vps_deploy -o IdentitiesOnly=yes" git clone git@github.com:Trinket-OS-BR/infra-vps.git /srv/infra-vps

# 2. uma vez: segredos (ficam só na VPS, fora do Git)
cd /srv/infra-vps && git config core.sshCommand "ssh -i ~/.ssh/infra_vps_deploy -o IdentitiesOnly=yes"
cp platform/postgres/.env.example platform/postgres/.env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" platform/postgres/.env

# 3. subir tudo o que está em services.list
scripts/validate.sh && scripts/up.sh
scripts/postgres-create-db.sh offer /srv/secrets/offer-db.env

# depois, a cada mudança na receita
git pull && scripts/up.sh
```

## Estado de verificação

Nada foi executado em Docker real ainda (daemon local parado); `validate.sh` roda na VPS.
