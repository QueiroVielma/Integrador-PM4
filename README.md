# PM-04 · Projeto Final de DevOps e Infraestrutura

Implantação do **ToDo App** (demanda "Feira de Profissões",
[escopo original](https://github.com/LaercioMLB/todo-app/blob/main/escopo.pdf)) na AWS:

- infraestrutura provisionada com **Terraform**
- VMs configuradas e mantidas com **Ansible**
- tudo operado pelo **GitHub Actions** (ninguém roda Terraform/Ansible na mão)

## Arquitetura

```
              Visitantes (navegador)
                      │ HTTPS  https://todo.martinazzo.dev.br
                      │ (Route 53 aponta o domínio para o ALB; certificado gratuito do ACM)
                      ▼
   ┌──────── VPC 10.0.0.0/16 ──────────────────────────────────┐
   │  Sub-redes PUBLICAS (10.0.1.0/24 e 10.0.2.0/24)            │
   │     ┌─────────────────────┐        ┌──────────────┐        │
   │     │ Application LB (ALB)│        │ NAT Gateway  │        │
   │     └──────────┬──────────┘        └──────▲───────┘        │
   │                │ :80 (health: /health)    │ saida (apt,    │
   │  Sub-rede PRIVADA (10.0.10.0/24)          │ imagens, SSM)  │
   │     ┌──────────▼────────────┐  :27017  ┌──┴──────────────┐ │
   │     │ VM app                ├─────────►│ VM db           │ │
   │     │  Nginx+React -> API   │          │  MongoDB 8.0    │ │
   │     └───────────────────────┘          │  /opt/mongo     │ │
   │                                        └─────────────────┘ │
   └────────────────────────────────────────────────────────────┘
```

| Requisito do escopo | Como foi atendido |
|---|---|
| REQ-01 Servidores | 2 VMs t3.small; MongoDB sozinho na VM db |
| REQ-02 Rede privada | VMs sem IP público; porta 27017 liberada só para o security group da VM app |
| REQ-03 Acessos | sem porta 22: Ansible usa SSH dentro do Session Manager; usuário `todo` próprio no banco; senhas em GitHub Secrets |
| REQ-04 Persistência | dados em `/opt/mongo/data` na VM (fora do container); backup diário às 03:00 com 7 dias de retenção; teste de restauração em banco isolado |
| REQ-05 Publicação | domínio próprio `todo.martinazzo.dev.br` com HTTPS (certificado ACM no ALB); quem entra por HTTP é redirecionado para HTTPS; `/todos` e a interface no mesmo endereço |
| REQ-06 Disponibilidade | `restart: always` nos containers; `/health` só responde 200 se a API estiver conectada ao banco (usado pelo ALB, pelo Docker e pela pipeline) |

## Estrutura do repositório

```
app/                      -> código do ToDo App (adaptado para a nuvem)
  backend/                -> API Express; banco configurado por variável de ambiente, rota /health
  frontend/               -> React + nginx.conf que encaminha /todos para a API
  docker-compose.yaml     -> para rodar localmente
.github/workflows/
  pipeline.yml            -> build das imagens + Terraform + Ansible + teste na URL pública
  operacao.yml            -> saúde, logs, reiniciar, backup, testar restauração, limpar lista
  destroy.yml             -> derruba tudo (manual, pede para digitar DESTRUIR)
terraform/
  network.tf security.tf iam.tf compute.tf alb.tf dns.tf outputs.tf
ansible/
  site.yml                -> deploy completo
  operacao.yml            -> rotinas do dia a dia
  roles/sistema           -> pacotes do sistema e atualizações do SO (parâmetro da pipeline)
  roles/docker            -> instala Docker nas duas VMs
  roles/database          -> MongoDB com autenticação, scripts e cron de backup
  roles/app               -> containers backend e frontend na versão pedida
```

### Adaptações feitas na aplicação

- O frontend chamava `http://localhost:5000` fixo: agora chama `/todos` no mesmo endereço e o Nginx encaminha para a API.
- A conexão do backend com o banco estava fixa no código (`root:rootpassword`): agora vem de variáveis de ambiente.
- O CORS aberto foi removido, porque frontend e API ficam no mesmo endereço.
- Foi criada a rota `/health`, e a API tenta reconectar se o banco ainda não estiver pronto.
- As imagens agora têm tag fixa (`node:20.18.1-alpine`, `nginx:1.27.3-alpine`, `mongo:8.0.4`) e o build usa `npm ci`.

## Domínio (Registro.br + Route 53)

O domínio `martinazzo.dev.br` foi comprado no Registro.br, e o DNS dele é atendido pelo **Route 53**.
Assim o Terraform consegue sozinho validar o certificado HTTPS e apontar `todo.martinazzo.dev.br` para o load balancer.

A zona do Route 53 foi criada **uma única vez**, fora do Terraform, igual ao bucket do state. O destroy não apaga a zona, então os nameservers cadastrados no Registro.br nunca mudam. Custo: US$ 0,50/mês.

```bash
aws route53 create-hosted-zone --name martinazzo.dev.br --caller-reference pm04-zona
```

Nameservers da zona (cadastrados no Registro.br):

```
ns-1296.awsdns-34.org
ns-22.awsdns-02.com
ns-1613.awsdns-09.co.uk
ns-850.awsdns-42.net
```

Para conferir se a delegação já funciona: `nslookup -type=NS martinazzo.dev.br 8.8.8.8` precisa mostrar os servidores `awsdns`.

## Secrets e variáveis do GitHub

Em **Settings > Secrets and variables > Actions**:

| Tipo | Nome | Conteúdo |
|---|---|---|
| Variable | `TF_STATE_BUCKET` | `pm04-tfstate-2026` |
| Secret | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | chave do usuário IAM |
| Secret | `AWS_SESSION_TOKEN` | só se usar AWS Academy |
| Secret | `SSH_PUBLIC_KEY` / `SSH_PRIVATE_KEY` | par de chaves usado pelo Ansible |
| Secret | `DB_PASSWORD` | senha do usuário `todo` (aplicação) no MongoDB |
| Secret | `DB_ROOT_PASSWORD` | senha do `root` do MongoDB |

O token do registry de imagens (`GITHUB_TOKEN`) é criado automaticamente pelo GitHub em cada execução.

## Como usar

### Subir / atualizar (pipeline)

O push na `main` roda tudo sozinho. Também dá para rodar manualmente em **Actions > Pipeline PM-04 > Run workflow**.

1. **Construir imagens**: `docker build` da API e do frontend, publicadas em `ghcr.io/<usuario>/todo-*:<sha do commit>`.
2. **Provisionar (Terraform)**: fmt, validate, plan e apply. Na primeira vez leva uns 10 min por causa do NAT e do ALB.
3. **Configurar e implantar (Ansible)**: instala o Docker, sobe o MongoDB, faz um backup antes de atualizar e sobe a nova versão da aplicação.
4. **Teste final**: chama `http://.../health` e `/todos`. A URL e a versão aparecem no resumo da execução.

**Parâmetros da execução manual** (Run workflow):

| Parâmetro | O que faz |
|---|---|
| `versao` | SHA de um commit já implantado (rollback); vazio = versão atual |
| `tipo_vm_app` / `tipo_vm_db` | tamanho das VMs. A troca é feita na mesma VM (para e volta), sem recriar e sem perder os dados |
| `atualizar_so` | aplica `apt dist-upgrade` e reinicia a VM se precisar. Desligado, o Ansible só mostra quantas atualizações estão pendentes |
| `pacotes_extras` | pacotes do apt para instalar além dos padrão (`ca-certificates curl dnsutils net-tools jq htop unzip`) |

No push os parâmetros ficam vazios: valem os tamanhos do `terraform.tfvars` e o SO não é atualizado. Para mudar o tamanho de vez, edite o `terraform.tfvars`; se mudar só pela execução manual, o próximo push volta ao valor do arquivo.

O Ansible mostra a versão que está rodando e a versão pedida antes de atualizar e, no fim, confere se os containers estão rodando a versão pedida.

Pull Request para a `main` roda só build, fmt, validate e plan, sem aplicar nada.

### Voltar para a versão anterior (rollback)

**Actions > Pipeline PM-04 > Run workflow**, colar no campo *versao* o SHA de um commit que já foi implantado.
A pipeline pula o build e sobe as imagens daquela versão. O banco não é alterado.

### Rotinas de operação

**Actions > Operacao > Run workflow** e escolher:

| Ação | O que faz |
|---|---|
| `saude` | estado dos containers e resposta do `/health` |
| `logs` | últimas 30 linhas do MongoDB, da API e do Nginx |
| `reiniciar` | reinicia os containers (não apaga tarefas) |
| `backup` | faz um backup agora em `/opt/mongo/backups` |
| `testar-restauracao` | faz um backup, restaura no banco `restore-teste`, compara a quantidade de tarefas e apaga o banco de teste (a lista da demonstração não é mexida) |
| `limpar-lista` | faz um backup e deixa uma lista nova para a próxima apresentação |

Restaurar de verdade (só em caso de perda de dados), conectando na VM db pelo Session Manager:

```bash
sudo ls /opt/mongo/backups
sudo docker exec -i mongo sh -c 'mongorestore -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --drop' < /opt/mongo/backups/ARQUIVO.archive.gz
```

### Derrubar tudo depois da feira

**Actions > Destruir infraestrutura PM-04 > Run workflow** e digitar `DESTRUIR`.

- Isso apaga as VMs, **inclusive o banco e os backups**. Se quiser guardar a lista, rode antes a ação `backup` e copie o arquivo.
- Continuam existindo, e cobrando centavos: o bucket do state (`pm04-tfstate-2026`) e as imagens no ghcr.io (gratuito).

### Rodar localmente

```bash
cd app
docker compose up --build -d   # abrir http://localhost
```

## Testes obrigatórios da apresentação

Os três cenários são feitos em **Actions > Pipeline PM-04 > Run workflow**. Em cada execução, o resumo mostra os parâmetros, o resultado do `terraform plan`, o PLAY RECAP do Ansible e a URL testada.

### Cenário 1: criação inicial
Rodar com os parâmetros padrão (`t3.small` / `t3.small`, sem atualizar o SO, sem pacotes extras).

Evidências:
- Pipeline verde com os 3 jobs.
- Resumo mostrando `Plan: N to add, 0 to change, 0 to destroy`.
- Log do Ansible: pacotes instalados, Docker instalado, MongoDB e containers criados, mensagem "primeira instalacao".
- `https://todo.martinazzo.dev.br` aberto no navegador.

### Cenário 2: atualização do ambiente
Rodar mudando **`tipo_vm_app` para `t3.medium`** (infraestrutura) e preenchendo **`pacotes_extras` com `tcpdump traceroute`** (manutenção). Para mostrar a atualização do SO, ligue **`atualizar_so`** numa execução separada, antes deste cenário.

Evidências:
- Resumo do plan com `0 to add, 1 to change, 0 to destroy`: a VM muda de tamanho sem ser recriada.
- Log do Ansible: "Instalar pacotes..." como `changed`, e a quantidade de atualizações pendentes do SO.
- Tarefas criadas antes da mudança continuam na lista.
- Opcional, atualização de imagem: mudar um texto no `App.js` e fazer push. O log mostra "Rodando: ...:sha_antigo | Pedida: ...:sha_novo | vai atualizar".

### Cenário 3: reexecução sem alterações
Rodar de novo com **os mesmos parâmetros do cenário 2**.

Evidências:
- Resumo do plan com `No changes`.
- PLAY RECAP com `changed=0` nas duas VMs e o log com "nada a atualizar".
- Se `atualizar_so` estiver ligado e a Ubuntu tiver publicado uma atualização entre uma execução e outra, o upgrade aparece como `changed`. Isso é o comportamento esperado; para a demonstração, deixe `atualizar_so` desligado nos cenários 2 e 3.

> Se rodar com parâmetros diferentes (ou fizer push), o tamanho volta ao do `terraform.tfvars`, e isso é uma alteração.

### Validação da demanda
A tabela de requisitos no início deste README liga cada requisito do escopo à parte da infraestrutura que o atende.

Evidências: console EC2 com as 2 VMs sem IP público, target group *healthy*, security group do banco liberando a 27017 só para o SG da app, cadeado do HTTPS e as ações `saude`, `backup` e `testar-restauracao` do workflow Operacao.

## Evidências para o relatório

| Critério | Evidência |
|---|---|
| ACE-01/06 | print da pipeline verde (3 jobs) com a versão no resumo |
| ACE-02 | console EC2 mostrando as 2 VMs sem IP público |
| ACE-03 | security group do db (27017 só do sg-app) e `curl`/`nc` externo falhando |
| ACE-04 | celular abrindo https://todo.martinazzo.dev.br (cadeado): cadastrar, concluir, reabrir, excluir, recarregar |
| ACE-05 | criar tarefa, rodar `reiniciar`, rodar a pipeline de novo: a tarefa continua lá |
| ACE-07 | log das ações `backup` e `testar-restauracao` |
| ACE-08 | log das ações `saude` e `logs`; segredos aparecem como `***` |

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `terraform fmt -check` falhou | rode `terraform fmt -recursive` e faça commit |
| Ansible fica esperando a conexão | a VM ainda não registrou no SSM; espere até 10 min (Systems Manager > Fleet Manager) |
| Target group *unhealthy* | a API não conecta no banco: rode a ação `logs` |
| `denied` ao baixar a imagem | rode a pipeline completa (o login no ghcr.io usa o token da própria execução) |
| Pipeline parada em `aws_acm_certificate_validation` | o Registro.br ainda não está usando os nameservers do Route 53 (veja a seção Domínio) |
| Navegador não acha `todo.martinazzo.dev.br` | delegação do DNS ainda propagando; teste com `nslookup todo.martinazzo.dev.br 8.8.8.8` |
