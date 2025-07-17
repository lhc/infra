#!/usr/bin/env bash
# Aborta a execução em caso algum comando termine com o status diferente de zero
set -e

# Executar como root
if [ "$(id -u)" -ne 0 ]; then
    ( echo "Execute com sudo ou como root" ; exit 1 )
fi

[[ ${REPO} ]] || ( echo "REPO de instalação não informado" ; exit 1 )
[[ ${BRANCH} ]] || export BRANCH=main
[[ ${INSTALL_URL} ]] || ( echo "URL de instalação não informada" ; exit 1 )
[[ ${ARGOCD_VERSION} ]] || ( ARGOCD_VERSION="7.8.23" )

# Identifica o sistema operacional em uso
case "$(uname -s)" in
    Linux*) OS="linux" ;;
    *) OS="unknown" ;;
esac

# Identifica a arquitetura em uso
ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
    x86_64) ARCH="amd64" ;;
    *) ARCH="unknown" ;;
esac

# Identifica a distribuição em uso
DISTRO=$(grep -Po '^ID_LIKE=\K.*' /etc/os-release)
case "$DISTRO" in
    debian) DISTRO="debian-like" ;;
    *) DISTRO="unknown" ;;
esac

# Identifica a necessidade de instalar o kubectl
command -v kubectl &> /dev/null || \
( if [ "$OS" == "linux" ]; then
  curl -sLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
  command -v kubectl &> /dev/null || ( echo "Kubectl não pode ser instalado" ; exit 1 )
else
	echo "Não consigo instalar kubectl neste sistema operacional"
	exit 1
fi )

# Identifica a necessidade de instalar o docker
docker run --rm hello-world &> /dev/null || (\
if [ "$OS" == "linux" ]; then
		if [ "$DISTRO" == "debian-like" ]; then
    apt-get update
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  	docker run --rm hello-world &> /dev/null || ( echo "Docker não pode ser instalado" ; exit 1 )
  fi
else
	echo "Não consigo instalar docker neste sistema operacional"
	exit 1
fi )

# Identifica a necessidade de instalar o k3s
command -v k3s &> /dev/null || (\
if [ "$OS" == "linux" ]; then
	curl -sfL https://get.k3s.io | sh -
	command -v k3s &> /dev/null || ( echo "K3s não pode ser instalado" ; exit 1 )
else
	echo "Não consigo instalar k3s neste sistema operacional"
	exit 1
fi )

# Identifica a necessidade de instalar o helm
command -v helm &> /dev/null || (\
if [ "$OS" == "linux" ]; then
	curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
	command -v helm &> /dev/null || ( echo "Helm não pode ser instalado" ; exit 1 )
else
	echo "Não consigo instalar helm neste sistema operacional"
	exit 1
fi )

# Template RabbitMQ

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd --version ${ARGOCD_VERSION} -n argocd --create-namespace --set server.extraArgs={--insecure}

kubectl apply -f https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/apps/argo/ingress.yaml

if [[ ${APPS} ]]; then
	for APP in $APPS; do
		kubectl apply -f https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/apps/${APP}/app.yaml -n argocd
	done
fi

kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
kubectl patch svc kube-prometheus-grafana -n monitoring -p '{"spec": {"type": "NodePort"}}'

echo "\nK3S Node IP\n"
kubectl get node -o wide | awk -v OFS='\t\t' '{print $1, $6}'

echo "Portas dos serviços\n" 
export ALERT_MANAGER_PORT=$(kubectl get svc/kube-prometheus-kube-prome-alertmanager -o jsonpath="{range .spec.ports[*]} {.name} {.nodePort}" -n monitoring)
export ARGOCD_PORT=$(kubectl get svc/argocd-server -o jsonpath="{.spec.ports[1].name} {.spec.ports[1].nodePort}" -n argocd)
export GRAFANA_PORT=$(kubectl get svc/kube-prometheus-grafana -o jsonpath="{.spec.ports[0].name} {.spec.ports[0].nodePort}" -n monitoring)
export PROMETHEUS_PORT=$(kubectl get svc/kube-prometheus-kube-prome-prometheus -o jsonpath="{range .spec.ports[*]} {.name} {.nodePort}" -n monitoring)
export RABBITMQ_PORT=$(kubectl get svc/rabbitmq -o jsonpath="{range .spec.ports[*]} {.name} {.nodePort}" -n rabbitmq)
echo "ArgoCD: ${ARGOCD_PORT}\nGrafana: ${GRAFANA_PORT}\nPrometheus: ${PROMETHEUS_PORT}\nAlert Manager: ${ALERT_MANAGER_PORT}\nRabbitMQ: ${RABBITMQ_PORT}\n"

echo "Utilize o ip do k3s e as portas para acessar os serviços do homelab"