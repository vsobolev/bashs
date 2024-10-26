#!/bin/bash

# Обновляем репозитории
echo "Updating repositories..."
sudo apt update -y

# Устанавливаем nala
echo "Installing nala..."
sudo apt install nala -y

# Обновляем систему через nala
echo "Upgrading the system using nala..."
sudo nala upgrade -y

# Устанавливаем необходимые программы через nala
echo "Installing tmux, htop, glances, and docker using nala..."
sudo nala install tmux htop glances docker.io -y

# Завершено
echo "Installation complete!"
