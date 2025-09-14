@echo off
setlocal

if "%1"=="" goto help
if "%1"=="help" goto help
if "%1"=="build" goto build
if "%1"=="clean" goto clean
if "%1"=="test" goto test
if "%1"=="test-connection" goto test-connection
if "%1"=="deps" goto deps
if "%1"=="run" goto run
if "%1"=="run-migrate" goto run-migrate
if "%1"=="migrate" goto migrate
if "%1"=="migrate-drop" goto migrate-drop
if "%1"=="migrate-schema" goto migrate-schema

echo Unknown command: %1
goto help

:help
echo.
echo Supermarket Management System - Build Commands
echo.
echo Usage: make.bat [command]
echo.
echo Available commands:
echo   help             Show this help message
echo   build            Build the application
echo   clean            Clean build artifacts
echo   test             Run tests
echo   test-connection  Test database connection
echo   deps             Download dependencies
echo   run              Run the application
echo   run-migrate      Run the application with migration
echo   migrate          Run database migration
echo   migrate-drop     Drop all tables and recreate (WARNING: Data loss!)
echo   migrate-schema   Create schema only
echo.
goto end

:build
echo Building application...
go build -o supermarket-app.exe -v .
goto end

:clean
echo Cleaning build artifacts...
go clean
if exist supermarket-app.exe del supermarket-app.exe
goto end

:test
echo Running tests...
go test -v ./...
goto end

:test-connection
echo Testing database connection...
go run test_connection.go
goto end

:deps
echo Downloading dependencies...
go mod download
go mod tidy
goto end

:run
echo Running application...
go run main.go
goto end

:run-migrate
echo Running application with migration...
go run main.go -migrate
goto end

:migrate
echo Running database migration...
go run cmd/migrate/main.go
goto end

:migrate-drop
echo Dropping all tables and recreating...
echo WARNING: This will delete all data!
echo.
set /p confirm="Are you sure? (y/N): "
if /i "%confirm%"=="y" (
    go run cmd/migrate/main.go -drop
) else (
    echo Migration cancelled.
)
goto end

:migrate-schema
echo Creating schema only...
go run cmd/migrate/main.go -schema
goto end

:end
endlocal
