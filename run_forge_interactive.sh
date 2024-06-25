#!/bin/bash

# Función para pedir la dirección y el nombre
function clone_contract() {
    read -p "Introduce la dirección del contrato: " address
    read -p "Introduce el nombre del contrato: " name
    forge clone $address $name --no-commit
}

# Variable para controlar el bucle
continue_cloning=true

# Bucle para seguir clonando contratos hasta que el usuario decida parar
while $continue_cloning; do
    clone_contract
    read -p "¿Quieres clonar otro contrato? (s/n): " choice
    if [[ "$choice" != "s" && "$choice" != "S" ]]; then
        continue_cloning=false
    fi
done

echo "Todos los contratos han sido clonados."
