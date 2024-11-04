#!/bin/bash

# Переменные
JUPYTERHUB_DIR="/srv/jupyterhub"
JUPYTERHUB_VENV="$JUPYTERHUB_DIR/venv"
CONFIG_FILE="$JUPYTERHUB_DIR/jupyterhub_config.py"
USERS_FILE="$JUPYTERHUB_DIR/users.txt"

# Проверка и установка зависимостей
echo "Установка зависимостей..."
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nodejs npm

# Создание директорий для JupyterHub
echo "Создание директорий..."
sudo mkdir -p $JUPYTERHUB_DIR
sudo chown -R $(whoami):$(whoami) $JUPYTERHUB_DIR

# Установка виртуального окружения и JupyterHub
echo "Настройка виртуального окружения..."
python3 -m venv $JUPYTERHUB_VENV
source $JUPYTERHUB_VENV/bin/activate

echo "Установка JupyterHub и 'configurable-http-proxy'..."
pip install wheel jupyterhub notebook
npm install -g configurable-http-proxy

# Проверка установки configurable-http-proxy
if ! command -v configurable-http-proxy &> /dev/null; then
    echo "Ошибка: configurable-http-proxy не установлен. Убедитесь, что npm работает корректно."
    exit 1
fi

# Генерация файла конфигурации
echo "Создание файла конфигурации JupyterHub..."
if [ ! -f "$CONFIG_FILE" ]; then
    jupyterhub --generate-config -f $CONFIG_FILE
else
    echo "Файл конфигурации уже существует. Пропуск генерации."
fi

# Настройка пользовательской аутентификации
echo "Настройка пользовательской аутентификации..."
cat <<EOT >> $CONFIG_FILE
from jupyterhub.auth import Authenticator

class TxtAuthenticator(Authenticator):
    async def authenticate(self, handler, data):
        username = data["username"]
        password = data["password"]
        with open("$USERS_FILE", "r") as f:
            for line in f:
                stored_user, stored_pass = line.strip().split(":")
                if stored_user == username and stored_pass == password:
                    return username
        return None

c.JupyterHub.authenticator_class = TxtAuthenticator
EOT

# Создание файла users.txt для хранения данных пользователей
echo "Создание файла users.txt..."
echo "brainphill:secure_password" > $USERS_FILE

# Настройка службы systemd для JupyterHub
echo "Создание службы systemd для JupyterHub..."
sudo tee /etc/systemd/system/jupyterhub.service > /dev/null <<EOT
[Unit]
Description=JupyterHub Service
After=network.target

[Service]
Type=simple
ExecStart=$JUPYTERHUB_VENV/bin/jupyterhub -f $CONFIG_FILE
WorkingDirectory=$JUPYTERHUB_DIR
User=$(whoami)
Group=$(whoami)
Restart=always

[Install]
WantedBy=multi-user.target
EOT

# Перезагрузка systemd и включение автозапуска JupyterHub
echo "Перезагрузка systemd и включение автозапуска JupyterHub..."
sudo systemctl daemon-reload
sudo systemctl enable jupyterhub.service
sudo systemctl start jupyterhub.service

# Проверка статуса службы
echo "Проверка статуса службы JupyterHub..."
sudo systemctl status jupyterhub.service --no-pager
if systemctl is-active --quiet jupyterhub.service; then
    echo "JupyterHub успешно запущен! Он доступен по адресу http://<IP-адрес_сервера>:8888"
else
    echo "Ошибка запуска JupyterHub. Проверьте логи для диагностики."
fi
