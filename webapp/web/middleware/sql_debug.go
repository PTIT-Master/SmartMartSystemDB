package middleware

import (
	"github.com/gofiber/fiber/v2"
	"github.com/supermarket/database"
)

// SQLDebugMiddleware injects SQL logs into each request context
func SQLDebugMiddleware() fiber.Handler {
	return func(c *fiber.Ctx) error {
		// Get recent SQL queries before processing request
		beforeCount := len(database.SQLLogger.GetQueries())

		// Process request
		err := c.Next()

		// Get queries executed during this request
		afterQueries := database.SQLLogger.GetQueries()
		requestQueries := []database.QueryLog{}

		if len(afterQueries) > beforeCount {
			// Get only the queries from this request
			diff := len(afterQueries) - beforeCount
			if diff > 0 && diff <= len(afterQueries) {
				requestQueries = afterQueries[:diff]
			}
		}

		// Store in locals for templates
		c.Locals("SQLQueries", requestQueries)
		c.Locals("TotalSQLQueries", len(requestQueries))

		return err
	}
}
