#!/bin/bash

docker-compose down
rm -rf ./master/data/*
rm -rf ./slave/data_1/*
rm -rf ./slave/data_2/*
docker-compose build
docker-compose up -d

until docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_master database connection..."
    sleep 4
done

priv_stmt='GRANT REPLICATION SLAVE ON *.* TO "mydb_slave_user"@"%" IDENTIFIED BY "mydb_slave_pwd"; FLUSH PRIVILEGES;'
docker exec mysql_master sh -c "export MYSQL_PWD=111; mysql -u root -e '$priv_stmt'"

until docker-compose exec mysql_slave_1 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave_1 database connection..."
    sleep 4
done

until docker-compose exec mysql_slave_2 sh -c 'export MYSQL_PWD=111; mysql -u root -e ";"'
do
    echo "Waiting for mysql_slave_2 database connection..."
    sleep 4
done

docker-ip() {
    docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$@"
}

MS_STATUS=`docker exec mysql_master sh -c 'export MYSQL_PWD=111; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $MS_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $MS_STATUS | awk '{print $7}'`

start_slave_stmt="CHANGE MASTER TO MASTER_HOST='$(docker-ip mysql_master)',MASTER_USER='mydb_slave_user',MASTER_PASSWORD='mydb_slave_pwd',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_slave_cmd='export MYSQL_PWD=111; mysql -u root -e "'
start_slave_cmd+="$start_slave_stmt"
start_slave_cmd+='"'
docker exec mysql_slave_1 sh -c "$start_slave_cmd"
docker exec mysql_slave_2 sh -c "$start_slave_cmd"

docker exec mysql_slave_1 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"
docker exec mysql_slave_2 sh -c "export MYSQL_PWD=111; mysql -u root -e 'SHOW SLAVE STATUS \G'"

docker exec -i mysql_master sh -c "mysql -uroot -p111 mydb -e 'DROP TABLE cameras;'";
docker exec -i mysql_master sh -c "mysql -uroot -p111 mydb -e 'CREATE TABLE cameras (id int(11) NOT NULL AUTO_INCREMENT, brand varchar(32) NOT NULL DEFAULT \"\", model varchar(255) NOT NULL DEFAULT \"\", alt_search_words varchar(1500) NOT NULL DEFAULT \"\", PRIMARY KEY (id), KEY brand (brand)) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT=\"all cameras\";'";

for i in {1..100}
do
  echo "inserted $i cameras"
  docker exec -i mysql_master sh -c "mysql -uroot -p111 mydb -e 'INSERT INTO cameras VALUES ($i,\"canon\",\"Canon\",0);'";
  sleep 1
done