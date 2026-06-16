"""
Testes unitários para install.sh

Estratégia:
- Cada função de detecção do install.sh é isolada em tests/helpers/mock_env.sh
- Os testes invocam essas funções via subprocess, mockando o PATH para substituir
  binários reais (uname) por versões falsas que retornam valores controlados.
- Arquivos temporários simulam /etc/os-release para testar detecção de distro.
- Variáveis de ambiente simulam entradas do usuário (REPO, INSTALL_URL, etc).

Casos cobertos:
    detect_os:
        - Linux    -> "linux"
        - Darwin   -> "unknown"
    detect_arch:
        - x86_64   -> "amd64"
        - aarch64  -> "unknown"
        - armv7l   -> "unknown"
    detect_distro:
        - ID_LIKE=debian -> "debian-like"
        - ID_LIKE=rhel   -> "unknown"
        - sem ID_LIKE    -> "unknown"
    validate_required_vars:
        - sem REPO         -> exit 1 + mensagem de erro
        - sem INSTALL_URL  -> exit 1 + mensagem de erro
        - ambos presentes  -> exit 0
    resolve_argocd_version:
        - sem ARGOCD_VERSION -> versão padrão "7.8.23"
        - com ARGOCD_VERSION -> versão informada
        - (documenta o bug do install.sh original com subshell)
"""

import os
import stat
import subprocess
import tempfile
import unittest

HELPERS_DIR = os.path.join(os.path.dirname(__file__), "helpers")
MOCK_ENV = os.path.join(HELPERS_DIR, "mock_env.sh")


def run_function(func_name, env_override=None, os_release_content=None):
    """
    Executa uma função do mock_env.sh e retorna (stdout, stderr, returncode).

    Args:
        func_name: Nome da função a chamar (ex: "detect_os").
        env_override: Dict com variáveis de ambiente extras/substituições.
        os_release_content: Conteúdo a ser usado como /etc/os-release falso.
                            Se None, usa o arquivo real do sistema.
    """
    env = os.environ.copy()

    # Limpa variáveis que poderiam vazar do ambiente real e afetar os testes
    for var in ("REPO", "INSTALL_URL", "ARGOCD_VERSION", "BRANCH", "APPS"):
        env.pop(var, None)

    if env_override:
        env.update(env_override)

    if os_release_content is not None:
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".os-release", delete=False
        ) as f:
            f.write(os_release_content)
            env["OS_RELEASE_FILE"] = f.name

    try:
        result = subprocess.run(
            ["bash", MOCK_ENV, func_name],
            capture_output=True,
            text=True,
            env=env,
        )
    finally:
        if os_release_content is not None:
            os.unlink(env["OS_RELEASE_FILE"])

    return result.stdout.strip(), result.stderr.strip(), result.returncode


def make_fake_uname(uname_s=None, uname_m=None):
    """
    Cria um diretório temporário com um binário falso de 'uname' que retorna
    os valores especificados. Retorna o caminho do diretório para uso no PATH.

    Args:
        uname_s: Valor retornado por 'uname -s' (ex: "Linux", "Darwin").
        uname_m: Valor retornado por 'uname -m' (ex: "x86_64", "aarch64").
    """
    tmpdir = tempfile.mkdtemp()
    uname_path = os.path.join(tmpdir, "uname")

    # Constrói o script fake de uname
    script_lines = ["#!/usr/bin/env bash"]
    if uname_s is not None:
        script_lines.append(f'if [[ "$1" == "-s" ]]; then echo "{uname_s}"; exit 0; fi')
    if uname_m is not None:
        script_lines.append(f'if [[ "$1" == "-m" ]]; then echo "{uname_m}"; exit 0; fi')
    # Fallback: chama o uname real para qualquer outro argumento
    script_lines.append('exec /usr/bin/uname "$@"')

    with open(uname_path, "w") as f:
        f.write("\n".join(script_lines) + "\n")

    os.chmod(uname_path, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    return tmpdir


class TestDetectOS(unittest.TestCase):
    """Testes para a função detect_os do mock_env.sh"""

    def test_linux_retorna_linux(self):
        """uname -s == 'Linux' deve resultar em OS='linux'"""
        fake_dir = make_fake_uname(uname_s="Linux")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_os", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "linux")
        finally:
            import shutil
            shutil.rmtree(fake_dir)

    def test_darwin_retorna_unknown(self):
        """uname -s == 'Darwin' deve resultar em OS='unknown'"""
        fake_dir = make_fake_uname(uname_s="Darwin")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_os", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "unknown")
        finally:
            import shutil
            shutil.rmtree(fake_dir)

    def test_windows_retorna_unknown(self):
        """uname -s == 'MINGW64_NT' (Git Bash no Windows) deve resultar em OS='unknown'"""
        fake_dir = make_fake_uname(uname_s="MINGW64_NT")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_os", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "unknown")
        finally:
            import shutil
            shutil.rmtree(fake_dir)


class TestDetectArch(unittest.TestCase):
    """Testes para a função detect_arch do mock_env.sh"""

    def test_x86_64_retorna_amd64(self):
        """uname -m == 'x86_64' deve resultar em ARCH='amd64'"""
        fake_dir = make_fake_uname(uname_m="x86_64")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_arch", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "amd64")
        finally:
            import shutil
            shutil.rmtree(fake_dir)

    def test_aarch64_retorna_unknown(self):
        """uname -m == 'aarch64' (ARM64) deve resultar em ARCH='unknown'"""
        fake_dir = make_fake_uname(uname_m="aarch64")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_arch", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "unknown")
        finally:
            import shutil
            shutil.rmtree(fake_dir)

    def test_armv7l_retorna_unknown(self):
        """uname -m == 'armv7l' (Raspberry Pi 32-bit) deve resultar em ARCH='unknown'"""
        fake_dir = make_fake_uname(uname_m="armv7l")
        try:
            env = {"PATH": f"{fake_dir}:{os.environ['PATH']}"}
            stdout, _, returncode = run_function("detect_arch", env_override=env)
            self.assertEqual(returncode, 0)
            self.assertEqual(stdout, "unknown")
        finally:
            import shutil
            shutil.rmtree(fake_dir)


class TestDetectDistro(unittest.TestCase):
    """Testes para a função detect_distro do mock_env.sh"""

    def test_debian_retorna_debian_like(self):
        """ID_LIKE=debian deve resultar em DISTRO='debian-like'"""
        os_release = "ID=ubuntu\nID_LIKE=debian\nVERSION_CODENAME=jammy\n"
        stdout, _, returncode = run_function("detect_distro", os_release_content=os_release)
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "debian-like")

    def test_rhel_retorna_unknown(self):
        """ID_LIKE=rhel deve resultar em DISTRO='unknown'"""
        os_release = "ID=centos\nID_LIKE=rhel fedora\n"
        stdout, _, returncode = run_function("detect_distro", os_release_content=os_release)
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "unknown")

    def test_arch_retorna_unknown(self):
        """Arch Linux (sem ID_LIKE) deve resultar em DISTRO='unknown'"""
        os_release = "ID=arch\nNAME=Arch Linux\n"
        stdout, _, returncode = run_function("detect_distro", os_release_content=os_release)
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "unknown")

    def test_fedora_retorna_unknown(self):
        """ID_LIKE=fedora deve resultar em DISTRO='unknown'"""
        os_release = "ID=fedora\nID_LIKE=fedora\n"
        stdout, _, returncode = run_function("detect_distro", os_release_content=os_release)
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "unknown")

    def test_arquivo_ausente_retorna_unknown(self):
        """Ausência de /etc/os-release deve resultar em DISTRO='unknown' sem crash"""
        stdout, _, returncode = run_function(
            "detect_distro",
            env_override={"OS_RELEASE_FILE": "/tmp/nao_existe_os_release_99999"}
        )
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "unknown")


