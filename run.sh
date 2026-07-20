#!/bin/bash
cd /Users/douglasoliveira/Desktop/handcursor/HandCursorApp/HandCursorApp

echo "Compilando..."
swiftc Utils/main.swift -o HandCursor

if [ $? -eq 0 ]; then
    echo "Compilado com sucesso. Executando..."
    ./HandCursor
else
    echo "Erro de compilação!"
    exit 1
fi
