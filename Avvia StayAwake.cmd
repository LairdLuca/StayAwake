@echo off
rem Avvia StayAwake con i parametri di default (input ogni 10 minuti).
rem Il tool vive nell'area di notifica: per fermarlo, tasto destro sull'icona -> Esci.
rem Parametri opzionali: -IntervalloMinuti 12  -DurataOre 8  -Console
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0StayAwake.ps1" %*
