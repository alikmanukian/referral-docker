#!/bin/bash

OLD_CONTAINER_NAME="encryption"
DATA_FOLDER="data"

# Rename old image
IMAGE=$(docker images --format "{{.Repository}}:{{.Tag}}" | tail -n +2 | grep 'referral-factory/$OLD_CONTAINER_NAME:latest')
[[ ! -z "$IMAGE" ]] && docker tag $IMAGE referral-factory/$OLD_CONTAINER_NAME:v1 && docker image rm $IMAGE

# 3. Check encryption container exists
CONTAINER_EXISTS=$(docker ps --format "{{.Names}}" | awk 'NR>1' | grep $OLD_CONTAINER_NAME)

# 3. export db from old container
if [ ! -z "$CONTAINER_EXISTS" ] && [ "$CONTAINER_EXISTS" == $OLD_CONTAINER_NAME ]; then
  # Check db connection type on old container
  HOST=$(docker exec $OLD_CONTAINER_NAME cat /var/www/html/app/.env | grep DB_HOST)

  if [ $HOST == "DB_HOST=127.0.0.1" ]; then
    # export db from old container
    USERNAME=$(envInEncryption "DB_USERNAME") && \
    PASSWORD=$(envInEncryption "DB_PASSWORD") && \
    DATABASE=$(envInEncryption "DB_DATABASE") && \
    docker exec -e DB_USERNAME="$USERNAME" -e DB_PASSWORD="$PASSWORD" -e DB_DATABASE="$DATABASE" \
           encryption mysqldump -u"$USERNAME" -p"$PASSWORD" "$DATABASE" > "$DATA_FOLDER/db.sql"

    # copy mysql volume from container
    # docker cp $OLD_CONTAINER_NAME:/var/lib/mysql $DATA_FOLDER/mysql
    # copy app folder from docker container to host
    # docker cp $OLD_CONTAINER_NAME:/var/www/html/app $DATA_FOLDER/app
  fi

  # stop old container
  docker stop $OLD_CONTAINER_NAME
fi