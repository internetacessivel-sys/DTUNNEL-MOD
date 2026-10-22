#!/usr/bin/env bash
# Instalador do DTProto Server com bypass de token (binario ja patchado).
#
# uso:
#   ./install.sh [--port 443] [--plain-port 80 | --no-plain]
#                [--ssh-port 22] [--subnet 10.10.0.0/16] [--tun tun0]
#                [--loglevel info] [--no-sysctl]
set -euo pipefail

PORT=443
PLAIN_PORT=80
SSH_PORT=22
SUBNET="10.10.0.0/16"
TUN="tun0"
LOGLEVEL="info"
SYSCTL=1

usage() {
  cat <<'EOF'
uso: ./install.sh [opcoes]
  --port 443          porta TLS (padrao: 443)
  --plain-port 80     porta sem TLS (padrao: 80)
  --no-plain          nao abre listener sem TLS (recomendado)
  --ssh-port 22       SSH local de destino (padrao: 22)
  --subnet CIDR       subnet virtual (padrao: 10.10.0.0/16)
  --tun NOME          interface tun (padrao: tun0)
  --loglevel LEVEL    info|debug (padrao: info)
  --no-sysctl         nao altera sysctl
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --port)       PORT="$2"; shift 2 ;;
    --plain-port) PLAIN_PORT="$2"; shift 2 ;;
    --no-plain)   PLAIN_PORT=""; shift ;;
    --ssh-port)   SSH_PORT="$2"; shift 2 ;;
    --subnet)     SUBNET="$2"; shift 2 ;;
    --tun)        TUN="$2"; shift 2 ;;
    --loglevel)   LOGLEVEL="$2"; shift 2 ;;
    --no-sysctl)  SYSCTL=0; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "opcao invalida: $1"; usage; exit 1 ;;
  esac
done

[ "$(id -u)" = 0 ] || { echo "ERRO: rode como root"; exit 1; }
cd "$(dirname "$0")"
[ -f proto-server ] || { echo "ERRO: binario proto-server nao encontrado"; exit 1; }

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo "AVISO: o binario incluido e linux-amd64; esta maquina e $ARCH."
  echo "       Baixe o release oficial da sua arch e rode:"
  echo "       python3 patch_token_bypass.py <binario>"
fi

echo "[1/6] dependencias"
if command -v apt-get >/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libpam0g jq curl iproute2 iptables >/dev/null
elif command -v dnf >/dev/null; then
  dnf install -y -q pam jq curl iproute iptables >/dev/null
elif command -v yum >/dev/null; then
  yum install -y -q pam jq curl iproute iptables >/dev/null
fi

echo "[2/6] parando instancia anterior"
if systemctl is-active --quiet proto-server 2>/dev/null; then
  timeout 15 systemctl stop proto-server 2>/dev/null || systemctl kill -s KILL proto-server 2>/dev/null || true
  sleep 1
fi

echo "[3/6] binario"
install -m 0755 proto-server /usr/local/bin/proto-server
python3 ./patch_token_bypass.py /usr/local/bin/proto-server --check >/dev/null || {
  echo "ERRO: binario sem o bypass de token"; exit 1; }

echo "[4/6] configuracao"
mkdir -p /etc/proto-server
LISTEN="$(printf '    { "host": "0.0.0.0", "port": %s, "ssl": true }' "$PORT")"
if [ -n "$PLAIN_PORT" ]; then
  LISTEN="$LISTEN,$(printf '\n    { "host": "0.0.0.0", "port": %s, "ssl": false }' "$PLAIN_PORT")"
fi
cat > /etc/proto-server/config.json <<EOF
{
  "server": {
    "virtual_subnet_cidr": "$SUBNET",
    "stats_file": "/etc/proto-server/stats.json",
    "auth": { "system": true },
    "tun": { "name": "$TUN", "buffer_size": 65536 }
  },
  "proxy": {
    "enabled": true,
    "listen": [
$LISTEN
    ]
  }
}
EOF

echo "[5/6] systemd"
cat > /etc/systemd/system/proto-server.service <<EOF
[Unit]
Description=DTProto Server (patched)
After=network.target

[Service]
Type=simple
TimeoutStopSec=10
ExecStart=/usr/local/bin/proto-server --log-level $LOGLEVEL --config /etc/proto-server/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

if [ "$SYSCTL" = 1 ]; then
  cat > /etc/sysctl.d/99-dtproto.conf <<'EOF'
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 33554432
net.core.wmem_default = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432
net.core.netdev_max_backlog = 100000
net.ipv4.tcp_fastopen = 3
EOF
  sysctl --system >/dev/null 2>&1 || true
fi

systemctl daemon-reload
systemctl enable proto-server >/dev/null 2>&1
systemctl restart proto-server || true
sleep 3

echo "[6/6] status"
systemctl is-active proto-server || true
ss -ltn | grep -E ":($PORT|${PLAIN_PORT:-$PORT})\b" || true
echo
echo "OK. Configure no app/painel:"
echo "  host: $(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || echo SEU_IP)"
echo "  porta: $PORT (TLS)   ssh: $SSH_PORT   usuario: usuario do sistema (PAM)"
echo "  payload: GET / HTTP/1.1[lf]Host: [host][lf]Upgrade: websocket[lf][lf]"
echo
echo "ATENCAO: nao exponha a porta plaintext ($PLAIN_PORT) para a internet."
echo "Conexoes sem connector vazam buffer e travam o accept do servidor."
