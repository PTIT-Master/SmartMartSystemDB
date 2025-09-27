package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/supermarket/config"
	"github.com/supermarket/database"
	"github.com/supermarket/web"
)

func main() {
	// Command line flags
	var (
		migrate = flag.Bool("migrate", false, "Run database migration on startup")
		seed    = flag.Bool("seed", false, "Seed database with sample data")
		help    = flag.Bool("help", false, "Show help")
	)

	flag.Parse()

	if *help {
		showHelp()
		return
	}

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Initialize database connection
	if err := database.Initialize(&cfg.Database); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}
	defer database.Close()

	// Check database connection and schema
	if err := database.CheckConnection(database.DB); err != nil {
		log.Fatalf("Database connection check failed: %v", err)
	}

	// Run migration if requested
	if *migrate {
		log.Println("Running database migration...")
		if err := database.AutoMigrate(database.DB); err != nil {
			log.Fatalf("Failed to migrate database: %v", err)
		}
		log.Println("Migration completed successfully")
	}

	// Seed database if requested
	if *seed {
		log.Println("Seeding database with sample data...")
		if err := database.SeedData(database.DB); err != nil {
			log.Fatalf("Failed to seed database: %v", err)
		}
		log.Println("Database seeded successfully")
	}

	// Create and start web server
	server := web.NewServer()

	// Start server in a goroutine
	go func() {
		if err := server.Start(cfg.App.Port); err != nil {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Setup graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	// Wait for interrupt signal
	<-quit
	log.Println("Shutting down server...")
}

func showHelp() {
	log.Println(`
Supermarket Management System Server

Usage:
  go run main.go [options]

Options:
  -migrate  Run GORM AutoMigrate on startup
  -seed     Seed database with sample data
  -help     Show this help message

Examples:
  # Start server only
  go run main.go

  # Start server with migration
  go run main.go -migrate

  # Start server with migration and seed
  go run main.go -migrate -seed

  # Seed data only
  go run main.go -seed

For full migration control, use:
  go run cmd/migrate/main.go

For full seed control, use:
  go run cmd/seed/main.go
`)
}
