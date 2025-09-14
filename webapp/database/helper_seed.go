package database

import (
	"time"

	"github.com/supermarket/models"
	"gorm.io/gorm"
)

// getCategoryID retrieves category ID by name
func getCategoryID(tx *gorm.DB, categoryName string) uint {
	var category models.ProductCategory
	tx.Where("category_name = ?", categoryName).First(&category)
	return category.CategoryID
}

// getRandomPaymentMethod returns a random payment method based on day and sale parameters
func getRandomPaymentMethod(day, sale int) models.PaymentMethod {
	methods := []models.PaymentMethod{
		models.PaymentCash,
		models.PaymentCard,
		models.PaymentCard, // Weight towards card payments
	}
	return methods[(day+sale)%len(methods)]
}

// Helper functions for creating pointers
func strPtr(s string) *string {
	return &s
}

func intPtr(i int) *int {
	return &i
}

func uintPtr(u uint) *uint {
	return &u
}

func floatPtr(f float64) *float64 {
	return &f
}

func timePtr(t time.Time) *time.Time {
	return &t
}

func paymentMethodPtr(pm models.PaymentMethod) *models.PaymentMethod {
	return &pm
}
