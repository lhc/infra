# Contribuindo

- [Iniciando](#iniciando)
  - [Bem-vindo](#bem-vindo)
  - [Guia do contribuidor](#guia-do-contribuidor)
  - [Pré requisitos](#pre-requisitos)
    - [Crie uma conta no Github](#crie-uma-conta-no-github)
    - [Código de conduta](#codigo-de-conduta)
  - [Boas práticas](#boas-praticas)
    - [Nomeando ramos de desenvolvimento](#nomeando-galhos-de-desenvolvimento)
    - [versionamento](#versionamento)
    - [Mensagens de commits](#mensagens-de-commits)
    - [Abrindo um PR](#abrindo-um-pr)
    - [Revisando PR](#revisando-um-pr)
    - [Revisando o seu próprio pr](#revisando-o-seu-proprio-pr)
    - [Aprovações de PR](#aprovacoes-de-pr)
  - [Comunidade](#comunidade)
  - [Eventos](#eventos)
  - [Encontros](#encontros)

## Bem-vindo

## Guia do Contribuidor

Bem-vindo, este guia é divido nas seguintes seções.
É recomendado que você siga os passos a seguir na ordem proposta.

- [Bem-vindo](#bem-vindo) - Essa página
- [Pré-requisitos](#pre-requisitos) - Passos que você deve completar antes
   de começar a contribuir
- [Sua primeira contriuição](./FIRST-CONTRIBUTION.md) - Algumas coisas que precisa saber
  antes de realizar a sua primeira contribuição

## Pré-requisitos

### Crie uma conta no Github

Antes de começar a contribuir, [crie a sua conta](http://github.com/signup) de usuário e adicione a sua chave para assinar os commits.

### Realize uma bifurcação deste projeto para a sua conta do GitHub:

- Acesse https://github.com/lhc/infra/fork
- Caso queira copiar todas as ramificações desmarque a caixa `Copy the main branch only`
- Após clonar o repositório para a sua máquina, ajustes os apontamentos remotos
```sh
$ git remote rename origin upstream
$ git remote add origin git@github.com:<seu usuario github>/infra.git 
```

Nota: Caso tenha utilizado outro nome para a sua bifurcação, ajuste o nome do repositório no comando acima


### Código de conduta

Por favor certifique-se de ler o código [Código de conduta](https://github.com/lhc/estatuto/blob/master/src/codigo_conduta.md)

## Boas práticas

A seguir listamos algumas boas práticas

### Versionamento

Utilizamos versionamento semântico para gerar os lançamentos de novas versões. Para saber mais consulte a [documentação](https://semver.org/lang/pt-BR/) correspondente.

### Nomeando ramos de desenvolvimento

Ao começar a trabalhar em uma contriuição, nomeio o seu ramo seguindo a convenção abaixo, isso deixa claro a intensão 
de sua contribuição de forma a não necessário olhar o códio previamente para entender qual o seu objetivo.

1. Utilize nomes descritivos, esse nome deve refletir o trabalho realizado em seu ramo
2. Utilize caixa baixa
3. Utilize hífen para separar as palavras
4. Utilize caracteres alfa-numéricos, evite pontuações, espaços e `_` ou qualquer outro caracter não alfa-numérico
5. Utilize os prefixos abaixo:

  - `feature` ou `feat` para novas funcionalidades
  - `fix` Para resoluções de problemas em seu ramo
  - `hotfix` Para resoluções de problemas no ramo principal (`main`)
  - `docs` Para ajustes ou novas seções de documentação
6. Se a sua contribuição estiver atralada relaciona com uma tarefa do projeto, adicione o seu identificador após o prefixo

**Exemplo**:

```
docs/LH-123-argocd-setup-manifests
```

### Mensagens de commit

Mensagens de commit bem formatadas, ajudam a manter homogeneidade de estilo e também facilitam a criação de umam lista
de mudanças de forma automatizada.

Utilizamos `Conventional commits` para descrever as funcionalidades, ajustes e alterações significativas.
As mensagens devem obrigatoriamente ter o seguinte formato:

```
<tipo>[escopo opcional]: <descrição>

[corpo opcional]

[rodapé opcional]
````

As memsagens contêm os seguintes elementos estruturais para a comunicar a **intenção** do commit


1.fix: um commit do tipo fix corrige um bug na sua base de código (isso correlaciona-se com PATCH no Versionamento Semântico). 
2. feat: um commit do tipo feat introduz uma nova funcionalidade na base de código (isso correlaciona-se com MINOR no Versionamento Semântico).
3. BREAKING CHANGE: um commit que possui um rodapé BREAKING CHANGE:, ou adiciona um ! após o tipo/escopo, introduz uma mudança de API quebrando a compatibilidade (correlacionando com MAJOR no Versionamento Semântico). 
   Um BREAKING CHANGE pode ser parte de commits de qualquer tipo. 
4. `tipos` e diferentes de fix: e feat: são permitidos, por exemplo, o @commitlint/config-conventional (baseado na convenção do Angular)
    recomenda `build:`, `chore:`, `ci:`, `docs:`, `style:`, `refactor:`, `perf:`, `test:`, e outros. 
5. Rodapés diferentes de BREAKING CHANGE: <descrição> podem ser fornecidos e seguir uma convenção semelhante ao [formato de trailers do git](https://git-scm.com/docs/git-interpret-trailers/pt_BR)."

**Não recomendado**

```
Alterei a aplicação do ArgoCD para o Prometheus para utilizar os valores de um arquivo
```

**Recomendado**

Mensagem de commit com escopo e ! para chamar a atenção para quebra a compatibilidade
```
feat(api)!: envia email para o cliente quando o produto é enviado
```

Para maiores detalhes, consulte a [documentação](https://www.conventionalcommits.org/pt-br/v1.0.0/).

### Abrindo um PR

Procure criar PRs curtos com um propósito único. PRs curtos são mais fáceis s rápidos de revisar e provê um histórico claro de mudanças.
Escreva títulos e descrições claras de forma que os revisores entendam rapidamente o que o PR faz. Utilizamos um modelo para agilizar a criação dos PRs e
manter a homogeneidade.

### Revisando um PR

Ao prover comentários no PR, utilize a convenção abaixo, de forma que fique claro o que deve ser alterado e por qual motivo.

**Exemplo**: Solicitação de mudanças

**Deve**: Utilizar um arquivo values.yaml para passar os parâmetros para o chart 
**Razão**: A utilização de `source.helm.values` não é considerado uma boa prática, pois mistura dois tipos de manifestos

Revisões contendo a etiqueta **Deve**, obrigatoriamente deve ser marcado como solicitação de alteração

**Exemplo**: Sugestão de melhorias

**Deveria**: Criar um repositório para os arquivos `values.yaml` na organização
**Razão**: Torna mais fácil a manutenção e atualização dos charts.

Solicitações com a etiqueta **Deveria** são sugestões de melhoria e que deveria ser acatada pela pessoa que abriu o PR.

**Exemplo**:

**Nit**: Poderia ser criado um diretório para os manifestos do ArgoCD
**Razão**: A configuração do ArgoCD seria realizada via GitOps desde o início

Solitações com a etiqueta **Nit** são sugestões de melhorias não essenciais, mas que os revisores enchergam como um benefício para o projeto.
Essas solitações podem ser acatadas ou não pela pessoa que abriu o PR

### Revisando o seu próprio PR

Antes de submeter o PR, realize a verificação das alterações e as teste localmente antes de submeter as suas alterações. Isso possibilita
que erros de digitação e problemas de configurações sejam detectados, antes que outras pessoas iniciem a revisão.

#### Aprovações de PR

Antes de ser incorporado no galho principal, o PR deve passar pela revisão por 2 membros do projeto, mais aprovação de um CODE OWNER.

## Comunidade

Discuções relativas ao projeto, serão conduzidas através de [tarefas](https://github.com/lhc/infra/issues), onde os participantes
podem enviar sugestões relativas ao projeto, contribuindo para um ambiente aberto e colaborativo para a comunidade. 

## Encontros

A agenda de eventos do LHC pode ser vista [aqui](https://eventos.lhc.net.br/).