class TestValidateRequiredVars(unittest.TestCase):
    """Testes para a função validate_required_vars do mock_env.sh"""

    def test_sem_repo_falha(self):
        """Sem REPO definido deve retornar exit code 1 e mensagem de erro"""
        stdout, stderr, returncode = run_function(
            "validate_required_vars",
            env_override={"INSTALL_URL": "https://example.com"}
        )
        self.assertNotEqual(returncode, 0)
        self.assertIn("REPO", stderr)

    def test_sem_install_url_falha(self):
        """Sem INSTALL_URL definido deve retornar exit code 1 e mensagem de erro"""
        stdout, stderr, returncode = run_function(
            "validate_required_vars",
            env_override={"REPO": "org/repo"}
        )
        self.assertNotEqual(returncode, 0)
        self.assertIn("URL", stderr)

    def test_ambas_variaveis_presentes_sucesso(self):
        """Com REPO e INSTALL_URL definidos deve retornar exit code 0"""
        stdout, stderr, returncode = run_function(
            "validate_required_vars",
            env_override={
                "REPO": "org/repo",
                "INSTALL_URL": "https://example.com"
            }
        )
        self.assertEqual(returncode, 0)

    def test_sem_nenhuma_var_falha_com_repo(self):
        """Sem nenhuma variável, o erro deve mencionar REPO (primeira verificação)"""
        stdout, stderr, returncode = run_function("validate_required_vars")
        self.assertNotEqual(returncode, 0)
        self.assertIn("REPO", stderr)


class TestResolveArgocdVersion(unittest.TestCase):
    """
    Testes para a função resolve_argocd_version do mock_env.sh.

    NOTA IMPORTANTE - Bug documentado no install.sh original (linha 13):
        [[ ${ARGOCD_VERSION} ]] || ( ARGOCD_VERSION="7.8.23" )
    O uso de subshell ( ... ) faz com que a atribuição ARGOCD_VERSION="7.8.23"
    seja perdida ao retornar ao shell pai. Como resultado, ARGOCD_VERSION
    permanece vazia mesmo após essa linha — e o helm install falha.
    A função resolve_argocd_version no mock_env.sh corrige esse comportamento.
    """

    VERSAO_PADRAO = "7.8.23"

    def test_sem_argocd_version_usa_padrao(self):
        """Sem ARGOCD_VERSION definida deve usar a versão padrão 7.8.23"""
        stdout, _, returncode = run_function("resolve_argocd_version")
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, self.VERSAO_PADRAO)

    def test_com_argocd_version_usa_informada(self):
        """Com ARGOCD_VERSION definida deve usar o valor informado"""
        stdout, _, returncode = run_function(
            "resolve_argocd_version",
            env_override={"ARGOCD_VERSION": "8.0.0"}
        )
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, "8.0.0")

    def test_versao_vazia_usa_padrao(self):
        """Com ARGOCD_VERSION vazia deve usar a versão padrão"""
        stdout, _, returncode = run_function(
            "resolve_argocd_version",
            env_override={"ARGOCD_VERSION": ""}
        )
        self.assertEqual(returncode, 0)
        self.assertEqual(stdout, self.VERSAO_PADRAO)


if __name__ == "__main__":
    unittest.main(verbosity=2)
