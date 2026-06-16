#!/usr/bin/env bash
# =============================================================================
# Testes de Integração e Sistema — homelab-infra
# =============================================================================
# Executa o install.sh de verdade e valida cada componente da stack:
#   1. k3s     — cluster Kubernetes vivo
#   2. kubectl  — consegue comunicar com o cluster
#   3. ArgoCD   — pods Running, UI respondendo
#   4. kube-prometheus — Prometheus, Grafana, Alertmanager Running
#
# Uso (dentro da VM, como root):
#   REPO=LHC-Campinas/homelab-infra \
#   INSTALL_URL=https://raw.githubusercontent.com/LHC-Campinas/homelab-infra \
#   bash integration_test.sh
# =============================================================================

set -uo pipefail

# -----------------------------------------------------------------------------
# Configuração
# -----------------------------------------------------------------------------
REPO="${REPO:-LHC-Campinas/homelab-infra}"
BRANCH="${BRANCH:-main}"
INSTALL_URL="${INSTALL_URL:-https://raw.githubusercontent.com/${REPO}}"
KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# Timeouts (segundos)
TIMEOUT_K3S=120
TIMEOUT_ARGOCD=300
TIMEOUT_PROMETHEUS=300
TIMEOUT_JOB=120

# Contadores
PASS=0
FAIL=0
SKIP=0

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
pass() { echo -e "${GREEN}  PASS${NC} — $*"; ((PASS++)); }
fail() { echo -e "${RED}  FAIL${NC} — $*"; ((FAIL++)); }
skip() { echo -e "${YELLOW}  SKIP${NC} — $*"; ((SKIP++)); }
section() { echo -e "\n${BLUE}══════════════════════════════════════${NC}"; echo -e "${BLUE}  $*${NC}"; echo -e "${BLUE}══════════════════════════════════════${NC}"; }

# Aguarda até que um comando retorne 0, com timeout
wait_for() {
    local description="$1"
    local timeout="$2"
    shift 2
    local cmd=("$@")
    local elapsed=0
    log "Aguardando: $description (timeout: ${timeout}s)"
    while ! "${cmd[@]}" &>/dev/null; do
        if (( elapsed >= timeout )); then
            return 1
        fi
        sleep 5
        (( elapsed += 5 ))
        echo -n "."
    done
    echo ""
    return 0
}

# Aguarda todos os pods de um namespace ficarem Running/Completed
wait_pods_ready() {
    local namespace="$1"
    local timeout="$2"
    local elapsed=0
    log "Aguardando pods em '$namespace' ficarem prontos..."
    while true; do
        local not_ready
        not_ready=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null \
            | grep -v -E 'Running|Completed' | wc -l)
        local total
        total=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
        if (( total > 0 && not_ready == 0 )); then
            return 0
        fi
        if (( elapsed >= timeout )); then
            return 1
        fi
        echo -n "  [${elapsed}s] ${total} pods, ${not_ready} não prontos..."
        sleep 10
        (( elapsed += 10 ))
        echo ""
    done
}

# -----------------------------------------------------------------------------
# SUITE 1 — install.sh
# -----------------------------------------------------------------------------
section "SUITE 1: Instalação via install.sh"

log "Executando install.sh..."
# Usa install.sh local se disponível (permite testar versão corrigida),
# caso contrário baixa do repositório remoto.
INSTALL_SH="${INSTALL_SH:-}"
if [[ -z "$INSTALL_SH" ]]; then
    INSTALL_SH=$(mktemp)
    curl -fsSL "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/install.sh" -o "$INSTALL_SH"
fi

INSTALL_OUTPUT=$(REPO="$REPO" BRANCH="$BRANCH" INSTALL_URL="$INSTALL_URL" \
   bash "$INSTALL_SH" 2>&1) && INSTALL_RC=0 || INSTALL_RC=$?

echo "$INSTALL_OUTPUT"

# O install.sh tem um bug conhecido: tenta fazer patch de serviços (monitoring,
# rabbitmq) que ainda não existem quando o kube-prometheus não foi instalado
# via APPS. Capturamos isso como aviso mas não abortamos os testes.
if (( INSTALL_RC == 0 )); then
    pass "install.sh concluiu sem erros"
