# ToDo App na AWS · Documentação Técnica

Novembro de 2026 · PM-04 Projeto Final · Equipe: QueiroVielma

## Visão geral e escopo

O ToDo App roda na AWS (us-east-2) em 2 VMs criadas pelo Terraform, configuradas pelo Ansible e operadas só por pipelines do GitHub Actions. A demanda é a da "Feira de Profissões" ([escopo original](https://github.com/LaercioMLB/todo-app/blob/main/escopo.pdf)): colocar a lista de tarefas no ar para os visitantes usarem pelo celular, com o banco separado da aplicação e sem ninguém precisar entrar nos servidores para manter.

A aplicação é a do repositório `todo-app`: frontend React servido por Nginx, API Node.js/Express e MongoDB. Não desenvolvemos o sistema, só fizemos os ajustes necessários para ele rodar na nuvem (lista no fim do documento).

Endereço: **https://todo.martinazzo.dev.br**

| Pedido | O que foi entregue |
| --- | --- |
| REQ-01 · servidores | 2 VMs t3.small: uma para a aplicação e outra só para o MongoDB |
| REQ-02 · rede privada | As duas VMs ficam em sub-rede privada, sem IP público. A porta 27017 só aceita conexão do security group da aplicação |
| REQ-03 · acessos | Nenhuma porta 22 aberta. O Ansible entra por SSH dentro do Session Manager. O banco tem usuário próprio da aplicação (`todo`), e as senhas ficam nos GitHub Secrets |
| REQ-04 · persistência | Dados do MongoDB em `/opt/mongo/data`, fora do container. Backup todo dia às 03:00 com 7 dias de retenção, e teste de restauração em banco separado |
| REQ-05 · publicação | Domínio próprio com HTTPS (certificado do ACM no load balancer). Quem entra por HTTP é redirecionado |
| REQ-06 · disponibilidade | Containers com `restart: always`. A rota `/health` só responde 200 se a API estiver conectada no banco, e o ALB usa ela para saber se a VM está saudável |
| 3.1 · pipeline | GitHub Actions com execução manual e parâmetros. Terraform e Ansible rodam em sequência e a execução para no primeiro erro |
| 3.2 · Terraform | Variáveis, `init`/`plan`/`apply` pela pipeline, state no S3 com lock. Trocar o tamanho da VM não recria a máquina |
| 3.3 · Ansible | Instala pacotes e Docker, sobe os containers na versão pedida, atualiza o sistema operacional quando pedido e confere se tudo está rodando |

**Stack:** AWS (VPC, EC2, ALB, NAT, Route 53, ACM, SSM, S3, IAM) · Terraform 1.17 · Ansible · Docker · GitHub Actions · GHCR.

Custo estimado: cerca de US$ 0,12/hora com tudo ligado (uns US$ 3 por dia), quase tudo do NAT Gateway e do load balancer. Por isso o ambiente fica ligado só para testes e apresentação, e é destruído depois. A zona DNS fica sempre (US$ 0,50/mês).

## Arquitetura

Duas VMs numa sub-rede privada. A única coisa exposta para a internet é o load balancer, nas portas 80 e 443.

```
              Visitantes (navegador / celular)
                      │ HTTPS  https://todo.martinazzo.dev.br
                      │ (Route 53 aponta o domínio para o ALB; certificado do ACM)
                      ▼
   ┌──────── VPC 10.0.0.0/16 ──────────────────────────────────┐
   │  Sub-redes PÚBLICAS (10.0.1.0/24 e 10.0.2.0/24)            │
   │     ┌─────────────────────┐        ┌──────────────┐        │
   │     │ Application LB (ALB)│        │ NAT Gateway  │        │
   │     └──────────┬──────────┘        └──────▲───────┘        │
   │                │ :80 (health: /health)    │ saída (apt,    │
   │  Sub-rede PRIVADA (10.0.10.0/24)          │ imagens, SSM)  │
   │     ┌──────────▼────────────┐  :27017  ┌──┴──────────────┐ │
   │     │ VM app                ├─────────►│ VM db           │ │
   │     │  Nginx+React -> API   │          │  MongoDB 8.0    │ │
   │     └───────────────────────┘          │  /opt/mongo     │ │
   │                                        └─────────────────┘ │
   └────────────────────────────────────────────────────────────┘
```

O visitante acessa o domínio, o ALB recebe a conexão HTTPS e repassa para o Nginx da VM app. O Nginx entrega o React e manda o que for `/todos` para a API, que fala com o MongoDB pelo IP privado. As VMs só saem para a internet pelo NAT (para instalar pacotes, baixar imagens e falar com o Session Manager), e nada de fora consegue chegar nelas diretamente.

| VM | Sub-rede | Exposição | Executa |
| --- | --- | --- | --- |
| `pm04-app` | Privada, sem IP público | Porta 80 só do security group do ALB | Containers `frontend` (Nginx + React) e `backend` (API) |
| `pm04-db` | Privada, sem IP público | Porta 27017 só do security group da app | Container `mongo` (MongoDB 8.0.4), backup diário |

Por que não um IP público direto na VM: o IP muda quando a VM é recriada, a VM ficaria exposta na internet e não teria health check. Com o ALB o endereço é fixo, o certificado fica nele e dá para colocar mais VMs atrás depois.

### Estrutura do repositório

| Pasta | Conteúdo |
| --- | --- |
| `app/` | Código do ToDo App (backend, frontend, `docker-compose.yaml` para rodar local) |
| `terraform/` | Rede, security groups, IAM, VMs, ALB, domínio e certificado |
| `ansible/` | `site.yml` (deploy), `operacao.yml` (rotinas) e os roles `sistema`, `docker`, `database`, `app` |
| `.github/workflows/` | `pipeline.yml`, `operacao.yml`, `destroy.yml` |

## Terraform · provisionamento

O Terraform cria toda a infraestrutura e entrega para o Ansible os IDs das VMs e o IP privado do banco, pelos outputs.

### O que foi criado uma vez só, fora do Terraform

Duas coisas precisam existir antes da primeira execução e não podem ser apagadas pelo destroy:

- **Bucket do state** `pm04-tfstate-2026`: versionado. Criado pela CLI da AWS.
- **Zona DNS** `martinazzo.dev.br` no Route 53: se fosse criada pelo Terraform, cada destroy geraria nameservers novos e seria preciso trocar no Registro.br de novo.

### Arquivos

| Arquivo | Recursos | Pontos importantes |
| --- | --- | --- |
| `providers.tf` | Provider AWS e backend S3 | `use_lockfile = true` (lock no próprio S3). Tags `Project`, `Environment` e `ManagedBy` em todos os recursos |
| `network.tf` | VPC, 2 sub-redes públicas, 1 privada, IGW, NAT, rotas | A rota padrão da sub-rede privada vai para o NAT |
| `security.tf` | 3 security groups | Regras apontando para outros security groups, não para IPs: ALB → app :80, app → db :27017 |
| `iam.tf` | Role e instance profile | Só a política `AmazonSSMManagedInstanceCore`, para as VMs aparecerem no Session Manager |
| `compute.tf` | 2 EC2, key pair | Ubuntu 24.04, disco gp3 criptografado, `ignore_changes = [ami]` para não recriar a VM quando sai uma AMI nova |
| `alb.tf` | ALB, target group, listeners | Health check em `/health`. Porta 80 redireciona para 443 |
| `dns.tf` | Certificado ACM, registros no Route 53 | O certificado é validado sozinho por DNS. `todo.martinazzo.dev.br` aponta para o ALB |
| `outputs.tf` | Outputs | `app_url`, `app_instance_id`, `db_instance_id`, `db_private_ip`, `app_private_ip` |

**Variáveis:** ficam no `terraform.tfvars` (região, tamanhos das VMs, health check, domínio). A chave SSH pública vem do secret `SSH_PUBLIC_KEY`, e os tamanhos das VMs podem ser trocados pelos parâmetros da pipeline.

**Alteração sem recriar:** trocar `tipo_vm_app` ou `tipo_vm_db` faz uma atualização no lugar (`~` no plan). A VM para e volta com o mesmo disco e o mesmo IP privado, então o banco não perde nada.

## Ansible · configuração e deploy

O Ansible pega as VMs vazias e deixa a aplicação rodando: pacotes, Docker, MongoDB, containers da aplicação e verificação no final. Ele roda no runner do GitHub Actions.

### Inventário gerado a partir do Terraform

Não existe inventário fixo no Git. O `gerar-inventario.sh` recebe os outputs do Terraform e monta o `inventory.ini`:

| Grupo | Host | Como conecta |
| --- | --- | --- |
| `app` | ID da instância (ex.: `i-0abc...`) | SSH com `ProxyCommand aws ssm start-session` |
| `db` | ID da instância | Igual |

O IP privado do banco vira a variável `db_host`, usada pela API. Como a conexão passa pelo Session Manager, não precisa de bastion nem de porta 22 aberta.

### `site.yml` · ordem de execução

1. **Todas as VMs:** espera a VM aparecer no Session Manager (até 10 min na primeira vez), depois roles `sistema` e `docker`.
2. **db:** role `database`.
3. **app:** role `app`.

### Roles

| Role | Onde | O que faz |
| --- | --- | --- |
| `sistema` | todas | Espera o cloud-init, instala `ca-certificates curl dnsutils net-tools jq htop unzip` e os pacotes extras pedidos. Mostra quantas atualizações do SO estão pendentes e, se `atualizar_so` estiver ligado, faz o `apt dist-upgrade` e reinicia a VM se precisar |
| `docker` | todas | Docker e a biblioteca Python do Docker, serviço habilitado |
| `database` | db | Pastas de dados e backup, script de inicialização (cria o usuário `todo` e 3 tarefas de exemplo só na primeira vez), container `mongo` com autenticação, scripts de operação, cron do backup e um backup antes de qualquer atualização |
| `app` | app | Mostra a versão rodando e a pedida, testa a conexão com o banco, faz login no GHCR só se tiver versão nova, sobe `backend` e `frontend` na rede `todo-net`, espera `/health` = 200 e confere se os containers estão na versão pedida |

As senhas chegam por variável de ambiente e as tarefas que mexem com elas usam `no_log: true`, então não aparecem no log da pipeline.

Idempotência: rodando de novo sem mudar nada, nenhuma tarefa fica como `changed`. O container só é recriado quando a imagem ou a configuração muda.

### `operacao.yml` · rotinas

Não muda a configuração das VMs. Recebe a variável `acao`:

- `saude`: estado dos containers e resposta do `/health`
- `logs`: últimas 30 linhas do MongoDB, da API e do Nginx
- `reiniciar`: reinicia os containers e espera o banco voltar
- `backup`: faz um backup na hora
- `testar-restauracao`: restaura o último backup no banco `restore-teste`, compara a quantidade de tarefas e apaga o banco de teste
- `limpar-lista`: faz um backup e deixa só as 3 tarefas de exemplo

## Pipelines (GitHub Actions)

São 3 workflows. Os três usam o mesmo grupo de `concurrency` (`infra-pm04`), então nunca rodam dois ao mesmo tempo mexendo na infraestrutura.

| Workflow | Gatilho | O que faz |
| --- | --- | --- |
| `pipeline.yml` | push na `main` (em `app/`, `terraform/`, `ansible/` ou no próprio arquivo), Run workflow com parâmetros, Pull Request | Build das imagens, Terraform, Ansible e teste pela URL pública |
| `operacao.yml` | Run workflow | Rotinas do dia a dia, sem mexer na infraestrutura |
| `destroy.yml` | Run workflow, digitando `DESTRUIR` | `terraform destroy` |

### `pipeline.yml`

1. **Construir imagens:** confere a sintaxe da API, faz o build do backend e do frontend e publica no GHCR com a tag igual ao SHA do commit (`ghcr.io/queirovielma/todo-backend:<sha>`). O login usa o `GITHUB_TOKEN` da própria execução. Em Pull Request só faz o build, sem publicar.
2. **Provisionar (Terraform):** `fmt -check`, `init`, `validate`, `plan` e `apply` do plano salvo. O resultado do plan vai para o resumo da execução.
3. **Configurar e implantar (Ansible):** só começa se os dois jobs anteriores deram certo. Instala o plugin do Session Manager e o Ansible, gera o inventário com os outputs, roda o `site.yml` e coloca o PLAY RECAP no resumo.
4. **Teste final:** chama `https://todo.martinazzo.dev.br/health` e `/todos` de fora da AWS. Se não responder em 10 minutos, a pipeline falha.

**Parâmetros do Run workflow:**

| Parâmetro | Padrão | O que faz |
| --- | --- | --- |
| `versao` | vazio | SHA de uma versão já implantada, para voltar (rollback). Vazio = commit atual |
| `tipo_vm_app` | `t3.small` | Tamanho da VM da aplicação (`t3.micro`, `t3.small`, `t3.medium`) |
| `tipo_vm_db` | `t3.small` | Tamanho da VM do banco |
| `atualizar_so` | desligado | Aplica as atualizações do sistema operacional |
| `pacotes_extras` | vazio | Pacotes do apt separados por espaço (ex.: `tcpdump traceroute`) |

No push os parâmetros ficam vazios e valem os tamanhos do `terraform.tfvars`. Se uma execução manual mudar o tamanho de uma VM, a próxima com o padrão volta para o valor do arquivo.

### Segredos e variáveis do GitHub

| Nome | Tipo | Uso |
| --- | --- | --- |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Usuário IAM da pipeline |
| `AWS_SESSION_TOKEN` | Secret | Só se usar AWS Academy |
| `SSH_PUBLIC_KEY` | Secret | Vira o key pair das VMs no Terraform |
| `SSH_PRIVATE_KEY` | Secret | Usada pelo Ansible para entrar nas VMs |
| `DB_PASSWORD` | Secret | Senha do usuário `todo` do MongoDB (usada pela API) |
| `DB_ROOT_PASSWORD` | Secret | Senha do `root` do MongoDB (usada nos backups) |
| `TF_STATE_BUCKET` | Variable | `pm04-tfstate-2026` |
| `GITHUB_TOKEN` | Automático | Publicar e baixar as imagens no GHCR |

## Como cada parte se comunica

Nenhuma ferramenta chama a outra diretamente. O GitHub Actions coordena tudo, e os dados passam pelo state, pelos outputs dos jobs e pelo GHCR.

| De → Para | O que passa | Como |
| --- | --- | --- |
| GitHub → Terraform | Chave SSH pública e tamanhos das VMs | `TF_VAR_ssh_public_key` e `-var` no plan |
| Terraform ↔ S3 | State | Backend S3 `pm04/terraform.tfstate` com lock |
| Terraform → Ansible | IDs das VMs, IP privado do banco, URL | Outputs do job → `gerar-inventario.sh` → `inventory.ini` |
| GitHub → Ansible | Senhas, versão, parâmetros | Variáveis de ambiente lidas no `group_vars/all.yml` |
| Runner → VMs | Comandos do Ansible | SSH dentro do Session Manager |
| Job de build → GHCR → VM app | Imagens `todo-backend` e `todo-frontend` | Push no GHCR, o Ansible faz login temporário e a VM baixa pelo NAT |
| API → MongoDB | Tarefas | `MONGO_HOST` = IP privado do banco, porta 27017 |
| Visitante → aplicação | HTTPS | Route 53 → ALB :443 → Nginx :80 → `/todos` → API :5000 |

## Fluxo completo de um deploy

1. **Preparação (uma vez):** bucket do state e zona DNS criados pela CLI, nameservers trocados no Registro.br, secrets cadastrados no GitHub.
2. **Disparo:** push na `main` ou Run workflow com os parâmetros.
3. **Build:** imagens da API e do frontend publicadas no GHCR com o SHA do commit.
4. **Terraform:** plan e apply. Na primeira vez cria tudo (uns 5 minutos), nas próximas aplica só a diferença.
5. **Ansible:** pacotes e Docker nas duas VMs, MongoDB e backup na db, containers da aplicação na app.
6. **Teste final:** `/health` e `/todos` pelo domínio público. A URL, a versão e os resultados ficam no resumo da execução.
7. **Dia a dia:** workflow `operacao` para saúde, logs, reinício e backup. O backup automático roda às 03:00 pelo cron da VM db.
8. **Fim:** workflow `destroy` depois da apresentação.

### Em caso de falha

- **Falha no Terraform:** o Ansible nem começa. Corrige o código e roda de novo.
- **Falha no Ansible:** a infraestrutura já existe. Como o playbook é idempotente, é só corrigir e rodar de novo (o plan vem sem mudanças).
- **Versão com problema:** Run workflow com o SHA da versão anterior no campo `versao`. O build é pulado e só os containers da aplicação são trocados.
- **Perda de dados:** restaurar o último backup (comando no fim do documento).

## Roteiro para a apresentação

Os três testes obrigatórios são feitos pelo Run workflow da pipeline. Em cada execução, o resumo mostra os parâmetros, o resultado do plan, o PLAY RECAP e a URL testada.

| Cenário | Como rodar | O que mostrar |
| --- | --- | --- |
| 1 · Criação inicial | Parâmetros padrão | `Plan: N to add`; log instalando pacotes, Docker e containers; site abrindo com cadeado |
| 2 · Atualização | `tipo_vm_app = t3.medium` e `pacotes_extras = tcpdump traceroute` | `0 to add, 1 to change, 0 to destroy` (a VM não é recriada); pacotes como `changed`; tarefas criadas antes continuam lá |
| 3 · Sem alterações | Os mesmos parâmetros do cenário 2 | `No changes` no plan e `changed=0` nas duas VMs |

Observações:

- A atualização do SO (`atualizar_so`) fica melhor numa execução separada, antes do cenário 2. Se ficar ligada no cenário 3 e sair uma atualização nova da Ubuntu entre as duas execuções, ela aparece como `changed`.
- Para mostrar a troca de imagem: mudar um texto no `App.js` e fazer push. O log do Ansible mostra a versão antiga, a nova e "vai atualizar".

### Validação da demanda

| Critério | Evidência |
| --- | --- |
| ACE-01/06 | Pipeline verde com os 3 jobs e a versão no resumo |
| ACE-02 | Console EC2 com as 2 VMs sem IP público |
| ACE-03 | Security group do banco liberando 27017 só para o SG da app |
| ACE-04 | Celular abrindo https://todo.martinazzo.dev.br: cadastrar, concluir, excluir, recarregar |
| ACE-05 | Criar tarefa, rodar `reiniciar` e a pipeline de novo: a tarefa continua lá |
| ACE-07 | Log das ações `backup` e `testar-restauracao` |
| ACE-08 | Log das ações `saude` e `logs`, com as senhas aparecendo como `***` |

### Pontos de atenção

- **Custo por hora:** NAT e ALB cobram mesmo sem acesso. Rodar o `destroy` depois da apresentação.
- **Destroy apaga o banco:** as tarefas e os backups ficam no disco das VMs. Se quiser guardar a lista, rodar a ação `backup` antes e copiar o arquivo.
- **Senha do banco:** o usuário `todo` é criado só na primeira subida do MongoDB. Trocar o `DB_PASSWORD` depois exige destruir e subir de novo.
- **Uma única zona de disponibilidade:** as VMs ficam na mesma AZ. Para alta disponibilidade seria preciso uma segunda VM app em outra AZ atrás do ALB e réplica do MongoDB.
- **Access key em vez de OIDC:** a pipeline usa chave de usuário IAM guardada nos Secrets.

### Próximos passos possíveis

- Mandar os backups para um bucket S3, para não dependerem do disco da VM.
- Colocar verificação de segurança na pipeline (Gitleaks, Trivy).
- Trocar a access key por OIDC.
- Segunda VM da aplicação em outra AZ.

## Domínio (Registro.br + Route 53)

O domínio `martinazzo.dev.br` foi comprado no Registro.br e o DNS dele foi delegado para o Route 53. Assim o Terraform consegue validar o certificado e criar o registro `todo.martinazzo.dev.br` sozinho.

Nameservers cadastrados no Registro.br:

```
ns-1296.awsdns-34.org
ns-22.awsdns-02.com
ns-1613.awsdns-09.co.uk
ns-850.awsdns-42.net
```

Para conferir: `nslookup -type=NS martinazzo.dev.br 8.8.8.8` tem que mostrar os servidores `awsdns`.

## Adaptações feitas na aplicação

- O frontend chamava `http://localhost:5000` fixo. Agora chama `/todos` no mesmo endereço e o Nginx repassa para a API.
- A conexão com o banco estava no código (`root:rootpassword`). Agora vem de variáveis de ambiente.
- O CORS aberto foi removido, porque frontend e API ficam no mesmo endereço.
- Foi criada a rota `/health`, e a API tenta reconectar se o banco ainda não estiver pronto.
- As imagens base têm tag fixa (`node:20.18.1-alpine`, `nginx:1.27.3-alpine`, `mongo:8.0.4`) e o build usa `npm ci`.

## Manual rápido

**Rodar localmente:**

```bash
cd app
docker compose up --build -d   # abrir http://localhost
```

**Restaurar um backup de verdade** (só se perder dados), entrando na VM db pelo Session Manager:

```bash
sudo ls /opt/mongo/backups
sudo docker exec -i mongo sh -c 'mongorestore -u root -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --drop' < /opt/mongo/backups/ARQUIVO.archive.gz
```

**Problemas comuns:**

| Sintoma | Causa provável |
| --- | --- |
| `terraform fmt -check` falhou | Rodar `terraform fmt -recursive` e fazer commit |
| Ansible esperando conexão | A VM ainda não registrou no Session Manager. Pode levar até 10 min (Systems Manager > Fleet Manager) |
| Target group *unhealthy* | A API não conecta no banco. Rodar a ação `logs` |
| `denied` ao baixar a imagem | Rodar a pipeline completa (o login no GHCR usa o token da execução) |
| Pipeline parada em `aws_acm_certificate_validation` | O Registro.br ainda não está usando os nameservers do Route 53 |
| Navegador não acha o site | DNS ainda propagando ou cache do navegador. Testar em janela anônima ou `nslookup todo.martinazzo.dev.br 8.8.8.8` |
