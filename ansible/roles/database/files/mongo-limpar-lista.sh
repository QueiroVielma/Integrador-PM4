#!/bin/sh
# Prepara uma lista nova para a proxima apresentacao.
# Faz backup ANTES de apagar, para poder voltar se foi engano.
set -eu
/usr/local/bin/mongo-backup.sh

docker exec mongo sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$MONGO_INITDB_DATABASE" --eval "
  const apagadas = db.todos.deleteMany({}).deletedCount;
  db.todos.insertMany([
    { text: \"Bem-vindo a Feira de Profissoes!\", completed: false },
    { text: \"Adicione uma tarefa\", completed: false },
    { text: \"Clique no texto para concluir\", completed: true },
  ]);
  print(\"Tarefas apagadas: \" + apagadas + \" | lista nova com \" + db.todos.countDocuments() + \" tarefas\");
"'
