#!/bin/bash

set -e  

APP_NAME="smartbag-app-api"
GIT_REPO="https://github.com/CleisonFreitas/smartbag-app-api.git"
INSTALL_DIR="./$APP_NAME"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

if [ "$1" == "--force" ]; then
  echo -e "${GREEN}🚀 Limpando instalação anterior...${NC}"
  rm -rf "$INSTALL_DIR"
fi

echo -e "${GREEN}🚀 Iniciando instalação da Smartbag API...${NC}"

# 1. Atualizar pacotes e instalar apenas o essencial
echo -e "${GREEN}🔍 Verificando se Git, Docker e Docker Compose já estão instalados...${NC}"

if ! command -v git &> /dev/null; then
  echo -e "${GREEN}📥 Instalando Git...${NC}"
  sudo apt install -y git
else
  echo -e "${GREEN}✅ Git já instalado.${NC}"
fi

if ! command -v docker &> /dev/null; then
  echo -e "${GREEN}📥 Instalando Docker...${NC}"
  sudo apt update -y
  sudo apt install -y docker.io
  sudo systemctl enable docker
  sudo systemctl start docker
else
  echo -e "${GREEN}✅ Docker já instalado.${NC}"
fi

if ! command -v docker-compose &> /dev/null; then
  echo -e "${GREEN}📥 Instalando Docker Compose...${NC}"
  sudo apt install -y docker-compose
else
  echo -e "${GREEN}✅ Docker Compose já instalado.${NC}"
fi

# 2. Iniciar Docker
if ! systemctl is-active --quiet docker; then
  echo -e "${GREEN}🐳 Iniciando Docker...${NC}"
  sudo systemctl enable docker
  sudo systemctl start docker
else
  echo -e "${GREEN}✅ Docker já está em execução.${NC}"
fi

# 3. Clonar o repositório
echo -e "${GREEN}📦 Clonando o repositório Laravel...${NC}"
if [ -d "$INSTALL_DIR" ]; then
  echo -e "${RED}❗ O diretório $INSTALL_DIR já existe. Abortando.${NC}"
  exit 1
fi

git clone "$GIT_REPO" "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 4. Instalar dependências do projeto com Composer no container (sem depender do host)
echo -e "${GREEN}📦 Instalando dependências com Composer (via Docker)...${NC}"
docker run --rm \
    -u "$(id -u):$(id -g)" \
    -v "$(pwd):/var/www/html" \
    -w /var/www/html \
    laravelsail/php84-composer:latest \
    composer install

# 5. Criar .env se necessário
if [ ! -f .env ]; then
  echo -e "${GREEN}⚙️ Criando .env a partir de .env.example...${NC}"
  cp .env.example .env
fi

# 6. Criar e preencher .env.testing
if [ -f ".env.testing.example" ]; then
  echo -e "${GREEN}🧪 Criando .env.testing...${NC}"
  cp .env.testing.example .env.testing

  generate_random() {
  tr -dc 'a-zA-Z0-9#@' </dev/urandom | head -c 14
}

# Ler os valores do .env original
DB_USERNAME=$(grep "^DB_USERNAME=" .env | cut -d '=' -f2-)
DB_PASSWORD=$(grep "^DB_PASSWORD=" .env | cut -d '=' -f2-)

# Se estiver vazio, gera um novo e atualiza o .env original
if [ -z "$DB_USERNAME" ]; then
  DB_USERNAME=$(generate_random)
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env
fi

if [ -z "$DB_PASSWORD" ]; then
  DB_PASSWORD=$(generate_random)
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env
fi

  sed -i "s/^DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env.testing
  sed -i "s/^DB_HOST=.*/DB_HOST=mysql/" .env.testing
  sed -i "s/^DB_PORT=.*/DB_PORT=3306/" .env.testing
  sed -i "s/^DB_DATABASE=.*/DB_DATABASE=smartbag_db/" .env.testing
  sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USERNAME/" .env.testing
  sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=$DB_PASSWORD/" .env.testing
  sed -i "s/^FORWARD_DB_PORT=.*/FORWARD_DB_PORT=3307/" .env.testing
else
  echo -e "${RED}⚠️ Arquivo .env.testing.example não encontrado.${NC}"
fi

# 7. Subir containers com Sail
echo -e "${GREEN}🚀 Subindo containers com Laravel Sail...${NC}"
./vendor/bin/sail up -d

# 8. Gerar chave da aplicação
echo -e "${GREEN}🔑 Gerando chave da aplicação...${NC}"
./vendor/bin/sail artisan key:generate

# 9. Rodar migrations padrão
echo -e "${GREEN}🛠️ Rodando migrations...${NC}"
./vendor/bin/sail artisan migrate:fresh --seed

# 10. Rodar migrations de teste
echo -e "${GREEN}🧪 Rodando migrations de teste...${NC}"
./vendor/bin/sail artisan migrate --env=testing

echo -e "${GREEN}✅ Deploy concluído com sucesso!${NC}"

# Bonus. rodar testes
./vendor/bin/sail test --env=testing

# Extra.
# Perguntar se deseja instalar o app Flutter
echo
read -p "📱 Deseja instalar o app Flutter também? (s/n): " instalar_flutter

if [[ "$instalar_flutter" == "s" || "$instalar_flutter" == "S" ]]; then
  echo -e "${GREEN}🔍 Verificando versão do Flutter...${NC}"

  if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter não está instalado. Instale o SDK antes de prosseguir.${NC}"
    exit 1
  fi

  FLUTTER_INFO=$(flutter --version)
  FLUTTER_VERSION=$(echo "$FLUTTER_INFO" | grep 'Flutter' | awk '{print $2}')
  FLUTTER_CHANNEL=$(echo "$FLUTTER_INFO" | grep 'channel' | awk -F 'channel ' '{print $2}' | awk '{print $1}')

  REQUIRED_VERSION="3.29.0"
  REQUIRED_CHANNEL="stable"

  if [[ "$FLUTTER_VERSION" != "$REQUIRED_VERSION" || "$FLUTTER_CHANNEL" != "$REQUIRED_CHANNEL" ]]; then
    echo -e "${RED}❌ Versão incompatível do Flutter.${NC}"
    echo -e "    Versão necessária: ${GREEN}$REQUIRED_VERSION • channel $REQUIRED_CHANNEL${NC}"
    echo -e "    Versão atual:      ${RED}$FLUTTER_VERSION • channel $FLUTTER_CHANNEL${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Versão do Flutter válida: $FLUTTER_VERSION ($FLUTTER_CHANNEL)${NC}"
  
  # Clonar e instalar o app
  FLUTTER_REPO="https://github.com/CleisonFreitas/smartbag-app-ui.git"
  FLUTTER_DIR="../smartbag-app"

  if [ -d "$FLUTTER_DIR" ]; then
    echo -e "${RED}❗ O diretório do app já existe em $FLUTTER_DIR. Abortando instalação.${NC}"
  else
    git clone "$FLUTTER_REPO" "$FLUTTER_DIR"
    cd "$FLUTTER_DIR"

    echo -e "${GREEN}📦 Instalando dependências do Flutter...${NC}"
    flutter pub get

    echo -e "${GREEN}✅ App Flutter instalado com sucesso em $FLUTTER_DIR.${NC}"
  fi

else
  echo -e "${GREEN}🚫 Instalação do app Flutter ignorada.${NC}"
fi