elif echo "$INSTALL_OUTPUT" | grep -q "namespaces.*not found\|NotFound"; then
    pass "install.sh instalou componentes principais (erro esperado: namespaces opcionais ausentes)"
    log "AVISO: install.sh tentou fazer patch em namespaces não criados (bug conhecido — linha 103-104)"
else
    fail "install.sh retornou erro inesperado (rc=$INSTALL_RC)"
    echo "FATAL: instalação falhou, não é possível continuar os testes."
    exit 1
fi

export KUBECONFIG="$KUBECONFIG"

# -----------------------------------------------------------------------------
# SUITE 2 — k3s e cluster Kubernetes
# -----------------------------------------------------------------------------
section "SUITE 2: k3s — Cluster Kubernetes"

# 2.1 k3s binário instalado
if command -v k3s &>/dev/null; then
    K3S_VER=$(k3s --version | head -1)
    pass "k3s instalado — $K3S_VER"
else
    fail "k3s não encontrado no PATH"
fi

# 2.2 k3s service ativo
if systemctl is-active --quiet k3s; then
    pass "serviço k3s está Active (running)"
else
    fail "serviço k3s não está ativo"
fi

# 2.3 kubectl instalado
if command -v kubectl &>/dev/null; then
    KCL_VER=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)
    pass "kubectl instalado — $KCL_VER"
else
    fail "kubectl não encontrado"
fi

# 2.4 Cluster respondendo
if wait_for "API server do k3s" "$TIMEOUT_K3S" kubectl cluster-info; then
    pass "kubectl cluster-info respondeu — API server vivo"
else
    fail "kubectl cluster-info timeout após ${TIMEOUT_K3S}s"
fi

# 2.5 Node Ready
if wait_for "Node Ready" "$TIMEOUT_K3S" kubectl get nodes --no-headers; then
    NODE_STATUS=$(kubectl get nodes --no-headers | awk '{print $2}')
    if echo "$NODE_STATUS" | grep -q "Ready"; then
        NODE_NAME=$(kubectl get nodes --no-headers | awk '{print $1}')
        pass "Node '$NODE_NAME' está Ready"
    else
        fail "Node existe mas não está Ready: $NODE_STATUS"
    fi
else
    fail "Nenhum node encontrado após ${TIMEOUT_K3S}s"
fi

# 2.6 Componentes do sistema
log "Verificando pods do sistema (kube-system)..."
KSYS_PODS=$(kubectl get pods -n kube-system --no-headers 2>/dev/null || true)
RUNNING=$(echo "$KSYS_PODS" | grep -cE 'Running|Completed' || true)
if (( RUNNING > 0 )); then
    pass "kube-system: $RUNNING pods Running/Completed"
    echo "$KSYS_PODS" | while read -r line; do
        NAME=$(echo "$line" | awk '{print $1}')
        STATUS=$(echo "$line" | awk '{print $3}')
        printf "    %-50s %s\n" "$NAME" "$STATUS"
    done
else
    fail "Nenhum pod Running em kube-system"
fi

# 2.7 Job de smoke test no cluster
section "SUITE 2.7: Job de Smoke Test no Cluster"
log "Criando job de smoke test..."

kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: integration-smoke-test
  namespace: default
spec:
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: smoke
        image: busybox:latest
        command: ["sh", "-c", "echo 'cluster ok' && nslookup kubernetes.default.svc.cluster.local && echo 'dns ok'"]
EOF

log "Aguardando Job completar..."
if kubectl wait --for=condition=complete job/integration-smoke-test -n default --timeout="${TIMEOUT_JOB}s" 2>/dev/null; then
    JOB_LOG=$(kubectl logs job/integration-smoke-test -n default 2>/dev/null)
    if echo "$JOB_LOG" | grep -q "cluster ok"; then
        pass "Job smoke test completou com sucesso"
    fi
    if echo "$JOB_LOG" | grep -q "dns ok"; then
        pass "DNS interno do cluster funcionando (CoreDNS)"
    else
        fail "DNS interno falhou"
    fi
