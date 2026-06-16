#!/usr/bin/env bash
# Helper que expõe apenas a lógica de detecção do install.sh como funções isoladas.
# Usado pelos testes Python para validar o comportamento sem executar instalações reais.

# Recebe o caminho de um /etc/os-release falso via variável OS_RELEASE_FILE.
# Se não definido, usa o real.
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"

# ----------------------------------------------------------------------------
# detect_os
# Retorna "linux" ou "unknown" com base em uname -s
# ----------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Linux*) echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

# ----------------------------------------------------------------------------
# detect_arch
# Retorna "amd64" ou "unknown" com base em uname -m
# ----------------------------------------------------------------------------
detect_arch() {
    local arch_raw
    arch_raw=$(uname -m)
    case "$arch_raw" in
        x86_64) echo "amd64" ;;
        *)      echo "unknown" ;;
    esac
}

# ----------------------------------------------------------------------------
# detect_distro
# Retorna "debian-like" ou "unknown" com base em ID_LIKE no os-release
# ----------------------------------------------------------------------------
detect_distro() {
    local distro
    distro=$(grep -Po '^ID_LIKE=\K.*' "$OS_RELEASE_FILE" 2>/dev/null || echo "")
    case "$distro" in
        debian) echo "debian-like" ;;
        *)      echo "unknown" ;;
    esac
}

# ----------------------------------------------------------------------------
# validate_required_vars
# Verifica se REPO e INSTALL_URL estão definidos.
# Retorna 0 se válido, 1 se algum estiver ausente. Imprime mensagem de erro.
# ----------------------------------------------------------------------------
validate_required_vars() {
    if [[ -z "${REPO}" ]]; then
        echo "REPO de instalação não informado" >&2
        return 1
    fi
    if [[ -z "${INSTALL_URL}" ]]; then
        echo "URL de instalação não informada" >&2
        return 1
    fi
    return 0
}

# ----------------------------------------------------------------------------
# resolve_argocd_version
# Retorna a versão do ArgoCD: usa ARGOCD_VERSION se definida, senão o padrão.
# Nota: no install.sh original, a versão padrão é definida dentro de subshell
# com ( ARGOCD_VERSION="7.8.23" ), o que NÃO propaga para o shell pai. Esta
# função corrige esse comportamento.
# ----------------------------------------------------------------------------
DEFAULT_ARGOCD_VERSION="7.8.23"

resolve_argocd_version() {
    echo "${ARGOCD_VERSION:-$DEFAULT_ARGOCD_VERSION}"
}

# ----------------------------------------------------------------------------
# Ponto de entrada: executa a função passada como primeiro argumento
# Uso: bash mock_env.sh <nome_da_funcao> [args...]
# ----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    "$@"
fi
