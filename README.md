# DTunnel — Servidor próprio + App modificado

Roda o **DTunnel** com backend próprio: um servidor gRPC que serve as
configurações/ conexões para o app, um **painel web** para editar tudo pelo
navegador, e o **app modificado** apontando para esse servidor.

```
                    ┌──────────────────────────────┐
   celular ────────▶│  app DTunnel (mod)           │
   (Android)        │  fala gRPC/TLS               │
                    └──────────────┬───────────────┘
                                    │  porta 8443
                                   ▼
                    ┌──────────────────────────────┐
                    │  servidor Node.js            │
                    │  ├─ ConfigService            │
                    │  ├─ AppConfigService         │
                    │  ├─ TextService              │
                    │  └─ DeviceService            │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │  painel web (8080)            │
                    │  edita data/*.json             │
                    └──────────────────────────────┘
```

**1. No servidor** — Subir o backend (gera CA, certificado e chave de assinatura):

Envie o arquivo **dtunnel-server.tar.gz** para alguma pasta no servidor. Feito isso, podemos prosseguir:

> Descompactar o arquivo: `tar xzf dtunnel-server.tar.gz && cd dtunnel-server`
> Executar o instalador: `./install.sh SEU_IP 8443 8080 SENHA_PAINEL`

Se tudo ocorrer bem, o painel estará acessível no navegador em `http://SEU_IP:8080`. O usuário padrão é **panel** e a senha é a que você definiu no comando de instalação!

---

**2. No seu PC** — Instalar dependências e compilar o APK:

Na pasta onde **está** o arquivo **dtunnel-mod.tar.gz**, clique com o botão direito do mouse, abra o terminal e rode os comandos:

> Descompactar o arquivo: `tar xzf dtunnel-mod.tar.gz && cd dtunnel-mod`
> Dar permissões: `chmod +x *`
> Instalar dependências: `./install_deps.sh`
> Baixar os certificados do servidor: `./sync_keys.sh SEU_IP root`
> Compilar o APP: `./make_mod.sh SEU_IP 8443`
