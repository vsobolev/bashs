#!/bin/bash

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запустите скрипт с правами суперпользователя (sudo)."
  exit
fi

# Функция для установки необходимых пакетов
install_packages() {
  echo "Устанавливаем необходимые пакеты..."
  apt update
  apt install -y mdadm apache2 mariadb-server libapache2-mod-php7.4 \
                 php7.4 php7.4-mysql php7.4-xml php7.4-mbstring php7.4-curl \
                 php7.4-gd php7.4-zip php7.4-intl php7.4-json php7.4-imagick
}

# Функция для настройки RAID массива
setup_raid() {
  echo "Доступные диски:"
  lsblk -d -e 7,11 | grep -v "$(df / | tail -1 | awk '{print $1}' | cut -d'/' -f3)"

  echo "Введите имя первого диска для RAID (например, sdb):"
  read first_disk

  echo "Введите имя второго диска для RAID (например, sdc):"
  read second_disk

  echo "Создаем RAID 1 массив на $first_disk и $second_disk..."
  mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 /dev/$first_disk /dev/$second_disk

  echo "Создаем файловую систему ext4 на RAID массиве..."
  mkfs.ext4 /dev/md0

  echo "Монтируем RAID массив в /mnt/raid..."
  mkdir -p /mnt/raid
  mount /dev/md0 /mnt/raid

  echo "/dev/md0    /mnt/raid    ext4    defaults    0    0" >> /etc/fstab

  echo "Создаем конфигурационный файл для mdadm..."
  mdadm --detail --scan | tee -a /etc/mdadm/mdadm.conf
  update-initramfs -u

  echo "RAID массив успешно настроен!"
}

# Функция для настройки отдельного диска
setup_single_disk() {
  echo "Доступные диски:"
  lsblk -d -e 7,11 | grep -v "$(df / | tail -1 | awk '{print $1}' | cut -d'/' -f3)"

  echo "Введите имя диска для подключения (например, sdb):"
  read single_disk

  echo "Создаем файловую систему ext4 на /dev/$single_disk..."
  mkfs.ext4 /dev/$single_disk

  echo "Монтируем диск в /mnt/owncloud_data..."
  mkdir -p /mnt/owncloud_data
  mount /dev/$single_disk /mnt/owncloud_data

  echo "/dev/$single_disk    /mnt/owncloud_data    ext4    defaults    0    0" >> /etc/fstab

  echo "Диск успешно подключен!"
}

# Функция для установки ownCloud
install_owncloud() {
  local ip_address
  ip_address=$(hostname -I | awk '{print $1}')  # Получаем первый IP адрес

  echo "Скачиваем и устанавливаем ownCloud..."
  wget https://download.owncloud.org/community/owncloud-complete-latest.tar.bz2
  tar -xjf owncloud-complete-latest.tar.bz2
  mv owncloud /var/www/owncloud

  echo "Устанавливаем права доступа..."
  chown -R www-data:www-data /var/www/owncloud
  chmod -R 755 /var/www/owncloud

  echo "Настраиваем базу данных..."
  mysql -u root -e "CREATE DATABASE owncloud;"
  mysql -u root -e "CREATE USER 'ownclouduser'@'localhost' IDENTIFIED BY 'password';"
  mysql -u root -e "GRANT ALL PRIVILEGES ON owncloud.* TO 'ownclouduser'@'localhost';"
  mysql -u root -e "FLUSH PRIVILEGES;"

  echo "Настраиваем Apache..."
  cat <<EOF > /etc/apache2/sites-available/owncloud.conf
<VirtualHost *:80>
    DocumentRoot /var/www/owncloud
    ServerName $ip_address

    <Directory /var/www/owncloud/>
        Options +FollowSymlinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    <IfModule mod_dav.c>
        Dav off
    </IfModule>
</VirtualHost>
EOF

  a2ensite owncloud.conf
  a2enmod rewrite headers env dir mime
  systemctl restart apache2

  echo "ownCloud успешно установлен! Перейдите на http://$ip_address для завершения настройки."
}

# Главная функция
main() {
  echo "Хотите ли вы создать RAID массив? (да/нет)"
  read create_raid

  if [ "$create_raid" == "да" ]; then
    setup_raid
    data_dir="/mnt/raid"
  else
    setup_single_disk
    data_dir="/mnt/owncloud_data"
  fi

  # Установка пакетов и ownCloud
  install_packages
  install_owncloud

  echo "Настройка завершена! Каталог данных ownCloud настроен в $data_dir."
}

# Запуск основной функции
main