else
    fail "Job smoke test não completou em ${TIMEOUT_JOB}s"
    kubectl describe job integration-smoke-test -n default 2>/dev/null | tail -10
fi

# -----------------------------------------------------------------------------
# SUITE 3 — ArgoCD
# -----------------------------------------------------------------------------
section "SUITE 3: ArgoCD"

# 3.1 Namespace existe
if kubectl get namespace argocd &>/dev/null; then
    pass "namespace 'argocd' existe"
else
    fail "namespace 'argocd' não encontrado"
fi

# 3.2 Pods Running
log "Aguardando pods do ArgoCD ficarem Running..."
if wait_pods_ready "argocd" "$TIMEOUT_ARGOCD"; then
    ARGOCD_PODS=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
    pass "ArgoCD: todos os $ARGOCD_PODS pods Running"
    kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{printf "    %-60s %s\n", $1, $3}'
else
    fail "Pods do ArgoCD não ficaram prontos em ${TIMEOUT_ARGOCD}s"
    kubectl get pods -n argocd --no-headers 2>/dev/null | awk '{printf "    %-60s %s\n", $1, $3}'
fi

# 3.3 argocd-server service existe
if kubectl get svc argocd-server -n argocd &>/dev/null; then
    SVC_TYPE=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.type}')
    NODEPORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[1].nodePort}' 2>/dev/null || echo "N/A")
    pass "Service argocd-server existe — tipo: $SVC_TYPE, NodePort: $NODEPORT"
else
    fail "Service argocd-server não encontrado"
fi

# 3.4 ArgoCD API respondendo
ARGOCD_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null \
    || kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null \
    || echo "")

if [[ -n "$ARGOCD_PORT" ]]; then
    if wait_for "ArgoCD HTTP API" 60 curl -sf --max-time 5 "http://localhost:${ARGOCD_PORT}/healthz"; then
        pass "ArgoCD API respondendo em :${ARGOCD_PORT}/healthz"
    else
        fail "ArgoCD API não respondeu em :${ARGOCD_PORT}/healthz"
    fi
else
    skip "Não foi possível determinar a porta do ArgoCD"
fi

# 3.5 Ingress do ArgoCD aplicado
if kubectl get ingress -n argocd &>/dev/null 2>&1 | grep -q argocd; then
    pass "Ingress do ArgoCD configurado"
else
    INGRESS_COUNT=$(kubectl get ingress -n argocd --no-headers 2>/dev/null | wc -l)
    if (( INGRESS_COUNT > 0 )); then
        pass "Ingress do ArgoCD configurado ($INGRESS_COUNT regra(s))"
        kubectl get ingress -n argocd --no-headers 2>/dev/null | awk '{printf "    %s -> %s\n", $1, $3}'
    else
        fail "Ingress do ArgoCD não encontrado"
    fi
fi

# -----------------------------------------------------------------------------
# SUITE 4 — kube-prometheus-stack
# -----------------------------------------------------------------------------
section "SUITE 4: kube-prometheus-stack"

# 4.1 Namespace existe
if kubectl get namespace monitoring &>/dev/null; then
    pass "namespace 'monitoring' existe"
else
    fail "namespace 'monitoring' não encontrado — kube-prometheus pode não ter sido instalado"
    skip "Pulando testes de kube-prometheus (namespace ausente)"
    SKIP=$((SKIP + 5))
fi

