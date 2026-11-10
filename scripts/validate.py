#!/usr/bin/env python3
"""Confere cada serviço de cada compose.yaml contra docs/padroes.md, sem subir nada.

Chamado por scripts/validate.sh. Usa `docker compose config` (não precisa do daemon) e olha
serviço por serviço: um arquivo com dois serviços não passa só porque um deles está certo.
Serviço com `profiles:` é tarefa manual (ex.: migração): não exige restart nem healthcheck.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARCA_HEALTH = "# healthcheck: definido no Dockerfile"
FAIXA_APP = range(4100, 4130)
FAIXA_PLATAFORMA = range(4130, 4150)


def compose_config(pasta):
    env = dict(os.environ, IMAGE_TAG="validate", IMAGE_OWNER="validate")
    cmd = ["docker", "compose", "--profile", "*", "config", "--no-env-resolution", "--format", "json"]
    try:
        r = subprocess.run(cmd, cwd=pasta, env=env, capture_output=True, text=True, encoding="utf-8")
    except FileNotFoundError:
        return None, "docker não encontrado"
    if r.returncode != 0:
        linhas = (r.stderr or "").strip().splitlines()
        return None, "docker compose config falhou: " + (linhas[-1] if linhas else "sem mensagem")
    return json.loads(r.stdout), None


def tag_da_imagem(imagem):
    if "@sha256:" in imagem:
        return "digest"
    ultimo = imagem.rsplit("/", 1)[-1]
    return ultimo.split(":", 1)[1] if ":" in ultimo else ""


def confere_servico(svc, cfg, plataforma, produto, servico, principal, bruto):
    p = []
    nome = cfg.get("container_name", "")
    if not nome:
        p.append("sem container_name")
    elif plataforma:
        if not re.fullmatch(r"platform-[a-z0-9-]+", nome):
            p.append(f"container_name '{nome}' fora do padrão platform-<serviço>")
    elif principal and nome != f"{produto}-{servico}-production":
        p.append(f"container_name '{nome}' deveria ser '{produto}-{servico}-production'")
    elif not principal and not nome.startswith(f"{produto}-{servico}-"):
        p.append(f"container_name '{nome}' deveria começar com '{produto}-{servico}-'")

    if principal:
        if cfg.get("restart") != "unless-stopped":
            p.append("sem restart: unless-stopped")
        if not cfg.get("healthcheck") and MARCA_HEALTH not in bruto:
            p.append("sem healthcheck")
    if cfg.get("init") is not True:
        p.append("sem init: true")
    for campo in ("mem_limit", "cpus", "pids_limit"):
        if not cfg.get(campo):
            p.append(f"sem {campo}")
    if "no-new-privileges:true" not in (cfg.get("security_opt") or []):
        p.append("sem no-new-privileges")
    log = cfg.get("logging") or {}
    opcoes = log.get("options") or {}
    if log.get("driver") != "json-file" or "max-size" not in opcoes or "max-file" not in opcoes:
        p.append("sem rotação de logs (json-file com max-size e max-file)")

    rotulos = cfg.get("labels") or {}
    for r in ("app.product", "app.service", "app.environment"):
        if not rotulos.get(r):
            p.append(f"sem rótulo {r}")
    esperado = "platform" if plataforma else produto
    if rotulos.get("app.product") and rotulos["app.product"] != esperado:
        p.append(f"rótulo app.product '{rotulos['app.product']}' deveria ser '{esperado}'")
    if rotulos.get("app.environment") and rotulos["app.environment"] != "production":
        p.append("rótulo app.environment deveria ser 'production'")

    if not plataforma and "ALL" not in (cfg.get("cap_drop") or []):
        p.append("app sem cap_drop: [ALL]")

    tag = tag_da_imagem(cfg.get("image", ""))
    if not tag:
        p.append("imagem sem versão")
    elif tag == "latest":
        p.append("usa :latest")

    if cfg.get("ports") and not (plataforma and servico == "proxy"):
        p.append("publica porta no host")
    return [f"[{svc}] {x}" for x in p]


def main():
    os.chdir(ROOT)
    sys.stdout.reconfigure(encoding="utf-8")
    padroes = (ROOT / "docs/padroes.md").read_text(encoding="utf-8")
    diagrama = (ROOT / "docs/diagrama.md").read_text(encoding="utf-8")
    arquivos = sorted(list(Path("platform").rglob("compose.yaml")) + list(Path("apps").rglob("compose.yaml")))
    falhou = False
    portas = {}  # porta -> arquivo que a declarou primeiro

    for arq in arquivos:
        rel = arq.as_posix()
        partes = arq.parts
        problemas, avisos = [], []
        plataforma = partes[0] == "platform"
        if plataforma and len(partes) == 3:
            produto, servico = "platform", partes[1]
        elif not plataforma and len(partes) == 5 and partes[2] == "production":
            produto, servico = partes[1], partes[3]
        else:
            print(f"FALHA  {rel}\n         - pasta fora do padrão (platform/<serviço>/ ou apps/<produto>/production/<serviço>/)")
            falhou = True
            continue

        bruto = arq.read_text(encoding="utf-8")
        if re.search(r":-(admin|password|senha)", bruto):
            problemas.append("senha padrão no compose")
        if plataforma and not re.search(rf"\b{re.escape(servico)}\b", diagrama, re.I):
            problemas.append(f'serviço "{servico}" não consta em docs/diagrama.md')

        cfg, erro = compose_config(arq.parent)
        if erro:
            problemas.append(erro)
        else:
            esperado = f"platform-{servico}" if plataforma else f"{produto}-{servico}-production"
            if cfg.get("name") != esperado:
                problemas.append(f"name: '{cfg.get('name')}' deveria ser '{esperado}'")
            servicos = cfg.get("services") or {}
            if not any(not s.get("profiles") for s in servicos.values()):
                problemas.append("nenhum serviço sem profiles (nada sobe com up.sh)")
            for svc, s in servicos.items():
                principal = not s.get("profiles")
                problemas += confere_servico(svc, s, plataforma, produto, servico, principal, bruto)
                for porta in s.get("expose") or []:
                    n = int(str(porta).split("/")[0])
                    faixa = FAIXA_PLATAFORMA if plataforma else FAIXA_APP
                    if n not in faixa:
                        problemas.append(f"[{svc}] porta {n} fora da faixa {faixa.start}-{faixa.stop - 1}")
                    if not re.search(rf"\b{n}\b", padroes):
                        problemas.append(f"[{svc}] porta {n} não registrada em docs/padroes.md")
                    if n in portas and portas[n] != rel:
                        problemas.append(f"[{svc}] porta {n} já usada em {portas[n]}")
                    portas.setdefault(n, rel)
            # Só aviso: dar nome a um volume que já existe cria um volume novo e vazio. Migre antes de corrigir.
            for chave, vol in (cfg.get("volumes") or {}).items():
                if not vol.get("external") and vol.get("name") != chave:
                    avisos.append(f"volume '{chave}' sem name: explícito (hoje vira '{vol.get('name')}')")

        if problemas:
            falhou = True
            print(f"FALHA  {rel}")
            for x in problemas:
                print(f"         - {x}")
        else:
            print(f"OK     {rel}")
        for x in avisos:
            print(f"         aviso: {x}")

    # services.list só pode apontar para pastas que existem; receita fora da lista é só aviso.
    ativos = [l.strip() for l in (ROOT / "services.list").read_text(encoding="utf-8").splitlines()
              if l.strip() and not l.strip().startswith("#")]
    for pasta in ativos:
        if not (ROOT / pasta / "compose.yaml").is_file():
            falhou = True
            print(f"FALHA  services.list\n         - '{pasta}' não tem compose.yaml")
    for arq in arquivos:
        if arq.parent.as_posix() not in ativos:
            print(f"         aviso: {arq.parent.as_posix()} não está em services.list (não sobe com up.sh)")

    return 1 if falhou else 0


if __name__ == "__main__":
    sys.exit(main())
