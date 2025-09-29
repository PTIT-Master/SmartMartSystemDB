package database

import (
	"log"
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// SimulationConfig holds simulation parameters
type SimulationConfig struct {
	StartDate         time.Time
	EndDate           time.Time
	DB                *gorm.DB
	MinShelfStock     int     // Minimum stock on shelf before restock
	MinWarehouseStock int     // Minimum warehouse stock before reorder
	AverageDailySales int     // Average number of sales per day
	RestockThreshold  float64 // Percentage threshold for restocking (e.g., 0.3 = 30%)
}

// StoreSimulation handles the store simulation
type StoreSimulation struct {
	config          SimulationConfig
	products        []models.Product
	customers       []models.Customer
	employees       []models.Employee
	suppliers       []models.Supplier
	warehouses      []models.Warehouse
	shelves         []models.DisplayShelf
	currentDate     time.Time
	orderCounter    int
	transferCounter int
	invoiceCounter  int
}

// printSimulationSummary prints summary statistics
func (s *StoreSimulation) printSimulationSummary() {
	log.Println("\n=== Simulation Summary ===")

	// Count totals
	var orderCount, invoiceCount, transferCount int64
	s.config.DB.Model(&models.PurchaseOrder{}).Count(&orderCount)
	s.config.DB.Model(&models.SalesInvoice{}).Count(&invoiceCount)
	s.config.DB.Model(&models.StockTransfer{}).Count(&transferCount)

	// Calculate revenue
	var totalRevenue struct {
		Total float64
	}
	s.config.DB.Model(&models.SalesInvoice{}).
		Select("SUM(total_amount) as total").
		Where("invoice_date >= ? AND invoice_date <= ?", s.config.StartDate, s.config.EndDate).
		Scan(&totalRevenue)

	log.Printf("📊 Purchase Orders: %d", orderCount)
	log.Printf("💰 Sales Invoices: %d", invoiceCount)
	log.Printf("📦 Stock Transfers: %d", transferCount)
	log.Printf("💵 Total Revenue: %.2f VND", totalRevenue.Total)
}

// RunSimulation is the main entry point for the simulation
// This now uses the new realistic simulation approach
func RunSimulation(db *gorm.DB, startDate, endDate time.Time) error {
	// Use the new realistic simulation that follows the requirements:
	// 1. Order from suppliers when warehouse is low
	// 2. Stock arrives in warehouse
	// 3. Transfer stock to shelves as needed
	// 4. Sell to customers daily
	// 5. Restock shelves when empty from warehouse
	// 6. Reorder from suppliers when warehouse is empty
	return RunRealisticSimulation(db, startDate, endDate)
}
