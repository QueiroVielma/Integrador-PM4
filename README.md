# ToDo App na AWS — PM-04

Lista de tarefas (frontend React/Nginx, API Node.js/Express e MongoDB) implantada na **AWS** com **Terraform**, **Ansible** e **GitHub Actions**. A demanda é a da "Feira de Profissões" ([escopo](https://github.com/LaercioMLB/todo-app/blob/main/escopo.pdf)).

Endereço: **https://todo.martinazzo.dev.br**

> ⚠️ **O ambiente gera custo** (≈ US$ 0,12/hora com tudo ligado, quase tudo do NAT Gateway e do load balancer). Deixe ligado só para testes e apresentação e rode o **Destruir** ao terminar.

## Arquitetura

```
Internet ──443 (80→301)──▶ ALB ──80──▶ VM app (privada): Nginx + React → API ──27017──▶ VM db (privada): MongoDB
VMs ──NAT──▶ internet (pacotes, imagens do GHCR, Session Manager)
```

- **VPC** `10.0.0.0/16` em `us-east-2`: 2 sub-redes públicas (ALB e NAT) e 1 privada (as duas VMs).
- **2 VMs** Ubuntu 24.04 t3.small, sem IP público: `vm-pm04-app` e `vm-pm04-db`.
- **Domínio** `martinazzo.dev.br` (Registro.br) delegado para o Route 53, com certificado do ACM no ALB.
- **Acesso às VMs** só pelo Session Manager. Nenhuma porta 22 aberta.
- **Backup** do MongoDB todo dia às 03:00, com 7 dias de retenção.

| Pasta | Conteúdo |
|---|---|
| `app/` | Código da aplicação e `docker-compose.yaml` para rodar local |
| `terraform/` | Rede, security groups, IAM, VMs, ALB, domínio e certificado |
| `ansible/` | `site.yml` (deploy), `operacao.yml` (rotinas) e os roles `sistema`, `docker`, `database`, `app` |
| `.github/workflows/` | `pipeline.yml`, `operacao.yml`, `destroy.yml` |

## Pré-requisitos

- Conta AWS e AWS CLI configurada (região `us-east-2`)
- Repositório no GitHub com Actions habilitado
- Par de chaves SSH:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/pm04
```

## 1. Preparação (uma vez)

Duas coisas ficam fora do Terraform, porque não podem ser apagadas pelo destroy:

- **Bucket do state** `pm04-tfstate-2026` (versionado), criado pela CLI.
- **Zona DNS** `martinazzo.dev.br` no Route 53. Os nameservers dela foram cadastrados no Registro.br:

```
ns-1296.awsdns-34.org
ns-22.awsdns-02.com
ns-1613.awsdns-09.co.uk
ns-850.awsdns-42.net
```

## 2. Configuração do GitHub

Em **Settings → Secrets and variables → Actions**:

| Tipo | Nome | Valor |
|---|---|---|
| Secret | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Chave do usuário IAM da pipeline |
| Secret | `AWS_SESSION_TOKEN` | Só se usar AWS Academy |
| Secret | `SSH_PUBLIC_KEY` | Conteúdo de `~/.ssh/pm04.pub` |
| Secret | `SSH_PRIVATE_KEY` | Conteúdo de `~/.ssh/pm04` |
| Secret | `DB_PASSWORD` | Senha do usuário `todo` do MongoDB |
| Secret | `DB_ROOT_PASSWORD` | Senha do `root` do MongoDB |
| Variable | `TF_STATE_BUCKET` | `pm04-tfstate-2026` |

## 3. Criar ou atualizar o ambiente

A pipeline roda sozinha a cada push na `main` (em `app/`, `terraform/` ou `ansible/`) ou manualmente em **Actions → Pipeline PM-04 → Run workflow**:

| Parâmetro | Padrão | Efeito |
|---|---|---|
| `environment` | `prod` | Ambiente (`dev`, `homolog`, `prod`), cada um com state próprio |
| `instance_name` | `vm-pm04` | Nome das VMs |
| `app_instance_type` / `db_instance_type` | `t3.small` | Tamanho das VMs (troca sem recriar, dados preservados) |
| `docker_image` / `docker_tag` | vazio | Imagem e versão. Vazio = constrói o commit atual. Um SHA antigo faz rollback |
| `update_os` | `false` | Atualizar o sistema operacional |
| `extra_packages` | vazio | Pacotes extras do apt, ex.: `tcpdump traceroute` |

O fluxo é: build das imagens no GHCR → `terraform plan`/`apply` → Ansible pelo Session Manager → teste em `https://todo.martinazzo.dev.br/health`. O resumo da execução mostra os parâmetros, o resultado do plan e o PLAY RECAP.

**Ordem do Ansible:**
1. Pacotes e atualizações (`sistema`)
2. Docker (`docker`)
3. MongoDB, usuário da aplicação e backup (`database`)
4. API e frontend na versão pedida, com verificação no final (`app`)

## 4. Operação

**Actions → Operacao PM-04**: `saude`, `logs`, `reiniciar`, `backup`, `testar-restauracao` e `limpar-lista`.

## 5. Destruir o ambiente

**Actions → Destruir infraestrutura PM-04**, escolhendo o ambiente e digitando `DESTRUIR`. Apaga tudo, inclusive o banco. O bucket do state e a zona DNS continuam.

## Executar localmente

```bash
cd app
docker compose up --build -d
```

Acesse http://localhost.
