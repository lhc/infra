# shellcheck shell=bash

Describe "Cluster install:" cluster:default
  Include ./install_helper.sh
  setup() {
    set_env_vars
    detect_os
    detect_arch
    detect_distro
  }
  
  BeforeEach 'setup'
 
  Describe "kubectl:" cluster:deps:kubectl
    It "should be installed at /usr/local/bin"
      When call install_kubectl
      Path kubectl='/usr/local/bin/kubectl'
      The output should not include "Não consigo instalar kubectl"
      The path kubectl should be file
      The path kubectl should be executable
    End
  End

 Describe "helm:" cluster:deps:helm
   It "should be installed successfuly"
     When call install_helm
       Path helm='/usr/local/bin/helm'
       The status should be success
       The path helm should be file
       The path helm should be executable
    End
  End
  
 Describe "docker:" cluster:deps:docker
   It "should be installed successfuly"
     When call install_docker
       Path docker='/usr/bin/docker'
       The output should not include "Docker não pode ser instalado"
       The status should be success
       The path docker should be file
       The path docker should be executable
     End
   End

 Describe "k3s:" cluster:k3s
   It "should be installed successfuly"
     When call install_k3s
       The status should be success
       The output should include "Starting k3s"
       The stderr should include "Created symlink"
   End
   It "should have the cluster up and running" cluster:k3s:running
     When run command sudo systemctl status k3s
       The status should be success
       The output should include "active (running)"
   End
   It "should copy kubectl config and set KUBECONFIG variable" cluster:k3s:conf
     When call setup_kubeconfig
       The variable KUBECONFIG should be present
       The variable KUBECONFIG should be exported
    End
 End
 
 Describe "ArgoCD:" cluster:argocd:repo:add
  It "should have added argocd helm repository"
     When call add_argocd_helm_repo
     The status should be success
     The output should include "\"argo\" has been added to your repositories"
  End
 End

 Describe "ArgoCD Helm update repo:" cluster:argocd:repo:update
   It "should have update argocd helm repository"
     When call update_argocd_helm_repo
      The status should be success
      The output should include "got an update from the \"argo\" chart repository"
   End
 End

 Describe "ArgoCD:" cluster:argocd:deploy
   It "should be deployed successfuly"
     When call deploy_argocd
     The status should be success
     The output should include "NAME: argocd"
     The output should include "STATUS: deployed"
   End
 End

 Describe "Stacks installation:" cluster:argocd:stacks
   It "should have deployed ${APP} stacks"
     When call install_apps
     The status should be success
     #Temp
     The output should include "unchanged"
    End
  End

  Describe "${APPS} status:" cluster:argocd:stacks:status
    It "should have ${APPS} healthy"
     When run kubectl get application -n argocd
     The status should be success
     The output should include "${APPS} Synced Healthy"
   End
 End

  Describe "Stacks "

  Describe "Rabbitmq:" cluster:rabbitmq-operator:stacks
    It "should have deployed the operator successfully"
      When run kubectl get deployment.apps/rabbitmq-cluster-operator -n rabbitmq-system -o json
      The output should include "\"kind\": \"Deployment\""
      The output should include "\"app.kubernetes.io/component\": \"rabbitmq-operator\""
       The output should include "\"availableReplicas\": 1"
    End
  End

  Describe "Rabbitmq:" cluster:rabbitmq:stacks
    It "should have deployed the instance successfully"
      When run kubectl get all -n rabbitmq -o json
      The output should include "\"kind\": \"RabbitmqCluster\""
      The output should include "\"availableReplicas\": 1"
    End
  End

  Describe "Patch services:" cluster:services:patch
    It "must set service type as \"NodePort\""
      When run patch_services
      The status should be success
      The output should include "service/argocd-server patched"
    End
  End

  Describe "Service type:" cluster:services:type
    It "should have set argocd-server spec.type as \"NodePort\""
      When run kubectl get service argocd-server -n argocd -o json
      The output should include "\"type\": \"NodePort\""
    End

    It "should have set kube-prometheus-grafana spec.type as \"NodePort\""
      When run kubectl get service kube-prometheus-grafana -n monitoring -o json
      The output should include "\"type\": \"NodePort\""
    End
  End

End
