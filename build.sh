#!/bin/bash

docker-compose down
rm -rf ./master/data/*
rm -rf ./slave/data/*
docker-compose build
docker-compose up -d


echo "Waiting for mysql to get up"
# Give 60 seconds for master and slave to come up
sleep 60

echo "Create MySQL Servers (master / slave repl)"
echo "-----------------"

docker_ip() {
    docker inspect --format '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}

until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -h '$(docker_ip mysql_master)' -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

priv_stmt='GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%" IDENTIFIED BY "mydb_slave_pwd"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -h '$(docker_ip mysql_master)' -u root -e '$priv_stmt'"

until docker-compose exec mysql_slave sh -c 'export MYSQL_PWD=111; mysql -h '$(docker_ip mysql_slave)' -u root -e ";"'
do
    echo "Waiting for mysql_slave database connection..."
    sleep 4
done


MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -h '$(docker_ip mysql_master)' -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

start_slave_stmt="CHANGE MASTER TO MASTER_HOST='$(docker_ip mysql_master)',MASTER_USER='mydb_slave_user',MASTER_PASSWORD='mydb_slave_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=111; mysql -h localhost -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave sh -c "$start_slave_cmd"

docker exec mysql_slave sh -c "export MYSQL_PWD=111; mysql -h localhost -u root -e 'SHOW SLAVE STATUS \G'"
