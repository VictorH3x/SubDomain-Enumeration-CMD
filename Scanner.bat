@ECHO OFF
CLS

:: ============================================================================
:: --- MAIN SCRIPT EXECUTION ---
:: ============================================================================

:MainMenu
CLS
ECHO ======================================
ECHO     CMD Subdomain Enumerator
ECHO ======================================
ECHO.

:GetDomain
SET "targetDomain="
SET /P "targetDomain=Please enter the domain you want to scan (e.g., example.com): "
IF NOT DEFINED targetDomain (
    ECHO.
    ECHO Domain cannot be empty. Please try again.
    TIMEOUT /T 2 /NOBREAK >nul
    GOTO GetDomain
)

:ChooseScan
CLS
ECHO Target Domain: %targetDomain%
ECHO --------------------------------------
ECHO Please choose a scan type:
ECHO.
ECHO [1] Passive Scan (via Certificate Transparency Logs)
ECHO [2] Active Scan (via Wordlist Brute-Force)
ECHO [3] Zone Transfer Scan (Checks for a specific misconfiguration)
ECHO [Q] Quit
ECHO.

CHOICE /C 123Q /N /M "Enter your choice:"

IF ERRORLEVEL 4 GOTO Quit
IF ERRORLEVEL 3 GOTO ZoneTransferScan
IF ERRORLEVEL 2 GOTO ActiveScan
IF ERRORLEVEL 1 GOTO PassiveScan


:: ============================================================================
:: --- SCANNING LOGIC SECTIONS ---
:: ============================================================================

:PassiveScan
ECHO.
ECHO [*] Starting Passive Scan...
ECHO [*] This requires 'curl.exe', available in modern Windows.
ECHO [*] Querying crt.sh API...
ECHO.

curl -s "https://crt.sh/?q=%%.%targetDomain%&output=json" | findstr /I "name_value" > temp_results.txt

ECHO --- Discovered Subdomains (may include duplicates) ---
FOR /F "tokens=2 delims=:" %%A IN (temp_results.txt) DO (
    FOR /F "tokens=1 delims=," %%B IN ("%%A") DO (
        ECHO %%~B
    )
)
IF EXIST temp_results.txt DEL temp_results.txt
GOTO FinalPause

:ActiveScan
ECHO.
ECHO [*] Starting Active Scan...
SET "wordlistPath="
SET /P "wordlistPath=Please enter the full path to your subdomain wordlist file: "

IF NOT EXIST "%wordlistPath%" (
    ECHO.
    ECHO ERROR: The specified wordlist file was not found.
    GOTO FinalPause
)

ECHO.
ECHO --- Searching for active subdomains... ---
FOR /F "delims=" %%G IN (%wordlistPath%) DO (
    ECHO Checking: %%G.%targetDomain%
    nslookup %%G.%targetDomain% 2>nul | findstr /I "Non-existent domain" >nul || (
        ECHO [+] Found: %%G.%targetDomain%
    )
)
GOTO FinalPause

:: --- THIS SECTION HAS BEEN REWRITTEN FOR ROBUSTNESS ---
:ZoneTransferScan
ECHO.
ECHO [*] Starting Zone Transfer Scan...
ECHO [*] Identifying Name Servers for %targetDomain%...

nslookup -type=ns %targetDomain% > ns_results.txt

ECHO.
ECHO [*] Found Name Servers. Now attempting zone transfer from each...
ECHO.

:: This is a more robust parsing method that checks tokens explicitly.
FOR /F "tokens=1,2,3,4" %%A IN ('findstr /I "nameserver" ns_results.txt') DO (
    IF /I "%%B"=="nameserver" (
        IF /I "%%C"=="=" (
            CALL :AttemptAXFR %%D
        )
    )
)

IF EXIST ns_results.txt DEL ns_results.txt
GOTO FinalPause

:: This is a subroutine for the actual AXFR attempt.
:AttemptAXFR
SET "nsServer=%1"
ECHO [*] Attempting AXFR from %nsServer%...

(
    ECHO server %nsServer%
    ECHO ls -d %targetDomain%
) > axfr_commands.tmp

nslookup < axfr_commands.tmp | findstr /I /C:"*** Can't list domain" >nul && (
    ECHO [-] Zone Transfer failed from %nsServer% (This is normal)
) || (
    ECHO [SUCCESS] Zone Transfer may have succeeded from %nsServer%!
    ECHO --- Records Found ---
    nslookup < axfr_commands.tmp
)
IF EXIST axfr_commands.tmp DEL axfr_commands.tmp
EXIT /B


:Quit
ECHO Exiting.
GOTO End

:FinalPause
ECHO.
ECHO Scan session finished.
PAUSE

:End
EXIT /B