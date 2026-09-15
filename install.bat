@echo off
REM Install the prom module onto the KDB-X module search path so it loads with:  prom:use`prom
REM
REM   install.bat            install into the first entry of q's default module search path
REM                          (asks q for .Q.m.SP; falls back to %QHOME%\mod if q is not on PATH)
REM   install.bat <dir>      install into <dir>\prom instead
REM
REM To run from a checkout without installing, set QPATH to the repository root instead.

SET SRC_DIR=%~dp0prom
IF NOT EXIST "%SRC_DIR%\init.q" (
    ECHO ERROR: %SRC_DIR%\init.q not found; run this script from the repository root
    EXIT /B 1
)

SET MOD_DIR=%~1

IF "%MOD_DIR%"=="" (
    WHERE q >NUL 2>&1
    IF NOT ERRORLEVEL 1 (
        FOR /F "usebackq delims=" %%P IN (`ECHO -1 first .Q.m.SP; exit 0 ^| q -q 2^>NUL`) DO (
            IF "%MOD_DIR%"=="" SET MOD_DIR=%%P
        )
    )
)

IF "%MOD_DIR%"=="" (
    IF "%QHOME%"=="" (
        ECHO ERROR: could not determine the module search path ^(q not on PATH and QHOME not set^).
        ECHO        Re-run as: install.bat ^<module search dir^>
        EXIT /B 1
    )
    SET MOD_DIR=%QHOME%\mod
)

SET DEST_DIR=%MOD_DIR%\prom
ECHO Installing prom module to %DEST_DIR% ...
IF NOT EXIST "%DEST_DIR%" MKDIR "%DEST_DIR%"
COPY /Y "%SRC_DIR%\*.q" "%DEST_DIR%\" >NUL
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: Copy failed
    EXIT /B %ERRORLEVEL%
)

ECHO Install complete. Load with:  prom:use`prom
EXIT /B 0
