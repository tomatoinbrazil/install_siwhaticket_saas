#!/bin/bash
#
# functions for setting up app backend
#######################################
# creates POSTGRES db
# Arguments:
#   None
#######################################
backend_postgres_create() {
  print_banner
  printf "${WHITE} 💻 Criando Banco Postgres & Redis Docker Instance...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  usermod -aG docker deploy
  docker run --name redis-${instancia_add} -p ${redis_port}:6379 --restart always --detach --memory=512m --cpus=0.25 redis redis-server --requirepass ${mysql_root_password}

  sleep 2
  sudo su - postgres <<EOF
    createdb ${instancia_add};
    psql
    CREATE USER ${instancia_add} SUPERUSER INHERIT CREATEDB CREATEROLE;
    ALTER USER ${instancia_add} PASSWORD '${mysql_root_password}';
    \q
    exit
EOF

sleep 2

}

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

  # ensure idempotency
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=${frontend_url%%/*}
  frontend_url=https://$frontend_url

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
PROXY_PORT=443
PORT=${backend_port}

DB_TIMEZONE=-03:00
DB_HOST=localhost
DB_DIALECT=postgres
DB_PORT=5432
DB_USER=${instancia_add}
DB_PASS=${mysql_root_password}
DB_NAME=${instancia_add}
DB_TIMEZONE=Europe/Lisbon

MASTER_KEY=

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

REDIS_URI=redis://${mysql_root_password}@127.0.0.1:${redis_port}
REDIS_OPT_LIMITER_MAX=1
REGIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=10000
CONNECTIONS_LIMIT=10000
CLOSED_SEND_BY_ME=true

GERENCIANET_SANDBOX=false

STRIPE_OK_URL=${frontend_url}/financeiro
STRIPE_CANCEL_URL=${frontend_url}/financeiro

MP_NOTIFICATION_URL=${backend_url}/subscription/mercadopagowebhook

PM2_COMMAND='pm2 restart ${instancia_add}-backend'

[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
backend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm install
EOF

  sleep 2
}

#######################################
# compiles backend code
# Arguments:
#   None
#######################################
backend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm run build
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su <<EOF
  cd /home/deploy/${empresa_atualizar}
  pm2 stop ${empresa_atualizar}-backend
  #git reset --hard
  #git config --global safe.directory '*'
  #git pull -f
  cd /home/deploy/${empresa_atualizar}/backend
  npm install
  npm install @types/fs-extra
  rm -rf dist 
  npm run build
  npx sequelize db:migrate
  pm2 start ${empresa_atualizar}-backend --max-memory-restart 2048M --node-args="--max-old-space-size=2048" --cron-restart="0 6 * * *"
  pm2 save 
EOF

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
backend_db_migrate() {
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:migrate
EOF

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:seed:all
EOF

  sleep 2
}

#######################################
# starts backend using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
backend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  sudo pm2 start dist/server.js --name ${instancia_add}-backend
  sudo pm2 reload ${instancia_add}-backend --max-memory-restart 300M --cron-restart="0 6 * * *"
  sudo pm2 save --force
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_hostname=$(echo "${backend_url/https:\/\/}")

sudo su - root << EOF
cat > /etc/nginx/sites-available/${instancia_add}-backend << 'END'
server {
  server_name $backend_hostname;

  proxy_ssl_server_name on;
  underscores_in_headers on;

  proxy_connect_timeout  600;
  proxy_send_timeout     600;
  proxy_read_timeout     600;
  send_timeout           600;
  client_max_body_size  100M;

  
  location / {
    proxy_pass http://127.0.0.1:${backend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_socket_keepalive on;
  }
}
END
ln -s /etc/nginx/sites-available/${instancia_add}-backend /etc/nginx/sites-enabled
EOF

  sleep 2
}
