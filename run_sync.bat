@echo off
:: Launches sync.ps1 without needing to change PowerShell's execution policy globally.
:: sync.ps1 handles its own UAC elevation prompt, so this just needs to run once.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1"
