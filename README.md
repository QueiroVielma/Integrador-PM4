# PM-04 · Projeto Final de DevOps e Infraestrutura

Infraestrutura na AWS provisionada com **Terraform**, configurada com **Ansible**
e operada inteiramente por uma **pipeline no GitHub Actions**.

## Arquitetura

```
                Internet
                   │  HTTP :80
                   ▼
   ┌──────── VPC 10.0.0.0/16 ─────────────────────────────┐
   │  Sub-redes PUBLICAS (10.0.1.0/24 e 10.0.2.0/24)       │
   │     ┌─────────────────────┐     ┌──────────────┐     │
   │     │ Application LB (ALB)│     │ NAT Gateway  │     │
   │     └──────────┬──────────┘     └──────▲───────┘     │
   │                │ :80                   │ saida (apt, │
   │  Sub-rede PRIVADA (10.0.10.0/24)       │ docker, SSM)│
   │     ┌──────────▼──────────┐   :3306  ┌─┴────────────┐│
   │     │ VM app (Docker)     ├─────────►│ VM db (MySQL)││
   │     └─────────────────────┘          └──────────────┘│
   └──────────────────────────────────────────────────────┘
```

- Somente o **load balancer** recebe trafego da internet.
- As duas VMs ficam em sub-rede privada, **sem IP publico e sem porta 22 aberta**.
- A VM do banco so aceita conexao na porta 3306 vinda da VM da aplicacao.
- O NAT Gateway permite apenas que as VMs *saiam* para a internet (instalar pacotes e baixar imagens).
- O Ansible acessa as VMs por SSH **dentro de um tunel do AWS Systems Manager (Session Manager)**, por isso nao precisa de bastion.

## Estrutura do repositorio

```
.github/workflows/
  pipeline.yml   -> fmt, validate, plan, apply e depois Ansible + teste pelo ALB
  destroy.yml    -> derruba tudo (manual, pede confirmacao)
terraform/
  providers.tf   -> provider AWS e backend S3 (state remoto)
  variables.tf / terraform.tfvars
  network.tf     -> VPC, sub-redes, IGW, NAT, rotas
  security.tf    -> security groups (ALB, app, db)
  iam.tf         -> permissao do Session Manager para as VMs
  compute.tf     -> VM app e VM db (Ubuntu 24.04)
  alb.tf         -> load balancer, target group e listener
  outputs.tf
ansible/
  site.yml       -> playbook principal
  group_vars/all.yml -> imagens (tag fixa), nomes do banco
  roles/docker   -> instala Docker nas duas VMs
  roles/database -> container MySQL com volume na VM
  roles/app      -> container da aplicacao conectado ao banco
```

## Secrets e variaveis do GitHub

Em **Settings > Secrets and variables > Actions**:

| Tipo | Nome | Conteudo |
|---|---|---|
| Secret | `AWS_ACCESS_KEY_ID` | chave de acesso da AWS |
| Secret | `AWS_SECRET_ACCESS_KEY` | segredo da chave |
| Secret | `AWS_SESSION_TOKEN` | so se usar AWS Academy (muda a cada sessao do lab) |
| Secret | `SSH_PUBLIC_KEY` | conteudo do `~/.ssh/pm04.pub` |
| Secret | `SSH_PRIVATE_KEY` | conteudo do `~/.ssh/pm04` |
| Secret | `DB_PASSWORD` | senha do usuario da aplicacao no MySQL |
| Secret | `DB_ROOT_PASSWORD` | senha do root do MySQL |
| Variable | `TF_STATE_BUCKET` | nome do bucket S3 do state |

Nenhuma credencial fica no codigo.

## Passo a passo (WSL)

### 1. Conferir as ferramentas

```bash
terraform -version
ansible --version
aws --version          # se nao tiver: sudo apt install -y awscli  (ou instalador oficial v2)
git --version
```

### 2. Configurar a AWS CLI e testar

