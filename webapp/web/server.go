package web

import (
	"fmt"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/template/html/v2"
	"github.com/supermarket/web/handlers"
	"github.com/supermarket/web/middleware"
)

// Server represents the web server
type Server struct {
	app *fiber.App
}

// NewServer creates a new Fiber server
func NewServer() *Server {
	// Initialize template engine
	engine := html.New("./web/templates", ".html")
	engine.Reload(true) // Enable hot reload for development

	// Add custom template functions
	engine.AddFunc("formatDate", func(t time.Time) string {
		return t.Format("02/01/2006 15:04")
	})
	engine.AddFunc("formatCurrency", func(amount float64) string {
		return fmt.Sprintf("%.0f VND", amount)
	})
	engine.AddFunc("formatDuration", func(d time.Duration) string {
		if d < time.Millisecond {
			return fmt.Sprintf("%.2fµs", float64(d.Nanoseconds())/1000)
		}
		return fmt.Sprintf("%.2fms", float64(d.Nanoseconds())/1000000)
	})

	// Create Fiber app with template engine
	app := fiber.New(fiber.Config{
		Views: engine,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}

			// Check if it's an API request
			if c.Get("Content-Type") == "application/json" {
				return c.Status(code).JSON(fiber.Map{
					"error": err.Error(),
				})
			}

			// HTML error page
			return c.Status(code).Render("pages/error", fiber.Map{
				"Title": "Error",
				"Error": err.Error(),
				"Code":  code,
			})
		},
	})

	// Middleware
	app.Use(recover.New())
	app.Use(cors.New())
	app.Use(logger.New(logger.Config{
		Format: "[${time}] ${status} - ${latency} ${method} ${path}\n",
	}))

	// Custom middleware to inject SQL logs into context
	app.Use(middleware.SQLDebugMiddleware())

	// Static files
	app.Static("/static", "./web/static")

	// Setup routes
	setupRoutes(app)

	return &Server{app: app}
}

// Start starts the server
func (s *Server) Start(port string) error {
	log.Printf("Server starting on http://localhost:%s", port)
	return s.app.Listen(":" + port)
}

// setupRoutes configures all application routes
func setupRoutes(app *fiber.App) {
	// Home page
	app.Get("/", handlers.HomePage)

	// Debug endpoint for SQL logs
	app.Get("/api/debug/sql", handlers.GetSQLLogs)
	app.Delete("/api/debug/sql", handlers.ClearSQLLogs)

	// Product management
	products := app.Group("/products")
	products.Get("/", handlers.ProductList)
	products.Get("/new", handlers.ProductNew)
	products.Post("/", handlers.ProductCreate)
	products.Get("/:id", handlers.ProductView)
	products.Get("/:id/edit", handlers.ProductEdit)
	products.Put("/:id", handlers.ProductUpdate)
	products.Delete("/:id", handlers.ProductDelete)

	// Employee management
	employees := app.Group("/employees")
	employees.Get("/", handlers.EmployeeList)
	employees.Get("/new", handlers.EmployeeNew)
	employees.Post("/", handlers.EmployeeCreate)
	employees.Get("/:id", handlers.EmployeeView)
	employees.Get("/:id/edit", handlers.EmployeeEdit)
	employees.Put("/:id", handlers.EmployeeUpdate)
	employees.Delete("/:id", handlers.EmployeeDelete)

	// Customer management
	customers := app.Group("/customers")
	customers.Get("/", handlers.CustomerList)
	customers.Get("/new", handlers.CustomerNew)
	customers.Post("/", handlers.CustomerCreate)
	customers.Get("/:id", handlers.CustomerView)
	customers.Get("/:id/edit", handlers.CustomerEdit)
	customers.Put("/:id", handlers.CustomerUpdate)
	customers.Delete("/:id", handlers.CustomerDelete)

	// Inventory management
	inventory := app.Group("/inventory")
	inventory.Get("/", handlers.InventoryOverview)
	inventory.Get("/warehouse", handlers.WarehouseInventory)
	inventory.Get("/shelf", handlers.ShelfInventory)
	inventory.Post("/transfer", handlers.StockTransfer)
	inventory.Get("/low-stock", handlers.LowStockAlert)
	inventory.Get("/expired", handlers.ExpiredProducts)

	// Sales operations
	sales := app.Group("/sales")
	sales.Get("/", handlers.SalesList)
	sales.Get("/new", handlers.SalesNew)
	sales.Post("/", handlers.SalesCreate)
	sales.Get("/:id", handlers.SalesView)
	sales.Get("/invoice/:id", handlers.SalesInvoice)

	// Reports and statistics
	reports := app.Group("/reports")
	reports.Get("/", handlers.ReportsOverview)
	reports.Get("/sales", handlers.SalesReport)
	reports.Get("/products", handlers.ProductReport)
	reports.Get("/revenue", handlers.RevenueReport)
	reports.Get("/suppliers", handlers.SupplierReport)
	reports.Get("/customers", handlers.CustomerReport)

	// API endpoints for AJAX operations
	api := app.Group("/api")

	// Product categories
	api.Get("/categories", handlers.GetCategories)
	api.Get("/categories/:id/products", handlers.GetCategoryProducts)

	// Shelves
	api.Get("/shelves", handlers.GetShelves)
	api.Get("/shelves/:id/products", handlers.GetShelfProducts)

	// Real-time inventory check
	api.Get("/inventory/check/:productId", handlers.CheckInventory)

	// Discount calculation
	api.Post("/discount/calculate", handlers.CalculateDiscount)
}
