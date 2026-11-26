# PM-04 · Projeto Final de DevOps e Infraestrutura

Implantação do **ToDo App** (demanda "Feira de Profissões",
[escopo original](https://github.com/LaercioMLB/todo-app/blob/main/escopo.pdf)) na AWS:

- infraestrutura provisionada com **Terraform**
- VMs configuradas e mantidas com **Ansible**
- tudo operado pelo **GitHub Actions** (ninguém roda Terraform/Ansible na mão)

## Arquitetura

```
              Visitantes (navegador)
                      │ HTTPS
                      ▼
            CloudFront (https://xxxx.cloudfront.net)
                      │ HTTP
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
| REQ-05 Publicação | CloudFront dá URL HTTPS sem precisar comprar domínio; `/todos` e a interface no mesmo endereço |
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
  network.tf security.tf iam.tf compute.tf alb.tf cloudfront.tf outputs.tf
ansible/
  site.yml                -> deploy completo
  operacao.yml            -> rotinas do dia a dia
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
2. **Provisionar (Terraform)**: fmt, validate, plan e apply. Na primeira vez leva uns 10 min por causa do NAT, do ALB e do CloudFront.
3. **Configurar e implantar (Ansible)**: instala o Docker, sobe o MongoDB, faz um backup antes de atualizar e sobe a nova versão da aplicação.
4. **Teste final**: chama `https://.../health` e `/todos`. A URL e a versão aparecem no resumo da execução.

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
- O CloudFront demora alguns minutos para ser desativado, então o destroy é mais lento que o apply.

### Rodar localmente

```bash
cd app
docker compose up --build -d   # abrir http://localhost
```

## Evidências para o relatório

| Critério | Evidência |
|---|---|
| ACE-01/06 | print da pipeline verde (3 jobs) com a versão no resumo |
| ACE-02 | console EC2 mostrando as 2 VMs sem IP público |
| ACE-03 | security group do db (27017 só do sg-app) e `curl`/`nc` externo falhando |
| ACE-04 | celular abrindo a URL HTTPS: cadastrar, concluir, reabrir, excluir, recarregar |
| ACE-05 | criar tarefa, rodar `reiniciar`, rodar a pipeline de novo: a tarefa continua lá |
| ACE-07 | log das ações `backup` e `testar-restauracao` |
| ACE-08 | log das ações `saude` e `logs`; segredos aparecem como `***` |

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| `terraform fmt -check` falhou | rode `terraform fmt -recursive` e faça commit |
| Erro de permissão no CloudFront | o usuário IAM precisa de permissão no CloudFront (ou `AdministratorAccess`) |
| Conta nova sem permissão para CloudFront | coloque `habilitar_https = false` no tfvars (fica só HTTP pelo ALB) |
| Ansible fica esperando a conexão | a VM ainda não registrou no SSM; espere até 10 min (Systems Manager > Fleet Manager) |
| Target group *unhealthy* | a API não conecta no banco: rode a ação `logs` |
| `denied` ao baixar a imagem | rode a pipeline completa (o login no ghcr.io usa o token da própria execução) |