```bash
aws configure          # access key, secret, regiao us-east-2, formato json
# AWS Academy: copie o bloco de "AWS Details > AWS CLI" para ~/.aws/credentials
aws sts get-caller-identity
```

### 3. Criar o bucket do state (unico passo manual, feito uma vez)

O state precisa ficar fora do computador para a pipeline enxergar.
O nome do bucket tem que ser unico no mundo:

```bash
BUCKET=pm04-tfstate-seunome-2026
aws s3api create-bucket --bucket $BUCKET --region us-east-2 \
  --create-bucket-configuration LocationConstraint=us-east-2
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
```

### 4. Gerar a chave SSH do projeto

```bash
ssh-keygen -t ed25519 -f ~/.ssh/pm04 -N "" -C "pm04"
cat ~/.ssh/pm04.pub    # vai no secret SSH_PUBLIC_KEY
cat ~/.ssh/pm04        # vai no secret SSH_PRIVATE_KEY (copie tudo, inclusive BEGIN/END)
```

### 5. Validar localmente antes de subir

```bash
cd terraform
terraform fmt -recursive
terraform init -backend=false
terraform validate
cd ../ansible
ansible-galaxy collection install -r requirements.yml
cp inventory.example.ini inventory.ini
ansible-playbook site.yml --syntax-check
rm inventory.ini
```

### 6. Criar o repositorio no GitHub e cadastrar os secrets

```bash
cd ..
git init -b main
git add .
git commit -m "Projeto final PM-04: Terraform + Ansible + pipeline"
git remote add origin https://github.com/SEU_USUARIO/pm04-projeto-final.git
git push -u origin main
```

Cadastre os secrets e a variable da tabela acima. Se o push rodou a pipeline
antes dos secrets existirem, va em **Actions > Pipeline PM-04 > Run workflow**.

### 7. Acompanhar a pipeline

Na aba **Actions**:

1. Job **Provisionar (Terraform)**: fmt, init, validate, plan e apply (~5 min, o NAT e o ALB demoram).
2. Job **Configurar (Ansible)**: espera as VMs aparecerem no Session Manager, instala Docker,
   sobe o MySQL e a aplicacao.
3. Ultimo passo testa a URL do load balancer e escreve o link no resumo da execucao.

### 8. Fazer mudancas (sempre pela pipeline)

- Atualizar a aplicacao: trocar a tag de `app_image` em `ansible/group_vars/all.yml`, commit e push.
- Mudar a infraestrutura: alterar os `.tf`, abrir um Pull Request (a pipeline mostra o `plan`)
  e depois fazer merge na `main` (a pipeline aplica).

### 9. Derrubar tudo no fim (para nao gastar credito)

**Actions > Destruir infraestrutura PM-04 > Run workflow** e digitar `DESTRUIR`.
O bucket do state continua existindo (pode apagar manualmente no final do semestre).

## Evidencias para o relatorio

- Print da execucao verde da pipeline (os 2 jobs) e do log do `terraform plan/apply`.
- Print do log do Ansible com o `PLAY RECAP` sem falhas.
- Print da aplicacao aberta pela URL do ALB.
- Print do console da AWS: VMs **sem IP publico**, security groups e o target group *healthy*.
- Print de uma segunda execucao da pipeline sem mudancas no `plan` e com o Ansible
  sem recriar containers (mostra que a configuracao e mantida e idempotente).
- Print de uma mudanca de tag da imagem sendo aplicada pela pipeline.

## Problemas comuns

| Sintoma | Causa provavel |
|---|---|
| `terraform fmt -check` falhou | rode `terraform fmt -recursive` e faca commit |
| Erro de IAM ao criar role (AWS Academy) | descomente `instance_profile_name = "LabInstanceProfile"` no tfvars |
| Ansible fica esperando a conexao | VM ainda nao registrou no SSM; espera ate 10 min. Veja em Systems Manager > Fleet Manager |
| `ExpiredToken` | credenciais do AWS Academy expiraram; atualize os 3 secrets da AWS |
| Target group *unhealthy* | porta ou `health_check_path` diferente da aplicacao |
