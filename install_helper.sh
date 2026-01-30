#!/usr/bin/env bash

 detect_arch() {
    ARCH_RAW=$(uname -m)
    case "$ARCH_RAW" in
        x86_64) ARCH="amd64" ;;
        *) ARCH="unknown" ;;
    esac
    export ARCH
}

detect_os() {
    case "$(uname -s)" in
        Linux*) OS="linux" ;;
        *) OS="unknown" ;;
    esac
    export OS
}

detect_distro() {
    DISTRO=$(grep -Po '^ID_LIKE=\K.*' /etc/os-release)
    case "$DISTRO" in
        debian) DISTRO="debian-like" ;;
        *) DISTRO="unknown" ;;
    esac
    export DISTRO
}

set_env_vars() {
   [[ ${REPO} ]] || export REPO="marcpires/infra-lhc"
   [[ ${BRANCH} ]] || export BRANCH="feat/35-install-defaults"
   [[ ${INSTALL_URL} ]] || export INSTALL_URL="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/install.sh"
   [[ ${ARGOCD_VERSION} ]] || export ARGOCD_VERSION="9.3.4"
   [[ ${RABBITMQ_OPERATOR_VERSION} ]] || export RABBITMQ_OPERATOR_VERSION="v2.19.0"
   [[ ${APPS} ]] || export APPS=("kube-prometheus" "rabbitmq")
}

install_helm() {
    if ! command -v helm &> /dev/null; then
        if [ "$OS" == "linux" ]; then
            curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            command -v helm &> /dev/null || { echo "Helm não pode ser instalado"; exit 1; }
        else
            echo "Não consigo instalar helm neste sistema operacional"
            exit 1
        fi
    fi
}

install_k3s() {
    if ! command -v k3s &> /dev/null; then
        if [ "$OS" == "linux" ]; then
            curl -sfL https://get.k3s.io | sh -
            command -v k3s &> /dev/null || { echo "K3s não pode ser instalado"; exit 1; }
        else
            echo "Não consigo instalar k3s neste sistema operacional"
            exit 1
        fi
    fi
}

setup_kubeconfig() {
    DIRS_=$(ls -d /home/*)
    if [[ -d ${DIRS_} ]]; then
        echo "Copiando arquivo para o kubectl" 
      for DIR in "${DIRS_[@]}"; do
          sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/k3s-config.yaml
      done
   fi   
}

install_docker() {
    if ! docker run --rm hello-world &> /dev/null; then
        if [ "$OS" == "linux" ]; then
            if [ "$DISTRO" == "debian-like" ]; then
                apt-get update
                apt-get install -y ca-certificates curl
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                chmod a+r /etc/apt/keyrings/docker.asc
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
                    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
                    | tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                docker run --rm hello-world &> /dev/null || { echo "Docker não pode ser instalado"; exit 1; }
            fi
        else
            echo "Não consigo instalar docker neste sistema operacional"
            exit 1
        fi
    fi
}

verify_kubectl() {
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/${OS}/${ARCH}/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
}

install_kubectl() {
    if ! command -v kubectl &> /dev/null; then
      echo "Instalando kubectl para ${ARCH}"
      if [ "${OS}" == "linux" ]; then
           curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
           chmod +x kubectl
           sudo mv kubectl /usr/local/bin/
           command -v kubectl &> /dev/null || ( echo "Kubectl não pode ser instalado" ; exit 1 )
       else
           echo "Não consigo instalar kubectl neste sistema operacional"
           exit 1
       fi
    fi
}

add_argocd_helm_repo() {
    helm repo add argo https://argoproj.github.io/argo-helm
}

update_argocd_helm_repo() {
    helm repo update
}

deploy_argocd() {
    helm upgrade --install argocd argo/argo-cd --version "${ARGOCD_VERSION}" -n argocd --create-namespace --set server.extraArgs=\{--insecure\}
    kubectl apply -f "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/apps/argo/ingress.yaml"
}

install_apps() {
    if [[ ${APPS} ]]; then
        for APP in "${APPS[@]}"; do
          kubectl apply -f "https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/apps/${APP}/app.yaml"
        done
    fi
}

patch_services() {
  echo "Realizando o ajuste dos serviços para acesso via ip e porta"
  kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
}
