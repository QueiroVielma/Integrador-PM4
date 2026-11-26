#!/bin/sh
# Restaura o ULTIMO backup em um banco separado ("restore-teste"), confere
# quantas tarefas voltaram e apaga o banco de teste.
# A lista da demonstracao (banco todo-app) nao e tocada.
set -eu
ULTIMO=$(ls -1t /opt/mongo/backups/todo-*.archive.gz | head -n 1)
echo "Restaurando $ULTIMO no banco isolado restore-teste"

docker exec -i mongo sh -c 'mongorestore --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip --drop --nsFrom="$MONGO_INITDB_DATABASE.*" --nsTo="restore-teste.*"' < "$ULTIMO"

docker exec mongo sh -c 'mongosh --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "
  const original = db.getSiblingDB(process.env.MONGO_INITDB_DATABASE).todos.countDocuments();
  const teste = db.getSiblingDB(\"restore-teste\");
  print(\"Tarefas no backup restaurado: \" + teste.todos.countDocuments());
  print(\"Tarefas na lista atual:       \" + original);
  teste.dropDatabase();
  print(\"Banco restore-teste removido\");
"'
