package web

import (
	"encoding/json"
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

	// Debug: List available templates
	fmt.Println("DEBUG: Template engine initialized")
	fmt.Println("DEBUG: Template directory: ./web/templates")

	// Add custom template functions
	engine.AddFunc("formatDate", func(t time.Time) string {
		return t.Format("02/01/2006 15:04")
	})
	engine.AddFunc("formatDateYMD", func(t time.Time) string {
		return t.Format("2006-01-02")
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
	engine.AddFunc("mul", func(a, b int) int {
		return a * b
	})
	engine.AddFunc("div", func(a, b int) int {
		if b == 0 {
			return 0
		}
		return a / b
	})
	engine.AddFunc("json", func(v interface{}) string {
		b, err := json.Marshal(v)
		if err != nil {
			return "{}"
		}
		return string(b)
	})
	engine.AddFunc("add", func(a, b int) int {
		return a + b
	})
	engine.AddFunc("sub", func(a, b int) int {
		return a - b
	})
	engine.AddFunc("len", func(slice interface{}) int {
		switch v := slice.(type) {
		case []interface{}:
			return len(v)
		default:
			return 0
		}
	})

	// Create Fiber app with template engine
	app := fiber.New(fiber.Config{
		Views: engine,
		// Enable debug mode for development
		EnablePrintRoutes: true,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}

			// Log error details to console
			log.Printf("ERROR [%s %s]: %v", c.Method(), c.Path(), err)

			// Check if it's an API request
			if c.Get("Content-Type") == "application/json" {
				return c.Status(code).JSON(fiber.Map{
					"error": err.Error(),
				})
			}

			// HTML error page
			return c.Status(code).Render("pages/error", fiber.Map{
				"Title":           "Error",
				"Error":           err.Error(),
				"Code":            code,
				"SQLQueries":      c.Locals("SQLQueries"),
				"TotalSQLQueries": c.Locals("TotalSQLQueries"),
			}, "layouts/base")
		},
	})

	// Middleware
	app.Use(recover.New(recover.Config{
		EnableStackTrace: true,
	}))
	app.Use(cors.New())
	app.Use(logger.New(logger.Config{
		Format: "[${time}] ${status} - ${latency} ${method} ${path} ${error}\n",
	}))

	// Custom middleware to inject SQL logs into context
	app.Use(middleware.SQLDebugMiddleware())

	// Method override middleware for HTML forms
	app.Use(func(c *fiber.Ctx) error {
		if c.Method() == "POST" {
			method := c.FormValue("_method")
			if method != "" {
				c.Method(method)
			}
		}
		return c.Next()
	})

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

	// Display shelf management - must be before /:id routes
	products.Get("/shelves", handlers.DisplayShelfList)
	products.Get("/shelves/new", handlers.DisplayShelfNew)
	products.Post("/shelves", handlers.DisplayShelfCreate)
	products.Get("/shelves/:id", handlers.DisplayShelfView)
	products.Get("/shelves/:id/edit", handlers.DisplayShelfEdit)
	products.Put("/shelves/:id", handlers.DisplayShelfUpdate)
	products.Delete("/shelves/:id", handlers.DisplayShelfDelete)

	// Shelf layout management - must be before /:id routes
	products.Get("/shelf-layouts", handlers.ShelfLayoutList)
	products.Get("/shelf-layouts/new", handlers.ShelfLayoutNew)
	products.Post("/shelf-layouts", handlers.ShelfLayoutCreate)
	products.Get("/shelf-layouts/:id", handlers.ShelfLayoutView)
	products.Get("/shelf-layouts/:id/edit", handlers.ShelfLayoutEdit)
	products.Put("/shelf-layouts/:id", handlers.ShelfLayoutUpdate)
	products.Delete("/shelf-layouts/:id", handlers.ShelfLayoutDelete)

	// Product detail routes - must be after /shelves routes
	products.Get("/:id", handlers.ProductView)
	products.Get("/:id/edit", handlers.ProductEdit)
	products.Put("/:id", handlers.ProductUpdate)
	products.Delete("/:id", handlers.ProductDelete)

	// Employee management (order matters: specific routes before ":id")
	employees := app.Group("/employees")
	// Specific subroutes first
	employees.Get("/work-hours", handlers.WorkHourList)
	employees.Get("/work-hours/new", handlers.WorkHourNew)
	employees.Post("/work-hours", handlers.WorkHourCreate)
	employees.Get("/work-hours/:id/edit", handlers.WorkHourEdit)
	employees.Put("/work-hours/:id", handlers.WorkHourUpdate)
	employees.Delete("/work-hours/:id", handlers.WorkHourDelete)
	employees.Get("/salary", handlers.SalarySummary)
	// Then base list/create
	employees.Get("/", handlers.EmployeeList)
	employees.Get("/new", handlers.EmployeeNew)
	employees.Post("/", handlers.EmployeeCreate)
	// Finally ID-based routes
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
	inventory.Get("/transfer", handlers.StockTransferForm)
	inventory.Post("/transfer", handlers.StockTransfer)
	inventory.Get("/low-stock", handlers.LowStockAlert)
	inventory.Get("/expired", handlers.ExpiredProducts)
	inventory.Get("/transfers", handlers.StockTransferHistory)
	inventory.Post("/apply-discount", handlers.ApplyDiscountRules)

	// Discount rules management
	inventory.Get("/discount-rules", handlers.DiscountRulesList)
	inventory.Post("/discount-rules", handlers.CreateDiscountRule)
	inventory.Put("/discount-rules/:id", handlers.UpdateDiscountRule)
	inventory.Delete("/discount-rules/:id", handlers.DeleteDiscountRule)

	// Purchase order management
	purchaseOrders := app.Group("/purchase-orders")
	purchaseOrders.Get("/", handlers.PurchaseOrderList)
	purchaseOrders.Get("/new", handlers.PurchaseOrderNew)
	purchaseOrders.Get("/create", handlers.PurchaseOrderNew) // Alias for /new
	purchaseOrders.Post("/", handlers.PurchaseOrderCreate)
	purchaseOrders.Get("/:id", handlers.PurchaseOrderView)
	purchaseOrders.Get("/:id/edit", handlers.PurchaseOrderEdit)
	purchaseOrders.Put("/:id", handlers.PurchaseOrderUpdate)
	purchaseOrders.Delete("/:id", handlers.PurchaseOrderDelete)

	// Sales operations
	sales := app.Group("/sales")
	sales.Get("/", handlers.SalesList)
	sales.Get("/simple", handlers.SalesListSimple)
	sales.Get("/test", func(c *fiber.Ctx) error {
		return c.Render("pages/sales/test", fiber.Map{
			"InvoiceCount": 5,
			"Invoices": []fiber.Map{
				{"InvoiceNo": "TEST001", "TotalAmount": 100000},
				{"InvoiceNo": "TEST002", "TotalAmount": 200000},
			},
		})
	})
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

	// Positions admin
	positions := app.Group("/positions")
	positions.Get("/", handlers.PositionList)
	positions.Get("/new", handlers.PositionNew)
	positions.Post("/", handlers.PositionCreate)
	positions.Get("/:id", handlers.PositionView)
	positions.Get("/:id/edit", handlers.PositionEdit)
	positions.Put("/:id", handlers.PositionUpdate)
	positions.Delete("/:id", handlers.PositionDelete)

	// Membership levels admin
	levels := app.Group("/membership-levels")
	levels.Get("/", handlers.LevelList)
	levels.Get("/new", handlers.LevelNew)
	levels.Post("/", handlers.LevelCreate)
	levels.Get("/:id", handlers.LevelView)
	levels.Get("/:id/edit", handlers.LevelEdit)
	levels.Put("/:id", handlers.LevelUpdate)
	levels.Delete("/:id", handlers.LevelDelete)

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

	// Discount rules API
	apiInventory := api.Group("/inventory")
	apiInventory.Post("/discount-rules", handlers.CreateDiscountRule)
	apiInventory.Put("/discount-rules/:id", handlers.UpdateDiscountRule)
	apiInventory.Delete("/discount-rules/:id", handlers.DeleteDiscountRule)
	// Warehouse utilities
	apiInventory.Post("/warehouse/expiry", handlers.UpdateWarehouseExpiry)

	// Inventory disposal endpoints
	apiInventory.Delete("/warehouse/:id", handlers.DeleteWarehouseInventory)
	apiInventory.Delete("/shelf/:id", handlers.DeleteShelfInventory)
	apiInventory.Post("/dispose-all-expired", handlers.DisposeAllExpired)

	// Warehouse management
	warehouses := app.Group("/warehouses")
	warehouses.Get("/", handlers.WarehouseList)
	warehouses.Get("/new", handlers.WarehouseNew)
	warehouses.Post("/", handlers.WarehouseCreate)
	warehouses.Get("/:id", handlers.WarehouseView)
	warehouses.Get("/:id/edit", handlers.WarehouseEdit)
	warehouses.Put("/:id", handlers.WarehouseUpdate)
	warehouses.Delete("/:id", handlers.WarehouseDelete)
}
