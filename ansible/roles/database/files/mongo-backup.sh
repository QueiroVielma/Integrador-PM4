#!/bin/sh
# Backup do banco da aplicacao. Usa as credenciais que ja estao dentro do
# container (variaveis de ambiente), entao nenhuma senha fica neste arquivo.
set -eu
DIR=/opt/mongo/backups
RETENCAO="${BACKUP_RETENCAO_DIAS:-7}"
ARQUIVO="$DIR/todo-$(date +%Y%m%d-%H%M%S).archive.gz"

docker exec mongo sh -c 'mongodump --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --db "$MONGO_INITDB_DATABASE" --archive --gzip' > "$ARQUIVO"

# Apaga backups mais antigos que a retencao
find "$DIR" -name 'todo-*.archive.gz' -mtime +"$RETENCAO" -delete

echo "Backup criado: $ARQUIVO ($(du -h "$ARQUIVO" | cut -f1))"
echo "Backups guardados: $(ls -1 "$DIR"/todo-*.archive.gz | wc -l)"
