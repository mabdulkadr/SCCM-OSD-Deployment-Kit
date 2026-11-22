@ECHO OFF
TITLE SCCM OSD Deployment Kit - GUI tools
ECHO Select a GUI tool:
ECHO   1 = Deployment Wizard
ECHO   2 = Pre-Staging Tool
ECHO   3 = Start Deployment Wizard (task sequence wrapper)
CHOICE /C 123 /N /M "Enter 1, 2 or 3: "
IF ERRORLEVEL 3 GOTO WRAPPER
IF ERRORLEVEL 2 GOTO PRESTAGE
POWERSHELL.EXE -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DeploymentWizard\Invoke-DeploymentWizardUI.ps1"
GOTO END
:PRESTAGE
POWERSHELL.EXE -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0SCCM-OSD-PreStaging\SCCM-OSD-PreStaging.ps1"
GOTO END
:WRAPPER
POWERSHELL.EXE -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0DeploymentWizard\Start-DeploymentWizard.ps1"
:END
IF ERRORLEVEL 1 ECHO The script exited with an error.
PAUSE
