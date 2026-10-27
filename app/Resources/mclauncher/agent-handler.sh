#!/bin/zsh
origin= method= target=
IFS=' ' read -r method target _
while IFS= read -r line; do
  line=${line%$'\r'}
  [[ -z $line ]] && break
  [[ ${line:l} == origin:* ]] && origin=${line#*: }
done
cors=$'Access-Control-Allow-Origin: https://mojang\r\nAccess-Control-Allow-Private-Network: true\r\nAccess-Control-Allow-Methods: GET, POST\r\n'
if [[ $origin != https://mojang ]]; then
  printf 'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
  exit 0
fi
if [[ $method == GET && $target == /installed ]]; then
  # whether the game is installed, for the button's Play/Install (app not running)
  exe="${0:h}/game/Dungeons/Binaries/WinGDK/Dungeons-WinGDK-Shipping.exe"
  body='{"installed":false}'; [[ -f $exe ]] && body='{"installed":true}'
  printf 'HTTP/1.1 200 OK\r\n%sContent-Type: application/json\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' "$cors" ${#body} "$body"
  exit 0
fi
printf 'HTTP/1.1 204 No Content\r\n%sContent-Length: 0\r\nConnection: close\r\n\r\n' "$cors"
if [[ $method == POST && $target == /play ]]; then
  # hidden: Minecraft Launcher shows the app's state (MCLauncherLink.swift)
  /usr/bin/open -g -j macd2://play
fi
