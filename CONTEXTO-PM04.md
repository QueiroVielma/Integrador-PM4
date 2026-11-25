# Contexto do Projeto PM-04 (para continuar em outro workspace)

## O trabalho
- Disciplina: PM-04 · Projeto Final | DevOps e Infraestrutura
- Prazo do PDF: **27/11/2026**, anexado na Blackboard (integrantes, análise da demanda,
  decisões de arquitetura, link do repositório Git, evidências de execução)
- Apresentação: primeira semana de dezembro/2026, com todos os integrantes
- Regras do professor:
  - Infra **provisionada pelo Terraform** e **configurada/mantida pelo Ansible**, com
    **todas as mudanças operadas pela pipeline** (não vale rodar Terraform/Ansible na mão)
  - Credenciais em Secrets, nunca no código
  - Imagens com tag explícita (se usar `latest`, provar a atualização)
  - Infra deve ter relação com a demanda do sistema
- Pedido do aluno: fazer de forma simples, com cara de projeto de estudante
- Ainda **não foi enviado**: o link do repositório de aplicações que o professor deu
  e o documento de demanda. Hoje a VM da aplicação sobe um `nginx:1.27.3-alpine` de
  teste no lugar da aplicação real.

## Ambiente do aluno
- Windows: Terraform (provider aws 6.74.0 baixado), AWS CLI com credenciais
  configuradas, Git — tudo no PowerShell
- WSL: só o Ansible
- Chave SSH reaproveitada: `C:\Users\Queiro Ubeda\.ssh\id_rsa` e `id_rsa.pub`
- Região AWS: `us-east-2` (Ohio)
- Projeto de teste antigo em `C:\terraform-projetos` (main.tf, variables.tf etc. na raiz):
  state vazio, nada criado na AWS. Decidido **começar do zero** reaproveitando o estilo.

## Arquitetura decidida
- VPC própria `10.0.0.0/16`
- 2 sub-redes públicas (`10.0.1.0/24`, `10.0.2.0/24`) → só o **ALB** e o **NAT Gateway**
- 1 sub-rede privada (`10.0.10.0/24`) → **VM app** e **VM db** (Ubuntu 24.04, t3.small,
  sem IP público, sem porta 22 aberta)
- Security groups: internet → ALB :80 → app :80 → db :3306
- NAT só para saída (apt, imagens Docker, SSM) — decisão já registrada no ADR-002 do aluno
- Acesso do Ansible às VMs privadas: **SSH dentro de túnel do AWS Session Manager (SSM)**,
  sem bastion. `iam.tf` cria role com `AmazonSSMManagedInstanceCore`
  (ou usa `LabInstanceProfile` se for AWS Academy, via `instance_profile_name`)
- State remoto em S3 com `use_lockfile = true`

## Estrutura do repositório
Pasta: `C:\terraform-projetos\pm04-projeto-final`
```
.github/workflows/pipeline.yml  -> PR: fmt/validate/plan | main: apply + Ansible + teste no ALB
.github/workflows/destroy.yml   -> manual, pede digitar DESTRUIR
terraform/ providers.tf variables.tf terraform.tfvars network.tf security.tf
           iam.tf compute.tf alb.tf outputs.tf
ansible/   ansible.cfg requirements.yml (community.docker) inventory.example.ini
           site.yml group_vars/all.yml roles/{docker,database,app}/tasks/main.yml
README.md  -> passo a passo completo (PowerShell + WSL)
.gitignore -> state, tfplan, inventory.ini, chaves
```
- O inventário real é gerado pela pipeline com os IDs das instâncias (`terraform output`)
- MySQL `mysql:8.4.3` em container, dados em `/opt/mysql/data` na VM db
- App recebe `DB_HOST/DB_*` e `SPRING_DATASOURCE_*` por variável de ambiente
- Senhas lidas de env (`DB_PASSWORD`, `DB_ROOT_PASSWORD`) vindas dos Secrets

## O que já foi feito
- [x] Código Terraform, Ansible e pipeline escritos
- [x] `terraform fmt` + `init -backend=false` + `validate` OK no Windows
      (o `fmt` reformatou o `iam.tf`)
- [x] `ansible-playbook --syntax-check` OK
- [x] Bucket do state criado: **`pm04-tfstate-2026`** (us-east-2) — o aluno apagou o
      primeiro (`pm04-tfstate-seunome-2026`) e recriou com esse nome.
      **Conferir se o versionamento foi ligado no bucket novo.**

## Pendências (em ordem)
1. **Mover a pasta dos workflows** (as ferramentas remotas não podem escrever em
   `.github/workflows`, por isso ela ficou com nome temporário):
   ```powershell
   cd C:\terraform-projetos\pm04-projeto-final
   New-Item -ItemType Directory .github
   Move-Item "mover-para-.github-workflows" .github\workflows
   Get-ChildItem .github\workflows   # deve mostrar destroy.yml e pipeline.yml
   ```
2. Criar repositório vazio no GitHub e fazer o push:
   ```powershell
   git init -b main
   git add .
   git status   # conferir que nenhuma chave/state entrou
   git commit -m "Projeto final PM-04: Terraform + Ansible + pipeline"
   git remote add origin https://github.com/SEU_USUARIO/pm04-projeto-final.git
   git push -u origin main
   ```
   (Incluir o `terraform/.terraform.lock.hcl` no commit é recomendado.)
3. GitHub → Settings → Secrets and variables → Actions:
   | Tipo | Nome | Valor |
   |---|---|---|
   | Variable | `TF_STATE_BUCKET` | `pm04-tfstate-2026` |
   | Secret | `AWS_ACCESS_KEY_ID` | access key |
   | Secret | `AWS_SECRET_ACCESS_KEY` | secret key |
   | Secret | `AWS_SESSION_TOKEN` | só se for AWS Academy |
   | Secret | `SSH_PUBLIC_KEY` | conteúdo de `id_rsa.pub` |
   | Secret | `SSH_PRIVATE_KEY` | conteúdo de `id_rsa` (com BEGIN/END) |
   | Secret | `DB_PASSWORD` | senha do usuário da app |
   | Secret | `DB_ROOT_PASSWORD` | senha do root do MySQL |
4. Rodar a pipeline (Actions → Pipeline PM-04 → Run workflow) e corrigir erros
5. Trocar o nginx pela aplicação real do repositório do professor
   (`app_image`, `app_container_port`, `health_check_path` em `ansible/group_vars/all.yml`
   e `app_port`/`health_check_path` no Terraform)
6. Montar o relatório em PDF e juntar evidências (prints da pipeline verde, PLAY RECAP,
   app no ALB, VMs sem IP público, target group healthy, segunda execução idempotente)
7. Para a apresentação: workflow **Destruir** → pipeline de novo (recria do zero).
   O bucket do state fica fora disso (bootstrap feito uma vez).

## Pontos de atenção conhecidos
- AWS Academy: descomentar `instance_profile_name = "LabInstanceProfile"` no tfvars e
  atualizar os 3 secrets da AWS a cada sessão. Não confirmado se o LabInstanceProfile
  libera o SSM — se o Ansible travar no `wait_for_connection`, investigar isso primeiro.
- O Ansible ignora o `ansible.cfg` em `/mnt/c` no WSL: usar `-i inventory.example.ini`.
- Custo: NAT Gateway e ALB cobram por hora — destruir ao fim de cada teste.
