#!/bin/bash

# Переменные
IMAGE_NAME="jupyterhub-docker"
CONTAINER_NAME="jupyterhub-container"
CONFIG_FILE="jupyterhub_config.py"
CHECK_INTERVAL=5 # интервал проверки в секундах
MAX_ATTEMPTS=24  # максимум 2 минуты (24 * 5 секунд = 120 секунд)
DOCKERFILE_CONTENT="
# Dockerfile для установки JupyterHub
FROM ubuntu:24.04

# Установка зависимостей
RUN apt-get update -y && \\
    apt-get install -y python3 python3-pip python3-venv sudo && \\
    apt-get clean

# Создание пользователя jupyterhub
RUN useradd -m -d /srv/jupyterhub -s /bin/bash jupyterhub && \\
    usermod -aG sudo jupyterhub && \\
    mkdir -p /srv/jupyterhub/data && \\
    chown root:jupyterhub /srv/jupyterhub/data && \\
    chmod g+w /srv/jupyterhub/data

# Создание виртуального окружения и установка JupyterHub
RUN python3 -m venv /srv/jupyterhub/venv && \\
    /srv/jupyterhub/venv/bin/pip install --upgrade pip && \\
    /srv/jupyterhub/venv/bin/pip install jupyterhub

# Копирование конфигурационного файла
COPY ${CONFIG_FILE} /srv/jupyterhub/${CONFIG_FILE}
COPY users.txt /srv/jupyterhub/users.txt

# Создание директорий для пользователей
RUN mkdir -p /srv/jupyterhub/brainphill /srv/jupyterhub/student && \\
    chown -R jupyterhub:jupyterhub /srv/jupyterhub/brainphill /srv/jupyterhub/student && \\
    chmod g+w /srv/jupyterhub/brainphill /srv/jupyterhub/student

# Генерация cookie secret для JupyterHub
RUN if [ ! -f /srv/jupyterhub/data/jupyterhub_cookie_secret ]; then \\
        openssl rand -hex 32 > /srv/jupyterhub/data/jupyterhub_cookie_secret; \\
    fi

# Переключение на пользователя jupyterhub
USER jupyterhub

# Рабочая директория
WORKDIR /srv/jupyterhub

# Запуск JupyterHub
CMD [\"jupyterhub\", \"-f\", \"/srv/jupyterhub/${CONFIG_FILE}\"]
"

CONFIG_FILE_CONTENT="
from jupyterhub.auth import Authenticator  # Добавлено исправление

class TxtAuthenticator(Authenticator):
    def authenticate(self, handler, data):
        username = data['username']
        password = data['password']
        with open('/srv/jupyterhub/users.txt', 'r') as f:
            for line in f:
                stored_user, stored_pass = line.strip().split(':')
                if username == stored_user and password == stored_pass:
                    return username
        return None

c.JupyterHub.authenticator_class = TxtAuthenticator
c.Authenticator.admin_users = {'brainphill'}
c.JupyterHub.cookie_secret_file = '/srv/jupyterhub/data/jupyterhub_cookie_secret'
c.JupyterHub.port = 8888
c.JupyterHub.bind_url = 'http://:8888'
c.JupyterHub.spawner_class = 'simple'
c.Spawner.default_url = '/lab'
"

# Создание Dockerfile и конфигурационных файлов
echo "${DOCKERFILE_CONTENT}" > Dockerfile
echo "${CONFIG_FILE_CONTENT}" > ${CONFIG_FILE}
echo "brainphill:password" > users.txt
echo "student:password" >> users.txt

# Сборка Docker образа
echo "Сборка Docker-образа..."
docker build -t ${IMAGE_NAME} .

# Запуск Docker-контейнера
echo "Запуск Docker-контейнера..."
docker run -d -p 8888:8888 --name ${CONTAINER_NAME} ${IMAGE_NAME}

# Проверка успешности запуска контейнера
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    STATUS=$(docker inspect -f '{{.State.Running}}' ${CONTAINER_NAME} 2>/dev/null)
    if [ "$STATUS" == "true" ]; then
        echo "Docker-контейнер успешно запущен и работает."
        echo "JupyterHub доступен по адресу http://<IP-адрес_сервера>:8888"
        exit 0
    fi
    echo "Ожидание запуска контейнера... Попытка $((ATTEMPT+1)) из $MAX_ATTEMPTS"
    sleep $CHECK_INTERVAL
    ATTEMPT=$((ATTEMPT+1))
done

# Если контейнер не запущен
echo "Ошибка: Docker-контейнер не запустился. Проверьте логи для диагностики."
docker logs ${CONTAINER_NAME}
exit 1