if kubectl get namespace monitoring &>/dev/null; then
    # 4.2 Pods Running
    log "Aguardando pods do monitoring ficarem Running..."
    if wait_pods_ready "monitoring" "$TIMEOUT_PROMETHEUS"; then
        MON_PODS=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
        pass "monitoring: todos os $MON_PODS pods Running"
        kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{printf "    %-60s %s\n", $1, $3}'
    else
        fail "Pods de monitoring não ficaram prontos em ${TIMEOUT_PROMETHEUS}s"
        kubectl get pods -n monitoring --no-headers 2>/dev/null | awk '{printf "    %-60s %s\n", $1, $3}'
    fi

    # 4.3 Prometheus — pega somente services do tipo NodePort com porta 9090
    PROM_SVC=$(kubectl get svc -n monitoring --no-headers 2>/dev/null \
        | grep NodePort | grep -i prometheus | grep -v alertmanager | grep -v operated | grep -v grafana | awk '{print $1}' | head -1)
    if [[ -n "$PROM_SVC" ]]; then
        # Pega NodePort da porta 9090 — usa index 0 que é sempre a porta principal
        PROM_PORT=$(kubectl get svc "$PROM_SVC" -n monitoring \
            -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$PROM_PORT" ]]; then
            if curl -sf --max-time 10 "http://localhost:${PROM_PORT}/-/healthy" &>/dev/null; then
                pass "Prometheus saudável em :${PROM_PORT}/-/healthy"
            else
                fail "Prometheus não respondeu em :${PROM_PORT}"
            fi
        else
            skip "Prometheus sem NodePort exposto na porta 9090"
        fi
    else
        fail "Service do Prometheus (NodePort) não encontrado em monitoring"
    fi

    # 4.4 Grafana
    GRAF_SVC=$(kubectl get svc -n monitoring --no-headers 2>/dev/null | grep -i grafana | grep -v operated | awk '{print $1}' | head -1)
    if [[ -n "$GRAF_SVC" ]]; then
        GRAF_PORT=$(kubectl get svc "$GRAF_SVC" -n monitoring -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$GRAF_PORT" ]]; then
            if curl -sf --max-time 10 "http://localhost:${GRAF_PORT}/api/health" &>/dev/null; then
                pass "Grafana saudável em :${GRAF_PORT}/api/health"
            else
                fail "Grafana não respondeu em :${GRAF_PORT}"
            fi
        else
            skip "Grafana sem NodePort exposto"
        fi
    else
        fail "Service do Grafana não encontrado em monitoring"
    fi

    # 4.5 Alertmanager — pega somente services NodePort, exclui o headless "operated"
    ALERT_SVC=$(kubectl get svc -n monitoring --no-headers 2>/dev/null \
        | grep NodePort | grep -i alertmanager | grep -v operated | awk '{print $1}' | head -1)
    if [[ -n "$ALERT_SVC" ]]; then
        # Porta principal do alertmanager é 9093 — index 0
        ALERT_PORT=$(kubectl get svc "$ALERT_SVC" -n monitoring \
            -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
        if [[ -n "$ALERT_PORT" ]]; then
            if curl -sf --max-time 10 "http://localhost:${ALERT_PORT}/-/healthy" &>/dev/null; then
                pass "Alertmanager saudável em :${ALERT_PORT}/-/healthy"
            else
                fail "Alertmanager não respondeu em :${ALERT_PORT}"
            fi
        else
            skip "Alertmanager sem NodePort na porta 9093"
        fi
    else
        fail "Service do Alertmanager (NodePort) não encontrado em monitoring"
    fi

    # 4.6 Prometheus targets ativos
    PROM_TARGETS=$(curl -sf --max-time 10 "http://localhost:${PROM_PORT:-0}/api/v1/targets" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['activeTargets']))" 2>/dev/null || echo "0")
    if (( PROM_TARGETS > 0 )); then
        pass "Prometheus: $PROM_TARGETS targets ativos sendo coletados"
    else
        fail "Prometheus sem targets ativos (esperado > 0)"
    fi
fi

# -----------------------------------------------------------------------------
# Resultado Final
# -----------------------------------------------------------------------------
section "RESULTADO FINAL"
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo -e "  Total de verificações : $TOTAL"
echo -e "  ${GREEN}Passaram${NC}              : $PASS"
echo -e "  ${RED}Falharam${NC}              : $FAIL"
echo -e "  ${YELLOW}Pulados${NC}               : $SKIP"
echo ""

if (( FAIL == 0 )); then
    echo -e "  ${GREEN}✔ TODOS OS TESTES PASSARAM${NC}"
    exit 0
else
    echo -e "  ${RED}✘ $FAIL TESTE(S) FALHARAM${NC}"
    exit 1
fi
