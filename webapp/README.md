# Supermarket Management System - Go Web Application

## 📋 Overview

Web application for supermarket retail management system built with Go and GORM, following BCNF database design principles.

## 🏗️ Project Structure

```
webapp/
├── config/          # Configuration management
│   └── config.go    # Database and app configuration
├── database/        # Database connection and migration
│   ├── connection.go # Database connection setup
│   └── migration.go  # Migration utilities
├── models/          # GORM models (BCNF normalized)
│   ├── base.go             # Base model structures
│   ├── product_category.go # Product categories
│   ├── supplier.go         # Suppliers
│   ├── product.go          # Products
│   ├── discount_rule.go    # Discount rules
│   ├── warehouse.go        # Warehouse & inventory
│   ├── display_shelf.go    # Display shelves & layout
│   ├── employee.go         # Employees & positions
│   ├── customer.go         # Customers & membership
│   ├── sales_invoice.go    # Sales invoices
│   ├── purchase_order.go   # Purchase orders
│   ├── stock_transfer.go   # Stock transfers
│   └── models.go           # Model registry
├── main.go          # Application entry point
├── go.mod           # Go module file
└── env.example      # Environment configuration example
```

## 🚀 Setup Instructions

### 1. Prerequisites

- Go 1.24 or higher
- PostgreSQL 13 or higher
- Git

### 2. Database Setup

You have two options for setting up the database:

#### Option A: Using GORM AutoMigrate (Recommended for new projects)

```bash
# Create database
psql -U postgres -c "CREATE DATABASE supermarket;"

# Navigate to webapp directory
cd webapp

# Run migration
go run cmd/migrate/main.go

# Or use Makefile
make migrate
```

#### Option B: Using SQL Scripts (For complete functionality with triggers)

```bash
# Connect to PostgreSQL
psql -U postgres

# Create database
CREATE DATABASE supermarket;

# Connect to the database
\c supermarket

# Run the schema script
\i ../sql/01_schema.sql

# Run the functions script (optional)
\i ../sql/02_functions.sql

# Insert sample data (optional)
\i ../sql/04_insert_sample_data.sql
```

### 3. Application Setup

```bash
# Navigate to webapp directory
cd webapp

# Copy environment configuration
cp env.example .env

# Edit .env with your database credentials
# Update DB_PASSWORD and other settings as needed

# Download dependencies
go mod download

# Run the application
go run main.go
```

## 🔧 Configuration

Create a `.env` file in the webapp directory with the following configuration:

```env
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_password_here
DB_NAME=supermarket
DB_SSLMODE=disable

# Application Configuration
APP_ENV=development
APP_PORT=8080
```

## 📊 Database Models

The application uses GORM models that map to the PostgreSQL schema following BCNF normalization:

### Core Entities
- **Products & Categories**: Product catalog management
- **Suppliers**: Supplier information and relationships
- **Warehouse & Inventory**: Stock management in warehouse
- **Display Shelves**: Shelf layout and inventory
- **Employees & Positions**: Staff management
- **Customers & Membership**: Customer loyalty program

### Transactional Entities
- **Sales Invoices**: Sales transactions
- **Purchase Orders**: Supplier orders
- **Stock Transfers**: Warehouse to shelf transfers

### Business Rules (Enforced at DB level)
- Selling price must be greater than import price
- Each shelf can only display products from one category
- Stock quantities cannot be negative
- Automatic membership level upgrades based on spending
- Triggers for inventory updates after sales

## 🔨 Development

### Running in Development Mode

```bash
# With hot reload (install air first)
go install github.com/cosmtrek/air@latest
air

# Or standard run
go run main.go

# Run with auto-migration
go run main.go -migrate
```

### Database Migration Commands

```bash
# On Linux/macOS - Using Makefile
make migrate          # Run migration
make migrate-drop     # Drop all tables and recreate
make migrate-schema   # Create schema only
make test-connection  # Test database connection

# On Windows - Using make.bat
make.bat migrate          # Run migration
make.bat migrate-drop     # Drop all tables and recreate
make.bat migrate-schema   # Create schema only
make.bat test-connection  # Test database connection

# Using Go directly (all platforms)
go run cmd/migrate/main.go          # Run migration
go run cmd/migrate/main.go -drop    # Drop and recreate
go run cmd/migrate/main.go -schema  # Schema only
go run test_connection.go           # Test connection
```

### Building for Production

```bash
# Build the application
go build -o supermarket-app main.go

# Run the binary
./supermarket-app

# Run with migration
./supermarket-app -migrate
```

## 📝 Important Notes

1. **Schema Management Options**:
   - **GORM AutoMigrate**: Convenient for development and new projects. Creates tables, indexes, and basic constraints.
   - **SQL Scripts**: Recommended for production. Includes triggers, stored procedures, and complex constraints.

2. **Database Connection**: The application automatically sets the search path to the `supermarket` schema.

3. **Model Relationships**: GORM models include relationship definitions for easy data loading with Preload/Joins.

4. **Time Handling**: All timestamps use local time zone.

5. **Migration Notes**:
   - GORM AutoMigrate creates tables and basic constraints
   - Custom constraints and indexes are added automatically
   - For full functionality (triggers, functions), use SQL scripts

## 🔄 Next Steps

To complete the web application, you'll need to add:

1. **API Layer**
   - RESTful endpoints
   - Request/response DTOs
   - Validation middleware

2. **Business Logic**
   - Service layer for business operations
   - Transaction management
   - Error handling

3. **Authentication**
   - User authentication
   - JWT tokens
   - Role-based access control

4. **Frontend**
   - Web UI (React/Vue/Angular)
   - Admin dashboard
   - POS interface

## 📚 Dependencies

- `gorm.io/gorm` - ORM library
- `gorm.io/driver/postgres` - PostgreSQL driver
- `github.com/joho/godotenv` - Environment variable management

## 🤝 Contributing

1. Follow Go best practices and conventions
2. Maintain BCNF normalization in any schema changes
3. Write tests for new features
4. Update documentation as needed

## 📄 License

[Your License Here]
