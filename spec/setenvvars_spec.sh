# shellcheck shell=bash

Describe "set_env_vars" vars:default

  Include ./install_helper.sh
  
  It "sets default environment variables"    
    When call set_env_vars
      The variable REPO should eq "marcpires/infra-lhc"
      The variable BRANCH should eq "feat/35-install-defaults"
      The variable INSTALL_URL should include "install.sh"
      The variable ARGOCD_VERSION should eq "9.3.4"
      The variable RABBITMQ_OPERATOR_VERSION should eq "v2.19.0"
      The variable APPS should eq 'kube-prometheus'
    End
  End

Describe "setup_kubeconfig" vars:kubeconf
  Skip "kubeconfig"
  Include ./install_helper.sh
  It "should set copy k3s config file and set KUBECONFIG environment variable"
    When call setup_kubeconfig
    Path kubeconfig='/home/${USER_HOME}/k3s_config.yaml'
    The path kubeconfig should be file
  End
End
