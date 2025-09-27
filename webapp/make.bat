@echo off

if "%1"=="" goto help

if "%1"=="build" goto build
if "%1"=="run" goto run
if "%1"=="migrate" goto migrate
if "%1"=="seed" goto seed
if "%1"=="migrate-seed" goto migrate-seed
if "%1"=="clean" goto clean
if "%1"=="test" goto test
if "%1"=="help" goto help

:build
echo Building application...
go build -o supermarket.exe main.go
echo Build complete: supermarket.exe
goto end

:run
echo Starting server...
go run main.go
goto end

:migrate
echo Running database migration...
go run main.go -migrate
goto end

:seed
echo Seeding database...
go run main.go -seed
goto end

:migrate-seed
echo Running migration and seeding...
go run main.go -migrate -seed
goto end

:clean
echo Cleaning build files...
del /f supermarket.exe 2>nul
del /f test_build.exe 2>nul
echo Clean complete
goto end

:test
echo Testing build...
go build -o test_build.exe
if %errorlevel% neq 0 (
    echo Build failed!
) else (
    echo Build successful!
    del /f test_build.exe
)
goto end

:help
echo Supermarket Management System - Build Commands
echo.
echo Usage: make.bat [command]
echo.
echo Commands:
echo   build         Build the application
echo   run           Run the server
echo   migrate       Run database migration
echo   seed          Seed database with sample data
echo   migrate-seed  Run migration and seed
echo   clean         Remove build files
echo   test          Test if build works
echo   help          Show this help message
echo.

:end